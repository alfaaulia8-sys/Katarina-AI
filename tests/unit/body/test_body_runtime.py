from __future__ import annotations

import unittest
from pathlib import Path

from katarina.body import KatarinaBodyRuntime


ROOT = Path(__file__).resolve().parents[3]


class KatarinaBodyRuntimeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.runtime = KatarinaBodyRuntime(ROOT)

    def test_runtime_loads_all_body_stages(self):
        snap = self.runtime.snapshot()
        self.assertEqual(snap.loaded_stages, tuple(range(11, 41)))

    def test_runtime_dependency_order_is_valid(self):
        self.assertTrue(self.runtime.dependency_order_is_valid())

    def test_runtime_policy_pending_is_explicit(self):
        snap = self.runtime.snapshot()
        self.assertEqual(snap.policy_pending_stages, (14, 15, 16, 17, 38))

    def test_runtime_windows_pending_is_explicit(self):
        snap = self.runtime.snapshot()
        self.assertEqual(snap.windows_pending_stages, (35, 36, 38))

    def test_runtime_never_claims_live_readiness(self):
        snap = self.runtime.snapshot()
        self.assertFalse(snap.strategy_policy_finalized)
        self.assertFalse(snap.risk_policy_finalized)
        self.assertFalse(snap.live_risk_ready)
        self.assertFalse(snap.live_execution_enabled)
        self.runtime.assert_fail_closed()

    def test_policy_stage_process_is_blocked(self):
        for stage in (14, 15, 16, 17, 38):
            with self.subTest(stage=stage):
                result = self.runtime.process(stage, {"audit": True})
                self.assertFalse(result.accepted)
                self.assertFalse(result.live_risk_ready)
                self.assertFalse(result.live_execution_authority)

    def test_unknown_stage_is_rejected(self):
        with self.assertRaises(KeyError):
            self.runtime.component(41)


if __name__ == "__main__":
    unittest.main()
