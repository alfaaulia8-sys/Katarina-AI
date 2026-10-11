#!/usr/bin/env python3
"""Fail-closed Stage 14/15 audit: exploratory selection is NOT policy approval."""
from __future__ import annotations
import argparse
import json
from pathlib import Path


def inspect(selection: dict, final: dict, stage14: dict, stage15: dict) -> dict:
    errors = []
    if selection.get("policy_sha256") != final.get("policy_sha256"):
        errors.append("policy_hash_mismatch")
    if not selection.get("research_only") or not final.get("research_only"):
        errors.append("research_boundary_missing")
    if selection.get("live_risk_authorized") is not False or final.get("live_risk_authorized") is not False:
        errors.append("live_risk_claim_without_authorization")
    if selection.get("validated_strategy") is not False or final.get("validated_strategy") is not False:
        errors.append("unreviewed_strategy_promotion")
    if not stage14.get("policy_pending") or not stage15.get("policy_pending"):
        errors.append("unapproved_policy_marked_final")
    if any(stage.get("live_execution_authority", True) for stage in (stage14, stage15)):
        errors.append("execution_authority_enabled")
    choices = selection.get("choices", [])
    cells = final.get("cells", [])
    if not isinstance(choices, list) or not isinstance(cells, list):
        errors.append("invalid_candidate_cells")
        choices, cells = [], []
    chosen = {(c.get("side"), c.get("regime"), c.get("candidate")) for c in choices}
    audited = {(c.get("side"), c.get("regime"), c.get("candidate")) for c in cells}
    if not chosen or not chosen.issubset(audited):
        errors.append("missing_final_candidate_evidence")
    for cell in cells:
        if cell.get("result") not in ("REJECTED", "PASS_RESEARCH_SCREEN"):
            errors.append("unknown_final_result")
    notes = " ".join(str(x) for x in final.get("limitations", []))
    already_seen = "previously inspected" in notes.lower()
    reasons = []
    if already_seen:
        reasons.append("final_period_previously_inspected_not_independent")
    if any(c.get("result") == "REJECTED" for c in cells):
        reasons.append("one_or_more_selected_candidates_rejected_in_final")
    if not any(c.get("side") == "BUY" for c in cells):
        reasons.append("buy_side_final_evidence_missing")
    reasons.extend(("strategy_policy_unfinalized", "live_authorization_not_requested"))
    if errors:
        status = "FAIL_STRATEGY_RESEARCH_EVIDENCE_INTEGRITY"
    else:
        status = "PASS_STRATEGY_EVIDENCE_FAIL_CLOSED"
    return {
        "result": status,
        "integrity_errors": sorted(set(errors)),
        "stage14_15_release_qualified": False,
        "independent_blind_holdout_confirmed": False,
        "live_execution_enabled": False,
        "selection_candidates": len(choices),
        "final_candidates": len(cells),
        "final_rejections": sum(c.get("result") == "REJECTED" for c in cells),
        "buy_side_final_candidates": sum(c.get("side") == "BUY" for c in cells),
        "sell_side_final_candidates": sum(c.get("side") == "SELL" for c in cells),
        "blocked_reasons": reasons,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, default=Path("."))
    parser.add_argument("--output", type=Path,
                        default=Path("build/validation/stage14-15-research-honesty.json"))
    args = parser.parse_args()
    repo = args.repo_root.resolve()
    load = lambda p: json.loads((repo / p).read_text(encoding="utf-8"))
    report = inspect(
        load("docs/validation/2026-10-10-strategy-selection.json"),
        load("docs/validation/2026-10-10-strategy-final-audit.json"),
        load("config/stages/stage14.json"),
        load("config/stages/stage15.json"),
    )
    path = args.output if args.output.is_absolute() else repo / args.output
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(report["result"], report["blocked_reasons"])
    return 0 if not report["integrity_errors"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
