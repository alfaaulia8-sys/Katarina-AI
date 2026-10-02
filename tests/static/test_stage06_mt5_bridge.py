import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
EA = ROOT / "mt5" / "Experts" / "KatarinaBridgeEA.mq5"
INCLUDE = ROOT / "mt5" / "Include" / "Katarina"


class Stage06Mt5StaticTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.ea = EA.read_text(encoding="utf-8")
        cls.all_mt5 = cls.ea + "\n" + "\n".join(
            path.read_text(encoding="utf-8")
            for path in sorted(INCLUDE.glob("*.mqh"))
        )

    def test_no_discretionary_strategy_indicators(self):
        forbidden = (
            "iRSI(",
            "iMA(",
            "iMACD(",
            "iStochastic(",
            "iBands(",
            "iADX(",
        )
        for token in forbidden:
            self.assertNotIn(token, self.all_mt5)

    def test_no_live_submission_path_in_stage06(self):
        self.assertNotIn("OrderSend(", self.all_mt5)
        self.assertNotIn("OrderSendAsync(", self.all_mt5)
        self.assertIn("SetExecutionArmed(false)", self.ea)

    def test_no_concrete_network_transport(self):
        for token in ("WebRequest(", "SocketCreate(", "Zmq", "ZeroMQ"):
            self.assertNotIn(token, self.all_mt5)

    def test_fast_handlers_exist(self):
        self.assertIn("void OnTick(void)", self.ea)
        self.assertIn("void OnTradeTransaction(", self.ea)
        self.assertIn("g_latest_tick.Capture(captured)", self.ea)
        self.assertIn("g_trade_events.Push(captured)", self.ea)

    def test_trade_handler_defers_heavy_reason_lookup(self):
        handler = self.ea.split("void OnTradeTransaction(", 1)[1].split(
            "void OnTimer(void)", 1
        )[0]
        self.assertNotIn("HistorySelect(", handler)
        self.assertNotIn("HistoryDeal", handler)
        self.assertNotIn("KatEnrichReasonEvidence", handler)

    def test_fail_closed_integrity_and_duplicate_guard(self):
        self.assertIn(
            "KAT_BLOCK_CRITICAL_QUEUE_OVERFLOW",
            self.all_mt5,
        )
        self.assertIn("g_instance_guard.Acquire(", self.ea)
        self.assertIn("g_instance_guard.Refresh()", self.ea)
        self.assertIn("g_instance_guard.Release()", self.ea)

    def test_complete_snapshot_source_present(self):
        source = (
            INCLUDE / "NativeSnapshot.mqh"
        ).read_text(encoding="utf-8")
        self.assertIn("PositionsTotal()", source)
        self.assertIn("PositionGetTicket(i)", source)
        self.assertIn("OrdersTotal()", source)
        self.assertIn("OrderGetTicket(i)", source)
        self.assertIn("BuildStable", source)

    def test_standard_cent_uses_native_facts(self):
        source = (
            INCLUDE / "NativeFacts.mqh"
        ).read_text(encoding="utf-8")
        self.assertIn("ACCOUNT_CURRENCY_DIGITS", source)
        self.assertIn("SYMBOL_TRADE_TICK_VALUE", source)
        self.assertIn("SYMBOL_TRADE_CONTRACT_SIZE", source)
        self.assertNotIn("/100", source)
        self.assertNotIn("*100", source)


if __name__ == "__main__":
    unittest.main()
