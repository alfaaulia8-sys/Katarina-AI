import unittest
from katarina.engines.risk import RiskGovernor,RiskRequest,RiskAction
from katarina.engines.sizing import PositionSizingEngine
from katarina.engines.execution import ExecutionEngine,ExecutionIntent
from katarina.engines.position import PositionManager,PositionState,ManagementAction
from katarina.engines.evaluation import TradeEvaluationEngine

class Stage1620Tests(unittest.TestCase):
    def test_risk_hard_cap_is_five_percent(self):
        d=RiskGovernor().evaluate(RiskRequest(.10,0,0,.1,2,True,True))
        self.assertEqual(d.action,RiskAction.REDUCE)
        self.assertLessEqual(d.approved_fraction,.05)
        self.assertAlmostEqual(d.approved_fraction,.05)

    def test_daily_drawdown_ten_percent_pauses_new_risk(self):
        d=RiskGovernor().evaluate(RiskRequest(.01,0,0,.1,2,True,True,.10))
        self.assertEqual(d.action,RiskAction.PAUSE)
        self.assertEqual(d.approved_fraction,0.0)
        self.assertEqual(d.reason,"daily_drawdown_limit")

    def test_daily_drawdown_below_limit_can_continue(self):
        d=RiskGovernor().evaluate(RiskRequest(.01,0,0,.1,2,True,True,.099))
        self.assertEqual(d.action,RiskAction.APPROVE)

    def test_risk_pause_unhealthy(self):
        d=RiskGovernor().evaluate(RiskRequest(.01,0,0,.1,2,False,True))
        self.assertEqual(d.action,RiskAction.PAUSE)

    def test_sizing(self):
        r=PositionSizingEngine().size(equity=10000,risk_fraction=.01,stop_distance=10,value_per_price_unit_per_lot=10,volume_min=.01,volume_max=10,volume_step=.01)
        self.assertTrue(r.valid); self.assertGreater(r.volume,0)

    def test_execution_disarmed(self):
        e=ExecutionEngine(); i=ExecutionIntent("x","BUY","XAUUSD",.1,2000,None,"d","r")
        self.assertFalse(e.preflight(i,execution_armed=False,fresh=True,reconciled=True,spread_ok=True).allowed)

    def test_execution_idempotent(self):
        e=ExecutionEngine(); i=ExecutionIntent("x","BUY","XAUUSD",.1,2000,None,"d","r")
        self.assertTrue(e.reserve(i)); self.assertFalse(e.reserve(i))

    def test_position_protection(self):
        p=PositionState("BUY",100,125,90,10); d=PositionManager().decide(p); self.assertIn(d.action,{ManagementAction.MODIFY_SL,ManagementAction.HOLD})

    def test_trade_evaluation(self):
        e=TradeEvaluationEngine().evaluate(side="BUY",entry=100,exit_price=120,stop_distance=10,lowest=95,highest=125,total_cost=1,evidence_score=.8,uncertainty=.2)
        self.assertGreater(e.r_multiple,1); self.assertGreater(e.decision_quality,.5)

if __name__=="__main__": unittest.main()
