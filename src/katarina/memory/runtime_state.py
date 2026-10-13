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
        # Reject incompatible 30% reserve / old DD limits BEFORE mutating
        # any live runtime component. A signed migration must be reviewed
        # separately; never silently unlock protected balance on restart.
        if capital is not None and snap.capital:
            old_reserve=float(snap.capital["reserve_fraction"])
            old_growth=float(snap.capital["growth_multiple"])
            if (abs(old_reserve-capital.reserve_fraction)>1e-12
                    or abs(old_growth-capital.growth_multiple)>1e-12):
                raise ValueError("legacy_capital_snapshot_requires_approved_migration")
        if snap.account_risk:
            risk_limits=snap.account_risk
            if abs(float(risk_limits.get("max_open_risk",0))-account_risk.max_open_risk)>1e-12:
                raise ValueError("incompatible_open_risk_snapshot")
            for label,tracker in (("daily",account_risk.daily),
                                  ("total",account_risk.total)):
                section=risk_limits.get(label,{})
                if abs(float(section.get("limit",-1))-tracker.limit)>1e-12:
                    raise ValueError("legacy_drawdown_snapshot_requires_review")
        if any(not isinstance(item,dict) or item.get("origin")!="KATARINA"
               for item in snap.execution_recovery.values()):
            raise ValueError("untrusted_legacy_recovery_state")
        account_risk.restore_state(snap.account_risk)
        rr_tracker.restore(snap.rr_peak)
        execution_recovery.restore_state(snap.execution_recovery)
        broker_risk.restore_state(snap.broker_risk)
        if capital is not None and snap.capital:
            capital.restore_state(snap.capital)
        return True
