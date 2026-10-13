"""Fail-closed Stage 38 evidence validation; never sends broker orders."""
import unittest

from katarina.governance.live_validation import (
    LiveMicroRiskValidator, LiveValidationEvidence,
)


def evidence(**changes):
    data=dict(
        human_approved=True,
        demo_pass=True,
        broker_compatibility_pass=True,
        reconciliation_pass=True,
        stress_pass=True,
        monitoring_ready=True,
        requested_risk_fraction=.01,
    )
    data.update(changes)
    return LiveValidationEvidence(**data)


class LiveRiskEvidenceTests(unittest.TestCase):
    def test_properly_verified_flags_still_only_yield_risk_fraction_quote(self):
        out=LiveMicroRiskValidator().evaluate(evidence(requested_risk_fraction=.08))
        self.assertTrue(out.allowed)
        self.assertAlmostEqual(out.approved_risk_fraction,.05)

    def test_false_or_unknown_evidence_never_passes(self):
        for name in (
            "human_approved","demo_pass","broker_compatibility_pass",
            "reconciliation_pass","stress_pass","monitoring_ready",
        ):
            for wrong in (False,"False","True",1,None):
                with self.subTest(field=name,value=wrong):
                    out=LiveMicroRiskValidator().evaluate(evidence(**{name:wrong}))
                    self.assertFalse(out.allowed)
                    self.assertEqual(out.approved_risk_fraction,0)

    def test_nonfinite_risk_never_qualifies(self):
        for value in (float("nan"),float("inf"),-float("inf"),0,-1,
                      None,True,".01",10**900):
            with self.subTest(value=str(value)[:30]):
                out=LiveMicroRiskValidator().evaluate(
                    evidence(requested_risk_fraction=value))
                self.assertFalse(out.allowed)
                self.assertEqual(out.approved_risk_fraction,0)


if __name__=="__main__":
    unittest.main()
