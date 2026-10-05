from __future__ import annotations

import importlib
import unittest

from katarina.body.functional import PaperFill


def component(stage: int):
    return importlib.import_module(
        f"katarina.body.stage{stage:02d}"
    ).Component()


class Stage36PaperTradingGuardTests(unittest.TestCase):
    def test_paper_ledger_is_deterministic_and_has_no_broker_mutation(self):
        c = component(36)
        self.assertFalse(c.broker_mutation_enabled)
        c.simulate_fill(PaperFill("a", 3000000, 10, "BUY", "XAUUSD"))
        c.simulate_fill(PaperFill("b", 3000100, 4, "SELL", "XAUUSD"))
        c.simulate_fill(PaperFill("c", 100000, 3, "BUY", "BTCUSD"))
        self.assertEqual(c.position_units("XAUUSD"), 6)
        self.assertEqual(c.position_units("BTCUSD"), 3)
        self.assertEqual(len(c.fills()), 3)

    def test_duplicate_paper_order_id_is_rejected(self):
        c = component(36)
        fill = PaperFill("same", 3000000, 1, "BUY")
        c.simulate_fill(fill)
        with self.assertRaises(ValueError):
            c.simulate_fill(fill)

    def test_invalid_paper_fill_fails_closed(self):
        with self.assertRaises(ValueError):
            PaperFill("bad", 0, 1, "BUY")
        with self.assertRaises(ValueError):
            PaperFill("bad", 1, 0, "BUY")
        with self.assertRaises(ValueError):
            PaperFill("bad", 1, 1, "HOLD")


class Stage38MicroRiskGateTests(unittest.TestCase):
    def test_missing_prerequisites_are_explicit(self):
        out = component(38).validate({})
        self.assertFalse(out["approved"])
        self.assertFalse(out["all_prerequisites_present"])
        self.assertEqual(
            set(out["missing_prerequisites"]),
            {
                "strategy_policy_finalized",
                "risk_policy_finalized",
                "stage35_tester_passed",
                "stage36_demo_passed",
                "stage37_stress_passed",
                "health_ready",
                "reconciliation_ready",
            },
        )

    def test_even_complete_prerequisites_do_not_enable_live_in_body_build(self):
        payload = {
            "strategy_policy_finalized": True,
            "risk_policy_finalized": True,
            "stage35_tester_passed": True,
            "stage36_demo_passed": True,
            "stage37_stress_passed": True,
            "health_ready": True,
            "reconciliation_ready": True,
        }
        out = component(38).validate(payload)
        self.assertTrue(out["all_prerequisites_present"])
        self.assertEqual(out["missing_prerequisites"], ())
        self.assertFalse(out["approved"])
        self.assertFalse(out["live_risk_ready"])
        self.assertFalse(out["live_execution_authority"])


if __name__ == "__main__":
    unittest.main()
