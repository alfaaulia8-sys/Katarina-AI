"""Read-only fan-in of untrusted Cloud Hand research telemetry.

No socket, cloud credential, command transport, order sender, watchdog SLO,
or live Owner control. Cloud/Owner operational policies remain unresolved.
"""
from __future__ import annotations

from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from hashlib import sha256
from hmac import compare_digest
import json
from collections import defaultdict
from typing import Sequence

from katarina.intelligence.unified_research_handoff import OwnerResearchReceipt


@dataclass(frozen=True)
class OwnerHandsSnapshot:
    inspected_at_utc: str
    reports: tuple[dict, ...]
    symbol_conflicts: tuple[str, ...]
    status: str = "UNVERIFIED_OFFLINE_HAND_TELEMETRY"
    owner_controls: str = "READ_ONLY_NO_REMOTE_COMMANDS"
    cloud_authenticated: bool = False
    live_execution_authorized: bool = False
    orders_submitted: int = 0

    def owner_view(self) -> dict:
        return asdict(self)


def consolidate_hand_reports(
    reports: Sequence[OwnerResearchReceipt], *,
    inspected_at_utc: datetime,
) -> OwnerHandsSnapshot:
    """Verify in-process integrity and causality, never source authenticity."""
    if (not isinstance(inspected_at_utc, datetime)
            or inspected_at_utc.tzinfo is None
            or inspected_at_utc.utcoffset() is None):
        raise ValueError("owner_review_clock_invalid")
    if not isinstance(reports, (tuple, list)):
        raise ValueError("hand_report_collection_invalid")
    inspected = inspected_at_utc.astimezone(timezone.utc)
    seen = set()
    inspected_reports = []
    by_symbol: dict[str, set[str]] = defaultdict(set)
    for report in reports:
        if not isinstance(report, OwnerResearchReceipt):
            raise ValueError("unverified_report_type")
        if (not report.research_only or report.live_execution_authorized
                or report.strategy_promoted or report.orders_submitted != 0):
            raise ValueError("untrusted_hand_execution_claim")
        if not report.hand_id:
            raise ValueError("missing_hand_identity")
        key = (report.hand_id, report.symbol)
        if key in seen:
            raise ValueError("duplicate_hand_symbol_report")
        seen.add(key)
        try:
            instant = datetime.fromisoformat(report.observed_utc)
        except (ValueError, TypeError) as exc:
            raise ValueError("unverified_hand_clock") from exc
        if instant.tzinfo is None or instant.utcoffset() is None:
            raise ValueError("unverified_hand_clock")
        if instant.astimezone(timezone.utc) > inspected:
            raise ValueError("future_hand_observation")
        evidence = dict(
            observed_utc=report.observed_utc,
            source_digest=report.source_digest,
            symbol=report.symbol, side=report.side, regime=report.regime,
            playbook=report.playbook, action=report.action,
            entry=report.entry, stop=report.stop, target=report.target,
            reasons=report.reasons, hand_id=report.hand_id,
        )
        try:
            expected = sha256(json.dumps(evidence, sort_keys=True,
                                         allow_nan=False,
                                         separators=(",", ":")).encode()).hexdigest()
        except (TypeError, ValueError) as exc:
            raise ValueError("invalid_hand_report_payload") from exc
        if (not isinstance(report.digest, str)
                or not compare_digest(report.digest, expected)):
            raise ValueError("hand_report_integrity_mismatch")
        if report.action == "RESEARCH_CANDIDATE":
            by_symbol[report.symbol].add(report.side)
        inspected_reports.append(report.owner_view())
    conflicts = tuple(sorted(symbol for symbol, sides in by_symbol.items()
                             if len(sides) > 1))
    inspected_reports.sort(key=lambda r: (r["hand_id"], r["symbol"]))
    return OwnerHandsSnapshot(
        inspected_at_utc=inspected.isoformat(),
        reports=tuple(inspected_reports),
        symbol_conflicts=conflicts,
    )
