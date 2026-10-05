from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "stage35" / "Run-KatarinaStage35Tester.ps1"


class Stage35TesterRunnerStaticTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.text = SCRIPT.read_text(encoding="utf-8")

    def test_headless_config_launch_is_present(self):
        self.assertIn('"/config:$IniPath"', self.text)
        self.assertIn("Start-Process -FilePath $TerminalPath", self.text)

    def test_real_ticks_is_default_and_governed(self):
        self.assertIn("[int]$Model = 4", self.text)
        self.assertIn('"Model=$Model"', self.text)
        self.assertIn("model_real_ticks = ($Model -eq 4)", self.text)

    def test_single_backtest_and_terminal_shutdown_are_forced(self):
        self.assertIn('"Optimization=0"', self.text)
        self.assertIn('"ShutdownTerminal=1"', self.text)
        self.assertIn('"Visual=0"', self.text)

    def test_evidence_remains_fail_closed_for_live_authority(self):
        self.assertIn("live_risk_ready = $false", self.text)
        self.assertIn("live_execution_enabled = $false", self.text)

    def test_report_hash_and_timeout_are_recorded(self):
        self.assertIn("report_sha256", self.text)
        self.assertIn("timed_out", self.text)
        self.assertIn("TimeoutSeconds", self.text)

    def test_runner_contains_no_live_trading_credentials_or_order_send(self):
        lower = self.text.lower()
        forbidden = (
            "order_send",
            "ordersend",
            "password=",
            "login=",
            "ctrade",
            "positionclose",
        )
        for marker in forbidden:
            with self.subTest(marker=marker):
                self.assertNotIn(marker, lower)


if __name__ == "__main__":
    unittest.main()
