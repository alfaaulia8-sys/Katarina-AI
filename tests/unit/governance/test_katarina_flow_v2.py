"""Checks the 15-role GitHub-hosted scheduler → specialists → QA → manager → release."""
from __future__ import annotations

from datetime import datetime, timezone
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from scripts.ai.katarina_flow_v2 import (
    SPECIALISTS, VERSION, digest, manager, open_receipt, qa, release,
    scheduler, specialist,
)

SHA="4"*40


def prepare(folder, *, commit=SHA):
    schedule=scheduler(commit,datetime(2026,10,13,2,tzinfo=timezone.utc))
    (folder/"schedule.json").write_text(json.dumps(schedule))
    for role in SPECIALISTS:
        r=specialist(role,schedule,commit)
        (folder/(role+".json")).write_text(json.dumps(r))
    return schedule


class FlowTests(unittest.TestCase):
    def test_scheduler_is_wib_deadline_and_caps_parallelism(self):
        early=scheduler(SHA,datetime(2026,10,12,23,tzinfo=timezone.utc))
        self.assertEqual(early["day_index"],1)
        self.assertEqual(early["current_priority"],"AUDIT_AND_LOCK_SCOPE")
        self.assertEqual(early["max_parallel"],4)
        self.assertEqual(early["retry_limit"],1)
        self.assertEqual(early["deadline_wib"],"2026-10-19")
        self.assertEqual(early["dependency_order"],
                         ["scheduler","specialists","qa","manager","release"])
        self.assertFalse(early["auto_merge"])
        self.assertFalse(early["live_trading"])

    def test_scheduler_blocks_bad_commit_and_naive_clock(self):
        with self.assertRaises(ValueError):
            scheduler("main",datetime.now(timezone.utc))
        with self.assertRaises(ValueError):
            scheduler(SHA,datetime(2026,10,13))

    def test_all_specialists_generate_read_only_actual_reports(self):
        with TemporaryDirectory() as temp:
            folder=Path(temp)
            p=prepare(folder)
            self.assertEqual(len(SPECIALISTS),11)
            for name in SPECIALISTS:
                item=json.loads((folder/(name+".json")).read_text())
                self.assertEqual(item["status"],"PASS_ENGINEERING_ONLY")
                self.assertEqual(item["schedule_receipt_sha256"],
                                 p["receipt_sha256"])
                self.assertFalse(item["can_write_repo"])
                self.assertFalse(item["can_execute_orders"])
                self.assertFalse(item["model_production_authorized"])
                self.assertIsInstance(item["findings"],dict)

    def test_qa_manager_release_full_receipt_chain_blocks_real_trading(self):
        with TemporaryDirectory() as temp:
            folder=Path(temp)
            prepare(folder)
            checked=qa(folder,SHA,True)
            self.assertTrue(checked["all_specialists_checked"])
            self.assertTrue(checked["regression_passed"])
            (folder/"qa.json").write_text(json.dumps(checked))
            head=manager(folder,SHA)
            self.assertEqual(head["specialists_verified"],11)
            self.assertEqual(head["engineering_status"],"PASS")
            self.assertFalse(head["live_trading"])
            (folder/"manager.json").write_text(json.dumps(head))
            rel=release(folder,SHA)
            self.assertEqual(rel["v1_release_status"],"BLOCKED")
            self.assertFalse(rel["release_candidate_promoted"])
            self.assertFalse(rel["live_execution_enabled"])
            self.assertEqual(rel["orders_sent"],0)

    def test_missing_specialist_is_blocked(self):
        with TemporaryDirectory() as temp:
            folder=Path(temp);prepare(folder)
            (folder/"security.json").unlink()
            with self.assertRaises(ValueError):
                qa(folder,SHA,True)

    def test_tampering_and_stale_commit_rejected(self):
        with TemporaryDirectory() as temp:
            folder=Path(temp);prepare(folder)
            p=folder/"data.json"
            record=json.loads(p.read_text())
            record["findings"]["real_OHLC_validated"]=True
            p.write_text(json.dumps(record))
            with self.assertRaises(ValueError):
                qa(folder,SHA,True)
            with self.assertRaises(ValueError):
                open_receipt(folder/"schedule.json",commit="0"*40,kind="schedule")

    def test_regression_failure_blocks_manager(self):
        with TemporaryDirectory() as temp:
            folder=Path(temp);prepare(folder)
            record=qa(folder,SHA,False)
            self.assertEqual(record["status"],"BLOCKED_REGRESSION")
            (folder/"qa.json").write_text(json.dumps(record))
            with self.assertRaises(ValueError):
                manager(folder,SHA)

    def test_qa_forgery_blocks_manager(self):
        with TemporaryDirectory() as temp:
            folder=Path(temp);prepare(folder)
            record=qa(folder,SHA,True)
            record["regression_passed"]=False
            (folder/"qa.json").write_text(json.dumps(record))
            with self.assertRaises(ValueError):
                manager(folder,SHA)

    def test_infra_does_not_clean_ram_or_touch_vps(self):
        with TemporaryDirectory() as temp:
            folder=Path(temp);prepare(folder)
            x=json.loads((folder/"infrastructure.json").read_text())
            self.assertEqual(x["findings"]["processes_terminated"],0)
            self.assertEqual(x["findings"]["vps_files_deleted"],0)
            self.assertEqual(x["findings"]["ram_cleanup"],
                             "NOT_APPLICABLE_ON_EPHEMERAL_RUNNER")

if __name__=="__main__":
    unittest.main()
