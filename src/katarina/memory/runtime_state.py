from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from katarina.memory.store import MemoryStore


EVENT_TYPE="runtime_state_snapshot_v1"


@dataclass(frozen=True, slots=True)
class RuntimeRecoverySnapshot:
    account_risk: dict[str,Any]
    rr_peak: dict[str,float]
    execution_recovery: dict[str,Any]
    broker_risk: dict[str,Any]
    capital: dict[str,Any]


class RuntimeStatePersistence:
    """Append-only Stage-10 persistence for restart-critical runtime state."""

    def __init__(self,store:MemoryStore):
        self.store=store

    def save_components(self,*,account_risk,rr_tracker,execution_recovery,broker_risk,capital=None)->None:
        payload={
            "account_risk":account_risk.snapshot_state(),
            "rr_peak":rr_tracker.snapshot(),
            "execution_recovery":execution_recovery.snapshot_state(),
            "broker_risk":broker_risk.snapshot_state(),
            "capital":{} if capital is None else capital.snapshot_state(),
        }
        event_id=MemoryStore.deterministic_id(EVENT_TYPE,payload)
        self.store.append_operational_event(EVENT_TYPE,payload,event_id=event_id)

    def load_latest(self)->RuntimeRecoverySnapshot|None:
        row=self.store.load_latest_operational_event(EVENT_TYPE)
        if row is None:return None
        p=row["payload"]
        return RuntimeRecoverySnapshot(
            dict(p.get("account_risk",{})),
            {str(k):float(v) for k,v in p.get("rr_peak",{}).items()},
            dict(p.get("execution_recovery",{})),
            dict(p.get("broker_risk",{})),
            dict(p.get("capital",{})),
        )

    def restore_components(self,*,account_risk,rr_tracker,execution_recovery,broker_risk,capital=None)->bool:
        snap=self.load_latest()
        if snap is None:return False
        account_risk.restore_state(snap.account_risk)
        rr_tracker.restore(snap.rr_peak)
        execution_recovery.restore_state(snap.execution_recovery)
        broker_risk.restore_state(snap.broker_risk)
        if capital is not None and snap.capital:
            capital.restore_state(snap.capital)
        return True
