import unittest
from pathlib import Path


ROOT=Path(__file__).resolve().parents[2]
CATALOG=ROOT/"mt5"/"Include"/"Katarina"/"MultiSymbolCatalog.mqh"
SOURCE=ROOT/"mt5"/"Include"/"Katarina"/"MultiSymbolMarketSource.mqh"
GATEWAY=ROOT/"mt5"/"Include"/"Katarina"/"MultiSymbolExecutionGateway.mqh"
INTENTS=ROOT/"mt5"/"Include"/"Katarina"/"Stage07"/"Kat1ExecutionIntents.mqh"
EA=ROOT/"mt5"/"Experts"/"KatarinaBridgeMultiSymbolExtensionEA.mq5"


class MultiSymbolBridgeExtensionStaticTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog=CATALOG.read_text(encoding="utf-8")
        cls.source=SOURCE.read_text(encoding="utf-8")
        cls.gateway=GATEWAY.read_text(encoding="utf-8")
        cls.intents=INTENTS.read_text(encoding="utf-8")
        cls.ea=EA.read_text(encoding="utf-8")

    def test_uses_named_symbol_market_data_not_fake_ontick_scope(self):
        self.assertIn("SymbolInfoTick(symbol",self.catalog)
        self.assertIn("SymbolIsSynchronized(symbol)",self.catalog)
        self.assertIn("EventSetMillisecondTimer(50)",self.ea)
        self.assertIn("Chart OnTick is not used as proof",self.ea)

    def test_bounded_polling(self):
        self.assertIn("InpPollPerTimer",self.ea)
        self.assertIn("MathMin(InpPollPerTimer,32)",self.ea)
        self.assertIn("PollNext",self.source)

    def test_execution_default_is_disarmed(self):
        self.assertIn("InpExecutionArmed=false",self.ea)
        self.assertIn("if(!execution_armed)",self.gateway)

    def test_ordercheck_precedes_async_send(self):
        self.assertIn("OrderCheck(",self.gateway)
        self.assertIn("OrderSendAsync(",self.gateway)
        self.assertLess(self.gateway.index("OrderCheck("),self.gateway.index("OrderSendAsync("))

    def test_open_intent_binds_instrument_spec_account_revision_and_expiry(self):
        for token in ("instrument_id","spec_revision","approved_account_revision","submit_expiry_ns"):
            self.assertIn(token,self.intents)
            self.assertIn(token,self.gateway)

    def test_no_discretionary_indicators_in_bridge_extension(self):
        combined=self.catalog+self.source+self.gateway+self.ea
        for token in ("iRSI(","iMA(","iMACD(","iStochastic(","iBands(","iADX("):
            self.assertNotIn(token,combined)

    def test_instrument_identity_is_stable_and_spec_revision_persistent(self):
        self.assertIn("KatStableInstrumentId",self.catalog)
        self.assertIn("KAT1/instrument/v1|",self.catalog)
        self.assertIn("FindInstrument",self.catalog)
        self.assertIn("KAT_MS_REV_",self.catalog)
        self.assertIn("KAT_MS_FP_",self.catalog)
        self.assertIn("KatPersistentSpecRevision",self.catalog)


if __name__=="__main__": unittest.main()
