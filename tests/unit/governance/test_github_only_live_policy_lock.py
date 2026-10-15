"""Ensure GitHub-only development never silently enables live execution."""
import unittest

from katarina.policies.risk import DEFAULT_RISK_POLICY, RiskPolicy
from katarina.policies.strategy import DEFAULT_STRATEGY_POLICY, StrategyPolicy


class GitHubOnlyPolicyLockTests(unittest.TestCase):
    def test_strategy_defaults_to_unfinalized_and_no_live_authority(self):
        self.assertEqual(DEFAULT_STRATEGY_POLICY.name, "UNFINALIZED")
        self.assertFalse(DEFAULT_STRATEGY_POLICY.finalized)
        self.assertFalse(DEFAULT_STRATEGY_POLICY.live_execution_authority)

    def test_strategy_rejects_live_authority_even_if_finalized(self):
        with self.assertRaises(ValueError):
            StrategyPolicy(name="research", finalized=True, live_execution_authority=True)

    def test_risk_defaults_to_no_live_authority(self):
        self.assertEqual(DEFAULT_RISK_POLICY.name, "UNFINALIZED")
        self.assertFalse(DEFAULT_RISK_POLICY.finalized)
        self.assertIsNone(DEFAULT_RISK_POLICY.max_risk_fraction_ppm)
        self.assertFalse(DEFAULT_RISK_POLICY.live_risk_ready)
        self.assertFalse(DEFAULT_RISK_POLICY.live_execution_authority)

    def test_risk_rejects_execution_and_readiness(self):
        for overrides in ({"live_risk_ready": True}, {"live_execution_authority": True}):
            with self.subTest(overrides=overrides), self.assertRaises(ValueError):
                RiskPolicy(**overrides)

    def test_risk_rejects_negative_fraction(self):
        with self.assertRaises(ValueError):
            RiskPolicy(max_risk_fraction_ppm=-1)


if __name__ == "__main__":
    unittest.main()
