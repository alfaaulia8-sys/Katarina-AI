from __future__ import annotations
from dataclasses import dataclass, asdict
from enum import Enum
from hashlib import sha256
import json
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from katarina.engines.position import RRManagementPlan

class IntentState(str, Enum):
    CREATED="CREATED"; VALIDATED="VALIDATED"; SUBMITTING="SUBMITTING"; UNKNOWN="UNKNOWN"; REJECTED="REJECTED"

@dataclass(frozen=True, slots=True)
class ExecutionIntent:
    intent_id: str
    side: str
    symbol: str
    volume: float
    stop_loss: float
    take_profit: float|None
    decision_id: str
    risk_id: str
    instrument_id: int = 0
    spec_revision: int = 0

@dataclass(frozen=True, slots=True)
class ExecutionPreflight:
    allowed: bool
    reason: str

@dataclass(frozen=True, slots=True)
class PositionManagementCommand:
    """Abstract command matching frozen KAT1 management intents."""
    message_type: str
    position_id: str
    reduce_volume: float = 0.0
    new_stop: float|None = None

class ExecutionEngine:
    def __init__(self):
        self._known: dict[str,str]={}

    @staticmethod
    def deterministic_id(payload: dict) -> str:
        return sha256(json.dumps(payload,sort_keys=True,separators=(",",":")).encode()).hexdigest()

    def preflight(self, intent: ExecutionIntent, *, execution_armed: bool, fresh: bool, reconciled: bool, spread_ok: bool) -> ExecutionPreflight:
        if not execution_armed: return ExecutionPreflight(False,"execution_disarmed")
        if not fresh or not reconciled: return ExecutionPreflight(False,"stale_or_unreconciled")
        if not spread_ok: return ExecutionPreflight(False,"spread_guard")
        if intent.volume<=0 or intent.stop_loss<=0 or intent.side not in {"BUY","SELL"}: return ExecutionPreflight(False,"invalid_intent")
        if not intent.decision_id or not intent.risk_id: return ExecutionPreflight(False,"missing_lineage")
        return ExecutionPreflight(True,"ok")

    def reserve(self, intent: ExecutionIntent) -> bool:
        fingerprint=self.deterministic_id(asdict(intent))
        prior=self._known.get(intent.intent_id)
        if prior is not None and prior!=fingerprint: raise RuntimeError("idempotency_conflict")
        inserted=prior is None; self._known[intent.intent_id]=fingerprint; return inserted

    @staticmethod
    def management_commands(plan: "RRManagementPlan") -> tuple[PositionManagementCommand,...]:
        commands=[]
        if plan.reduce_required:
            commands.append(PositionManagementCommand(
                "REDUCE_INTENT",plan.position_id,reduce_volume=plan.partial_close_volume
            ))
        if plan.modify_sl_required and plan.new_stop is not None:
            commands.append(PositionManagementCommand(
                "MODIFY_PROTECTION_INTENT",plan.position_id,new_stop=plan.new_stop
            ))
        return tuple(commands)
