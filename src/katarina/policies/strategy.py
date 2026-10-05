from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class StrategyPolicy:
    """User-owned strategy policy placeholder.

    The KATARINA body may be completed while this remains unfinalized.
    No default strategy is silently selected.
    """

    name: str = "UNFINALIZED"
    version: str = "0"
    finalized: bool = False
    live_execution_authority: bool = False

    def __post_init__(self) -> None:
        if self.live_execution_authority:
            raise ValueError("strategy policy cannot grant live execution authority")


DEFAULT_STRATEGY_POLICY = StrategyPolicy()


__all__ = ("DEFAULT_STRATEGY_POLICY", "StrategyPolicy")
