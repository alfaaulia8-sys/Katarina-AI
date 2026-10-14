"""Integration contract: a single pinned Katarina V1 engineering tree."""
from copy import deepcopy
import json
from contextlib import closing
from pathlib import Path
from unittest.mock import patch
import sqlite3
import tempfile
import unittest

from scripts.ai.verify_unified_katarina import verify
from katarina.intelligence.prospective_shadow_book import ProspectiveShadowBook

ROOT=Path(__file__).resolve().parents[2]


class UnifiedKatarinaIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.profile=json.loads((ROOT/"config/katarina_unified_v1.json").read_text())

    def test_existing_core_brain_risk_broker_fit_one_profile(self):
        result=verify(self.profile,root=ROOT)
        self.assertEqual(result["status"],"INTEGRATED_OFFLINE_ENGINEERING_ONLY")
        self.assertEqual(result["modules_verified"],10)
        self.assertEqual(len(set(result["module_sha256"])),10)
        self.assertEqual(result["management"],"ON_HOLD")
        self.assertEqual(result["cumulative_profit_lock"],
                         "VERIFIED_THREE_MILESTONES_AND_RESTART")
        self.assertEqual(result["same_day_emergency_lockdown"],
                         "VERIFIED_NO_NEW_ENTRY")
        self.assertTrue(result["learning_policy_valid"])
        self.assertEqual(result["shadow_observations"],0)
        self.assertEqual(result["mode"],"TESTER_NO_ORDERS")
        self.assertFalse(result["live_execution_authorized"])
        self.assertEqual(result["orders_submitted"],0)

    def test_acceptance_rejects_old_reserve_overwrite_implementation(self):
        from katarina.engines.capital import CapitalCompoundingEngine
        original=CapitalCompoundingEngine.observe_balance

        def incorrectly_reset_lock(engine,balance):
            event=original(engine,balance)
            if event.milestone_triggered:
                engine.reserve_balance=round(engine.total_balance*.25,10)
                engine.active_balance=round(
                    engine.total_balance-engine.reserve_balance,10)
            return event

        with patch.object(CapitalCompoundingEngine,"observe_balance",
                          incorrectly_reset_lock):
            with self.assertRaisesRegex(
                    ValueError,"cumulative_profit_lock_policy_mismatch"):
                verify(self.profile,root=ROOT)

    def test_acceptance_rejects_same_day_emergency_bypass(self):
        from katarina.engines.risk import (
            RiskGovernor,RiskDecision,RiskAction,DrawdownMode,
        )
        original=RiskGovernor.evaluate

        def incorrectly_reopen(governor,request):
            authority=request.drawdown_authority
            if (authority is not None
                    and authority.mode is DrawdownMode.EMERGENCY_LOCKDOWN):
                return RiskDecision(RiskAction.APPROVE,.01,"unsafe")
            return original(governor,request)

        with patch.object(RiskGovernor,"evaluate",incorrectly_reopen):
            with self.assertRaisesRegex(
                    ValueError,"same_day_emergency_lockdown_bypass"):
                verify(self.profile,root=ROOT)

    def test_management_and_specialists_cannot_be_reactivated_by_manifest(self):
        for component in ("katarina_management", "eleven_specialists"):
            changed=deepcopy(self.profile)
            changed["on_hold"][component]=False
            with self.subTest(component=component):
                with self.assertRaisesRegex(ValueError,"management_on_hold_required"):
                    verify(changed,root=ROOT)
        changed=deepcopy(self.profile)
        changed["canonical"]["management"]="scripts/ai/management_acceptance.py"
        with self.assertRaisesRegex(ValueError,"incomplete_unified_component_registry"):
            verify(changed,root=ROOT)
        changed=deepcopy(self.profile)
        changed["operating_mode"]["management"]="MANUAL_QA_ON_PINNED_COMMIT"
        with self.assertRaisesRegex(ValueError,"management_on_hold_required"):
            verify(changed,root=ROOT)

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
            with closing(sqlite3.connect(target)) as db:
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
