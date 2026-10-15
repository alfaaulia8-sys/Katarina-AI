"""Owner-approved safety contract guard. Research-only: no broker calls."""

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class OwnerPolicyBaselineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.policy = json.loads((ROOT / "config/risk_governor_v2.json").read_text(encoding="utf-8"))
        cls.approval = (ROOT / "docs/architecture/OWNER_DECISIONS_ADDENDUM_20261014.md").read_text(encoding="utf-8")
        cls.baseline = (ROOT / "docs/architecture/KATARINA_OWNER_DESIGN_BASELINE_20261014.md").read_text(encoding="utf-8")

    def test_drawdown_limits_remain_owner_approved_not_new_defaults(self):
        p = self.policy
        self.assertEqual(p["drawdown_modes"], {
            "normal_below": .10, "caution_below": .23,
            "recovery_factor_only_below": .35, "emergency_at": .35,
        })
        self.assertEqual(p["hard_per_entry_fraction"], .05)
        self.assertEqual(p["max_open_risk_fraction"], .08)
        self.assertFalse(p["adaptive_risk"]["live_authorization"])

    def test_recovery_factor_never_authorizes_live(self):
        self.assertFalse(self.policy["recovery_factor"]["used_for_live_authorization"])
        self.assertTrue(self.policy["stage38"]["authorization_gate_required"])

    def test_owner_addendum_records_six_decisions_and_safe_disconnect(self):
        for required in (
            "D1 —", "D2 —", "D3 —", "D4 —", "D5 —", "D6 —",
            "NO NEW ENTRY", "Fast", "Deep", "cashflow-adjusted",
            "25%", "Risk Governor", "Live execution OFF",
        ):
            with self.subTest(required=required):
                self.assertIn(required, self.approval)

    def test_existing_owner_policy_preserves_manual_trade_protection(self):
        self.assertIn("Manual positions affect total account safety", self.baseline)
        self.assertIn("Katarina Management and its 11 specialists are REMOVED", self.baseline)
        self.assertIn("RECURRING PROFIT LOCK", self.baseline)


if __name__ == "__main__":
    unittest.main()
