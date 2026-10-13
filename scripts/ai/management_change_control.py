"""Fail-closed, review-only management patch proposals.

A worker may propose a file replacement, but this module never writes source,
executes proposed code, merges branches, accesses brokers or authorizes release.
The output is evidence for an independent human/QA review.
"""
from __future__ import annotations

import argparse
import ast
import difflib
from hashlib import sha256
import json
from pathlib import Path
import re

ALLOWED = frozenset({
    "scripts/ai/katarina_flow_v2.py",
    "scripts/ai/katarina_team.py",
    "scripts/ai/management_workplan.py",
    "scripts/ai/management_resources.py",
    "scripts/ai/management_acceptance.py",
    "tests/unit/governance/test_katarina_flow_v2.py",
    "tests/unit/governance/test_management_workplan.py",
    "tests/unit/governance/test_management_resources.py",
    "tests/unit/governance/test_management_acceptance.py",
})
MAX_PROPOSAL_BYTES = 260_000
MAX_PREVIEW_LINES = 100


def evaluate(root: Path, proposal: dict) -> dict:
    if (
        type(proposal) is not dict
        or set(proposal) != {
            "schema_version", "proposal_id", "target_path",
            "base_sha256", "proposed_source", "reason",
        }
        or type(proposal["schema_version"]) is not int
        or proposal["schema_version"] != 1
        or not isinstance(proposal["proposal_id"], str)
        or not re.fullmatch(r"MGT-P-[0-9]{3,6}", proposal["proposal_id"])
        or not isinstance(proposal["target_path"], str)
        or proposal["target_path"] not in ALLOWED
        or not isinstance(proposal["base_sha256"], str)
        or not re.fullmatch(r"[0-9a-f]{64}", proposal["base_sha256"])
        or not isinstance(proposal["proposed_source"], str)
        or not isinstance(proposal["reason"], str)
        or not 8 <= len(proposal["reason"].strip()) <= 2000
    ):
        raise ValueError("invalid_or_unauthorized_management_proposal")
    home = root.resolve(strict=True)
    target = home / proposal["target_path"]
    # Reject symlink targets, traversal and missing paths. Restrict all patches
    # to nontrading Management tooling and its own tests.
    if (
        not target.is_file() or target.is_symlink()
        or not target.resolve(strict=True).is_relative_to(home)
    ):
        raise ValueError("unsafe_management_patch_target")
    original = target.read_bytes()
    if sha256(original).hexdigest() != proposal["base_sha256"]:
        raise ValueError("stale_management_source_sha")
    candidate = proposal["proposed_source"].encode("utf-8")
    same_content = candidate.replace(b"\r\n", b"\n") == original.replace(b"\r\n", b"\n")
    if not candidate or len(candidate) > 250_000 or same_content:
        raise ValueError("empty_unchanged_or_oversized_patch")
    if b"\x00" in candidate:
        raise ValueError("binary_management_source_rejected")
    ast.parse(candidate, filename=proposal["target_path"])
    before = original.decode("utf-8").splitlines(keepends=True)
    after = candidate.decode("utf-8").splitlines(keepends=True)
    delta = list(difflib.unified_diff(
        before, after,
        fromfile="a/" + proposal["target_path"],
        tofile="b/" + proposal["target_path"],
    ))
    return {
        "proposal_id": proposal["proposal_id"],
        "target_path": proposal["target_path"],
        "base_sha256": proposal["base_sha256"],
        "proposed_sha256": sha256(candidate).hexdigest(),
        "diff_preview": "".join(delta[:MAX_PREVIEW_LINES]),
        "diff_preview_truncated": len(delta) > MAX_PREVIEW_LINES,
        "validation": "PYTHON_AST_PARSE_ONLY",
        "status": "PENDING_INDEPENDENT_QA_AND_OWNER_APPROVAL",
        "file_modified": False,
        "auto_merge": False,
        "live_trading_authorized": False,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--proposal", required=True, type=Path)
    arguments = parser.parse_args()
    proposal_path = arguments.proposal
    if not proposal_path.is_file() or proposal_path.stat().st_size > MAX_PROPOSAL_BYTES:
        raise ValueError("missing_or_oversized_proposal_file")
    data = json.loads(proposal_path.read_text(encoding="utf-8"))
    root = Path(__file__).resolve().parents[2]
    print(json.dumps(evaluate(root, data), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
