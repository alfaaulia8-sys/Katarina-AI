"""Auditable GitHub-hosted specialist team for Katarina V1 build.

Four roles execute independently; QA and manager verify their receipts.
These are deterministic engineering workers, not fabricated independent AI
personas. Optional external model connections are separate and unverified.
No network writes, MT5, generated code execution, auto-merge or live trading.
"""
from __future__ import annotations

import argparse
import ast
from datetime import datetime, timezone
from hashlib import sha256
import json
import os
from pathlib import Path
import py_compile
from statistics import mean

ROOT = Path(__file__).resolve().parents[2]
ROLES = ("ideas", "coding", "math", "logic")
VERSION = "KATARINA_PARALLEL_TEAM_V1"
BASELINE = "2026-10-13"
BLOCKERS = (
    "EXTERNAL_MODELS_REAL_RESPONSES_UNVERIFIED",
    "BROKER_OHLC_AND_TICK_VALIDATION_PENDING",
    "INDEPENDENT_FORWARD_EDGE_NOT_PROVEN",
)


def _encode(obj):
    return json.dumps(obj, sort_keys=True, separators=(",", ":"),
                      ensure_ascii=True, allow_nan=False).encode("utf-8")


def _receipt(payload: dict) -> str:
    return sha256(_encode(payload)).hexdigest()


def _secure_role(name: str, commit: str, result: dict) -> dict:
    if name not in ROLES or not commit or len(commit) > 100:
        raise ValueError("bad_team_identity")
    record = {
        "version": VERSION,
        "role": name,
        "commit": commit,
        "run_environment": "GITHUB_HOSTED_RESEARCH_ONLY",
        "status": "PASS",
        "findings": result,
        "live_authorized": False,
        "writes_code": False,
        "deploys_vps": False,
        "real_broker_results": False,
    }
    record["receipt_sha256"] = _receipt(record)
    return record


def ideas() -> dict:
    from katarina.intelligence.autonomous_strategy_discovery import discover
    from scripts.research.run_autonomous_strategy_discovery import deterministic_fixture
    result = discover(deterministic_fixture(), seed=77,
                      population=12, generations=2)
    assert result["candidate_trials"] > 0
    assert result["orders_sent"] == 0
    assert not result["held_out_was_used_in_selection"]
    return {
        "mandate": "generate reproducible hypotheses and ranked candidate genomes",
        "source": "SYNTHETIC_FABRICATED_HOURLY_FIXTURE",
        "trials": result["candidate_trials"],
        "shortlisted": [
            {"candidate_id": x["candidate_id"],
             "genome": x["genome"],
             "status": x["research_status"]}
            for x in result["candidate_rules"][:3]
        ],
        "next_proposal": "validate candidates on independently sourced UTC bars",
        "recommendation": "RESEARCH_ONLY",
    }


def coding() -> dict:
    paths = (
        "src/katarina/intelligence/autonomous_strategy_discovery.py",
        "src/katarina/intelligence/self_evolution_lab.py",
        "src/katarina/governance/multi_model_evolution_review.py",
        "src/katarina/governance/evolution.py",
    )
    hashes = {}
    for relative in paths:
        file = ROOT / relative
        py_compile.compile(str(file), doraise=True)
        tree = ast.parse(file.read_text(encoding="utf-8"))
        assert isinstance(tree, ast.Module)
        hashes[relative] = sha256(file.read_bytes()).hexdigest()
    assert len(set(hashes.values())) == len(hashes)
    return {
        "mandate": "compile and fingerprint strategy, learner and governance code",
        "modules_compiled": len(hashes),
        "sha256_per_source": hashes,
        "next_proposal": "implement approved patches only after independent QA",
        "recommendation": "NO_AUTONOMOUS_CODE_CHANGES",
    }


