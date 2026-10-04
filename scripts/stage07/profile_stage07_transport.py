from __future__ import annotations

import argparse
import asyncio
import json
import pathlib
import re
import statistics
import sys
import time

ROOT_DEFAULT = pathlib.Path(__file__).resolve().parents[2]


def percentile(values: list[float], p: float) -> float:
    ordered = sorted(values)
    if not ordered:
        return 0.0
    index = int(round((len(ordered) - 1) * p))
    return ordered[max(0, min(index, len(ordered) - 1))]


async def run_profile(root: pathlib.Path) -> dict[str, object]:
    sys.path.insert(0, str(root))
    sys.path.insert(0, str(root / "src"))

    from katarina.adapters.transport.kat1_codec import Kat1Codec, SchemaCatalog
    from katarina.adapters.transport.memory import create_memory_transport_pair
    from katarina.adapters.transport.tcp import Kat1TcpServerTransport
    from katarina.ports.transport import TransportBackpressureError

    vectors = json.loads(
        (root / "protocol" / "golden" / "kat1_v1_vectors.json").read_text(
            encoding="utf-8"
        )
    )["vectors"]
    hello = bytes.fromhex(next(item["hex"] for item in vectors if item["name"] == "HELLO"))

    codec = Kat1Codec(
        SchemaCatalog.from_path(root / "protocol" / "kat1_message_schemas_v1.json")
    )

    codec_samples_us: list[float] = []
    for _ in range(2000):
        started = time.perf_counter_ns()
        decoded = codec.decode(hello)
        if decoded.header.message_type != 1:
            raise RuntimeError("HELLO decode changed during profile")
        codec_samples_us.append((time.perf_counter_ns() - started) / 1000.0)

    left, right = create_memory_transport_pair(capacity=2)
    await left.start()
    await right.start()
    await left.send_frame(hello)
    await left.send_frame(hello)
    bounded_backpressure = False
    try:
        await left.send_frame(hello)
    except TransportBackpressureError:
        bounded_backpressure = True
    await right.receive_frame()
    await right.receive_frame()
    await left.stop()
    await right.stop()
    if not bounded_backpressure:
        raise RuntimeError("bounded memory transport did not signal backpressure")

    server = Kat1TcpServerTransport(host="127.0.0.1", port=0, receive_capacity=8)
    await server.start()
    endpoint = server.endpoint
    if endpoint is None:
        raise RuntimeError("TCP server did not expose endpoint")
    reader, writer = await asyncio.open_connection(endpoint[0], endpoint[1])

    tcp_samples_ms: list[float] = []
    try:
        for _ in range(120):
            started = time.perf_counter_ns()
            writer.write(hello)
            await writer.drain()
            received = await asyncio.wait_for(server.receive_frame(), timeout=2.0)
            await server.send_frame(received.frame, peer=received.peer)

            header = await asyncio.wait_for(reader.readexactly(52), timeout=2.0)
            frame_length = int.from_bytes(header[16:20], "little")
            body = await asyncio.wait_for(
                reader.readexactly(frame_length - 52), timeout=2.0
            )
            echoed = header + body
            if echoed != hello:
                raise RuntimeError("TCP loopback byte equality failed")
            tcp_samples_ms.append((time.perf_counter_ns() - started) / 1_000_000.0)
    finally:
        writer.close()
        try:
            await writer.wait_closed()
        except OSError:
            pass
        await server.stop()

    stage06 = (root / "mt5" / "Experts" / "KatarinaBridgeEA.mq5").read_text(
        encoding="utf-8"
    )
    stage07 = (root / "mt5" / "Experts" / "KatarinaBridgeStage07EA.mq5").read_text(
        encoding="utf-8"
    )
    bridge = (
        root / "mt5" / "Include" / "Katarina" / "Stage07" / "BridgeTransport.mqh"
    ).read_text(encoding="utf-8")

    def constant(text: str, name: str) -> int:
        match = re.search(rf"#define\s+{re.escape(name)}\s+(\d+)", text)
        if not match:
            raise RuntimeError(f"missing {name}")
        return int(match.group(1))

    names = (
        "KAT_STAGE06_TIMER_MS",
        "KAT_STAGE06_CRITICAL_QUEUE_CAPACITY",
        "KAT_STAGE06_DRAIN_BUDGET",
        "KAT_STAGE06_TIMER_BUDGET_US",
    )
    inherited = {name: constant(stage07, name) for name in names}
    original = {name: constant(stage06, name) for name in names}
    if inherited != original:
        raise RuntimeError("Stage-07 changed frozen Stage-06 timer/queue constants")

    pending_retry = all(
        token in bridge
        for token in (
            "m_pending_control",
            "FlushPendingControl",
            "if(!m_wire.SendFrame(m_pending_control))",
            "max_microseconds",
        )
    )
    if not pending_retry:
        raise RuntimeError("Stage-07 critical retry/backpressure guard is incomplete")

    tcp_p99_ms = percentile(tcp_samples_ms, 0.99)
    codec_p99_us = percentile(codec_samples_us, 0.99)

    gates = {
        "bounded_backpressure_signaled": bounded_backpressure,
        "tcp_byte_equality": True,
        "stage06_timer_budget_preserved": inherited["KAT_STAGE06_TIMER_BUDGET_US"] == 2000,
        "stage06_timer_period_preserved": inherited["KAT_STAGE06_TIMER_MS"] == 50,
        "critical_retry_without_sequence_reallocation": pending_retry,
        "tcp_p99_under_100ms_observation_gate": tcp_p99_ms < 100.0,
        "codec_p99_under_5ms_observation_gate": codec_p99_us < 5000.0,
    }
    passed = all(gates.values())

    return {
        "schema_version": 1,
        "stage": "07",
        "proof_type": "KATARINA_STAGE07_BACKPRESSURE_LATENCY_PROFILE",
        "sample_counts": {
            "codec_decode": len(codec_samples_us),
            "tcp_roundtrip": len(tcp_samples_ms),
        },
        "codec_decode_us": {
            "p50": round(percentile(codec_samples_us, 0.50), 3),
            "p95": round(percentile(codec_samples_us, 0.95), 3),
            "p99": round(codec_p99_us, 3),
            "max": round(max(codec_samples_us), 3),
            "mean": round(statistics.fmean(codec_samples_us), 3),
        },
        "tcp_loopback_roundtrip_ms": {
            "p50": round(percentile(tcp_samples_ms, 0.50), 3),
            "p95": round(percentile(tcp_samples_ms, 0.95), 3),
            "p99": round(tcp_p99_ms, 3),
            "max": round(max(tcp_samples_ms), 3),
            "mean": round(statistics.fmean(tcp_samples_ms), 3),
        },
        "frozen_stage06_budget": inherited,
        "gates": gates,
        "note": "Latency thresholds are Stage-07 observational sanity gates, not a live-trading SLA.",
        "result": (
            "PASS_STAGE07_BACKPRESSURE_LATENCY_PROFILE"
            if passed
            else "FAIL_STAGE07_BACKPRESSURE_LATENCY_PROFILE"
        ),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=pathlib.Path, default=ROOT_DEFAULT)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()

    evidence = asyncio.run(run_profile(args.repo_root.resolve()))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(evidence, indent=2), encoding="utf-8")
    print(json.dumps(evidence, indent=2))
    return 0 if evidence["result"].startswith("PASS_") else 1


if __name__ == "__main__":
    raise SystemExit(main())
