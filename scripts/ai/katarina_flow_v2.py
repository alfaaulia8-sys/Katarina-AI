"""Katarina V1 team scheduler and evidence-bound multi-role delivery pipeline.

This program is a deterministic GitHub-hosted orchestration worker; the
roles are NOT independently conscious LLM agents. No VPS changes, API keys,
code writes, automated PRs/merges, broker calls or production promotion.
"""
from __future__ import annotations

import argparse
import ast
from datetime import datetime, timedelta, timezone
from hashlib import sha256
import json
import os
from pathlib import Path
import py_compile
import re
import sys

from scripts.ai.management_workplan import audit_role, load_plan, verify_role, management_summary
from scripts.ai.management_resources import observe_workspace, safe_cache_inventory

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))  # script entrypoints need repository imports
SPECIALISTS = (
    "ideas", "coding", "math", "logic", "builder", "debugger",
    "runner_ops", "data", "ai_integration", "infrastructure", "security",
)
VERSION = "KATARINA_SCHEDULER_TEAM_V2"
WEEK_START = "2026-10-13"
DEADLINE = "2026-10-19"
PLAN = (
    "AUDIT_AND_LOCK_SCOPE",
    "VERIFY_TWO_REAL_EXTERNAL_AI_MODELS",
    "VALIDATE_REAL_MARKET_DATA",
    "DISCOVER_ON_REAL_CAUSAL_DATA",
    "TEST_SANDBOX_IMPROVEMENTS",
    "FULL_SYSTEM_INTEGRATION_QA",
    "FREEZE_V1_RESEARCH_RELEASE_CANDIDATE",
)
RELEASE_BLOCKERS = (
    "EXTERNAL_TWO_MODEL_RESPONSES_NOT_VERIFIED",
    "REAL_OHLC_TICK_INPUT_NOT_VALIDATED",
    "REAL_PROSPECTIVE_EDGE_NOT_PROVEN",
)
MAX_PARALLEL = 4
WIB = timezone(timedelta(hours=7), 'Asia/Jakarta')


def digest(record: dict) -> str:
    return sha256(json.dumps(
        record, sort_keys=True, separators=(",",":"), allow_nan=False
    ).encode("utf-8")).hexdigest()


def seal(record: dict) -> dict:
    record = dict(record)
    record["receipt_sha256"] = digest(record)
    return record


def open_receipt(path: Path, *, commit: str, kind: str) -> dict:
    if not path.is_file() or path.stat().st_size > 50000:
        raise ValueError("missing_or_oversized_"+kind)
    data = json.loads(path.read_text(encoding="utf-8"))
    receipt = data.pop("receipt_sha256",None)
    if receipt != digest(data):
        raise ValueError("tampered_"+kind+"_receipt")
    if (data.get("commit") != commit or data.get("version") != VERSION
            or data.get("kind") != kind):
        raise ValueError("stale_"+kind+"_receipt")
    return data


def scheduler(commit: str, now: datetime) -> dict:
    if not re.fullmatch(r"[0-9a-f]{40}",commit):
        raise ValueError("github_commit_sha_required")
    if now.tzinfo is None:
        raise ValueError("timezone_aware_clock_required")
    local_day = now.astimezone(WIB).date().isoformat()
    day_index = (datetime.fromisoformat(local_day) -
                 datetime.fromisoformat(WEEK_START)).days
    if 0 <= day_index < len(PLAN):
        current = PLAN[day_index]
        day = day_index+1
    elif day_index < 0:
        current = "NOT_STARTED"
        day = 0
    else:
        current = "DEADLINE_PASSED_REPORT_BLOCKERS"
        day = 8
    workplan, plan_digest = load_plan(ROOT)
    return seal({
        "kind":"schedule","version":VERSION,"commit":commit,
        "management_task_plan_sha256":plan_digest,
        "management_task_count":len(workplan["tasks"]),
        "current_day_wib":local_day,"deadline_wib":DEADLINE,
        "day_index":day,"current_priority":current,
        "locked_plan":list(PLAN),
        "parallel_roles":list(SPECIALISTS),
        "max_parallel":MAX_PARALLEL,"retry_limit":1,
        "dependency_order":["scheduler","specialists","qa","manager","release"],
        "execution":"MANUAL_GITHUB_HOSTED_ONLY",
        "auto_merge":False,"auto_deploy":False,"live_trading":False,
        "team_ready_to_claim_completion":False,
    })


