"""Management workplan: genuine scoped audit, integrity and fail-closed tests."""
from __future__ import annotations

from copy import deepcopy
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from scripts.ai.management_workplan import (
    ALLOWED_PREFIXES, ROLES, PLAN, audit_role, load_plan,
    management_summary, verify_role,
)

ROOT = Path(__file__).resolve().parents[3]


def fixture(root: Path) -> dict:
    original, _ = load_plan(ROOT)
    plan = deepcopy(original)
    target = root / PLAN
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(plan), encoding="utf-8")
    for task in plan["tasks"]:
        dest = root / task["path"]
        dest.parent.mkdir(parents=True, exist_ok=True)
        contents = (
            "def valid():\n    return True\n" if dest.suffix == ".py"
            else "name: Fixture\non:\n  workflow_dispatch:\n" if dest.suffix == ".yml"
            else "{}"
        )
        dest.write_text(contents, encoding="utf-8")
    return plan


class ManagementWorkplanTests(unittest.TestCase):
    def test_every_role_has_a_real_audited_file(self):
        plan, signature = load_plan(ROOT)
        self.assertEqual(len(plan["tasks"]), 11)
        self.assertEqual(set(x["owner_role"] for x in plan["tasks"]), ROLES)
        results = {role: audit_role(ROOT, role) for role in ROLES}
        for role, result in results.items():
            self.assertEqual(result["plan_sha256"], signature)
            self.assertTrue(result["tasks"][0]["size_bytes"] > 0)
            self.assertFalse(result["code_modified"])
            self.assertFalse(result["live_trading_authorized"])
            self.assertEqual(result["role"], role)
        manager = management_summary(ROOT, results)
        self.assertEqual(manager["verified_work_items"], 11)
        self.assertEqual(manager["verified_specialists"], 11)
        self.assertFalse(manager["autonomous_code_writes_verified"])

    def test_receipt_tampering_fails_qa(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            fixture(root)
            record = audit_role(root, "coding")
            record["tasks"][0]["sha256"] = "0" * 64
            with self.assertRaisesRegex(ValueError, "tampered"):
                verify_role(root, "coding", record)

    def test_source_changed_after_receipt_fails_qa(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            plan = fixture(root)
            result = audit_role(root, "security")
            name = next(x["path"] for x in plan["tasks"] if x["owner_role"] == "security")
            (root / name).write_text("def changed():\n    return False\n", encoding="utf-8")
            with self.assertRaises(ValueError):
                verify_role(root, "security", result)

    def test_scope_escape_and_duplicate_worker_fail_closed(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            plan = fixture(root)
            plan["tasks"][0]["path"] = "src/katarina/../../.env"
            (root / PLAN).write_text(json.dumps(plan), encoding="utf-8")
            with self.assertRaises(ValueError):
                load_plan(root)
            plan = fixture(root)
            plan["tasks"][0]["owner_role"] = plan["tasks"][1]["owner_role"]
            (root / PLAN).write_text(json.dumps(plan), encoding="utf-8")
            with self.assertRaises(ValueError):
                load_plan(root)

    def test_missing_team_receipt_fails_manager(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            fixture(root)
            all_roles = {role: audit_role(root, role) for role in ROLES}
            all_roles.pop("qa", None)  # QA is not a specialist; no change.
            all_roles.pop("logic")
            with self.assertRaises(ValueError):
                management_summary(root, all_roles)

    def test_corrupt_python_and_oversized_source_are_rejected(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            plan = fixture(root)
            path = next(x["path"] for x in plan["tasks"] if x["owner_role"] == "coding")
            (root / path).write_text("def broken(:\n", encoding="utf-8")
            with self.assertRaises(SyntaxError):
                audit_role(root, "coding")
            (root / path).write_text("x" * (plan["max_source_bytes"] + 1), encoding="utf-8")
            with self.assertRaises(ValueError):
                audit_role(root, "coding")

    def test_workplan_does_not_accept_unapproved_argument(self):
        with self.assertRaises(ValueError):
            load_plan(ROOT, plan_file="../elsewhere.json")


if __name__ == "__main__":
    unittest.main()
