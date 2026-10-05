from __future__ import annotations

import argparse
import importlib
import json
from pathlib import Path

from katarina.body import AuthorityClass, BodyRegistry


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", default=".")
    parser.add_argument("--output", default="build/body/body_framework_audit.json")
    args = parser.parse_args()

    root = Path(args.repo_root).resolve()
    registry = BodyRegistry(root)
    specs = registry.validate()

    receipts = []
    for spec in specs:
        component = importlib.import_module(spec.implementation_module).Component()
        result = component.process({"audit": True})
        receipts.append(
            {
                "stage": spec.stage,
                "name": spec.name,
                "authority": spec.authority.value,
                "policy_pending": spec.policy_pending,
                "windows_required": spec.windows_required,
                "reference_doc": spec.reference_doc,
                "component_import": "PASS",
                "body_process": "PASS",
                "live_risk_ready": result.live_risk_ready,
                "live_execution_authority": result.live_execution_authority,
            }
        )

    checks = {
        "stage_count_30": len(specs) == 30,
        "stage_range_11_40": [s.stage for s in specs] == list(range(11, 41)),
        "all_reference_docs_present": all(
            (root / s.reference_doc).is_file() for s in specs
        ),
        "all_live_risk_false": all(not s.live_risk_ready for s in specs),
        "all_live_execution_authority_false": all(
            not s.live_execution_authority for s in specs
        ),
        "policy_pending_explicit": {
            s.stage for s in specs if s.policy_pending
        } == {14, 15, 16, 17, 38},
        "windows_validation_explicit": {
            s.stage for s in specs if s.windows_required
        } == {35, 36, 38},
        "execution_paths_present_but_locked": all(
            not r["live_execution_authority"]
            for r in receipts
            if r["authority"] == AuthorityClass.EXECUTION_PATH.value
        ),
    }
    passed = all(checks.values())
    report = {
        "schema_version": 1,
        "proof_type": "KATARINA_BODY_FRAMEWORK_AUDIT",
        "stage_range": [11, 40],
        "checks": checks,
        "stages": receipts,
        "strategy_policy_finalized": False,
        "risk_policy_finalized": False,
        "live_risk_ready": False,
        "live_execution_enabled": False,
        "result": (
            "PASS_KATARINA_BODY_FRAMEWORK_11_40"
            if passed
            else "FAIL_KATARINA_BODY_FRAMEWORK_11_40"
        ),
    }

    out = root / args.output
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(report["result"])
    print(f"stages={len(receipts)}")
    print(f"output={out}")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
