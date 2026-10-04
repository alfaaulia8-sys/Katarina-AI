from __future__ import annotations

import random
import unittest

from katarina.health.engine import HealthPolicy, HealthSafetyEngine, HealthState


NOW = 2_000_000_000_000_000_000


class Stage09HealthPropertyTests(unittest.TestCase):
    def test_critical_queue_threshold_is_monotonic(self):
        rng = random.Random(909)
        policy = HealthPolicy()
        for _ in range(1000):
            depth = rng.randint(0, 2500)
            engine = HealthSafetyEngine(policy)
            engine.observe_data_fresh(True)
            engine.observe_health_event(
                {
                    "data_health": 1,
                    "transport_health": 1,
                    "execution_health": 1,
                    "reconciliation_health": 1,
                    "journal_health": 1,
                    "clock_health": 1,
                    "snapshot_health": 1,
                },
                observed_at_ns=NOW,
            )
            engine.observe_heartbeat(
                {
                    "critical_queue_depth": depth,
                    "market_queue_depth": 0,
                    "last_broker_observation_ns": NOW,
                },
                observed_at_ns=NOW,
            )
            state = engine.evaluate(now_ns=NOW).transport
            if depth >= policy.critical_queue_blocked_depth:
                self.assertEqual(state, HealthState.BLOCKED)
            elif depth >= policy.critical_queue_degraded_depth:
                self.assertEqual(state, HealthState.DEGRADED)
            else:
                self.assertIn(state, {HealthState.OK, HealthState.UNKNOWN})


if __name__ == "__main__":
    unittest.main()
