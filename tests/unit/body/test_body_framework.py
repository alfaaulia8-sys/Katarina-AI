from __future__ import annotations

import unittest
from pathlib import Path

from katarina.body import (
    AuthorityClass,
    BodyRegistry,
    PolicyState,
)
from katarina.policies import DEFAULT_RISK_POLICY, DEFAULT_STRATEGY_POLICY


ROOT = Path(__file__).resolve().parents[3]


class BodyFrameworkTests(unittest.TestCase):
    def setUp(self) -> None:
        self.registry = BodyRegistry(ROOT)
        self.specs = self.registry.validate()

    def test_stage_11_through_40_are_present(self):
        self.assertEqual([s.stage for s in self.specs], list(range(11, 41)))

    def test_every_stage_has_github_reference_note(self):
        for spec in self.specs:
            with self.subTest(stage=spec.stage):
                self.assertTrue((ROOT / spec.reference_doc).is_file())

    def test_every_stage_is_fail_closed_for_live_authority(self):
        for spec in self.specs:
            with self.subTest(stage=spec.stage):
                self.assertFalse(spec.live_risk_ready)
                self.assertFalse(spec.live_execution_authority)

    def test_execution_path_body_components_do_not_execute(self):
        import importlib

        for spec in self.specs:
            if spec.authority is not AuthorityClass.EXECUTION_PATH:
                continue
            with self.subTest(stage=spec.stage):
                component = importlib.import_module(
                    spec.implementation_module
                ).Component()
                result = component.process({"candidate": "test"})
                self.assertFalse(result.live_risk_ready)
                self.assertFalse(result.live_execution_authority)

    def test_policy_pending_stages_are_explicit(self):
        pending = {s.stage for s in self.specs if s.policy_pending}
        self.assertEqual(pending, {14, 15, 16, 17, 38})

    def test_windows_required_stages_are_explicit(self):
        required = {s.stage for s in self.specs if s.windows_required}
        self.assertEqual(required, {35, 36, 38})

    def test_default_strategy_policy_is_unfinalized(self):
        self.assertFalse(DEFAULT_STRATEGY_POLICY.finalized)
        self.assertFalse(DEFAULT_STRATEGY_POLICY.live_execution_authority)

    def test_default_risk_policy_is_unfinalized_and_has_no_risk_value(self):
        self.assertFalse(DEFAULT_RISK_POLICY.finalized)
        self.assertIsNone(DEFAULT_RISK_POLICY.max_risk_fraction_ppm)
        self.assertFalse(DEFAULT_RISK_POLICY.live_risk_ready)

    def test_policy_state_requires_all_three_explicit_approvals(self):
        self.assertFalse(PolicyState().live_policy_ready)
        self.assertFalse(
            PolicyState(
                strategy_finalized=True,
                risk_finalized=True,
                live_validation_approved=False,
            ).live_policy_ready
        )
        self.assertTrue(
            PolicyState(
                strategy_finalized=True,
                risk_finalized=True,
                live_validation_approved=True,
            ).live_policy_ready
        )


if __name__ == "__main__":
    unittest.main()
