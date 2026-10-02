from __future__ import annotations

from enum import Enum
from typing import Protocol, runtime_checkable

from katarina.contracts.runtime import SubscriptionSpec


class ComponentGraphError(RuntimeError):
    pass


class ComponentPhase(str, Enum):
    BOOTSTRAP = "bootstrap"
    RUNTIME = "runtime"


@runtime_checkable
class ManagedComponent(Protocol):
    name: str
    dependencies: tuple[str, ...]
    phase: ComponentPhase
    subscriptions: tuple[SubscriptionSpec, ...]

    async def initialize(self) -> None: ...
    async def start(self) -> None: ...
    async def stop(self) -> None: ...
    async def dispose(self) -> None: ...


def resolve_component_order(
    components: list[ManagedComponent],
) -> tuple[ManagedComponent, ...]:
    by_name: dict[str, ManagedComponent] = {}
    for component in components:
        if not component.name:
            raise ComponentGraphError("component name must be non-empty")
        if component.name in by_name:
            raise ComponentGraphError(f"duplicate component name: {component.name}")
        by_name[component.name] = component

    for component in components:
        for dep in component.dependencies:
            if dep not in by_name:
                raise ComponentGraphError(
                    f"component {component.name} depends on unknown component {dep}"
                )
            if (
                component.phase is ComponentPhase.BOOTSTRAP
                and by_name[dep].phase is ComponentPhase.RUNTIME
            ):
                raise ComponentGraphError(
                    f"bootstrap component {component.name} cannot depend on runtime component {dep}"
                )

    result: list[ManagedComponent] = []
    permanent: set[str] = set()
    temporary: set[str] = set()

    def visit(name: str) -> None:
        if name in permanent:
            return
        if name in temporary:
            raise ComponentGraphError(f"component dependency cycle detected at {name}")
        temporary.add(name)
        component = by_name[name]
        for dep in component.dependencies:
            visit(dep)
        temporary.remove(name)
        permanent.add(name)
        result.append(component)

    for component in components:
        visit(component.name)

    return tuple(result)