def math() -> dict:
    from katarina.intelligence.autonomous_strategy_discovery import (
        Genome, Rule, _simulate,
    )
    from scripts.research.run_autonomous_strategy_discovery import deterministic_fixture
    bars = deterministic_fixture()
    genome = Genome("SELL", (Rule("momentum_3", "<=", -0.5),), 1., 1.5, 3)
    indices = (60, 90, 110, 140, 170, 210, 250, 290)
    base = [_simulate(bars, i, genome, .7, spread_fraction=0,
                      fee_r=0)[1] for i in indices]
    stressed = [_simulate(bars, i, genome, .7, spread_fraction=.08,
                          fee_r=.12)[1] for i in indices]
    assert all(b <= a + 0.000001 for a, b in zip(base, stressed))
    return {
        "mandate": "check cost-stress monotonicity and sample limitations",
        "synthetic_samples": len(indices),
        "base_mean_modelled_r": round(mean(base), 6),
        "stress_mean_modelled_r": round(mean(stressed), 6),
        "every_stressed_result_not_better": True,
        "confidence": "NOT_REAL_ALPHA_EVIDENCE",
        "next_proposal": "calibrate commissions/spread/slippage to verified broker data",
        "recommendation": "COST_AWARE_RESEARCH_ONLY",
    }


def logic() -> dict:
    from katarina.intelligence.autonomous_strategy_discovery import (
        _features, Candle, discover,
    )
    from scripts.research.run_autonomous_strategy_discovery import deterministic_fixture
    bars = deterministic_fixture()
    altered = list(bars)
    i = 110
    source = altered[i]
    altered[i] = Candle(source.close_at, source.open,
                        source.high+20.,source.low-20.,source.close)
    assert _features(bars)[90] == _features(tuple(altered))[90]
    replay = discover(bars, seed=11, population=8, generations=1)
    assert not replay["held_out_was_used_in_selection"]
    assert replay["orders_sent"] == 0
    assert replay["production_action"] == "WAIT"
    return {
        "mandate": "verify causal features, immutable holdout and risk invariants",
        "future_bar_perturbation_did_not_change_prior_features": True,
        "holdout_used_for_selection": False,
        "orders_sent": 0,
        "production_action": "WAIT",
        "next_proposal": "add gap and multi-timeframe regime consistency tests",
        "recommendation": "RULES_FAIL_CLOSED",
    }


def specialist(role: str, commit: str) -> dict:
    workers = {"ideas": ideas, "coding": coding,
               "math": math, "logic": logic}
    if role not in workers:
        raise ValueError("unknown_specialist")
    return _secure_role(role, commit, workers[role]())


def validate_specialists(folder: Path, commit: str) -> dict:
    summaries = {}
    for name in ROLES:
        file = folder / (name + ".json")
        if not file.is_file() or file.stat().st_size > 50000:
            raise ValueError("missing_or_oversized_specialist_artifact:" + name)
        record = json.loads(file.read_text(encoding="utf-8"))
        receipt = record.pop("receipt_sha256", None)
        if (record.get("version") != VERSION or
                record.get("role") != name or
                record.get("commit") != commit or
                record.get("status") != "PASS" or
                record.get("run_environment") != "GITHUB_HOSTED_RESEARCH_ONLY" or
                record.get("live_authorized") is not False or
                record.get("writes_code") is not False or
                record.get("deploys_vps") is not False or
                record.get("real_broker_results") is not False or
                not isinstance(record.get("findings"), dict) or
                receipt != _receipt(record)):
            raise ValueError("tampered_or_stale_specialist_result:" + name)
        facts = record["findings"]
        required = {
            "ideas": ("trials", "shortlisted"),
            "coding": ("modules_compiled", "sha256_per_source"),
            "math": ("synthetic_samples", "every_stressed_result_not_better"),
            "logic": ("holdout_used_for_selection", "production_action"),
        }
        if any(key not in facts for key in required[name]):
            raise ValueError("missing_role_evidence:" + name)
        if name == "ideas" and (not 0 < facts["trials"] <= 192 or
                                len(facts["shortlisted"]) > 3):
            raise ValueError("unbounded_ideas")
        if name == "coding" and facts["modules_compiled"] != 4:
            raise ValueError("missing_code_audit")
        if name == "math" and facts["every_stressed_result_not_better"] is not True:
            raise ValueError("bad_math_audit")
        if name == "logic" and (facts["holdout_used_for_selection"] is not False
                                or facts["production_action"] != "WAIT"):
            raise ValueError("unsafe_logic")
        summaries[name] = {
            "status": "PASS",
            "receipt_sha256": receipt,
            "next_proposal": facts.get("next_proposal"),
        }
    return summaries


