from __future__ import annotations

import argparse
import json
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", default=".")
    parser.add_argument(
        "--output",
        default="build/governance/constitution_guard.json",
    )
    args = parser.parse_args()
    root = Path(args.repo_root).resolve()

    body_config = json.loads(
        (root / "config" / "body_build.json").read_text(encoding="utf-8")
    )

    stage_manifests = []
    for stage in range(11, 41):
        stage_manifests.append(
            json.loads(
                (
                    root
                    / "config"
                    / "stages"
                    / f"stage{stage:02d}.json"
                ).read_text(encoding="utf-8")
            )
        )

    protected_sources = []
    for folder in (
        root / "src" / "katarina" / "body",
        root / "src" / "katarina" / "policies",
        root / "src" / "katarina" / "persistence",
    ):
        for path in folder.glob("*.py"):
            protected_sources.append(path.read_text(encoding="utf-8"))
    combined = "\n".join(protected_sources)

    frozen_records = [
        root / "docs" / "reviews" / f"STAGE_{stage:02d}_FREEZE_RECORD.md"
        for stage in range(6, 10)
    ]

    checks = {
        "stage06_09_freeze_records_present": all(
            path.is_file() for path in frozen_records
        ),
        "body_live_execution_disabled": (
            body_config.get("live_execution_enabled") is False
        ),
        "body_live_risk_false": (
            body_config.get("live_risk_ready") is False
        ),
        "strategy_policy_unfinalized": (
            body_config.get("strategy_policy_finalized") is False
        ),
        "risk_policy_unfinalized": (
            body_config.get("risk_policy_finalized") is False
        ),
        "no_manifest_live_risk_ready": all(
            item.get("live_risk_ready") is False
            for item in stage_manifests
        ),
        "no_manifest_live_execution_authority": all(
            item.get("live_execution_authority") is False
            for item in stage_manifests
        ),
        "policy_pending_stages_locked": [
            item["stage"]
            for item in stage_manifests
            if item.get("policy_pending") is True
        ]
        == [14, 15, 16, 17, 38],
        "no_order_send_in_python_body": "OrderSend(" not in combined,
        "no_literal_live_execution_true": (
            "live_execution_authority=True" not in combined
        ),
        "no_literal_live_risk_true": "live_risk_ready=True" not in combined,
    }

    passed = all(checks.values())
    result = {
        "schema_version": 1,
        "proof_type": "KATARINA_CONSTITUTION_GUARD",
        "checks": checks,
        "live_risk_ready": False,
        "live_execution_enabled": False,
        "result": (
            "PASS_KATARINA_CONSTITUTION_GUARD"
            if passed
            else "FAIL_KATARINA_CONSTITUTION_GUARD"
        ),
    }
    out = root / args.output
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(result["result"])
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
