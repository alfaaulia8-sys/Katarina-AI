from __future__ import annotations

import argparse
import ast
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]


def check_readiness_authority(engine_path: pathlib.Path) -> bool:
    tree = ast.parse(engine_path.read_text(encoding="utf-8"))
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        func = node.func
        if not isinstance(func, ast.Attribute) or func.attr != "set":
            continue
        if not node.args:
            return False
        arg = node.args[0]
        if not (
            isinstance(arg, ast.Attribute)
            and isinstance(arg.value, ast.Name)
            and arg.value.id == "ReadinessSignal"
            and arg.attr == "DATA_FRESH"
        ):
            return False
    return True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=pathlib.Path, default=ROOT)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()
    root = args.repo_root.resolve()

    sys.path.insert(0, str(root / "src"))
    from katarina.contracts.runtime import EventEnvelope, RuntimeMode
    from katarina.core.readiness import ReadinessGate, ReadinessSignal
    from katarina.validation.engine import (
        DataValidationEngine,
        ValidatedIngestGate,
        ValidationReadinessTracker,
    )

    config = json.loads(
        (root / "config" / "data_validation_engine_draft.json").read_text(
            encoding="utf-8"
        )
    )
    schema = json.loads(
        (root / "protocol" / "kat1_message_schemas_v1.json").read_text(
            encoding="utf-8"
        )
    )
    names = {item["name"] for item in schema["messages"]}

    engine_path = root / "src" / "katarina" / "validation" / "engine.py"
    source = engine_path.read_text(encoding="utf-8")
    checks = {
        "stage07_freeze_present": (
            root / "docs" / "reviews" / "STAGE_07_FREEZE_RECORD.md"
        ).is_file(),
        "kat1_required_messages_present": {
            "TICK_EVENT",
            "BAR_EVENT",
            "SYMBOL_SPEC",
            "ACCOUNT_DELTA",
            "POSITION_DELTA",
            "ORDER_STATE_EVENT",
        }.issubset(names),
        "authority_no_trade": config["authority"]["may_trade"] is False,
        "authority_no_execution_arm": (
            config["authority"]["may_arm_execution"] is False
        ),
        "authority_no_position_sizing": (
            config["authority"]["may_size_positions"] is False
        ),
        "authority_no_order_submission": (
            config["authority"]["may_submit_orders"] is False
        ),
        "readiness_only_data_fresh": check_readiness_authority(engine_path),
        "no_broker_order_send": "OrderSend(" not in source,
        "symbol_spec_binding_present": "STALE_SYMBOL_SPEC" in source,
        "history_gap_guard_present": "HISTORY_SEQUENCE_GAP" in source,
        "ingest_accept_only_promotion": (
            "promoted_event=event if result.accepted else None" in source
        ),
        "account_semantics_present": "_validate_account_state" in source,
        "position_semantics_present": "_validate_position_state" in source,
        "order_semantics_present": "_validate_order_state" in source,
    }

    engine = DataValidationEngine()
    now = 2_000_000_000_000_000_000
    spec_event = EventEnvelope(
        topic="symbol.spec",
        source="mt5",
        source_time_ns=now,
        payload={
            "instrument_id": 1,
            "spec_revision": 1,
            "digits": 2,
            "price_scale": 2,
            "volume_scale": 2,
            "point_units": 1,
            "tick_size_units": 10,
            "volume_min_units": 1,
            "volume_max_units": 1000,
            "volume_step_units": 1,
            "canonical_symbol": "XAUUSD",
            "broker_symbol": "XAUUSD",
        },
    )
    tick_event = EventEnvelope(
        topic="market.tick",
        source="mt5",
        source_time_ns=now,
        payload={
            "instrument_id": 1,
            "spec_revision": 1,
            "bid_units": 265000,
            "ask_units": 265010,
        },
    )
    crossed = EventEnvelope(
        topic="market.tick",
        source="mt5",
        source_time_ns=now,
        payload={
            "instrument_id": 1,
            "spec_revision": 1,
            "bid_units": 265020,
            "ask_units": 265010,
        },
    )
    checks["runtime_spec_accept"] = engine.validate(
        spec_event, now_ns=now
    ).accepted
    gate = ValidatedIngestGate(engine)
    checks["runtime_valid_tick_promoted"] = gate.promote(
        tick_event, now_ns=now
    ).promoted
    checks["runtime_crossed_tick_blocked"] = not gate.promote(
        crossed, now_ns=now
    ).promoted

    tracker = ValidationReadinessTracker(("market.tick",))
    tracked_gate = ValidatedIngestGate(engine, tracker)
    tracked_gate.promote(tick_event, now_ns=now)
    readiness = ReadinessGate(RuntimeMode.LIVE)
    tracker.apply(readiness, now_ns=now)
    checks["runtime_data_fresh_set"] = readiness.is_set(
        ReadinessSignal.DATA_FRESH
    )
    checks["runtime_execution_not_armed"] = not readiness.is_set(
        ReadinessSignal.EXECUTION_ARMED
    )
    checks["runtime_live_execution_false"] = not readiness.live_execution_ready

    passed = all(checks.values())
    result = {
        "schema_version": 1,
        "stage": "08",
        "proof_type": "KATARINA_STAGE08_FINAL_CLEARANCE",
        "checks": checks,
        "live_risk_ready": False,
        "ready_for_stage09": passed,
        "result": (
            "PASS_STAGE08_FINAL_CLEARANCE"
            if passed
            else "FAIL_STAGE08_FINAL_CLEARANCE"
        ),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result, indent=2))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
