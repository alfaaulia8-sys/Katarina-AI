from __future__ import annotations

import importlib
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Mapping

from katarina.body.contracts import StageResult, StageSpec
from katarina.body.registry import BodyRegistry
from katarina.policies import DEFAULT_RISK_POLICY, DEFAULT_STRATEGY_POLICY


@dataclass(frozen=True, slots=True)
class BodyRuntimeSnapshot:
    loaded_stages: tuple[int, ...]
    policy_pending_stages: tuple[int, ...]
    windows_pending_stages: tuple[int, ...]
    strategy_policy_finalized: bool
    risk_policy_finalized: bool
    live_risk_ready: bool
    live_execution_enabled: bool


class KatarinaBodyRuntime:
    """Local Stage 11-40 body runtime.

    This runtime wires the body components into one deterministic registry.
    It deliberately does not own final strategy/risk policy and cannot grant
    live authority while those policies and external validations are pending.
    """

    def __init__(self, repo_root: str | Path) -> None:
        self.repo_root = Path(repo_root).resolve()
        self._specs = BodyRegistry(self.repo_root).validate()
        self._components: dict[int, Any] = {}
        for spec in self._specs:
            module = importlib.import_module(spec.implementation_module)
            self._components[spec.stage] = module.Component()

    @property
    def specs(self) -> tuple[StageSpec, ...]:
        return self._specs

    def component(self, stage: int) -> Any:
        try:
            return self._components[stage]
        except KeyError as exc:
            raise KeyError(f"body stage not loaded: {stage}") from exc

    def process(
        self,
        stage: int,
        payload: Mapping[str, Any] | None = None,
    ) -> StageResult:
        return self.component(stage).process(payload)

    def snapshot(self) -> BodyRuntimeSnapshot:
        return BodyRuntimeSnapshot(
            loaded_stages=tuple(spec.stage for spec in self._specs),
            policy_pending_stages=tuple(
                spec.stage for spec in self._specs if spec.policy_pending
            ),
            windows_pending_stages=tuple(
                spec.stage for spec in self._specs if spec.windows_required
            ),
            strategy_policy_finalized=DEFAULT_STRATEGY_POLICY.finalized,
            risk_policy_finalized=DEFAULT_RISK_POLICY.finalized,
            live_risk_ready=False,
            live_execution_enabled=False,
        )

    def dependency_order_is_valid(self) -> bool:
        seen = set(range(1, 11))
        for spec in self._specs:
            if any(dep not in seen for dep in spec.dependencies):
                return False
            seen.add(spec.stage)
        return True

    def assert_fail_closed(self) -> None:
        snapshot = self.snapshot()
        if snapshot.live_risk_ready or snapshot.live_execution_enabled:
            raise RuntimeError("KATARINA body unexpectedly gained live authority")
        for stage, component in self._components.items():
            if getattr(component, "live_execution_authority", False):
                raise RuntimeError(
                    f"Stage {stage} unexpectedly exposes live execution authority"
                )


__all__ = ("BodyRuntimeSnapshot", "KatarinaBodyRuntime")
