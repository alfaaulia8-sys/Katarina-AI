"""Evidence-linked, bounded recall for the existing Katarina cognitive brain.

Research-only. Does not create an agent, authorize orders, promote a model,
or mutate the independent Risk Governor. Raw event provenance stays append-only.
"""
from __future__ import annotations

from dataclasses import asdict, dataclass
from math import isfinite
import re
from typing import Literal

from katarina.memory.store import MemoryStore

EVENT_TYPE = "neuro_link_evidence_v1"
QUALITY = frozenset(("OBSERVED", "INDEPENDENTLY_VALIDATED", "DISPUTED"))
Mode = Literal["fast", "deep"]


def _normalise(value: str) -> str:
    return " ".join(re.findall(r"[a-z0-9]+", value.casefold()))


def _tags(values: tuple[str, ...]) -> tuple[str, ...]:
    return tuple(sorted({_normalise(v) for v in values if _normalise(v)}))


@dataclass(frozen=True, slots=True)
class CognitiveEvidence:
    evidence_id: str
    event_group_id: str
    observed_ns: int
    known_ns: int
    hypothesis: str
    tags: tuple[str, ...]
    decision: str
    outcome_net_r: float | None = None
    counterfactual_net_r: float | None = None
    quality: str = "OBSERVED"
    reason: str = ""

    def __post_init__(self) -> None:
        object.__setattr__(self, "tags", _tags(tuple(self.tags)))
        if (
            not self.evidence_id or not self.event_group_id
            or type(self.observed_ns) is not int or self.observed_ns <= 0
            or type(self.known_ns) is not int or self.known_ns < self.observed_ns
            or not _normalise(self.hypothesis) or not _normalise(self.decision)
            or not self.tags or self.quality not in QUALITY
        ):
            raise ValueError("invalid cognitive evidence")
        for value in (self.outcome_net_r, self.counterfactual_net_r):
            if value is not None and (not isfinite(value) or abs(value) > 1000):
                raise ValueError("invalid outcome")
        if (
            (self.outcome_net_r is not None or self.counterfactual_net_r is not None)
            and self.known_ns <= self.observed_ns
        ):
            raise ValueError("future outcome cannot be known at observation time")
        if self.quality == "INDEPENDENTLY_VALIDATED" and self.outcome_net_r is None:
            raise ValueError("validation requires an observed outcome")

    @property
    def pattern_key(self) -> str:
        # Stable coalescing of equivalent wording, but NEVER of different context.
        return "|".join((_normalise(self.hypothesis), self.decision.upper(), *self.tags))


@dataclass(frozen=True, slots=True)
class CognitiveLink:
    pattern_key: str
    hypothesis: str
    tags: tuple[str, ...]
    independent_events: int
    validated_events: int
    supportive_events: int
    adverse_events: int
    mean_net_r: float | None
    confidence: float
    quarantined: bool
    provenance_ids: tuple[str, ...]
    relevance: float


@dataclass(frozen=True, slots=True)
class NeuroLinkRecall:
    links: tuple[CognitiveLink, ...]
    records_considered: int
    history_truncated: bool
    research_only: bool = True
    live_risk_authorized: bool = False


