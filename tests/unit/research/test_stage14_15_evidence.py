"""Reject false Stage 14/15 promotion from development results."""
import unittest
from scripts.governance.audit_stage14_15_research import inspect

SELECTION = {
    "policy_sha256": "abc", "research_only": True,
    "live_risk_authorized": False, "validated_strategy": False,
    "choices": [{"side": "SELL", "regime": "DOWN", "candidate": "x"}],
}
FINAL = {
    "policy_sha256": "abc", "research_only": True,
    "live_risk_authorized": False, "validated_strategy": False,
    "cells": [{"side": "SELL", "regime": "DOWN", "candidate": "x", "result": "REJECTED"}],
    "limitations": ["Final history previously inspected."],
}
STAGE14 = {"policy_pending": True, "live_execution_authority": False}
STAGE15 = {"policy_pending": True, "live_execution_authority": False}


class Stage14_15EvidenceTests(unittest.TestCase):
    def check(self, selection=None, final=None, s14=None, s15=None):
        return inspect(selection or SELECTION, final or FINAL, s14 or STAGE14, s15 or STAGE15)

    def test_previously_inspected_final_remains_blocked(self):
        out = self.check()
        self.assertEqual(out["result"], "PASS_STRATEGY_EVIDENCE_FAIL_CLOSED")
        self.assertFalse(out["stage14_15_release_qualified"])
        self.assertEqual(out["final_rejections"], 1)
        self.assertIn("final_period_previously_inspected_not_independent", out["blocked_reasons"])

    def test_policy_hash_change_detected(self):
        out = self.check(final={**FINAL, "policy_sha256": "changed"})
        self.assertIn("policy_hash_mismatch", out["integrity_errors"])

    def test_missing_final_candidate_detected(self):
        out = self.check(final={**FINAL, "cells": []})
        self.assertIn("missing_final_candidate_evidence", out["integrity_errors"])

    def test_no_silent_live_upgrade(self):
        out = self.check(final={**FINAL, "live_risk_authorized": True})
        self.assertIn("live_risk_claim_without_authorization", out["integrity_errors"])
        out = self.check(s14={"policy_pending": False, "live_execution_authority": False})
        self.assertIn("unapproved_policy_marked_final", out["integrity_errors"])

    def test_even_positive_research_cell_not_live(self):
        cell = {**FINAL["cells"][0], "result": "PASS_RESEARCH_SCREEN"}
        out = self.check(final={**FINAL, "cells": [cell]})
        self.assertEqual(out["result"], "PASS_STRATEGY_EVIDENCE_FAIL_CLOSED")
        self.assertFalse(out["independent_blind_holdout_confirmed"])
        self.assertFalse(out["live_execution_enabled"])
