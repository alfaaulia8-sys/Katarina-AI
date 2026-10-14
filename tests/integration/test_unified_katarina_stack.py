"""Integration contract: a single pinned Katarina V1 engineering tree."""
from copy import deepcopy
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest

from scripts.ai.verify_unified_katarina import verify
from katarina.intelligence.prospective_shadow_book import ProspectiveShadowBook

ROOT=Path(__file__).resolve().parents[2]


class UnifiedKatarinaIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.profile=json.loads((ROOT/"config/katarina_unified_v1.json").read_text())

    def test_existing_core_management_brain_risk_broker_fit_one_profile(self):
        result=verify(self.profile,root=ROOT)
        self.assertEqual(result["status"],"INTEGRATED_OFFLINE_ENGINEERING_ONLY")
        self.assertEqual(result["modules_verified"],11)
        self.assertEqual(len(set(result["module_sha256"])),11)
        self.assertTrue(result["learning_policy_valid"])
        self.assertEqual(result["shadow_observations"],0)
        self.assertEqual(result["mode"],"TESTER_NO_ORDERS")
        self.assertFalse(result["live_execution_authorized"])
        self.assertEqual(result["orders_submitted"],0)

    def test_unready_components_cannot_be_reenabled_by_manifest(self):
        for key in self.profile["deferred"]:
            changed=deepcopy(self.profile)
            changed["deferred"][key]=True
            with self.subTest(component=key):
                with self.assertRaisesRegex(ValueError,"unapproved_unified"):
                    verify(changed,root=ROOT)
        spoof=deepcopy(self.profile)
        spoof["deferred"]["live_execution"]="false"
        with self.assertRaisesRegex(ValueError,"unapproved_unified"):
            verify(spoof,root=ROOT)

    def test_final_owner_policy_cannot_be_mutated(self):
        for key in self.profile["owner_limits"]:
            changed=deepcopy(self.profile)
            changed["owner_limits"][key]=.999
            with self.subTest(policy=key):
                with self.assertRaisesRegex(ValueError,"owner_limits_changed"):
                    verify(changed,root=ROOT)

    def test_all_canonical_parts_required_without_fallback_robot(self):
        changed=deepcopy(self.profile)
        changed["canonical"].pop("brain")
        with self.assertRaisesRegex(ValueError,"incomplete_unified"):
            verify(changed,root=ROOT)
        changed=deepcopy(self.profile)
        changed["canonical"]["brain"]="src/../../secrets.py"
        with self.assertRaisesRegex(ValueError,"invalid_canonical"):
            verify(changed,root=ROOT)

    def test_existing_shadow_sqlite_is_read_only(self):
        with tempfile.TemporaryDirectory() as directory:
            target=Path(directory)/"prospective.sqlite3"
            with sqlite3.connect(target) as db:
                ProspectiveShadowBook(db)
            before=target.read_bytes()
            result=verify(self.profile,root=ROOT,shadow_db=target)
            after=target.read_bytes()
            self.assertEqual(before,after)
            self.assertEqual(result["shadow_source"],"READ_ONLY_EXISTING_SQLITE")
            self.assertTrue(result["learning_policy_valid"])
            self.assertFalse(result["live_execution_authorized"])


if __name__=="__main__":
    unittest.main()
