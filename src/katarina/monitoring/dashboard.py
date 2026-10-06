from __future__ import annotations
from dataclasses import dataclass,asdict
import json
from typing import Any,Mapping

@dataclass(frozen=True, slots=True)
class DashboardSnapshot:
    lifecycle: str
    health: str
    execution_armed: bool
    equity: float
    open_risk: float
    regime: str
    decision: str
    model_version: str
    data: Mapping[str,Any]

class Dashboard:
    def render_json(self, snapshot: DashboardSnapshot) -> str:
        return json.dumps(asdict(snapshot),sort_keys=True,separators=(",",":"))

    def render_operational_json(self, snapshot) -> str:
        """Render the extended OperationalDashboardSnapshot without coupling Stage 32 to engines."""
        return json.dumps(asdict(snapshot),sort_keys=True,separators=(",",":"))