def _simple_compile(path: str) -> str:
    source=ROOT/path
    ast.parse(source.read_text(encoding="utf-8"),filename=path)
    py_compile.compile(str(source),doraise=True)
    return sha256(source.read_bytes()).hexdigest()


def _extra_role(role: str) -> dict:
    if role=="builder":
        modules=[
            "src/katarina/intelligence/autonomous_strategy_discovery.py",
            "src/katarina/intelligence/self_evolution_lab.py",
            "src/katarina/governance/multi_model_evolution_review.py",
            "scripts/ai/katarina_flow_v2.py",
        ]
        return {"kind":"COMPILE_AND_INTEGRATE_AUDIT",
                "compiled_modules":{p:_simple_compile(p) for p in modules},
                "new_build_ready":"RESEARCH_ONLY"}
    if role=="debugger":
        checked=[
            "scripts/ai/katarina_team.py",
            "scripts/ai/katarina_flow_v2.py",
            "scripts/research/run_autonomous_strategy_discovery.py",
        ]
        return {"kind":"ERROR_TRIAGE",
                "syntax_health":{p:_simple_compile(p) for p in checked},
                "auto_patch":False,
                "failure_handling":"REPRODUCE_THEN_BLOCK_QA_IF_FAILED",
                "current_failures_from_CI":"NOT_AVAILABLE_BEFORE_QA"}
    if role=="runner_ops":
        path=ROOT/".github/workflows/katarina-orchestrated-team.yml"
        source=path.read_text(encoding="utf-8")
        assert "  workflow_dispatch:" in source
        assert "runs-on: ubuntu-latest" in source
        assert "max-parallel: 4" in source
        assert "cancel-in-progress: true" in source
        assert "permissions:\n  contents: read" in source
        assert "persist-credentials: false" in source
        assert not re.search(r"(?m)^  (push|pull_request|schedule):",source)
        return {"kind":"RUNNER_HEALTH_AND_FANOUT",
                "only_manual":True,"max_parallel":4,
                "concurrency_cancel":True,
                "runner_kind":"GITHUB_HOSTED_UBUNTU",
                "workflow_hash":sha256(source.encode()).hexdigest()}
    if role=="data":
        from scripts.research.run_autonomous_strategy_discovery import deterministic_fixture
        from katarina.intelligence.autonomous_strategy_discovery import validate_bars
        bars=deterministic_fixture()
        validate_bars(bars)
        return {"kind":"DATA_INTEGRITY",
                "synthetic_bars_validated":len(bars),
                "source":"FABRICATED_SYNTHETIC_ONLY",
                "real_OHLC_validated":False,
                "utc_order_verified":True}
    if role=="ai_integration":
        from katarina.governance.external_model_bridge import (
            MODELS, GATEWAY, brief_for_external_models)
        assert len(MODELS)==2
        assert len({x.split("/",1)[0] for x in MODELS})==2
        assert GATEWAY.startswith("https://models.github.ai/")
        example=brief_for_external_models({
            "review_receipt_sha256":"a"*64,
            "decision":"WAIT_FOR_VERIFIED_EVIDENCE",
            "cohorts":[],
        })
        assert example["independently_verified_real_trades"]==0
        return {"kind":"AI_ADAPTER_CONTRACT",
                "model_authors":[x.split("/",1)[0] for x in MODELS],
                "external_calls_made_in_this_role":0,
                "real_two_model_connection_verified":False,
                "research_brief_allowlisted":True}
    if role=="infrastructure":
        # Ephemeral GitHub runner RAM is not a VPS service.
        # The worker observes its own memory; it never kills processes,
        # clears other jobs, deletes production files or restarts services.
        ram={}
        mem=Path("/proc/meminfo")
        if mem.is_file():
            for line in mem.read_text(encoding="ascii").splitlines():
                key,_,value=line.partition(":")
                if key in ("MemTotal","MemAvailable"):
                    ram[key+"_KiB"]=int(value.strip().split()[0])
        if ram and not (0 < ram["MemAvailable_KiB"] <= ram["MemTotal_KiB"]):
            raise RuntimeError("runner_memory_inconsistent")
        return {"kind":"GITHUB_HOSTED_RESOURCE_OBSERVER",
                "memory_snapshot":ram,"ram_cleanup":"NOT_APPLICABLE_ON_EPHEMERAL_RUNNER",
                "processes_terminated":0,"vps_files_deleted":0}
    if role=="security":
        wf=(ROOT/".github/workflows/katarina-orchestrated-team.yml").read_text()
        assert "permissions:\n  contents: read" in wf
        assert "persist-credentials: false" in wf
        assert "models: write" not in wf
        assert "write-all" not in wf
        assert "self-hosted" not in re.sub(
            r"(?m)^\s*#.*$", "", wf).lower()
        assert not re.search(r"(?m)^  (push|schedule|pull_request):",wf)
        return {"kind":"SECURITY_RISK_AUDIT",
                "workflow_read_only":True,
                "no_unattended_trigger":True,
                "no_self_hosted_execution":True,
                "no_repo_token_persistence":True,
                "production_risk_fraction":0}
    raise ValueError("unknown_team_role:"+role)


