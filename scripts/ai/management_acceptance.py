"""Serial Katarina Management acceptance on a pinned, clean checkout.

No broker, live trading, model API, automatic patch application or deployment.
The local regression gate actually runs its required tests before passing QA.
"""
from __future__ import annotations

import argparse
from datetime import datetime
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from tempfile import TemporaryDirectory

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "src"))

from scripts.ai.katarina_flow_v2 import (  # noqa: E402
    SPECIALISTS, WIB, manager, qa, release, scheduler, specialist,
)
from scripts.ai.management_resources import observe_workspace  # noqa: E402

# Explicit test list prevents recursive self-execution through
# test_management_acceptance.py, while covering all downstream safety gates.
REQUIRED_REGRESSIONS = (
    "tests.unit.governance.test_management_change_control",
    "tests.unit.governance.test_management_resources",
    "tests.unit.governance.test_management_workplan",
    "tests.unit.governance.test_katarina_flow_v2",
    "tests.static.test_github_action_fanout",
)


def run_required_regressions() -> dict:
    """Run real tests serially, fail closed on a failure or timeout."""
    env = dict(os.environ)
    env["PYTHONPATH"] = os.pathsep.join((str(ROOT), str(ROOT / "src")))
    argv = [sys.executable, "-B", "-m", "unittest", *REQUIRED_REGRESSIONS, "-q"]
    try:
        result = subprocess.run(
            argv, cwd=ROOT, env=env, capture_output=True, text=True,
            timeout=180, check=False,
        )
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError("management_regression_timeout") from exc
    if result.returncode:
        raise RuntimeError(
            "management_regression_failed:" + (result.stderr + result.stdout)[-1400:]
        )
    return {
        "passed": True,
        "suite_count": len(REQUIRED_REGRESSIONS),
        "suite_ids": list(REQUIRED_REGRESSIONS),
        "process_exit_code": result.returncode,
        "runner": "SINGLE_LOCAL_PYTHON_PROCESS",
        "summary": (result.stderr + result.stdout)[-400:],
    }


def run_acceptance(commit: str, *, verify_checkout: bool = False) -> dict:
    """Replay the 15-role chain with real required-test evidence."""
    if not isinstance(commit, str) or not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise ValueError("pinned_commit_sha_required")
    if verify_checkout:
        head = subprocess.run(
            ["git", "-C", str(ROOT), "rev-parse", "HEAD"],
            check=True, capture_output=True, text=True, timeout=10,
        ).stdout.strip()
        changed = subprocess.run(
            ["git", "-C", str(ROOT), "status", "--porcelain"],
            check=True, capture_output=True, text=True, timeout=10,
        ).stdout
        if head != commit or changed.strip():
            raise ValueError("checkout_not_pinned_or_clean")
    resources = observe_workspace(ROOT)
    if resources["free_disk_mb"] < 512 or (
        resources["available_ram_mb"] is not None
        and resources["available_ram_mb"] < 192
    ):
        raise RuntimeError("management_acceptance_blocked_low_resources")
    regressions = run_required_regressions()
    with TemporaryDirectory(prefix="katarina-management-acceptance-") as temp:
        folder = Path(temp)

        def save(name: str, receipt: dict) -> None:
            (folder / name).write_text(
                json.dumps(receipt, sort_keys=True, allow_nan=False),
                encoding="utf-8",
            )

        plan = scheduler(commit, datetime.now(WIB))
        save("schedule.json", plan)
        for role in SPECIALISTS:
            save(role + ".json", specialist(role, plan, commit))
        reviewed = qa(folder, commit, regression_pass=regressions["passed"])
        save("qa.json", reviewed)
        managed = manager(folder, commit)
        save("manager.json", managed)
        decision = release(folder, commit)

    if (
        managed["engineering_status"] != "PASS"
        or decision["v1_release_status"] != "BLOCKED"
        or decision["orders_sent"] != 0
        or decision["live_execution_enabled"] is not False
    ):
        raise RuntimeError("management_acceptance_unexpected_authorization")
    return {
        "status": "MANAGEMENT_ENGINEERING_ACCEPTANCE_PASS",
        "commit": commit,
        "checkout_verified": verify_checkout,
        "regression_evidence": regressions,
        "specialists_verified": managed["specialists_verified"],
        "work_items_verified": managed["management_work_summary"]["verified_work_items"],
        "qa_passed": managed["qa_passed"],
        "release_status": decision["v1_release_status"],
        "autonomous_code_writes_verified": managed["management_work_summary"]["autonomous_code_writes_verified"],
        "external_ai_workers_verified": managed["management_work_summary"]["external_ai_workers_verified"],
        "orders_sent": decision["orders_sent"],
        "resources": resources,
        "unresolved_release_blockers": decision["reasons"],
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--commit", required=True, help="40-char pinned Git commit SHA")
    args = parser.parse_args()
    print(json.dumps(run_acceptance(args.commit, verify_checkout=True), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
