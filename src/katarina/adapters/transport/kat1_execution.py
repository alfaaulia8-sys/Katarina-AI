from __future__ import annotations

from dataclasses import dataclass
from hashlib import sha256
from math import isfinite

from katarina.adapters.transport.kat1_codec import Kat1Codec
from katarina.engines.execution import ExecutionIntent


OPEN_INTENT=300


@dataclass(frozen=True, slots=True)
class Kat1ExecutionBinding:
    account_id_hex: str
    stream_id: int
    boot_id: int
    account_revision: int
    instrument_id: int
    spec_revision: int
    price_scale: int
    volume_scale: int


class Kat1OpenIntentEncoder:
    """Encodes one symbol-specific ExecutionIntent into frozen KAT1 OPEN_INTENT."""

    def __init__(self,codec:Kat1Codec):
        self.codec=codec

    @staticmethod
    def _id128(value:str)->bytes:
        try:
            raw=bytes.fromhex(value)
        except ValueError:
            raw=b""
        if len(raw)==16:
            return raw
        return sha256(value.encode()).digest()[:16]

    @staticmethod
    def _scaled(value:float,scale:int)->int:
        if not isfinite(value):
            raise ValueError("non_finite_execution_value")
        return int(round(value*(10**int(scale))))

    def encode(
        self,
        intent:ExecutionIntent,
        binding:Kat1ExecutionBinding,
        *,
        sequence:int,
        source_time_ns:int,
        snapshot_id:str,
        submit_expiry_ns:int,
        risk_policy_version:int=1,
        max_deviation_points:int=0,
    )->bytes:
        if intent.instrument_id != binding.instrument_id:
            raise ValueError("instrument_binding_mismatch")
        if intent.spec_revision not in {0,binding.spec_revision}:
            raise ValueError("spec_revision_mismatch")
        if intent.side not in {"BUY","SELL"}:
            raise ValueError("invalid_side")
        if intent.volume<=0 or intent.stop_loss<=0:
            raise ValueError("invalid_execution_intent")

        values={
            "account_id":bytes.fromhex(binding.account_id_hex),
            "execution_intent_id":self._id128(intent.intent_id),
            "order_id":self._id128("order:"+intent.intent_id),
            "snapshot_id":self._id128(snapshot_id),
            "decision_id":self._id128(intent.decision_id),
            "risk_decision_id":self._id128(intent.risk_id),
            "risk_binding_hash":sha256((intent.risk_id+"|"+intent.intent_id).encode()).digest(),
            "instrument_id":binding.instrument_id,
            "spec_revision":binding.spec_revision,
            "approved_account_revision":binding.account_revision,
            "approved_position_revision":0,
            "submit_expiry_ns":submit_expiry_ns,
            "risk_policy_version":risk_policy_version,
            "reserved_common":0,
            "pending_valid_until_ns":0,
            "volume_units":self._scaled(intent.volume,binding.volume_scale),
            "requested_price_units":0,
            "sl_units":self._scaled(intent.stop_loss,binding.price_scale),
            "tp_units":0 if intent.take_profit is None else self._scaled(intent.take_profit,binding.price_scale),
            "expected_net_volume_after_units":0,
            "max_deviation_points":max_deviation_points,
            "side":1 if intent.side=="BUY" else 2,
            "entry_type":1,
            "expected_position_effect":0,
            "netting_guard":0,
            "time_in_force":0,
            "filling_policy":0,
            "expected_net_side":0,
            "reserved0":0,
            "presence_flags":1 if intent.take_profit is not None else 0,
        }
        return self.codec.encode(
            message_type=OPEN_INTENT,
            schema_version=1,
            sequence=sequence,
            source_time_ns=source_time_ns,
            stream_id=binding.stream_id,
            boot_id=binding.boot_id,
            values=values,
        )
