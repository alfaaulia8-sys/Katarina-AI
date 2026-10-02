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
        for token in ("WebRequest(", "SocketCreate(", "#include <Zmq", "zmq_"):
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

    def test_local_capture_id_is_not_named_wire_sequence(self):
        buffer_source = (
            INCLUDE / "EventBuffer.mqh"
        ).read_text(encoding="utf-8")
        self.assertIn("local_capture_id", buffer_source)
        self.assertNotIn("capture_sequence", buffer_source)

    def test_request_result_fields_are_transaction_type_guarded(self):
        source = (
            INCLUDE / "EventBuffer.mqh"
        ).read_text(encoding="utf-8")
        self.assertIn(
            "trans.type==TRADE_TRANSACTION_REQUEST",
            source,
        )
        self.assertIn("request_result_valid", source)

    def test_realtime_execution_scope_is_chart_symbol_only(self):
        self.assertNotIn("InpApprovedSymbols", self.ea)
        self.assertIn(
            "g_symbol_registry.AddApproved(_Symbol)",
            self.ea,
        )

    def test_stream_id_uses_two_exact_uint32_halves(self):
        source = (
            INCLUDE / "BridgeIdentity.mqh"
        ).read_text(encoding="utf-8")
        self.assertIn("KAT_STREAM_HI_", source)
        self.assertIn("KAT_STREAM_LO_", source)
        self.assertIn("hi<<32", source)

    def test_duplicate_guard_is_server_and_login_scoped(self):
        source = (
            INCLUDE / "InstanceGuard.mqh"
        ).read_text(encoding="utf-8")
        self.assertIn("const string server", source)
        self.assertIn("GlobalVariableSetOnCondition", source)
        self.assertIn("GlobalVariableTemp", source)

    def test_mql_self_test_compiles_every_include_module(self):
        self_test = (
            ROOT / "mt5" / "Tests" / "KatarinaStage06SelfTest.mq5"
        ).read_text(encoding="utf-8")
        for path in sorted(INCLUDE.glob("*.mqh")):
            self.assertIn(
                f"<Katarina/{path.name}>",
                self_test,
            )


if __name__ == "__main__":
    unittest.main()
