from __future__ import annotations

import asyncio
from dataclasses import dataclass

from katarina.contracts.runtime import EventEnvelope, RuntimeMode
from katarina.core.component import (
    ComponentPhase,
    ManagedComponent,
    resolve_component_order,
)
from katarina.core.lifecycle import LifecycleMachine, LifecycleState
from katarina.core.message_bus import EventBus, Subscription
from katarina.core.queue import CriticalIngressOverflow, IngressQueue
from katarina.core.readiness import ReadinessGate, ReadinessSignal
from katarina.core.state import CoreStatus, RuntimeStateStore


class OrchestratorError(RuntimeError):
    pass


class OrchestratorFault(OrchestratorError):
    pass


@dataclass(frozen=True, slots=True)
class OrchestratorConfig:
    mode: RuntimeMode
    ingress_capacity: int


class KatarinaOrchestrator:
    """Central lifecycle and deterministic event coordinator.

    It does not contain trading edge, risk thresholds, protocol decoding,
    broker I/O, or persistence implementations.
    """

    def __init__(
        self,
        config: OrchestratorConfig,
        *,
        bus: EventBus | None = None,
        readiness: ReadinessGate | None = None,
    ) -> None:
        self.config = config
        self._bus = bus or EventBus()
        self.readiness = readiness or ReadinessGate(config.mode)
        self.readiness.reset_live_arming()
        self.lifecycle = LifecycleMachine()
        self.state = RuntimeStateStore(config.mode)
        self.ingress = IngressQueue(config.ingress_capacity)

        self._components: list[ManagedComponent] = []
        self._ordered_components: tuple[ManagedComponent, ...] = ()
        self._initialized: list[ManagedComponent] = []
        self._started: list[ManagedComponent] = []
        self._component_subscriptions: dict[
            str, list[Subscription]
        ] = {}

    def register_component(self, component: ManagedComponent) -> None:
        if self.lifecycle.state is not LifecycleState.CREATED:
            raise OrchestratorError(
                "components may be registered only before bootstrap"
            )
        self._components.append(component)

    @property
    def status(self) -> CoreStatus:
        return self.state.snapshot(
            self.lifecycle.state,
            self.readiness.snapshot(),
        )

    @property
    def new_live_risk_allowed(self) -> bool:
        return (
            self.lifecycle.state is LifecycleState.RUNNING
            and self.readiness.live_execution_ready
        )

    async def bootstrap(self) -> None:
        if self.lifecycle.state is not LifecycleState.CREATED:
            raise OrchestratorError(
                "bootstrap requires CREATED state"
            )
        try:
            self.lifecycle.transition(
                LifecycleState.INITIALIZING
            )
            self._ordered_components = resolve_component_order(
                self._components
            )

            for component in self._ordered_components:
                self._initialized.append(component)
                await component.initialize()

            self.lifecycle.transition(LifecycleState.STARTING)
            for component in self._ordered_components:
                if component.phase is ComponentPhase.BOOTSTRAP:
                    await self._start_component(component)

            self.lifecycle.transition(
                LifecycleState.RECOVERING
            )
            if self.readiness.core_ready:
                self.lifecycle.transition(
                    LifecycleState.READY
                )
        except Exception as exc:
            await self._fault(
                f"bootstrap failed: {exc}"
            )
            raise OrchestratorFault(str(exc)) from exc

    def set_readiness(
        self,
        signal: ReadinessSignal,
        value: bool,
    ) -> None:
        self.readiness.set(signal, value)
        state = self.lifecycle.state
        if (
            state is LifecycleState.RECOVERING
            and self.readiness.core_ready
        ):
            self.lifecycle.transition(
                LifecycleState.READY
            )
        elif (
            state is LifecycleState.READY
            and not self.readiness.core_ready
        ):
            self.lifecycle.transition(
                LifecycleState.RECOVERING
            )

    async def activate(self) -> None:
        if self.lifecycle.state is not LifecycleState.READY:
            raise OrchestratorError(
                "activate requires READY state"
            )
        try:
            self.lifecycle.transition(
                LifecycleState.STARTING
            )
            for component in self._ordered_components:
                if component.phase is ComponentPhase.RUNTIME:
                    await self._start_component(component)
            self.lifecycle.transition(
                LifecycleState.RUNNING
            )
        except Exception as exc:
            await self._fault(
                f"activation failed: {exc}"
            )
            raise OrchestratorFault(str(exc)) from exc

    async def submit(
        self,
        event: EventEnvelope,
    ) -> bool:
        if self.lifecycle.state in {
            LifecycleState.CREATED,
            LifecycleState.INITIALIZING,
            LifecycleState.STARTING,
            LifecycleState.STOPPING,
            LifecycleState.STOPPED,
            LifecycleState.FAULTING,
            LifecycleState.FAULTED,
            LifecycleState.DISPOSING,
            LifecycleState.DISPOSED,
        }:
            raise OrchestratorError(
                "cannot submit event while "
                f"{self.lifecycle.state.value}"
            )
        try:
            accepted = self.ingress.put_nowait(event)
        except CriticalIngressOverflow as exc:
            await self._fault(
                f"critical ingress overflow: {exc}"
            )
            raise OrchestratorFault(str(exc)) from exc

        if not accepted:
            self.state.record_drop()
        return accepted

    async def process_next(self) -> EventEnvelope:
        event = await self.ingress.get()
        await self._dispatch(event)
        return event

    async def run_until_idle(self) -> int:
        processed = 0
        while self.ingress.qsize():
            try:
                event = self.ingress.get_nowait()
            except asyncio.QueueEmpty:
                break
            await self._dispatch(event)
            processed += 1
        return processed

    async def _dispatch(
        self,
        event: EventEnvelope,
    ) -> None:
        if self.lifecycle.state not in {
            LifecycleState.RECOVERING,
            LifecycleState.READY,
            LifecycleState.RUNNING,
            LifecycleState.DEGRADED,
        }:
            raise OrchestratorError(
                "cannot dispatch while "
                f"{self.lifecycle.state.value}"
            )
        try:
            emitted = await self._bus.dispatch(event)
            self.state.record_processed()
            for child in emitted:
                await self.submit(child)
        except CriticalIngressOverflow as exc:
            await self._fault(
                f"critical ingress overflow: {exc}"
            )
            raise OrchestratorFault(str(exc)) from exc
        except Exception as exc:
            await self._fault(
                "event dispatch failed on "
                f"{event.topic}: {exc}"
            )
            raise OrchestratorFault(str(exc)) from exc

    async def degrade(self, reason: str) -> None:
        if self.lifecycle.state is not LifecycleState.RUNNING:
            raise OrchestratorError(
                "degrade requires RUNNING state"
            )
        self.lifecycle.transition(
            LifecycleState.DEGRADING
        )
        self.state.record_error(reason)
        self.lifecycle.transition(
            LifecycleState.DEGRADED
        )

    async def resume(self) -> None:
        if self.lifecycle.state is not LifecycleState.DEGRADED:
            raise OrchestratorError(
                "resume requires DEGRADED state"
            )
        if not self.readiness.core_ready:
            raise OrchestratorError(
                "cannot resume while core readiness is false"
            )
        self.lifecycle.transition(
            LifecycleState.RESUMING
        )
        self.lifecycle.transition(
            LifecycleState.RUNNING
        )

    async def stop(self) -> None:
        if self.lifecycle.state in {
            LifecycleState.STOPPED,
            LifecycleState.DISPOSED,
        }:
            return
        if self.lifecycle.state is LifecycleState.FAULTED:
            return
        if self.lifecycle.state not in {
            LifecycleState.RECOVERING,
            LifecycleState.READY,
            LifecycleState.RUNNING,
            LifecycleState.DEGRADED,
        }:
            raise OrchestratorError(
                "cannot stop while "
                f"{self.lifecycle.state.value}"
            )

        self.lifecycle.transition(
            LifecycleState.STOPPING
        )
        errors = await self._stop_started_components()
        if errors:
            await self._fault(
                "; ".join(errors),
                components_already_stopped=True,
            )
            raise OrchestratorFault(
                "; ".join(errors)
            )
        self.lifecycle.transition(
            LifecycleState.STOPPED
        )

    async def dispose(self) -> None:
        if self.lifecycle.state is LifecycleState.DISPOSED:
            return

        if self.lifecycle.state not in {
            LifecycleState.STOPPED,
            LifecycleState.FAULTED,
            LifecycleState.READY,
            LifecycleState.CREATED,
        }:
            await self.stop()

        if self.lifecycle.state is LifecycleState.READY:
            await self.stop()

        self.lifecycle.transition(
            LifecycleState.DISPOSING
        )

        errors: list[str] = []
        for component in reversed(self._initialized):
            try:
                await component.dispose()
            except Exception as exc:
                errors.append(
                    f"dispose {component.name}: {exc}"
                )

        if errors:
            self.lifecycle.transition(
                LifecycleState.FAULTING
            )
            self.state.record_error(
                "; ".join(errors)
            )
            self.lifecycle.transition(
                LifecycleState.FAULTED
            )
            raise OrchestratorFault(
                "; ".join(errors)
            )

        self.lifecycle.transition(
            LifecycleState.DISPOSED
        )

    async def _start_component(
        self,
        component: ManagedComponent,
    ) -> None:
        self._started.append(component)
        await component.start()

        tokens: list[Subscription] = []
        for spec in component.subscriptions:
            tokens.append(
                self._bus.subscribe(
                    spec.topic,
                    spec.handler,
                )
            )
        self._component_subscriptions[
            component.name
        ] = tokens

    async def _stop_started_components(
        self,
    ) -> list[str]:
        errors: list[str] = []

        for component in reversed(self._started):
            for token in self._component_subscriptions.pop(
                component.name,
                [],
            ):
                self._bus.unsubscribe(token)

            try:
                await component.stop()
            except Exception as exc:
                errors.append(
                    f"stop {component.name}: {exc}"
                )

        self._started.clear()
        return errors

    async def _fault(
        self,
        reason: str,
        *,
        components_already_stopped: bool = False,
    ) -> None:
        self.readiness.reset_live_arming()
        self.state.record_error(reason)

        if self.lifecycle.state is LifecycleState.FAULTED:
            return

        if self.lifecycle.state is not LifecycleState.FAULTING:
            if self.lifecycle.can_transition(
                LifecycleState.FAULTING
            ):
                self.lifecycle.transition(
                    LifecycleState.FAULTING
                )
            else:
                raise OrchestratorFault(reason)

        if not components_already_stopped:
            await self._stop_started_components()

        self.lifecycle.transition(
            LifecycleState.FAULTED
        )
