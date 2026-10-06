import unittest

from katarina.engines.account_risk_state import AccountRiskCoordinator, AccountRiskStateEngine
from katarina.engines.manual_risk import SharedAccountRiskEngine
from katarina.engines.multi_symbol_execution import MultiSymbolCandidate, MultiSymbolExecutionOrchestrator
from katarina.engines.opportunity import RankedOpportunity
from katarina.engines.risk import RiskGovernor
from katarina.engines.scalper_entry import EntryMode, EntryProposal, EntrySide


def opp(symbol,iid,score=.9,spec=1):
    return RankedOpportunity(
        symbol=symbol,
        instrument_id=iid,
        spec_revision=spec,
        score=score,
        proposal=EntryProposal(True,EntrySide.BUY,EntryMode.TREND_PULLBACK,score,1-score,2.0,1.0,3,("test",)),
        asset_class="FOREX",
        reasons=("test",),
    )

def cand(symbol,iid,score=.9):
    return MultiSymbolCandidate(
        opportunity=opp(symbol,iid,score),
        requested_risk_fraction=.05,
        base_volume=.10,
        volume_min=.01,
        volume_step=.01,
        stop_loss=1.0,
        take_profit=2.0,
        decision_id="decision-"+symbol,
        risk_id="risk-"+symbol,
    )


class MultiSymbolExecutionTests(unittest.TestCase):
    def _orchestrator(self):
        state=AccountRiskStateEngine(max_open_risk=.08)
        coord=AccountRiskCoordinator(state,RiskGovernor(hard_per_trade=.05,max_open_risk=.08))
        return MultiSymbolExecutionOrchestrator(risk=coord,max_new_positions=5),state

    def test_two_uncorrelated_markets_share_eight_percent_budget(self):
        o,state=self._orchestrator()
        positions=SharedAccountRiskEngine().assess([],equity=10000)
        plan=o.build_plan(
            [cand("EURUSD",1,.95),cand("XAUUSD",2,.90)],
            positions=positions,day_key="2026-10-06",
            returns={"EURUSD":[1,0,-1,0],"XAUUSD":[0,1,0,-1]},
        )
        self.assertEqual([x.symbol for x in plan.accepted],["EURUSD","XAUUSD"])
        self.assertAlmostEqual(plan.accepted[0].approved_risk_fraction,.05)
        self.assertAlmostEqual(plan.accepted[1].approved_risk_fraction,.03)
        self.assertAlmostEqual(plan.accepted[1].intent.volume,.06)
        self.assertAlmostEqual(state.reservations.total_fraction,.08)

    def test_third_market_has_no_capacity_after_eight_percent(self):
        o,_=self._orchestrator()
        positions=SharedAccountRiskEngine().assess([],equity=10000)
        plan=o.build_plan(
            [cand("EURUSD",1,.95),cand("XAUUSD",2,.90),cand("USDJPY",3,.85)],
            positions=positions,day_key="2026-10-06",
            returns={"EURUSD":[1,0,-1,0],"XAUUSD":[0,1,0,-1],"USDJPY":[1,-1,1,-1]},
        )
        self.assertEqual(len(plan.accepted),2)
        self.assertIn("USDJPY",[x.symbol for x in plan.rejected])

    def test_high_positive_correlation_can_block_second_market(self):
        o,state=self._orchestrator()
        positions=SharedAccountRiskEngine().assess([],equity=10000)
        series=[1,2,3,4,5]
        plan=o.build_plan(
            [cand("EURUSD",1,.95),cand("GBPUSD",2,.90)],
            positions=positions,day_key="2026-10-06",
            returns={"EURUSD":series,"GBPUSD":series},
        )
        self.assertEqual([x.symbol for x in plan.accepted],["EURUSD"])
        self.assertEqual(plan.rejected[0].reason,"correlation_exposure_cap")
        self.assertAlmostEqual(state.reservations.total_fraction,.05)

    def test_best_score_is_admitted_first_even_if_input_order_is_reversed(self):
        o,_=self._orchestrator()
        positions=SharedAccountRiskEngine().assess([],equity=10000)
        plan=o.build_plan(
            [cand("XAUUSD",2,.70),cand("EURUSD",1,.95)],
            positions=positions,day_key="2026-10-06",
            returns={"EURUSD":[1,0,-1],"XAUUSD":[0,1,0]},
        )
        self.assertEqual(plan.accepted[0].symbol,"EURUSD")
        self.assertAlmostEqual(plan.accepted[0].approved_risk_fraction,.05)

    def test_existing_account_risk_reduces_multi_symbol_capacity(self):
        o,state=self._orchestrator()
        state.reservations.reserve("existing",.04)
        positions=SharedAccountRiskEngine().assess([],equity=10000)
        plan=o.build_plan(
            [cand("EURUSD",1,.95),cand("XAUUSD",2,.90)],
            positions=positions,day_key="2026-10-06",
            returns={"EURUSD":[1,0,-1],"XAUUSD":[0,1,0]},
        )
        self.assertEqual(len(plan.accepted),1)
        self.assertAlmostEqual(plan.accepted[0].approved_risk_fraction,.04)
        self.assertAlmostEqual(state.reservations.total_fraction,.08)

    def test_duplicate_symbol_candidate_rejected(self):
        o,_=self._orchestrator()
        positions=SharedAccountRiskEngine().assess([],equity=10000)
        plan=o.build_plan(
            [cand("EURUSD",1,.95),cand("EURUSD",1,.90)],
            positions=positions,day_key="2026-10-06",returns={"EURUSD":[1,-1,1]},
        )
        self.assertEqual(len(plan.accepted),1)
        self.assertTrue(any(x.reason=="duplicate_symbol_candidate" for x in plan.rejected))


if __name__=="__main__": unittest.main()
