#!/usr/bin/env python3
"""Fail-closed guard against reintroducing obsolete VPS artifacts into the source tree.

This does not contact the VPS, delete files, mutate Git or inspect credentials.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path


def audit(root: Path, now: datetime | None = None) -> dict:
    now = now or datetime.now(timezone.utc)
    root = root.resolve()
    forbidden = [
        *root.glob("ops/vps/bootstrap/**/*"),
        *root.glob("ops/vps/rescue/*.trigger"),
        *root.glob("infrastructure/legacy-vps-control/**/*"),
        root / "docs/operations/VPS_FIRST_DEVELOPMENT.md",
        root / "ops/bridge/CONTROL_TEST.txt",
    ]
    forbidden = sorted(str(p.relative_to(root)) for p in forbidden if p.is_file())
    bad_requests: list[dict] = []
    valid_requests = 0
    for p in sorted((root / "ops/vps/requests").glob("**/*.json")):
        if not p.is_file():
            continue
        rel = str(p.relative_to(root))
        try:
            request = json.loads(p.read_text(encoding="utf-8"))
            expiry = request["expires_utc"]
            expires_at = datetime.fromisoformat(expiry.replace("Z", "+00:00"))
            if expires_at.tzinfo is None:
                raise ValueError("Missing expiry timezone")
            if expires_at <= now:
                bad_requests.append({"path": rel, "reason": "expired"})
            else:
                valid_requests += 1
        except (ValueError, KeyError, TypeError, json.JSONDecodeError) as exc:
            bad_requests.append({"path": rel, "reason": "invalid request or expiry"})
    return {
        "schema_version": 1,
        "result": "PASS_REPOSITORY_HYGIENE" if not forbidden and not bad_requests else "FAIL_REPOSITORY_HYGIENE",
        "checked_utc": now.isoformat(),
        "live_risk_ready": False,
        "forbidden_artifacts": forbidden,
        "expired_or_invalid_requests": bad_requests,
        "unexpired_request_count": valid_requests,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, default=Path("."))
    parser.add_argument("--output", type=Path, default=Path("build/repository-hygiene.json"))
    args = parser.parse_args()
    report = audit(args.repo_root)
    output = args.output
    if not output.is_absolute():
        output = args.repo_root / output
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(report["result"])
    print(f"forbidden={len(report['forbidden_artifacts'])} expired_or_invalid={len(report['expired_or_invalid_requests'])}")
    return 0 if report["result"].startswith("PASS") else 1


if __name__ == "__main__":
    raise SystemExit(main())
