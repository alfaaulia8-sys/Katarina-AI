from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from typing import Any, Mapping


class BodyStatus(str, Enum):
    BODY_FRAMEWORK_COMPLETE = "body_framework_complete"
    POLICY_PENDING = "policy_pending"
    WINDOWS_VALIDATION_PENDING = "windows_validation_pending"


class AuthorityClass(str, Enum):
    ANALYTIC = "analytic"
    ADVISORY = "advisory"
    GOVERNANCE = "governance"
    EXECUTION_PATH = "execution_path"
    OBSERVABILITY = "observability"


@dataclass(frozen=True, slots=True)
class StageSpec:
    stage: int
    name: str
    dependencies: tuple[int, ...]
    authority: AuthorityClass
    policy_pending: bool
    windows_required: bool
    implementation_module: str
    reference_doc: str
    status: BodyStatus = BodyStatus.BODY_FRAMEWORK_COMPLETE
    live_risk_ready: bool = False
    live_execution_authority: bool = False

    def __post_init__(self) -> None:
        if self.stage < 10 or self.stage > 40:
            raise ValueError("body stage must be between 10 and 40")
        if not self.name:
            raise ValueError("stage name must be non-empty")
        if any(dep <= 0 or dep >= self.stage for dep in self.dependencies):
            raise ValueError(
                f"stage {self.stage} dependencies must reference earlier stages"
            )
        if self.live_risk_ready or self.live_execution_authority:
            raise ValueError(
                "body build must remain fail-closed until final policy and "
                "governed live validation are explicitly completed"
            )


@dataclass(frozen=True, slots=True)
class StageResult:
    stage: int
    name: str
    accepted: bool
    reason: str
    payload: Mapping[str, Any]
    live_risk_ready: bool = False
    live_execution_authority: bool = False

    def __post_init__(self) -> None:
        if self.live_risk_ready or self.live_execution_authority:
            raise ValueError("body-stage results cannot grant live authority")


@dataclass(frozen=True, slots=True)
class PolicyState:
    strategy_finalized: bool = False
    risk_finalized: bool = False
    live_validation_approved: bool = False

    @property
    def live_policy_ready(self) -> bool:
        return (
            self.strategy_finalized
            and self.risk_finalized
            and self.live_validation_approved
        )


__all__ = (
    "AuthorityClass",
    "BodyStatus",
    "PolicyState",
    "StageResult",
    "StageSpec",
)
