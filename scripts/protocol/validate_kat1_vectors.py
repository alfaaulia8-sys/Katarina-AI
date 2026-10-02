#!/usr/bin/env python3
"""Validate KAT1 golden frame envelope and CRC32C without third-party packages."""

from __future__ import annotations

import json
import struct
import sys
from pathlib import Path

HEADER_BYTES = 52
MAGIC = b"KAT1"
CRC_PRESENT = 0x0001
HEADER = struct.Struct("<4sBBHHHHHIQQQQ")


def crc32c(data: bytes) -> int:
    poly = 0x82F63B78
    crc = 0xFFFFFFFF
    for byte in data:
        crc ^= byte
        for _ in range(8):
            crc = (crc >> 1) ^ (poly if crc & 1 else 0)
    return crc ^ 0xFFFFFFFF


def validate_frame(raw: bytes) -> None:
    if len(raw) < HEADER_BYTES:
        raise ValueError("frame shorter than header")

    (
        magic,
        wire_major,
        wire_minor,
        header_length,
        message_type,
        schema_version,
        block_length,
        flags,
        frame_length,
        sequence,
        source_time_ns,
        stream_id,
        boot_id,
    ) = HEADER.unpack_from(raw)

    if magic != MAGIC:
        raise ValueError("bad magic")
    if wire_major != 1 or wire_minor != 0:
        raise ValueError("unsupported wire version")
    if header_length != HEADER_BYTES:
        raise ValueError("bad header length")
    if frame_length != len(raw):
        raise ValueError("frame length mismatch")
    if frame_length < HEADER_BYTES + block_length:
        raise ValueError("root block exceeds frame")

    if flags & CRC_PRESENT:
        if len(raw) < HEADER_BYTES + 4:
            raise ValueError("CRC flag without trailer")
        expected = struct.unpack_from("<I", raw, len(raw) - 4)[0]
        actual = crc32c(raw[:-4])
        if actual != expected:
            raise ValueError(
                f"CRC mismatch: expected {expected:08x}, calculated {actual:08x}"
            )


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    vectors_path = root / "protocol" / "golden" / "kat1_v1_vectors.json"
    payload = json.loads(vectors_path.read_text(encoding="utf-8"))

    failures: list[str] = []
    for vector in payload["vectors"]:
        try:
            raw = bytes.fromhex(vector["hex"])
            validate_frame(raw)
            if len(raw) != vector["frame_length"]:
                raise ValueError("fixture frame_length metadata mismatch")
            trailer = struct.unpack_from("<I", raw, len(raw) - 4)[0]
            if f"{trailer:08x}" != vector["crc32c"]:
                raise ValueError("fixture CRC metadata mismatch")
        except Exception as exc:  # validation utility
            failures.append(f'{vector["name"]}: {exc}')

    if failures:
        for failure in failures:
            print(failure, file=sys.stderr)
        return 1

    print(f'KAT1 golden envelope validation passed: {len(payload["vectors"])} vectors')
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