def specialist(role: str, plan: dict, commit: str) -> dict:
    if role not in SPECIALISTS or role not in plan["parallel_roles"]:
        raise ValueError("role_not_scheduled")
    if role in ("ideas","coding","math","logic"):
        from scripts.ai.katarina_team import specialist as original
        result=original(role,commit)
        if result["status"]!="PASS":
            raise ValueError("legacy_specialist_failed")
        facts=dict(result["findings"])
        facts["legacy_specialist_receipt_sha256"]=result["receipt_sha256"]
    else:
        facts=_extra_role(role)
    task_evidence = audit_role(ROOT, role)
    if task_evidence["plan_sha256"] != plan["management_task_plan_sha256"]:
        raise ValueError("specialist_schedule_task_mismatch")
    return seal({
        "kind":"specialist","version":VERSION,"commit":commit,
        "management_task_evidence":task_evidence,
        "role":role,"status":"PASS_ENGINEERING_ONLY",
        "schedule_receipt_sha256":plan["receipt_sha256"],
        "findings":facts,
        "broker_real_profits_verified":False,
        "model_production_authorized":False,
        "can_write_repo":False,"can_execute_orders":False,
    })


def qa(folder: Path, commit: str, regression_pass: bool) -> dict:
    plan_raw=json.loads((folder/"schedule.json").read_text())
    sched=open_receipt(folder/"schedule.json",commit=commit,kind="schedule")
    _, expected_plan_digest = load_plan(ROOT)
    if (sched["management_task_plan_sha256"] != expected_plan_digest or
            sched["management_task_count"] != len(SPECIALISTS)):
        raise ValueError("management_workplan_stale")
    if sched["parallel_roles"] != list(SPECIALISTS) or sched["max_parallel"]>4:
        raise ValueError("schedule_scope_changed")
    results={}
    for role in SPECIALISTS:
        record=open_receipt(folder/(role+".json"),commit=commit,
                            kind="specialist")
        if (record.get("role")!=role or
                record.get("status")!="PASS_ENGINEERING_ONLY" or
                record.get("schedule_receipt_sha256")!=plan_raw["receipt_sha256"] or
                record.get("can_write_repo") is not False or
                record.get("can_execute_orders") is not False or
                record.get("model_production_authorized") is not False or
                not isinstance(record.get("findings"),dict)):
            raise ValueError("specialist_scope_or_integrity_failure:"+role)
        verify_role(ROOT, role, record.get("management_task_evidence"))
        if record["management_task_evidence"]["plan_sha256"] != sched["management_task_plan_sha256"]:
            raise ValueError("specialist_management_scope_mismatch")
        facts=record["findings"]
        if role=="infrastructure" and (facts.get("processes_terminated")!=0 or
                                      facts.get("vps_files_deleted")!=0):
            raise ValueError("unsafe_ram_cleaning")
        if role=="security" and facts.get("production_risk_fraction")!=0:
            raise ValueError("unsafe_security_result")
        results[role]=record["receipt_sha256"] if "receipt_sha256" in record else digest(record)
    return seal({
        "kind":"qa","version":VERSION,"commit":commit,
        "management_work_items_replayed":len(results),
        "management_workplan_sha256":expected_plan_digest,
        "status":"PASS_ENGINEERING_ONLY" if regression_pass else "BLOCKED_REGRESSION",
        "regression_passed":bool(regression_pass),
        "schedule_receipt_sha256":plan_raw["receipt_sha256"],
        "independent_specialist_receipts":results,
        "all_specialists_checked":len(results)==len(SPECIALISTS),
        "live_execution_authorized":False,"auto_merge":False,
    })


