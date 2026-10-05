from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "mt5" / "Tests" / "KatarinaStage36DemoGate.mq5"


class Stage36DemoGateStaticTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.text = SCRIPT.read_text(encoding="utf-8")
        cls.lower = cls.text.lower()

    def test_real_account_is_explicitly_forbidden(self):
        self.assertIn("ACCOUNT_TRADE_MODE_REAL", self.text)
        self.assertIn("REAL account is forbidden", self.text)

    def test_demo_and_contest_are_only_accepted_modes(self):
        self.assertIn("ACCOUNT_TRADE_MODE_DEMO", self.text)
        self.assertIn("ACCOUNT_TRADE_MODE_CONTEST", self.text)

    def test_evidence_never_claims_live_authority(self):
        self.assertIn('"broker_mutation","false"', self.text)
        self.assertIn('"live_risk_ready","false"', self.text)
        self.assertIn('"live_execution_enabled","false"', self.text)

    def test_no_trade_mutation_api_is_present(self):
        forbidden = (
            "ordersend",
            "order_send",
            "ctrade",
            "buy(",
            "sell(",
            "positionclose",
        )
        for marker in forbidden:
            with self.subTest(marker=marker):
                self.assertNotIn(marker, self.lower)


if __name__ == "__main__":
    unittest.main()
