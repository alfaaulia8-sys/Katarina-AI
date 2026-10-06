import unittest
from pathlib import Path

from katarina.adapters.transport.kat1_codec import Kat1Codec, SchemaCatalog
from katarina.adapters.transport.kat1_execution import Kat1ExecutionBinding, Kat1OpenIntentEncoder
from katarina.engines.execution import ExecutionIntent


ROOT=Path(__file__).resolve().parents[3]
SCHEMA=ROOT/"protocol"/"kat1_message_schemas_v1.json"


class Kat1MultiSymbolExecutionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.codec=Kat1Codec(SchemaCatalog.from_path(SCHEMA))
        cls.encoder=Kat1OpenIntentEncoder(cls.codec)

    def _intent(self,symbol,iid,spec):
        return ExecutionIntent(
            intent_id="intent-"+symbol,
            side="BUY",
            symbol=symbol,
            volume=.10,
            stop_loss=1.2345,
            take_profit=1.2500,
            decision_id="decision-"+symbol,
            risk_id="risk-"+symbol,
            instrument_id=iid,
            spec_revision=spec,
        )

    def _binding(self,iid,spec):
        return Kat1ExecutionBinding(
            account_id_hex="11"*16,
            stream_id=77,
            boot_id=88,
            account_revision=10,
            instrument_id=iid,
            spec_revision=spec,
            price_scale=5,
            volume_scale=2,
        )

    def test_each_symbol_encodes_its_own_instrument_id(self):
        a=self.encoder.encode(self._intent("EURUSD",101,7),self._binding(101,7),sequence=1,source_time_ns=1,snapshot_id="s",submit_expiry_ns=100)
        b=self.encoder.encode(self._intent("GBPUSD",202,9),self._binding(202,9),sequence=2,source_time_ns=2,snapshot_id="s",submit_expiry_ns=100)
        fa=self.codec.decode(a); fb=self.codec.decode(b)
        self.assertEqual(fa.header.message_type,300)
        self.assertEqual(fa.values["instrument_id"],101)
        self.assertEqual(fa.values["spec_revision"],7)
        self.assertEqual(fb.values["instrument_id"],202)
        self.assertEqual(fb.values["spec_revision"],9)

    def test_instrument_mismatch_fails_closed(self):
        with self.assertRaises(ValueError):
            self.encoder.encode(self._intent("EURUSD",101,7),self._binding(202,7),sequence=1,source_time_ns=1,snapshot_id="s",submit_expiry_ns=100)


if __name__=="__main__": unittest.main()