def qa(folder: Path, commit: str, regression_pass: bool) -> dict:
    role_summary = validate_specialists(folder, commit)
    status = "PASS_RESEARCH_ENGINEERING" if regression_pass else "BLOCKED_TESTS"
    record = {
        "version": VERSION,
        "commit": commit,
        "role": "qa",
        "status": status,
        "specialist_receipts": role_summary,
        "regression_tests_passed": regression_pass,
        "missing_real_market_validation": True,
        "no_release_to_live": True,
        "no_code_merge_authority": True,
    }
    record["receipt_sha256"] = _receipt(record)
    return record


def manager(folder: Path, commit: str) -> dict:
    file=folder/"qa.json"
    if not file.is_file() or file.stat().st_size > 50000:
        raise ValueError("qa_report_required")
    payload=json.loads(file.read_text(encoding="utf-8"))
    receipt=payload.pop("receipt_sha256",None)
    if (receipt != _receipt(payload) or payload.get("commit") != commit or
            payload.get("role") != "qa" or
            not isinstance(payload.get("specialist_receipts"),dict) or
            set(payload["specialist_receipts"]) != set(ROLES) or
            payload.get("no_release_to_live") is not True):
        raise ValueError("invalid_or_stale_qa_handoff")
    specialists=validate_specialists(folder,commit)
    if specialists != payload["specialist_receipts"]:
        raise ValueError("qa_specialist_handoff_mismatch")
    ok=(payload["status"] == "PASS_RESEARCH_ENGINEERING" and
        payload["regression_tests_passed"] is True)
    result={
        "version":VERSION,"role":"manager","commit":commit,
        "qa_result":payload["status"],
        "specialist_count":len(specialists),
        "specialist_status":{k:v["status"] for k,v in specialists.items()},
        "engineering_status":"PASS" if ok else "BLOCKED",
        "v1_release_status":"BLOCKED_UNTIL_ALL_ROADMAP_GATES_PASS",
        "known_blockers":list(BLOCKERS),
        "week_target":"2026-10-19",
        "next_priority":"VERIFY_TWO_REAL_EXTERNAL_MODEL_RESPONSES",
        "decision":"CONTINUE_OFFLINE_BUILD" if ok else "STOP_AND_FIX_QA",
        "orders_authorized":0,"live_execution_authorized":False,
        "auto_code_merge_authorized":False,
    }
    result["receipt_sha256"]=_receipt(result)
    return result


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("role",choices=(*ROLES,"qa","manager"))
    parser.add_argument("--folder",type=Path,default=Path("build/team/roles"))
    parser.add_argument("--commit",default=os.environ.get("GITHUB_SHA","local-test"))
    parser.add_argument("--regression",choices=("pass","fail"),default="fail")
    args=parser.parse_args()
    if args.role=="qa":
        record=qa(args.folder,args.commit,args.regression=="pass")
        output=args.folder/"qa.json"
    elif args.role=="manager":
        record=manager(args.folder,args.commit)
        output=args.folder/"manager.json"
    else:
        record=specialist(args.role,args.commit)
        output=args.folder/(args.role+".json")
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(json.dumps(record,indent=2,sort_keys=True,
                                 allow_nan=False)+"\n",encoding="utf-8")
    print("KATARINA_TEAM_ROLE",args.role,record["status"] if "status" in record
          else record["decision"],record["receipt_sha256"])

if __name__=="__main__":
    main()
