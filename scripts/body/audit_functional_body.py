from __future__ import annotations

import argparse
import importlib
import json
from pathlib import Path

from katarina.body import BodyRegistry


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", default=".")
    parser.add_argument(
        "--output",
        default="build/body/katarina_body_local_clearance.json",
    )
    args = parser.parse_args()

    root = Path(args.repo_root).resolve()
    registry = BodyRegistry(root)
    specs = registry.validate()

    stage10_path = root / "build" / "stage10" / "stage10_local_final_clearance.json"
    stage10 = (
        json.loads(stage10_path.read_text(encoding="utf-8"))
        if stage10_path.is_file()
        else {}
    )
    body_config = json.loads(
        (root / "config" / "body_build.json").read_text(encoding="utf-8")
    )

    stage_receipts = []
    functional_count = 0
    for spec in specs:
        manifest = json.loads(
            (
                root
                / "config"
                / "stages"
                / f"stage{spec.stage:02d}.json"
            ).read_text(encoding="utf-8")
        )
        component = importlib.import_module(spec.implementation_module).Component()
        result = component.process({"body_audit": True})
        kernel = str(manifest.get("functional_body_kernel", ""))
        functional = (
            manifest.get("functional_body_complete") is True
            and bool(kernel)
            and any(cls.__name__ == kernel for cls in type(component).__mro__)
        )
        functional_count += int(functional)

        should_block_process = (
            spec.policy_pending
            or spec.authority.value == "execution_path"
        )
        stage_receipts.append(
            {
                "stage": spec.stage,
                "name": spec.name,
                "functional_kernel": kernel,
                "functional_body_complete": functional,
                "github_reference_present": (
                    root / spec.reference_doc
                ).is_file(),
                "policy_pending": spec.policy_pending,
                "windows_validation_pending": spec.windows_required,
                "generic_process_blocked_when_required": (
                    (not result.accepted) if should_block_process else True
                ),
                "live_risk_ready": result.live_risk_ready,
                "live_execution_authority": result.live_execution_authority,
            }
        )

    policy_pending = [
        r["stage"] for r in stage_receipts if r["policy_pending"]
    ]
    windows_pending = [
        r["stage"]
        for r in stage_receipts
        if r["windows_validation_pending"]
    ]

    checks = {
        "stage10_local_final_clearance": (
            stage10.get("result")
            == "PASS_STAGE10_LOCAL_FINAL_CLEARANCE"
            and stage10.get("ready_for_stage11") is True
        ),
        "stage11_40_count": len(stage_receipts) == 30,
        "all_functional_kernels_present": functional_count == 30,
        "all_github_reference_notes_present": all(
            r["github_reference_present"] for r in stage_receipts
        ),
        "all_live_risk_false": all(
            not r["live_risk_ready"] for r in stage_receipts
        ),
        "all_live_execution_authority_false": all(
            not r["live_execution_authority"] for r in stage_receipts
        ),
        "policy_pending_exact": policy_pending == [14, 15, 16, 17, 38],
        "windows_pending_exact": windows_pending == [35, 36, 38],
        "blocked_paths_fail_closed": all(
            r["generic_process_blocked_when_required"]
            for r in stage_receipts
        ),
        "full_unit_regression_pass": (
            body_config.get("full_unit_regression") == "151/151 PASS"
        ),
        "strategy_policy_unfinalized": (
            body_config.get("strategy_policy_finalized") is False
        ),
        "risk_policy_unfinalized": (
            body_config.get("risk_policy_finalized") is False
        ),
        "live_execution_disabled": (
            body_config.get("live_execution_enabled") is False
        ),
    }

    passed = all(checks.values())
    evidence = {
        "schema_version": 1,
        "proof_type": "KATARINA_BODY_LOCAL_CLEARANCE",
        "stage_range": [10, 40],
        "checks": checks,
        "functional_stage_count": functional_count,
        "stages": stage_receipts,
        "body_complete": passed,
        "strategy_policy_finalized": False,
        "risk_policy_finalized": False,
        "policy_pending_stages": policy_pending,
        "windows_validation_pending_stages": windows_pending,
        "live_risk_ready": False,
        "live_execution_enabled": False,
        "production_ready": False,
        "github_pushed": False,
        "governed_freeze": False,
        "result": (
            "PASS_KATARINA_BODY_LOCAL_10_40"
            if passed
            else "FAIL_KATARINA_BODY_LOCAL_10_40"
        ),
    }

    out = root / args.output
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    print(evidence["result"])
    print(f"functional_stage_count={functional_count}")
    print(f"policy_pending={policy_pending}")
    print(f"windows_pending={windows_pending}")
    print(f"output={out}")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