class NeuroLinkMemory:
    """Association graph over existing immutable operational-event memory.

    Fast/deep are retrieval budgets, not separate models or brains. Observations
    from the same market event count ONCE regardless of replicated accounts.
    No learning can promote a live policy through this class.
    """

    def __init__(
        self, store: MemoryStore, *, max_fast_records: int = 512,
        max_deep_records: int = 4096, min_independent_evidence: int = 3,
    ) -> None:
        if not (1 <= max_fast_records <= max_deep_records <= 20000):
            raise ValueError("invalid retrieval budgets")
        if min_independent_evidence < 2:
            raise ValueError("minimum independent evidence must exceed one")
        self.store = store
        self.max_fast_records = max_fast_records
        self.max_deep_records = max_deep_records
        self.min_independent_evidence = min_independent_evidence

    def remember(self, evidence: CognitiveEvidence) -> bool:
        """Persist raw evidence once; duplicate ID with different data fails closed."""
        item = asdict(evidence)
        result = self.store.append_operational_event(
            EVENT_TYPE, item, event_id="neuro_link:" + evidence.evidence_id
        )
        return result.inserted

    def recall(
        self, context_tags: tuple[str, ...], *, as_of_ns: int,
        mode: Mode = "fast", limit: int = 5,
    ) -> NeuroLinkRecall:
        if type(as_of_ns) is not int or as_of_ns <= 0:
            raise ValueError("invalid as_of_ns")
        if mode not in ("fast", "deep") or not 1 <= limit <= 25:
            raise ValueError("invalid recall settings")
        query = set(_tags(tuple(context_tags)))
        if not query:
            return NeuroLinkRecall((), 0, False)
        budget = self.max_fast_records if mode == "fast" else self.max_deep_records
        # Fetch one extra row to indicate the bounded window is incomplete.
        records = self.store.load_recent_operational_events_of_type(
            EVENT_TYPE, limit=budget + 1
        )
        truncated = len(records) > budget
        records = records[-budget:]

        groups: dict[str, list[CognitiveEvidence]] = {}
        considered = 0
        for row in records:
            data = row["payload"]
            try:
                item = CognitiveEvidence(**data)
            except (TypeError, ValueError):
                continue  # Invalid events never influence recalled confidence.
            if item.observed_ns > as_of_ns or item.known_ns > as_of_ns:
                continue  # Causal visibility: no future outcomes.
            if not query.intersection(item.tags):
                continue
            considered += 1
            groups.setdefault(item.pattern_key, []).append(item)

        links = []
        for key, items in groups.items():
            # Correlated repetitions do not increase sample count or confidence.
            independent: dict[str, CognitiveEvidence] = {}
            disagreement: set[str] = set()
            provenance: set[str] = set()
            for item in items:
                provenance.add(item.evidence_id)
                previous = independent.get(item.event_group_id)
                if (previous is not None and
                    previous.outcome_net_r is not None and
                    item.outcome_net_r is not None and
                    previous.outcome_net_r != item.outcome_net_r):
                    disagreement.add(item.event_group_id)
                if previous is None or (
                    item.known_ns, item.evidence_id
                ) > (previous.known_ns, previous.evidence_id):
                    independent[item.event_group_id] = item

            observations = tuple(independent.values())
            validated = tuple(
                x for x in observations
                if x.quality == "INDEPENDENTLY_VALIDATED"
                and x.outcome_net_r is not None
                and x.event_group_id not in disagreement
            )
            supportive = sum(x.outcome_net_r > 0 for x in validated)
            adverse = sum(x.outcome_net_r <= 0 for x in validated)
            count = len(validated)
            strength = max(supportive, adverse) / count if count else 0.0
            confidence = min(1.0, count / self.min_independent_evidence) * strength
            score = len(query.intersection(items[0].tags)) / len(query.union(items[0].tags))
            quarantine = bool(
                count < self.min_independent_evidence
                or any(x.quality == "DISPUTED" for x in observations)
                or disagreement or strength < 0.67
            )
            links.append(CognitiveLink(
                pattern_key=key,
                hypothesis=items[0].hypothesis,
                tags=items[0].tags,
                independent_events=len(independent),
                validated_events=count,
                supportive_events=supportive,
                adverse_events=adverse,
                mean_net_r=(sum(x.outcome_net_r for x in validated) / count) if count else None,
                confidence=round(confidence, 6),
                quarantined=quarantine,
                provenance_ids=tuple(sorted(provenance)),
                relevance=round(score, 6),
            ))
        links.sort(key=lambda x: (-x.relevance, x.quarantined, -x.confidence, x.pattern_key))
        return NeuroLinkRecall(tuple(links[:limit]), considered, truncated)
