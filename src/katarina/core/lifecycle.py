from __future__ import annotations

from enum import Enum


class LifecycleError(RuntimeError):
    pass


class LifecycleState(str, Enum):
    CREATED = "created"
    INITIALIZING = "initializing"
    STARTING = "starting"
    RECOVERING = "recovering"
    READY = "ready"
    RUNNING = "running"
    DEGRADING = "degrading"
    DEGRADED = "degraded"
    RESUMING = "resuming"
    STOPPING = "stopping"
    STOPPED = "stopped"
    FAULTING = "faulting"
    FAULTED = "faulted"
    DISPOSING = "disposing"
    DISPOSED = "disposed"


_ALLOWED: dict[LifecycleState, frozenset[LifecycleState]] = {
    LifecycleState.CREATED: frozenset(
        {LifecycleState.INITIALIZING, LifecycleState.FAULTING, LifecycleState.DISPOSING}
    ),
    LifecycleState.INITIALIZING: frozenset({LifecycleState.STARTING, LifecycleState.FAULTING}),
    LifecycleState.STARTING: frozenset(
        {LifecycleState.RECOVERING, LifecycleState.RUNNING, LifecycleState.FAULTING}
    ),
    LifecycleState.RECOVERING: frozenset(
        {LifecycleState.READY, LifecycleState.STOPPING, LifecycleState.FAULTING}
    ),
    LifecycleState.READY: frozenset(
        {
            LifecycleState.STARTING,
            LifecycleState.RECOVERING,
            LifecycleState.STOPPING,
            LifecycleState.FAULTING,
            LifecycleState.DISPOSING,
        }
    ),
    LifecycleState.RUNNING: frozenset(
        {LifecycleState.DEGRADING, LifecycleState.STOPPING, LifecycleState.FAULTING}
    ),
    LifecycleState.DEGRADING: frozenset({LifecycleState.DEGRADED, LifecycleState.FAULTING}),
    LifecycleState.DEGRADED: frozenset(
        {LifecycleState.RESUMING, LifecycleState.STOPPING, LifecycleState.FAULTING}
    ),
    LifecycleState.RESUMING: frozenset({LifecycleState.RUNNING, LifecycleState.FAULTING}),
    LifecycleState.STOPPING: frozenset({LifecycleState.STOPPED, LifecycleState.FAULTING}),
    LifecycleState.STOPPED: frozenset({LifecycleState.DISPOSING, LifecycleState.FAULTING}),
    LifecycleState.FAULTING: frozenset({LifecycleState.FAULTED}),
    LifecycleState.FAULTED: frozenset({LifecycleState.DISPOSING}),
    LifecycleState.DISPOSING: frozenset({LifecycleState.DISPOSED, LifecycleState.FAULTING}),
    LifecycleState.DISPOSED: frozenset(),
}


class LifecycleMachine:
    def __init__(self) -> None:
        self._state = LifecycleState.CREATED

    @property
    def state(self) -> LifecycleState:
        return self._state

    def can_transition(self, target: LifecycleState) -> bool:
        return target in _ALLOWED[self._state]

    def transition(self, target: LifecycleState) -> LifecycleState:
        if not self.can_transition(target):
            raise LifecycleError(
                f"invalid lifecycle transition: {self._state.value} -> {target.value}"
            )
        self._state = target
        return self._state
