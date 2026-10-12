"""Auditable handoff, manager gate, and research-only team checks."""
from __future__ import annotations

import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from scripts.ai.katarina_team import (
    ROLES, _receipt, qa, manager, specialist, validate_specialists,
)

SHA="7"*40


def prepare(folder):
    for name in ROLES:
        record=specialist(name,SHA)
        (folder/(name+".json")).write_text(json.dumps(record),encoding="utf-8")


class ParallelTeamTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.roles={name:specialist(name,SHA) for name in ROLES}

    def test_specialists_produce_distinct_reproducible_receipts(self):
        self.assertEqual(len(self.roles),4)
        for name,record in self.roles.items():
            self.assertEqual(record,specialist(name,SHA))
            self.assertEqual(record["role"],name)
            self.assertEqual(record["status"],"PASS")
            self.assertFalse(record["live_authorized"])
            self.assertFalse(record["writes_code"])
            self.assertEqual(record["receipt_sha256"],_receipt({
                key:value for key,value in record.items()
                if key!="receipt_sha256"}))

    def test_manager_requires_successful_qa_and_retains_release_blockers(self):
        with TemporaryDirectory() as temp:
            directory=Path(temp)
            prepare(directory)
            report=qa(directory,SHA,True)
            (directory/"qa.json").write_text(json.dumps(report))
            decision=manager(directory,SHA)
            self.assertEqual(decision["specialist_count"],4)
            self.assertEqual(decision["engineering_status"],"PASS")
            self.assertEqual(decision["v1_release_status"],
                             "BLOCKED_UNTIL_ALL_ROADMAP_GATES_PASS")
            self.assertEqual(decision["orders_authorized"],0)
            self.assertFalse(decision["live_execution_authorized"])
            self.assertFalse(decision["auto_code_merge_authorized"])

    def test_qa_failure_stops_manager_promotion(self):
        with TemporaryDirectory() as temp:
            directory=Path(temp)
            prepare(directory)
            report=qa(directory,SHA,False)
            (directory/"qa.json").write_text(json.dumps(report))
            decision=manager(directory,SHA)
            self.assertEqual(decision["decision"],"STOP_AND_FIX_QA")
            self.assertEqual(decision["engineering_status"],"BLOCKED")

    def test_missing_role_blocks_and_no_fabricated_team(self):
        with TemporaryDirectory() as temp:
            directory=Path(temp)
            prepare(directory)
            (directory/"math.json").unlink()
            with self.assertRaises(ValueError):
                validate_specialists(directory,SHA)

    def test_tampered_and_stale_receipts_rejected(self):
        with TemporaryDirectory() as temp:
            directory=Path(temp)
            prepare(directory)
            path=directory/"ideas.json"
            tampered=json.loads(path.read_text())
            tampered["findings"]["trials"]=999
            path.write_text(json.dumps(tampered))
            with self.assertRaises(ValueError):
                validate_specialists(directory,SHA)
            original=self.roles["ideas"].copy()
            original["commit"]="stale"
            path.write_text(json.dumps(original))
            with self.assertRaises(ValueError):
                validate_specialists(directory,SHA)

    def test_manager_rejects_fake_qa(self):
        with TemporaryDirectory() as temp:
            directory=Path(temp)
            prepare(directory)
            report=qa(directory,SHA,True)
            report["regression_tests_passed"]=False
            (directory/"qa.json").write_text(json.dumps(report))
            with self.assertRaises(ValueError):
                manager(directory,SHA)

if __name__=="__main__":
    unittest.main()
