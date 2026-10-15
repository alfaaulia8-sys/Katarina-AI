"""The single research brain: perception, cognition and shared evidence memory.

Existing engines are capabilities, not independent workers. No broker gateway,
background scheduler, source rewrite or strategy promotion is available here.
Fast/Deep select existing retrieval budgets; they never change risk authority.
"""
from __future__ import annotations

from dataclasses import asdict, replace
from datetime import datetime, timezone
import sqlite3

from katarina.intelligence.market_decision_brain_v3 import MarketDecisionBrain
from katarina.intelligence.unified_cognitive_cycle import (
    run_unified_cognitive_cycle, verify_cognitive_history,
)
from katarina.intelligence.self_evolution_lab import (
    evaluate_shadow_self_evolution, derive_shadow_research_policy,
)
from katarina.intelligence.unified_adaptive_research_cycle import synthesize_offline_research
from katarina.memory.neuro_link import CognitiveEvidence, NeuroLinkMemory
from katarina.memory.store import MemoryStore


class UnifiedKatarinaBrain:
    """One owner of the causal research path, with independent risk outside it."""

    def __init__(self, shadow_db: sqlite3.Connection, memory: MemoryStore):
        self.shadow_db = shadow_db
        self.memory = memory
        self._perception = MarketDecisionBrain()
        self._knowledge = NeuroLinkMemory(memory)

    def evaluate_contextually(self, **evidence):
        # Preserve the existing market decision semantics and hard controls.
        return self._perception.evaluate_contextually(**evidence)

    def synthesize_entry_exit(self, **evidence):
        return synthesize_offline_research(self.shadow_db, **evidence)

    def run_unified_cognitive_cycle(
        self, *, as_of_utc: datetime, persist: bool = True,
        mode: str = "fast", context_tags: tuple[str, ...] = (),
    ) -> dict:
        if mode not in ("fast", "deep"):
            raise ValueError("invalid_single_brain_recall_mode")
        if (not isinstance(as_of_utc, datetime) or as_of_utc.tzinfo is None
                or as_of_utc.utcoffset() is None):
            raise ValueError("timezone_aware_cognitive_clock_required")
        clock = as_of_utc.astimezone(timezone.utc)
        # Verify the Owner's checkpoint before learning, including read-only runs.
        history = verify_cognitive_history(self.shadow_db)
        if history["last_event_as_of_utc"] is not None:
            last = datetime.fromisoformat(history["last_event_as_of_utc"])
            if last > clock:
                raise ValueError("cognitive_learning_clock_regressed")
        cognition = run_unified_cognitive_cycle(
            self.shadow_db, as_of_utc=clock, persist=persist)
        lab = evaluate_shadow_self_evolution(self.shadow_db, as_of_utc=clock)
        policy = derive_shadow_research_policy(lab)
        blockers = []
        if (cognition.get("source_snapshot_matches_active") is False
                or history["last_event_kind"] == "ROLLBACK"):
            blockers.append("OWNER_CHECKPOINT_HOLD")
        if (not persist and history["events"] and
                history["active_observation_sha256"] != cognition["observation_sha256"]):
            blockers.append("ACTIVE_CHECKPOINT_NOT_CURRENT_SNAPSHOT")
        tags = set(context_tags)
        inserted = 0
        if not blockers:
            for row in cognition["episodic_memory"]:
                # Quote markouts never become independently validated broker P/L.
                if row["status"] != "VIRTUAL_QUOTED":
                    continue
                row_tags = tuple(str(row[k]) for k in ("symbol", "method", "side", "regime"))
                tags.update(row_tags)
                if not persist:
                    continue
                observed = int(row["observed"] * 1_000_000_000)
                # First availability is this ingestion, never a backdated exit.
                evidence_id = "shadow:" + str(row["id"])
                previous = self.memory.load_operational_event("neuro_link:" + evidence_id)
                known = (previous["payload"]["known_ns"] if previous else
                         int(clock.timestamp() * 1_000_000_000))
                if known <= observed:
                    raise ValueError("noncausal_neuro_link_quote_outcome")
                evidence = CognitiveEvidence(
                    evidence_id=evidence_id,
                    event_group_id="shadow:" + str(row["id"]),
                    observed_ns=observed, known_ns=known,
                    hypothesis="quote association: " + str(row["method"]),
                    tags=row_tags, decision=str(row["side"]),
                    outcome_net_r=row["net_r"], quality="OBSERVED",
                    reason="VIRTUAL_QUOTE_MARKOUT_NOT_BROKER_EXECUTION",
                )
                inserted += int(self._knowledge.remember(evidence))
        recall = self._knowledge.recall(
            tuple(sorted(tags)), as_of_ns=int(clock.timestamp() * 1_000_000_000), mode=mode)
        if recall.history_truncated:
            blockers.append("KNOWLEDGE_RECALL_HISTORY_TRUNCATED")
        if blockers:
            policy = replace(policy, integrity_ok=False)
        # Rollback must quarantine recalled associations as well as future sampling.
        knowledge = asdict(recall)
        if blockers:
            knowledge["links"] = []
        return {
            "architecture":"SINGLE_COGNITIVE_BRAIN",
            "specialist_workers":0,
            "cognition":cognition, "self_evolution_lab":lab,
            "research_policy":policy,
            "knowledge_memory":{
                **knowledge, "mode":mode, "records_inserted":inserted,
                "quarantine_reasons":sorted(set(blockers)),
                "shared_memory":True,
                "import_scope":"BOUNDED_EPISODIC_EXAMPLES_NOT_FULL_HISTORY",
            },
            "orders_submitted":0, "live_execution_authorized":False,
        }
