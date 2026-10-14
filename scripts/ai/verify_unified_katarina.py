"""Single manual, no-orders acceptance view of the *existing* Katarina stack.

Does not start MT5, connect networks, create workers, place orders, alter
configurations, write data or authorize promotions. Intended for pinned
GitHub/VPS source synchronization and optional read-only shadow DB checking.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
from hashlib import sha256
import importlib
import json
from pathlib import Path
import sqlite3
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT / "src"))


def verify(profile: dict, *, root: Path = ROOT, shadow_db: Path | None = None) -> dict:
    if profile.get("schema_version") != 1 or profile.get("profile") != "KATARINA_UNIFIED_V1_RESEARCH_ONLY":
        raise ValueError("unrecognized_unified_profile")
    parts=profile.get("canonical")
    disabled=profile.get("deferred")
    modes=profile.get("operating_mode")
    if not isinstance(parts,dict) or len(parts)!=11 or not isinstance(disabled,dict):
        raise ValueError("incomplete_unified_component_registry")
    if set(disabled)!={
        "external_ai_workers","autonomous_source_rewrite",
        "unverified_broker_provenance","unverified_broker_clock",
        "automatic_capital_state_migration","background_scheduler",
        "live_execution"
    } or any(type(flag) is not bool or flag for flag in disabled.values()):
        raise ValueError("unapproved_unified_capability_enabled")
    if not isinstance(modes,dict) or modes.get("order_submission")!="DISABLED":
        raise ValueError("order_submission_must_remain_disabled")
    if modes.get("core")!="TESTER_ONLY" or modes.get("broker")!="OFFLINE_ADAPTER_IMPORT_ONLY":
        raise ValueError("unsafe_runtime_mode")
    limits=profile.get("owner_limits")
    expected={
        "profit_lock_fraction":.25,
        "max_risk_per_entry_fraction":.05,
        "max_open_risk_fraction":.08,
        "caution_drawdown_from":.10,
        "recovery_only_from":.23,
        "extreme_drawdown_from":.35,
    }
    if not isinstance(limits,dict) or set(limits)!=set(expected) or any(
        type(limits[k]) not in (float,int) or limits[k]!=v
        for k,v in expected.items()
    ):
        raise ValueError("owner_limits_changed")
    digest={}
    for name,rel in sorted(parts.items()):
        if (not isinstance(rel,str) or not rel.startswith(("src/","scripts/"))
                or Path(rel).is_absolute() or ".." in Path(rel).parts):
            raise ValueError("invalid_canonical_module_path")
        path=root/rel
        if not path.is_file():
            raise ValueError("missing_canonical_component:"+name)
        digest[name]=sha256(path.read_bytes()).hexdigest()

    # Validate actual import and construction of non-trading core, risk,
    # reserve accounting and a real but order-free shadow learning path.
    from katarina.contracts.runtime import RuntimeMode
    from katarina.core.orchestrator import KatarinaOrchestrator,OrchestratorConfig
    from katarina.engines.risk import RiskGovernor
    from katarina.engines.capital import CapitalCompoundingEngine
    from katarina.intelligence.prospective_shadow_book import ProspectiveShadowBook
    from katarina.intelligence.self_evolution_lab import (
        evaluate_shadow_self_evolution,derive_shadow_research_policy,
    )
    from katarina.adapters.mt5_account_pnl import Mt5ReadOnlyPnLAdapter
    core=KatarinaOrchestrator(OrchestratorConfig(RuntimeMode.TESTER,32))
    governor=RiskGovernor.from_config(root/"config/risk_governor_v2.json")
    capital=CapitalCompoundingEngine()
    if core.new_live_risk_allowed or capital.reserve_fraction!=.25:
        raise ValueError("unsafe_core_or_capital")
    if (governor.hard_per_trade>.05 or governor.max_open_risk>.08
            or governor.max_drawdown>.35 or governor.max_daily_drawdown>.35):
        raise ValueError("owner_risk_limits_exceeded")
    if not callable(Mt5ReadOnlyPnLAdapter):
        raise ValueError("broker_read_only_adapter_missing")
    if shadow_db is None:
        db=sqlite3.connect(":memory:")
        db_source="IN_MEMORY_EMPTY_NO_MARKET_EDGE"
        source_path=None
    else:
        target=Path(shadow_db).resolve(strict=True)
        if not target.is_file() or target.suffix.lower() not in (".db",".sqlite",".sqlite3"):
            raise ValueError("invalid_readonly_shadow_db")
        db=sqlite3.connect("file:"+target.as_posix()+"?mode=ro",uri=True)
        db_source="READ_ONLY_EXISTING_SQLITE"
        source_path=str(target)
    try:
        if shadow_db is None:
            ProspectiveShadowBook(db)
        report=evaluate_shadow_self_evolution(db,as_of_utc=datetime.now(timezone.utc))
        proposal=derive_shadow_research_policy(report)
    finally:
        db.close()
    return {
        "profile":profile["profile"],
        "status":"INTEGRATED_OFFLINE_ENGINEERING_ONLY",
        "modules_verified":len(digest),
        "module_sha256":digest,
        "mode":"TESTER_NO_ORDERS",
        "management":"MANUAL_ONLY",
        "unverified_optional_components_disabled":True,
        "shadow_source":db_source,
        "shadow_db_path":source_path,
        "shadow_observations":report["rows_read"],
        "shadow_cohorts":len(report["cohorts"]),
        "learning_integrity":report["data_integrity"],
        "learning_policy_valid":proposal.integrity_ok,
        "learning_source_sha256":report["source_digest_sha256"],
        "real_broker_edge_proven":False,
        "human_live_approval":False,
        "live_execution_authorized":False,
        "orders_submitted":0,
    }


def main() -> None:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile",type=Path,default=ROOT/"config/katarina_unified_v1.json")
    parser.add_argument("--shadow-db",type=Path,default=None)
    args=parser.parse_args()
    profile=json.loads(args.profile.read_text(encoding="utf-8"))
    print(json.dumps(verify(profile,shadow_db=args.shadow_db),indent=2,sort_keys=True))


if __name__=="__main__":
    main()
