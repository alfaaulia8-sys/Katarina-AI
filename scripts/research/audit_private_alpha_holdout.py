#!/usr/bin/env python3
"""Private holdout evidence bridge for KATARINA research, with no broker I/O.

Reads offline files explicitly supplied by an authorized researcher. Raw tick
files must NEVER be committed to a public GitHub repository. Even a passing
report is permission only for shadow research, not proof of broker identity,
independence, or live execution authority.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
from hashlib import sha256
import json
from pathlib import Path

from katarina.research.alpha_survival import (
    ClosedOutcome, FrozenHypothesis, REGIME_ROUTES, assess,
)

def utc(s):
    v = datetime.fromisoformat(str(s).replace("Z", "+00:00"))
    if v.tzinfo is None:
        raise ValueError("naive_event_time")
    return v.astimezone(timezone.utc)

def sha_file(path: Path) -> str:
    d = sha256()
    with path.open("rb") as src:
        for chunk in iter(lambda: src.read(1024 * 1024), b""):
            d.update(chunk)
    return d.hexdigest()

def blocked(reason: str) -> dict:
    return {
        "result": "BLOCKED_" + reason,
        "source_verified_by_file_digest": False,
        "external_attestation_independently_audited": False,
        "shadow_research_qualified": False,
        "alpha_proven_for_live": False,
        "live_execution_authorized": False,
    }

def run(repo: Path, *, manifest_path: Path | None, raw_source_path: Path | None,
        outcomes_path: Path | None, audit_at: datetime | None = None) -> dict:
    """Return report WITHOUT filename, credentials, account ID or raw outcomes."""
    if not manifest_path or not raw_source_path or not outcomes_path:
        return blocked("PRIVATE_INPUT_FILES_NOT_PROVIDED")
    if not all(p.is_file() for p in (manifest_path, raw_source_path, outcomes_path)):
        return blocked("PRIVATE_EVIDENCE_FILES_NOT_FOUND")
    try:
        protocol = json.loads(
            (repo / "config/research/alpha_regime_program_v1.json").read_text("utf-8"))
        manifest = json.loads(manifest_path.read_text("utf-8"))
        if manifest.get("schema_version") != 1:
            return blocked("UNKNOWN_EVIDENCE_SCHEMA")
        if manifest.get("origin") != "REAL_BROKER_BID_ASK_WITH_DOCUMENTED_COSTS":
            return blocked("BROKER_DATA_ORIGIN_NOT_ATTESTED")
        claimed_sha = str(manifest.get("raw_source_sha256", "")).lower()
        if len(claimed_sha) != 64 or claimed_sha != sha_file(raw_source_path):
            return blocked("SOURCE_FILE_HASH_MISMATCH")
        if manifest.get("symbol") not in protocol["symbols"]:
            return blocked("UNREGISTERED_MARKET")
        state, side, playbook = (
            manifest.get("market_state"), manifest.get("side"), manifest.get("playbook"))
        registered = REGIME_ROUTES.get(state)
        if registered is None or registered[0] == "WAIT":
            return blocked("NO_TRADE_OR_UNKNOWN_REGIME")
        if ((registered[0] != "BOTH" and side != registered[0])
                or side not in ("BUY", "SELL") or playbook != registered[1]):
            return blocked("UNREGISTERED_DIRECTION_OR_PLAYBOOK")
        freeze, start, end = (
            utc(protocol[k]) for k in (
                "preregistration_effective_at_utc",
                "new_holdout_start_utc",
                "new_holdout_end_utc"))
        if any(utc(manifest.get(k)) != t for k, t in (
                ("frozen_at_utc", freeze),
                ("holdout_start_utc", start),
                ("holdout_end_utc", end))):
            return blocked("FROZEN_BOUNDARY_MISMATCH")
        attestation = manifest.get("attestation", {})
        # Attestation is a signed-off research assertion, NOT verifiable
        # independently by this script. Manual external review is still needed.
        costs_ok = attestation.get("native_broker_costs_verified") is True
        contract_ok = attestation.get("broker_contract_verified") is True
        holdout_ok = attestation.get("holdout_independence_verified") is True
        if not (costs_ok and contract_ok and holdout_ok):
            return blocked("ATTESTATIONS_MISSING_OR_UNVERIFIED")
        if attestation.get("source_is_synthetic") is not False:
            return blocked("SYNTHETIC_EVIDENCE_DISALLOWED")
        rows = []
        with outcomes_path.open("r", encoding="utf-8") as handle:
            for line_number, line in enumerate(handle, 1):
                if not line.strip():
                    continue
                row = json.loads(line)
                if row.get("source_sha256") != claimed_sha:
                    return blocked("OUTCOME_SOURCE_HASH_MISMATCH")
                rows.append(ClosedOutcome(
                    event_id=str(row["event_id"]),
                    entry_at=utc(row["entry_at_utc"]),
                    exit_at=utc(row["exit_at_utc"]),
                    known_at=utc(row["known_at_utc"]),
                    dataset_sha256=claimed_sha,
                    net_r_after_reported_costs=float(row["net_r_after_reported_costs"]),
                ))
                if line_number > 100000:
                    return blocked("TOO_MANY_OUTCOMES")
        hypothesis = FrozenHypothesis(
            symbol=manifest["symbol"], market_state=state, side=side,
            playbook=playbook, freeze_at=freeze,
            holdout_start=start, holdout_end=end,
            dataset_sha256=claimed_sha,
            preregistered_tests=len(protocol["symbols"]) * 10,
            extra_cost_r=float(protocol["additional_cost_stress_R"]),
            independent_holdout_attested=True,
            actual_all_in_cost_attested=True,
            broker_contract_attested=True,
        )
        result = assess(
            hypothesis, rows, audit_at=audit_at or datetime.now(timezone.utc))
        return {
            "result": result["status"],
            "symbol": manifest["symbol"],
            "market_state": state,
            "side": side,
            "source_verified_by_file_digest": True,
            "external_attestation_independently_audited": False,
            "shadow_research_qualified": result["shadow_research_qualified"],
            "alpha_proven_for_live": False,
            "live_execution_authorized": False,
            "outcomes_evaluated": result["checked_outcomes"],
            "measurements": result["measurements"],
            "review_required_before_promoting": True,
        }
    except (ValueError, KeyError, TypeError, UnicodeError, OSError, OverflowError,
            json.JSONDecodeError):
        return blocked("MALFORMED_PRIVATE_EVIDENCE")

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, default=Path("."))
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--raw-source", type=Path)
    parser.add_argument("--outcomes", type=Path)
    parser.add_argument("--output", type=Path,
                        default=Path("build/validation/private-alpha-holdout.json"))
    args = parser.parse_args()
    root = args.repo_root.resolve()
    result = run(root, manifest_path=args.manifest, raw_source_path=args.raw_source,
                 outcomes_path=args.outcomes)
    path = args.output if args.output.is_absolute() else root / args.output
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(result, indent=2, allow_nan=False) + "\n", "utf-8")
    print(result["result"], "live_execution_authorized=False")
    return 0 if result["result"].startswith(("PASS_", "BLOCKED_")) else 1

if __name__ == "__main__":
    raise SystemExit(main())