def manager(folder: Path, commit: str) -> dict:
    sched=open_receipt(folder/"schedule.json",commit=commit,kind="schedule")
    check=qa(folder,commit,regression_pass=True)
    record=open_receipt(folder/"qa.json",commit=commit,kind="qa")
    if (record.get("status")!="PASS_ENGINEERING_ONLY" or
            record.get("regression_passed") is not True or
            record["independent_specialist_receipts"]!=check[
                "independent_specialist_receipts"]):
        raise ValueError("qa_not_approved")
    source_audits = {
        role: open_receipt(folder / (role + ".json"), commit=commit, kind="specialist")["management_task_evidence"]
        for role in SPECIALISTS
    }
    verified_work = management_summary(ROOT, source_audits)
    resources = observe_workspace(ROOT)
    cache_report = safe_cache_inventory(ROOT, max_paths=100)
    if record.get("management_work_items_replayed") != len(SPECIALISTS):
        raise ValueError("management_work_items_not_replayed")
    return seal({
        "kind":"manager","version":VERSION,"commit":commit,
        "management_work_summary":verified_work,
        "resource_safety_report": resources,
        "cache_inventory": cache_report,
        "specialists_verified":len(SPECIALISTS),
        "qa_passed":True,
        "plan_priority":sched["current_priority"],
        "week_deadline":DEADLINE,
        "engineering_status":"PASS",
        "release_status":"BLOCKED_UNTIL_REAL_AI_AND_MARKET_EVIDENCE",
        "remaining_blockers":list(RELEASE_BLOCKERS),
        "next_action":"VERIFY_REAL_MODEL_RESPONSES_AS_ROADMAP_D2",
        "auto_deployment":False,"live_trading":False,
    })


def release(folder: Path, commit: str) -> dict:
    record=open_receipt(folder/"manager.json",commit=commit,kind="manager")
    if record["engineering_status"]!="PASS" or record["live_trading"] is not False:
        raise ValueError("manager_or_governance_failed")
    return seal({
        "kind":"release","version":VERSION,"commit":commit,
        "build_team_status":"PASS",
        "v1_release_status":"BLOCKED",
        "reasons":list(RELEASE_BLOCKERS),
        "deadline_wib":DEADLINE,
        "release_candidate_promoted":False,
        "live_execution_enabled":False,
        "orders_sent":0,
    })


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("phase",choices=("scheduler","role","qa","manager","release"))
    parser.add_argument("--role",choices=SPECIALISTS)
    parser.add_argument("--folder",type=Path,default=Path("build/team-v2"))
    parser.add_argument("--commit",default=os.environ.get("GITHUB_SHA",""))
    parser.add_argument("--regression",choices=("pass","fail"),default="fail")
    arguments=parser.parse_args()
    folder=arguments.folder
    if arguments.phase=="scheduler":
        record=scheduler(arguments.commit,datetime.now(WIB))
        filename="schedule.json"
    elif arguments.phase=="role":
        p=json.loads((folder/"schedule.json").read_text())
        plan=open_receipt(folder/"schedule.json",commit=arguments.commit,
                          kind="schedule")
        plan["receipt_sha256"]=p["receipt_sha256"]
        record=specialist(arguments.role,plan,arguments.commit)
        filename=arguments.role+".json"
    elif arguments.phase=="qa":
        record=qa(folder,arguments.commit,arguments.regression=="pass")
        filename="qa.json"
    elif arguments.phase=="manager":
        record=manager(folder,arguments.commit)
        filename="manager.json"
    else:
        record=release(folder,arguments.commit)
        filename="release.json"
    folder.mkdir(parents=True,exist_ok=True)
    (folder/filename).write_text(
        json.dumps(record,indent=2,sort_keys=True,allow_nan=False)+"\n",
        encoding="utf-8")
    print("TEAM_FLOW_V2",arguments.phase,
          arguments.role or "",record.get("status",
          record.get("engineering_status",record.get("v1_release_status","PLAN"))),
          record["receipt_sha256"])


if __name__=="__main__":
    main()
