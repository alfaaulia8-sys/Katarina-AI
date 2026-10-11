#!/usr/bin/env python3
"""Check complete 7-market x 10-hypothesis research scope without granting alpha.

Future event-level broker data must enter a separately attested evidence import.
This audit checks the freeze/protocol and explicitly reports zero validated alpha.
"""
import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

from katarina.research.alpha_survival import REGIME_ROUTES, FrozenHypothesis, assess


def utc(text):
    d = datetime.fromisoformat(text.replace("Z", "+00:00"))
    if d.tzinfo is None:
        raise ValueError("naive_protocol_date")
    return d.astimezone(timezone.utc)


def audit(root: Path) -> dict:
    config = json.loads((root / "config/research/alpha_regime_program_v1.json").read_text("utf-8"))
    stage14 = json.loads((root / "config/stages/stage14.json").read_text("utf-8"))
    stage15 = json.loads((root / "config/stages/stage15.json").read_text("utf-8"))
    final = json.loads((root / "docs/validation/2026-10-10-strategy-final-audit.json").read_text("utf-8"))
    frozen = utc(config["preregistration_effective_at_utc"])
    start = utc(config["new_holdout_start_utc"])
    end = utc(config["new_holdout_end_utc"])
    symbols = config["symbols"]
    assert frozen < start < end
    assert len(symbols) == len(set(symbols)) == 7
    assert stage14["policy_pending"] and stage15["policy_pending"]
    assert not any(c.get("live_execution_authority", True) for c in (stage14, stage15))
    assert final["validated_strategy"] is False
    assert final["live_risk_authorized"] is False
    real_states = set(config["directional_regimes"]) | {config["dual_direction_regime"]}
    all_states = real_states | set(config["no_trade_regimes"])
    assert all_states == set(REGIME_ROUTES)
    assert all(REGIME_ROUTES[r][0] == "WAIT" for r in config["no_trade_regimes"])
    candidates = 0
    routes = []
    for symbol in symbols:
        for state in sorted(real_states):
            side, playbook = REGIME_ROUTES[state]
            for position in (("BUY", "SELL") if side == "BOTH" else (side,)):
                candidates += 1
                h = FrozenHypothesis(
                    symbol, state, position, playbook, frozen, start, end, "0"*64,
                    len(symbols)*10, config["additional_cost_stress_R"])
                result = assess(h, [], audit_at=frozen)
                assert result["status"] == "BLOCKED_UNATTESTED_REAL_HOLDOUT_AND_COSTS"
                routes.append({"symbol":symbol,"state":state,"side":position,
                               "playbook":playbook,"status":"WAIT_UNVERIFIED_HYPOTHESIS"})
    assert candidates == 70, candidates
    return {
        "result":"PASS_ALPHA_RESEARCH_PROGRAM_FAIL_CLOSED",
        "hypotheses_preregistered":candidates,
        "symbols":len(symbols),
        "market_states":len(REGIME_ROUTES),
        "prior_final_strategy_candidates_rejected":sum(
            x.get("result")=="REJECTED" for x in final.get("cells", [])),
        "independent_holdout_available":False,
        "actual_costs_verified_for_all_symbols":False,
        "validated_alpha_count":0,
        "live_execution_authorized":False,
        "research_only":True,
        "proposed_routes":routes,
    }


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--repo-root",type=Path,default=Path("."))
    parser.add_argument("--output",type=Path,default=Path("build/validation/alpha-regime-program.json"))
    args=parser.parse_args()
    root=args.repo_root.resolve()
    data=audit(root)
    out=args.output if args.output.is_absolute() else root/args.output
    out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(json.dumps(data,indent=2)+"\n",encoding="utf-8")
    print(data["result"],"cells=",data["hypotheses_preregistered"],
          "validated_alpha=",data["validated_alpha_count"])
    return 0

if __name__=="__main__":
    raise SystemExit(main())
