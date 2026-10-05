from __future__ import annotations

import unittest

from katarina.contracts.runtime import EventEnvelope, MessagePriority
from katarina.persistence import (
    EVENT_JOURNAL_POLICY,
    EXPERIENCE_MEMORY_POLICY,
    OPERATIONAL_SNAPSHOT_POLICY,
    TRANSIENT_POLICY,
    BoundaryPolicy,
    PersistenceLane,
    classify_persistence,
)


class Stage10PersistenceBoundaryTests(unittest.TestCase):
    def event(
        self,
        topic: str,
        priority: MessagePriority = MessagePriority.MARKET,
    ) -> EventEnvelope:
        return EventEnvelope(topic=topic, payload={}, priority=priority)

    def test_critical_priority_is_always_durable(self):
        policy = classify_persistence(
            self.event("unknown.future.topic", MessagePriority.CRITICAL)
        )
        self.assertIs(policy, EVENT_JOURNAL_POLICY)

    def test_risk_state_priority_is_always_durable(self):
        policy = classify_persistence(
            self.event("market.tick", MessagePriority.RISK_STATE)
        )
        self.assertIs(policy, EVENT_JOURNAL_POLICY)

    def test_safety_and_execution_topics_are_durable(self):
        topics = (
            "decision.created",
            "execution.reported",
            "order.accepted",
            "position.changed",
            "risk.limit_changed",
            "health.state",
            "reconcile.completed",
            "account.balance_changed",
        )
        for topic in topics:
            with self.subTest(topic=topic):
                self.assertIs(
                    classify_persistence(self.event(topic)),
                    EVENT_JOURNAL_POLICY,
                )

    def test_operational_snapshot_is_replaceable_and_rebuildable(self):
        policy = classify_persistence(self.event("snapshot.runtime"))
        self.assertIs(policy, OPERATIONAL_SNAPSHOT_POLICY)
        self.assertFalse(policy.append_only)
        self.assertTrue(policy.rebuildable)
        self.assertFalse(policy.recovery_authority)

    def test_experience_memory_is_append_only_but_not_recovery_authority(self):
        policy = classify_persistence(self.event("experience.trade_episode"))
        self.assertIs(policy, EXPERIENCE_MEMORY_POLICY)
        self.assertTrue(policy.append_only)
        self.assertTrue(policy.deterministic_id_required)
        self.assertFalse(policy.recovery_authority)
        self.assertFalse(policy.live_execution_authority)

    def test_market_and_transport_telemetry_are_transient_by_default(self):
        topics = (
            "market.tick",
            "market.bar",
            "transport.metrics",
            "transport.heartbeat",
            "heartbeat",
        )
        for topic in topics:
            with self.subTest(topic=topic):
                self.assertIs(
                    classify_persistence(self.event(topic)),
                    TRANSIENT_POLICY,
                )

    def test_unknown_noncritical_event_is_transient_by_default(self):
        self.assertIs(
            classify_persistence(self.event("future.advisory")),
            TRANSIENT_POLICY,
        )

    def test_event_journal_contract_is_fail_closed(self):
        self.assertTrue(EVENT_JOURNAL_POLICY.append_only)
        self.assertTrue(EVENT_JOURNAL_POLICY.deterministic_id_required)
        self.assertFalse(EVENT_JOURNAL_POLICY.rebuildable)
        self.assertTrue(EVENT_JOURNAL_POLICY.recovery_authority)
        self.assertFalse(EVENT_JOURNAL_POLICY.live_execution_authority)

    def test_no_stage10_lane_can_grant_live_execution_authority(self):
        for policy in (
            TRANSIENT_POLICY,
            EVENT_JOURNAL_POLICY,
            OPERATIONAL_SNAPSHOT_POLICY,
            EXPERIENCE_MEMORY_POLICY,
        ):
            with self.subTest(lane=policy.lane):
                self.assertFalse(policy.live_execution_authority)

    def test_invalid_recovery_authority_boundary_is_rejected(self):
        with self.assertRaises(ValueError):
            BoundaryPolicy(
                lane=PersistenceLane.OPERATIONAL_SNAPSHOT,
                append_only=False,
                deterministic_id_required=False,
                rebuildable=True,
                recovery_authority=True,
            )

    def test_mutable_event_journal_is_rejected(self):
        with self.assertRaises(ValueError):
            BoundaryPolicy(
                lane=PersistenceLane.EVENT_JOURNAL,
                append_only=False,
                deterministic_id_required=True,
                rebuildable=False,
                recovery_authority=True,
            )


if __name__ == "__main__":
    unittest.main()
