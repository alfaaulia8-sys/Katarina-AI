from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "mt5" / "Tests" / "KatarinaStage36LivePreflight.mq5"


class Stage36LivePreflightStaticTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.text = SCRIPT.read_text(encoding="utf-8")
        cls.lower = cls.text.lower()

    def test_real_account_is_required_for_live_preflight(self):
        self.assertIn("ACCOUNT_TRADE_MODE_REAL", self.text)
        self.assertIn("REAL account required", self.text)
        self.assertNotIn("REAL account is forbidden", self.text)

    def test_terminal_and_trade_permissions_are_checked(self):
        self.assertIn("TERMINAL_CONNECTED", self.text)
        self.assertIn("TERMINAL_TRADE_ALLOWED", self.text)
        self.assertIn("account.trade_allowed", self.text)
        self.assertIn("account.expert_trade_allowed", self.text)

    def test_preflight_never_grants_live_authority(self):
        self.assertIn('"broker_mutation","false"', self.text)
        self.assertIn('"live_risk_ready","false"', self.text)
        self.assertIn('"live_execution_authority","false"', self.text)

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
