from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class RiskPolicy:
    """User-owned risk policy placeholder.

    No implicit percentage, leverage, lot formula, or live-risk approval is
    supplied by the body build.
    """

    name: str = "UNFINALIZED"
    version: str = "0"
    finalized: bool = False
    max_risk_fraction_ppm: int | None = None
    live_risk_ready: bool = False
    live_execution_authority: bool = False

    def __post_init__(self) -> None:
        if self.max_risk_fraction_ppm is not None and self.max_risk_fraction_ppm < 0:
            raise ValueError("max_risk_fraction_ppm must be non-negative")
        if self.live_risk_ready or self.live_execution_authority:
            raise ValueError("unfinalized risk policy must remain fail-closed")


DEFAULT_RISK_POLICY = RiskPolicy()


__all__ = ("DEFAULT_RISK_POLICY", "RiskPolicy")
