"""No post-hoc positive strategy promotions from two retrospective windows."""
import unittest
from scripts.research.compare_directional_replay_periods import compare_two_periods


def period(n,score):
    return {
        "live_execution_authorized":False,"orders_sent":0,
        "research_action":"WAIT",
        "backtest_is_independent_out_of_sample":False,
        "symbols":["XAUUSD.vx","EURUSD.vx"],
        "counters":{"evaluated":n*20,"proxy_completed":n,
                    "adaptive_selected":0},
        "method_side_scorecard":[
            {"method":"TREND_PULLBACK","side":"SELL",
             "n":n,"mean_modeled_net_r_by_cost":{"0.15":score}}
        ],
    }


class TestCrossPeriodNoPromotion(unittest.TestCase):
    def test_both_negative_is_falsification_not_live_strategy(self):
        x=compare_two_periods(period(25,-.2),period(35,-.45),
                              earlier_label="2026-09",later_label="2026-10")
        self.assertEqual(x["historical_decisions_evaluated"],1200)
        self.assertEqual(x["hypothetical_ohlc_outcomes"],60)
        self.assertEqual(x["repeated_negative_method_sides"],1)
        self.assertFalse(x["live_execution_authorized"])
        self.assertEqual(x["production_action"],"WAIT")

    def test_both_positive_does_not_prove_unseen_alpha(self):
        x=compare_two_periods(period(55,.2),period(40,.12),
                              earlier_label="2026-09",later_label="2026-10")
        self.assertEqual(x["repeated_negative_method_sides"],0)
        self.assertEqual(x["strategy_side_findings"][0]["verdict"],
                         "POSITIVE_BUT_INSPECTED_RETROSPECTIVE_WINDOWS")
        self.assertFalse(x["strategy_side_findings"][0]["live_strategy_authorized"])

    def test_mismatched_symbols_and_live_admission_rejected(self):
        bad=period(30,.2)
        bad["symbols"]=["EURUSD.vx"]
        with self.assertRaises(ValueError):
            compare_two_periods(period(30,-.1),bad,
                                earlier_label="2026-09",later_label="2026-10")
        bad=period(30,.2)
        bad["live_execution_authorized"]=True
        with self.assertRaises(ValueError):
            compare_two_periods(period(30,-.1),bad,
                                earlier_label="2026-09",later_label="2026-10")


if __name__=="__main__":unittest.main()
