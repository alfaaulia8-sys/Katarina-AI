from __future__ import annotations
from dataclasses import dataclass
from typing import Iterable,Any

@dataclass(frozen=True, slots=True)
class TesterEvent:
    sequence: int
    topic: str
    payload: Any

class TesterTransport:
    def __init__(self, events: Iterable[TesterEvent]):
        self._events=tuple(sorted(events,key=lambda e:e.sequence)); self._index=0
    def recv(self) -> TesterEvent|None:
        if self._index>=len(self._events): return None
        e=self._events[self._index]; self._index+=1; return e
    def reset(self) -> None: self._index=0

class StrategyTesterIntegration:
    def replay(self, transport: TesterTransport) -> list[TesterEvent]:
        out=[]
        while True:
            e=transport.recv()
            if e is None: break
            out.append(e)
        return out
