from __future__ import annotations

import argparse
import json
import pathlib
import re
from typing import Any


def load(path: pathlib.Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=pathlib.Path, required=True)
    parser.add_argument("--profile-evidence", type=pathlib.Path, required=True)
    parser.add_argument("--test-log", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()

    root = args.repo_root.resolve()
    config = load(root / "config" / "mt5_python_communication_draft.json")
    profile = load(args.profile_evidence)
    test_log = args.test_log.read_text(encoding="utf-8", errors="replace")

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

    native_tcp = (
        root
        / "mt5"
        / "Include"
        / "Katarina"
        / "Stage07"
        / "NativeTcpTransport.mqh"
    ).read_text(encoding="utf-8")
    tcp_test = (
        root / "mt5" / "Tests" / "KatarinaStage07TcpFallbackIntegration.mq5"
    ).read_text(encoding="utf-8")

    checks = {
        "stage06_frozen": (
            root / "docs" / "reviews" / "STAGE_06_FREEZE_RECORD.md"
        ).is_file(),
        "recorded_stage07_evidence_complete": all(
            key in evidence and int(evidence[key].get("run_id", 0)) > 0
            for key in required_evidence
        ),
        "recorded_stage07_results_pass": all(
            str(evidence[key].get("result", "")).startswith("PASS")
            for key in required_evidence
        ),
        "python_regression_37_pass": (
            "Ran 37 tests" in test_log
            and re.search(r"(?m)^OK\s*$", test_log) is not None
        ),
        "latency_backpressure_profile_pass": (
            profile.get("result")
            == "PASS_STAGE07_BACKPRESSURE_LATENCY_PROFILE"
            and all(bool(v) for v in profile.get("gates", {}).values())
        ),
        "native_tcp_source_complete": all(
            token in native_tcp
            for token in (
                "SocketCreate",
                "SocketConnect",
                "SocketSend",
                "SocketRead",
                "Kat1ValidateFrame",
                "127.0.0.1",
            )
        ),
        "native_tcp_runtime_test_present": all(
            token in tcp_test
            for token in (
                "Katarina_Stage07_tcp_fallback_result.txt",
                "CROSS_LANGUAGE_BYTE_EQUALITY_PASS",
                "result=",
            )
        ),
        "live_risk_remains_disabled": (
            evidence["cross_language_recovery"].get("live_risk_ready") is False
            and evidence["cross_process_reconnect"].get("live_risk_ready") is False
            and evidence["concrete_bridge_transport"].get("live_risk_ready") is False
        ),
        "reconnect_sequence_continuity": (
            evidence["cross_process_reconnect"].get("stream_id_stable") is True
            and evidence["cross_process_reconnect"].get("boot_id_changed") is True
            and evidence["cross_process_reconnect"].get("repeated_recovery") == "PASS"
        ),
    }

    all_preclearance = all(checks.values())
    blockers = [
        {
            "gate": "TCP_FALLBACK_INTEGRATION_PASS",
            "state": "BLOCKED_BY_MT5_TRUSTED_URL_PERMISSION",
            "required_terminal_action": (
                "Tools > Options > Expert Advisors > enable "
                "'Allow WebRequest for listed URL' and add 127.0.0.1"
            ),
            "security_reason": (
                "MetaTrader stores the trusted URL list in terminal-managed "
                "encrypted/binary settings and rejects plaintext startup injection."
            ),
        },
        {
            "gate": "FINAL_STAGE07_AUDIT_PASS",
            "state": "WAITING_FOR_TCP_FALLBACK_INTEGRATION_PASS",
        },
    ]

    result = {
        "schema_version": 1,
        "stage": "07",
        "proof_type": "KATARINA_STAGE07_PRECLEARANCE",
        "checks": checks,
        "profile": {
            "tcp_loopback_p99_ms": profile["tcp_loopback_roundtrip_ms"]["p99"],
            "codec_p99_us": profile["codec_decode_us"]["p99"],
            "timer_budget_us": profile["frozen_stage06_budget"][
                "KAT_STAGE06_TIMER_BUDGET_US"
            ],
        },
        "unresolved_acceptance_gates": blockers,
        "ready_for_stage08": False,
        "manual_terminal_permission_is_only_external_blocker": all_preclearance,
        "result": (
            "PASS_STAGE07_PRECLEARANCE_MANUAL_TERMINAL_PERMISSION_ONLY"
            if all_preclearance
            else "FAIL_STAGE07_PRECLEARANCE"
        ),
    }

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result, indent=2))
    return 0 if all_preclearance else 1


if __name__ == "__main__":
    raise SystemExit(main())
