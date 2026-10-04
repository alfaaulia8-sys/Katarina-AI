from __future__ import annotations

import argparse
import json
import pathlib
import re
from typing import Any


def load_json(path: pathlib.Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def bundle_file(bundle: dict[str, Any], name: str) -> str:
    for item in bundle.get("files", []):
        if item.get("name") == name and item.get("content_included"):
            return str(item.get("content", ""))
    raise RuntimeError(f"bundle evidence missing: {name}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=pathlib.Path, required=True)
    parser.add_argument("--profile-evidence", type=pathlib.Path, required=True)
    parser.add_argument("--tcp-bundle", type=pathlib.Path, required=True)
    parser.add_argument("--batch-bundle", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()

    root = args.repo_root.resolve()
    config = load_json(root / "config" / "mt5_python_communication_draft.json")
    profile = load_json(args.profile_evidence)
    tcp_bundle = load_json(args.tcp_bundle)
    batch_bundle = load_json(args.batch_bundle)

    checks: dict[str, bool] = {}

    checks["stage06_freeze_record"] = (
        root / "docs" / "reviews" / "STAGE_06_FREEZE_RECORD.md"
    ).is_file()

    evidence = config["evidence"]
    required_evidence = (
        "python_communication_baseline",
        "mql5_kat1_codec_baseline",
        "zeromq_capability",
        "cross_language_handshake",
        "cross_language_recovery",
        "mt5_wire_sequence_restart",
        "concrete_bridge_transport",
        "cross_process_reconnect",
        "native_account_record",
    )
    checks["recorded_stage07_evidence_complete"] = all(
        key in evidence and int(evidence[key].get("run_id", 0)) > 0
        for key in required_evidence
    )
    checks["recorded_stage07_results_pass"] = all(
        str(evidence[key].get("result", "")).startswith("PASS")
        for key in required_evidence
    )
    checks["live_risk_remains_disabled"] = (
        evidence["cross_language_recovery"].get("live_risk_ready") is False
        and evidence["cross_process_reconnect"].get("live_risk_ready") is False
        and evidence["concrete_bridge_transport"].get("live_risk_ready") is False
    )
    checks["cross_language_recovery_byte_equality"] = (
        evidence["cross_language_recovery"].get("byte_equality")
        == "PASS_BOTH_DIRECTIONS"
    )
    checks["reconnect_sequence_continuity"] = (
        evidence["cross_process_reconnect"].get("stream_id_stable") is True
        and evidence["cross_process_reconnect"].get("boot_id_changed") is True
        and evidence["cross_process_reconnect"].get("repeated_recovery") == "PASS"
    )

    tcp_receipt = tcp_bundle.get("receipt", {})
    tcp_text = bundle_file(tcp_bundle, "stage07_native_tcp_fallback_evidence.json")
    tcp = json.loads(tcp_text)
    checks["native_tcp_request_pass"] = int(tcp_receipt.get("exit_code", -1)) == 0
    checks["native_tcp_cross_language_pass"] = (
        tcp.get("result") == "PASS_STAGE07_NATIVE_TCP_FALLBACK"
        and tcp.get("cross_language_byte_equality") == "PASS"
        and tcp.get("framing") == "KAT1_FRAME_LENGTH_ONLY"
        and tcp.get("secondary_envelope") is False
    )

    batch_receipt = batch_bundle.get("receipt", {})
    batch_summary = json.loads(bundle_file(batch_bundle, "stage07_batch_summary.json"))
    test_stderr = bundle_file(batch_bundle, "batch_02_workspace_test_stderr.txt")
    checks["vps_batch_pass"] = (
        int(batch_receipt.get("exit_code", -1)) == 0
        and batch_summary.get("result") == "PASS"
        and batch_summary.get("completed_step_count") == 3
    )
    checks["python_regression_37_pass"] = (
        "Ran 37 tests" in test_stderr and re.search(r"\nOK\s*$", test_stderr) is not None
    )

    checks["latency_backpressure_profile_pass"] = (
        profile.get("result") == "PASS_STAGE07_BACKPRESSURE_LATENCY_PROFILE"
        and all(bool(v) for v in profile.get("gates", {}).values())
    )

    native_tcp_source = (
        root
        / "mt5"
        / "Include"
        / "Katarina"
        / "Stage07"
        / "NativeTcpTransport.mqh"
    ).read_text(encoding="utf-8")
    checks["native_tcp_source_present"] = all(
        token in native_tcp_source
        for token in (
            "SocketCreate",
            "SocketConnect",
            "SocketSend",
            "SocketRead",
            "127.0.0.1",
            "Kat1ValidateFrame",
        )
    )
    checks["native_tcp_localhost_only"] = (
        'host!="127.0.0.1" && host!="localhost"' in native_tcp_source
    )

    bridge = (
        root / "mt5" / "Include" / "Katarina" / "Stage07" / "BridgeTransport.mqh"
    ).read_text(encoding="utf-8")
    checks["critical_backpressure_retry_guard"] = all(
        token in bridge
        for token in (
            "m_pending_control",
            "FlushPendingControl",
            "if(!m_wire.SendFrame(m_pending_control))",
        )
    )

    checks["stage07_no_broker_order_submission"] = (
        "OrderSend(" not in (
            root / "mt5" / "Experts" / "KatarinaBridgeStage07EA.mq5"
        ).read_text(encoding="utf-8")
    )

    passed = all(checks.values())
    result = {
        "schema_version": 1,
        "stage": "07",
        "proof_type": "KATARINA_STAGE07_FINAL_CLEARANCE",
        "checks": checks,
        "profile": {
            "tcp_p99_ms": profile["tcp_loopback_roundtrip_ms"]["p99"],
            "codec_p99_us": profile["codec_decode_us"]["p99"],
            "timer_budget_us": profile["frozen_stage06_budget"][
                "KAT_STAGE06_TIMER_BUDGET_US"
            ],
        },
        "native_tcp": {
            "proof": tcp.get("result"),
            "ex5_sha256": tcp.get("ex5_sha256"),
        },
        "live_risk_ready": False,
        "ready_for_stage08": passed,
        "result": (
            "PASS_STAGE07_FINAL_CLEARANCE"
            if passed
            else "FAIL_STAGE07_FINAL_CLEARANCE"
        ),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result, indent=2))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
