"""Bounded, verifiable work assignments for the existing 15-role Management V2.

Runs ONLY source audits, without external APIs, shell, code execution, broker
access, file deletion or deployed policy mutation. Work is scoped by a reviewed
version-controlled manifest; source bytes remain unchanged.
"""
from __future__ import annotations

import ast
from hashlib import sha256
import json
from pathlib import Path, PurePosixPath
import re

ROLES = frozenset({
    "ideas", "coding", "math", "logic", "builder", "debugger",
    "runner_ops", "data", "ai_integration", "infrastructure", "security",
})
PLAN = "config/management-workplan-v1.json"
ALLOWED_PREFIXES = ("src/katarina/", "scripts/ai/", "tests/", ".github/workflows/")
EXTENSIONS = frozenset({".py", ".yml", ".yaml", ".json", ".md"})
PRIORITIES = frozenset({"high", "normal", "low"})


def _safe_source(root: Path, name: str) -> Path:
    """Reject absolute paths, traversal, symlinks and unrelated files."""
    if not isinstance(name, str) or not name or "\\" in name or "\x00" in name:
        raise ValueError("unsafe_source_path")
    p = PurePosixPath(name)
    if p.is_absolute() or any(part in ("..", ".", "") for part in p.parts):
        raise ValueError("unsafe_source_path")
    if not name.startswith(ALLOWED_PREFIXES) or p.suffix not in EXTENSIONS:
        raise ValueError("source_outside_review_scope")
    base = root.resolve(strict=True)
    candidate = root.joinpath(*p.parts)
    if candidate.is_symlink() or not candidate.resolve(strict=True).is_relative_to(base):
        raise ValueError("escaped_review_root")
    if not candidate.is_file():
        raise ValueError("source_not_file")
    return candidate


def load_plan(root: Path, plan_file: str = PLAN) -> tuple[dict, str]:
    # Plan path is a fixed trusted code-side constant, never untrusted input.
    if plan_file != PLAN:
        raise ValueError("unapproved_management_plan")
    raw = (root / plan_file).read_bytes()
    if len(raw) > 24000:
        raise ValueError("workplan_too_large")
    plan = json.loads(raw)
    if (
        type(plan) is not dict or plan.get("schema_version") != 1
        or not re.fullmatch(r"[a-z0-9-]{8,80}", str(plan.get("plan_id", "")))
        or not isinstance(plan.get("tasks"), list)
        or len(plan["tasks"]) != len(ROLES)
        or type(plan.get("max_source_bytes")) is not int
        or not 1024 <= plan["max_source_bytes"] <= 500000
    ):
        raise ValueError("invalid_workplan")
    ids, owners = set(), set()
    for task in plan["tasks"]:
        if not isinstance(task, dict) or set(task) != {
            "task_id", "owner_role", "path", "action", "priority"
        }:
            raise ValueError("invalid_work_item")
        if (
            not re.fullmatch(r"MGT-[0-9]{3}", str(task["task_id"]))
            or task["task_id"] in ids
            or task["owner_role"] not in ROLES
            or task["owner_role"] in owners
            or task["action"] != "source_audit"
            or task["priority"] not in PRIORITIES
        ):
            raise ValueError("invalid_work_assignment")
        _safe_source(root, task["path"])
        ids.add(task["task_id"])
        owners.add(task["owner_role"])
    if owners != ROLES:
        raise ValueError("missing_specialist_assignment")
    return plan, sha256(raw).hexdigest()


def audit_role(root: Path, role: str, *, plan_file: str = PLAN) -> dict:
    """Produce deterministic, replayable source evidence for one role."""
    if role not in ROLES:
        raise ValueError("unknown_management_role")
    plan, digest = load_plan(root, plan_file=plan_file)
    tasks = []
    for item in plan["tasks"]:
        if item["owner_role"] != role:
            continue
        source = _safe_source(root, item["path"])
        blob = source.read_bytes()
        if len(blob) > plan["max_source_bytes"]:
            raise ValueError("management_source_too_large")
        contents = blob.decode("utf-8")
        syntax = "TEXT_CHECKED"
        if source.suffix == ".py":
            ast.parse(contents, filename=item["path"])
            syntax = "PYTHON_AST_PASS"
        elif source.suffix == ".json":
            json.loads(contents)
            syntax = "JSON_PARSE_PASS"
        elif source.suffix in (".yml", ".yaml"):
            if not contents.strip() or not re.search(r"(?m)^(name|on|jobs):", contents):
                raise ValueError("workflow_shape_invalid")
            syntax = "WORKFLOW_TEXT_REVIEW_ONLY"
        elif not contents.strip():
            raise ValueError("empty_document")
        tasks.append({
            "task_id": item["task_id"],
            "priority": item["priority"],
            "path": item["path"],
            "sha256": sha256(blob).hexdigest(),
            "size_bytes": len(blob),
            "line_count": len(contents.splitlines()),
            "review_flags": len(re.findall(r"(?im)\b(?:TODO|FIXME)\b", contents)),
            "validation": syntax,
            "result": "SOURCE_VERIFIED_NO_CHANGES",
        })
    if not tasks:
        raise ValueError("role_has_no_tasks")
    return {
        "plan_id": plan["plan_id"],
        "plan_sha256": digest,
        "role": role,
        "task_count": len(tasks),
        "tasks": tasks,
        "execution": "BOUNDED_READ_ONLY_SOURCE_AUDIT",
        "code_modified": False,
        "vps_modified": False,
        "live_trading_authorized": False,
    }


def verify_role(root: Path, role: str, receipt: dict) -> dict:
    """QA replays each audited file against the locked manifest and source."""
    expected = audit_role(root, role)
    if receipt != expected:
        raise ValueError("stale_or_tampered_management_task_evidence:" + role)
    return expected


def management_summary(root: Path, receipts: dict[str, dict]) -> dict:
    """Manager-owned role coverage, with no synthetic claim of AI autonomy."""
    if set(receipts) != ROLES:
        raise ValueError("incomplete_management_team")
    verified = [verify_role(root, role, receipts[role]) for role in sorted(ROLES)]
    digests = {record["plan_sha256"] for record in verified}
    if len(digests) != 1:
        raise ValueError("inconsistent_management_plan")
    return {
        "verified_specialists": len(verified),
        "verified_work_items": sum(r["task_count"] for r in verified),
        "plan_sha256": digests.pop(),
        "real_source_integrity_verified": True,
        "autonomous_code_writes_verified": False,
        "external_ai_workers_verified": False,
        "status": "READ_ONLY_MANAGEMENT_BASELINE",
    }
