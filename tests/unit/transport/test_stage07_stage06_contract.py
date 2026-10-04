from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
STAGE06 = ROOT / "mt5" / "Experts" / "KatarinaBridgeEA.mq5"
STAGE07 = ROOT / "mt5" / "Experts" / "KatarinaBridgeStage07EA.mq5"


def _text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _define(source: str, name: str) -> str:
    match = re.search(
        rf"^#define\s+{re.escape(name)}\s+([^\r\n]+)$",
        source,
        re.MULTILINE,
    )
    if not match:
        raise AssertionError(f"missing define {name}")
    return match.group(1).strip()


class Stage07Stage06ContractSyncTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.stage06 = _text(STAGE06)
        cls.stage07 = _text(STAGE07)

    def test_stage07_preserves_stage06_timer_and_queue_safety_budget(self) -> None:
        names = (
            "KAT_STAGE06_TIMER_MS",
            "KAT_STAGE06_CRITICAL_QUEUE_CAPACITY",
            "KAT_STAGE06_DRAIN_BUDGET",
            "KAT_STAGE06_TIMER_BUDGET_US",
            "KAT_STAGE06_SNAPSHOT_START_MIN_US",
            "KAT_STAGE06_SNAPSHOT_MIN_INTERVAL_MS",
            "KAT_STAGE06_HEALTH_INTERVAL_MS",
            "KAT_STAGE06_INSTANCE_LEASE_SECONDS",
        )
        for name in names:
            self.assertEqual(
                _define(self.stage07, name),
                _define(self.stage06, name),
                name,
            )

    def test_stage07_preserves_execution_disarmed_invariant(self) -> None:
        self.assertIn("g_bridge_state.SetExecutionArmed(false);", self.stage07)
        self.assertNotIn("g_bridge_state.SetExecutionArmed(true);", self.stage07)

    def test_stage07_bridge_has_no_broker_order_submission(self) -> None:
        forbidden = (
            "OrderSend(",
            "OrderSendAsync(",
            "CTrade ",
            ".Buy(",
            ".Sell(",
            ".BuyLimit(",
            ".SellLimit(",
            ".BuyStop(",
            ".SellStop(",
        )
        for token in forbidden:
            self.assertNotIn(token, self.stage07, token)

    def test_stage07_uses_terminal_native_chart_symbol(self) -> None:
        self.assertIn("g_symbol_registry.AddApproved(_Symbol)", self.stage07)
        self.assertIn("SymbolInfoTick(_Symbol", self.stage07)
        self.assertIn("KatReadSessionState(_Symbol", self.stage07)

        # Runtime bridge source must not normalize or hard-code broker symbol
        # suffix/prefix conventions at the transport boundary.
        forbidden_runtime_symbols = (
            '"XAUUSD"',
            '"XAUUSD.vx"',
            '"XAUUSD.a"',
            '"EURUSD"',
            '"GOLD"',
        )
        for token in forbidden_runtime_symbols:
            self.assertNotIn(token, self.stage07, token)

    def test_stage07_extends_transport_without_mutating_stage06_null_transport(self) -> None:
        self.assertIn("CKatNullTransport    g_transport;", self.stage06)
        self.assertIn("CKatStage07Transport g_transport;", self.stage07)
        self.assertIn(
            "#include <Katarina/Stage07/BridgeTransport.mqh>",
            self.stage07,
        )

    def test_stage07_keeps_recovery_separate_from_live_risk(self) -> None:
        self.assertIn("g_bridge_state.EnterRecovering();", self.stage07)
        self.assertIn("g_bridge_state.SetExecutionArmed(false);", self.stage07)


if __name__ == "__main__":
    unittest.main()
