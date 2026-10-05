from __future__ import annotations

from collections.abc import Mapping
from typing import Any

from katarina.body.contracts import AuthorityClass, StageResult, StageSpec


class PassiveStageComponent:
    """Fail-closed Stage 11-40 body component.

    This is a stable integration shell, not trading edge. Analytic and
    observability shells may accept structured input for plumbing tests.
    Policy-pending and execution-path shells are explicitly blocked until
    their governed implementation/policy is finalized.
    """

    SPEC: StageSpec

    def __init__(self) -> None:
        if not hasattr(self, "SPEC"):
            raise TypeError("component must define SPEC")

    @property
    def stage(self) -> int:
        return self.SPEC.stage

    @property
    def name(self) -> str:
        return self.SPEC.name

    @property
    def live_execution_authority(self) -> bool:
        return False

    def process(self, payload: Mapping[str, Any] | None = None) -> StageResult:
        data = dict(payload or {})

        if self.SPEC.policy_pending:
            return StageResult(
                stage=self.SPEC.stage,
                name=self.SPEC.name,
                accepted=False,
                reason="final user-owned strategy/risk policy is pending",
                payload=data,
            )

        if self.SPEC.authority is AuthorityClass.EXECUTION_PATH:
            return StageResult(
                stage=self.SPEC.stage,
                name=self.SPEC.name,
                accepted=False,
                reason="execution-path body exists but mutation is disabled",
                payload=data,
            )

        return StageResult(
            stage=self.SPEC.stage,
            name=self.SPEC.name,
            accepted=True,
            reason="body framework available; no live authority granted",
            payload=data,
        )


__all__ = ("PassiveStageComponent",)
