from __future__ import annotations

import argparse
import ast
import json
import pathlib
import sys


def readiness_authority_is_health_only(path: pathlib.Path) -> bool:
    tree = ast.parse(path.read_text(encoding="utf-8"))
    calls = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
            if node.func.attr == "set" and node.args:
                calls.append(node.args[0])
    if not calls:
        return False
    return all(
        isinstance(arg, ast.Attribute)
        and isinstance(arg.value, ast.Name)
        and arg.value.id == "ReadinessSignal"
        and arg.attr == "HEALTH"
        for arg in calls
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()
    root = args.repo_root.resolve()
    sys.path.insert(0, str(root / "src"))

    from katarina.contracts.runtime import RuntimeMode
    from katarina.core.readiness import ReadinessGate, ReadinessSignal
    from katarina.health.engine import HealthSafetyEngine, HealthState

    config = json.loads(
        (root / "config" / "health_safety_engine_draft.json").read_text(
            encoding="utf-8"
        )
    )
    schema = json.loads(
        (root / "protocol" / "kat1_message_schemas_v1.json").read_text(
            encoding="utf-8"
        )
    )
    names = {item["name"] for item in schema["messages"]}
    engine_path = root / "src" / "katarina" / "health" / "engine.py"
    source = engine_path.read_text(encoding="utf-8")

    checks = {
        "stage08_freeze_present": (
            root / "docs" / "reviews" / "STAGE_08_FREEZE_RECORD.md"
        ).is_file(),
        "kat1_health_inputs_present": {
            "HEARTBEAT",
            "SESSION_STATE",
            "HEALTH_EVENT",
            "TRANSPORT_METRICS",
        }.issubset(names),
        "authority_no_trade": config["authority"]["may_trade"] is False,
        "authority_no_risk_approval": (
            config["authority"]["may_approve_risk"] is False
        ),
        "authority_no_execution_arm": (
            config["authority"]["may_arm_execution"] is False
        ),
        "authority_health_only": readiness_authority_is_health_only(engine_path),
        "no_broker_order_send": "OrderSend(" not in source,
        "heartbeat_stale_guard": "HEARTBEAT_STALE" in source,
        "critical_queue_guard": "CRITICAL_QUEUE_FULL" in source,
        "clock_skew_guard": "CLOCK_SKEW_BLOCKED" in source,
        "recovery_hysteresis": "healthy_streak_required" in source,
    }

    now = 2_000_000_000_000_000_000
    engine = HealthSafetyEngine()
    engine.observe_data_fresh(True)
    engine.observe_heartbeat(
        {
            "critical_queue_depth": 0,
            "market_queue_depth": 0,
            "last_broker_observation_ns": now,
        },
        observed_at_ns=now,
    )
    engine.observe_session_state(
        {
            "terminal_connected": 1,
            "session_open": 0,
            "fresh_tick": 0,
            "terminal_trade_allowed": 0,
            "mql_trade_allowed": 0,
            "symbol_trade_allowed": 0,
            "terminal_ping_us": 10_000,
            "server_time_ns": now,
        }
    )
    engine.observe_transport_metrics(
        {"decode_errors": 0, "rtt_us_p99": 10_000},
        observed_at_ns=now,
    )
    healthy = {
        "data_health": 1,
        "transport_health": 1,
        "execution_health": 1,
        "reconciliation_health": 1,
        "journal_health": 1,
        "clock_health": 1,
        "snapshot_health": 1,
    }
    engine.observe_health_event(healthy, observed_at_ns=now)
    engine.observe_health_event(healthy, observed_at_ns=now)

    readiness = ReadinessGate(RuntimeMode.LIVE)
    snapshot = engine.apply_readiness(readiness, now_ns=now)
    checks["runtime_overall_ok"] = snapshot.overall is HealthState.OK
    checks["runtime_health_ready"] = readiness.is_set(ReadinessSignal.HEALTH)
    checks["runtime_risk_not_ready"] = not readiness.is_set(ReadinessSignal.RISK)
    checks["runtime_execution_not_armed"] = not readiness.is_set(
        ReadinessSignal.EXECUTION_ARMED
    )
    checks["runtime_live_execution_false"] = not readiness.live_execution_ready

    engine.observe_heartbeat(
        {
            "critical_queue_depth": 2048,
            "market_queue_depth": 0,
            "last_broker_observation_ns": now,
        },
        observed_at_ns=now,
    )
    blocked = engine.apply_readiness(readiness, now_ns=now)
    checks["runtime_queue_pressure_blocks"] = (
        blocked.transport is HealthState.BLOCKED
        and not readiness.is_set(ReadinessSignal.HEALTH)
    )

    passed = all(checks.values())
    evidence = {
        "schema_version": 1,
        "stage": "09",
        "proof_type": "KATARINA_STAGE09_FINAL_CLEARANCE",
        "checks": checks,
        "live_risk_ready": False,
        "ready_for_stage10": passed,
        "result": (
            "PASS_STAGE09_FINAL_CLEARANCE"
            if passed
            else "FAIL_STAGE09_FINAL_CLEARANCE"
        ),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(evidence, indent=2), encoding="utf-8")
    print(json.dumps(evidence, indent=2))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
