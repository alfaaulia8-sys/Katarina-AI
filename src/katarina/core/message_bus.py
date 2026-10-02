from __future__ import annotations

import inspect
from collections import defaultdict
from dataclasses import dataclass

from katarina.contracts.runtime import EventEnvelope, EventHandler


@dataclass(frozen=True, slots=True)
class Subscription:
    token: int
    topic: str


class EventBus:
    """Deterministic in-process dispatcher.

    Handlers are invoked serially in subscription order. Emitted events are returned
    to the orchestrator and queued only after the current dispatch completes.
    """

    def __init__(self) -> None:
        self._next_token = 1
        self._subscriptions: dict[str, list[tuple[int, EventHandler]]] = defaultdict(list)

    def subscribe(self, topic: str, handler: EventHandler) -> Subscription:
        if not topic:
            raise ValueError("topic must be non-empty")
        token = self._next_token
        self._next_token += 1
        self._subscriptions[topic].append((token, handler))
        return Subscription(token=token, topic=topic)

    def unsubscribe(self, subscription: Subscription) -> bool:
        handlers = self._subscriptions.get(subscription.topic)
        if not handlers:
            return False
        remaining = [item for item in handlers if item[0] != subscription.token]
        removed = len(remaining) != len(handlers)
        if not removed:
            return False
        if remaining:
            self._subscriptions[subscription.topic] = remaining
        else:
            self._subscriptions.pop(subscription.topic, None)
        return True

    async def dispatch(self, event: EventEnvelope) -> tuple[EventEnvelope, ...]:
        ordered = list(self._subscriptions.get(event.topic, ()))
        ordered.extend(self._subscriptions.get("*", ()))
        ordered.sort(key=lambda item: item[0])

        emitted: list[EventEnvelope] = []
        for _, handler in ordered:
            result = handler(event)
            if inspect.isawaitable(result):
                result = await result
            if result is None:
                continue
            if isinstance(result, EventEnvelope):
                emitted.append(result)
                continue
            for item in result:
                if not isinstance(item, EventEnvelope):
                    raise TypeError(
                        "event handlers may emit only EventEnvelope instances"
                    )
                emitted.append(item)
        return tuple(emitted)
