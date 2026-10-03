from __future__ import annotations

import json
import struct
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Mapping

MAGIC = b"KAT1"
WIRE_MAJOR = 1
WIRE_MINOR = 0
HEADER_BYTES = 52
MAX_FRAME_BYTES = 65_536

CRC32C_PRESENT = 0x0001
CRITICAL_MESSAGE = 0x0002
SNAPSHOT_TRANSACTION = 0x0004
REPLAYED_FROM_DURABLE_JOURNAL = 0x0008
SUPPORTED_FLAGS = (
    CRC32C_PRESENT
    | CRITICAL_MESSAGE
    | SNAPSHOT_TRANSACTION
    | REPLAYED_FROM_DURABLE_JOURNAL
)

_HEADER = struct.Struct("<4sBBHHHHHIQQQQ")

_PRIMITIVES: dict[str, tuple[str, int]] = {
    "u8": ("<B", 1),
    "u16": ("<H", 2),
    "u32": ("<I", 4),
    "u64": ("<Q", 8),
    "i32": ("<i", 4),
    "i64": ("<q", 8),
}


class Kat1ProtocolError(ValueError):
    pass


@dataclass(frozen=True, slots=True)
class Kat1Header:
    message_type: int
    schema_version: int
    block_length: int
    flags: int
    frame_length: int
    sequence: int
    source_time_ns: int
    stream_id: int
    boot_id: int
    wire_major: int = WIRE_MAJOR
    wire_minor: int = WIRE_MINOR
    header_length: int = HEADER_BYTES


@dataclass(frozen=True, slots=True)
class Kat1Frame:
    header: Kat1Header
    values: Mapping[str, Any]
    payload: bytes
    crc32c: int | None = None


class SchemaCatalog:
    def __init__(self, payload: Mapping[str, Any]) -> None:
        if payload.get("protocol") != "KAT1":
            raise Kat1ProtocolError("schema catalog is not KAT1")
        self._messages: dict[tuple[int, int], Mapping[str, Any]] = {}
        for message in payload.get("messages", ()):
            key = (int(message["id"]), int(message["schema_version"]))
            if key in self._messages:
                raise Kat1ProtocolError(f"duplicate schema {key}")
            self._messages[key] = message

    @classmethod
    def from_path(cls, path: str | Path) -> "SchemaCatalog":
        data = json.loads(Path(path).read_text(encoding="utf-8"))
        return cls(data)

    def message(self, message_type: int, schema_version: int) -> Mapping[str, Any]:
        try:
            return self._messages[(message_type, schema_version)]
        except KeyError as exc:
            raise Kat1ProtocolError(
                f"unknown KAT1 schema message_type={message_type} "
                f"schema_version={schema_version}"
            ) from exc


def crc32c(data: bytes) -> int:
    poly = 0x82F63B78
    crc = 0xFFFFFFFF
    for byte in data:
        crc ^= byte
        for _ in range(8):
            crc = (crc >> 1) ^ (poly if crc & 1 else 0)
    return crc ^ 0xFFFFFFFF


def _decode_fixed(type_name: str, raw: bytes, offset: int) -> Any:
    if type_name in _PRIMITIVES:
        fmt, size = _PRIMITIVES[type_name]
        end = offset + size
        if end > len(raw):
            raise Kat1ProtocolError("fixed field exceeds root block")
        return struct.unpack_from(fmt, raw, offset)[0]

    if type_name == "id128":
        end = offset + 16
        if end > len(raw):
            raise Kat1ProtocolError("id128 exceeds root block")
        return raw[offset:end].hex()

    if type_name == "bytes32":
        end = offset + 32
        if end > len(raw):
            raise Kat1ProtocolError("bytes32 exceeds root block")
        return raw[offset:end].hex()

    raise Kat1ProtocolError(f"unsupported KAT1 primitive: {type_name}")


def _coerce_fixed_bytes(type_name: str, value: Any) -> bytes:
    if type_name in _PRIMITIVES:
        fmt, _ = _PRIMITIVES[type_name]
        try:
            return struct.pack(fmt, value)
        except (struct.error, TypeError) as exc:
            raise Kat1ProtocolError(
                f"cannot encode {type_name} value {value!r}"
            ) from exc

    if type_name == "id128":
        if isinstance(value, str):
            try:
                value = bytes.fromhex(value)
            except ValueError as exc:
                raise Kat1ProtocolError("invalid id128 hex") from exc
        if not isinstance(value, (bytes, bytearray)) or len(value) != 16:
            raise Kat1ProtocolError("id128 must be exactly 16 bytes")
        return bytes(value)

    if type_name == "bytes32":
        if isinstance(value, str):
            try:
                value = bytes.fromhex(value)
            except ValueError as exc:
                raise Kat1ProtocolError("invalid bytes32 hex") from exc
        if not isinstance(value, (bytes, bytearray)) or len(value) != 32:
            raise Kat1ProtocolError("bytes32 must be exactly 32 bytes")
        return bytes(value)

    raise Kat1ProtocolError(f"unsupported KAT1 primitive: {type_name}")


def _decode_variables(
    schema: Mapping[str, Any],
    variable_bytes: bytes,
    values: dict[str, Any],
) -> None:
    cursor = 0
    fields = list(schema.get("variable_fields", ()))

    for index, field in enumerate(fields):
        encoding = field["encoding"]
        name = field["name"]

        if encoding == "u16_length_utf8":
            if cursor + 2 > len(variable_bytes):
                raise Kat1ProtocolError(f"{name}: missing string length")
            length = struct.unpack_from("<H", variable_bytes, cursor)[0]
            cursor += 2
            max_bytes = int(field["max_bytes"])
            if length > max_bytes:
                raise Kat1ProtocolError(f"{name}: exceeds max_bytes")
            end = cursor + length
            if end > len(variable_bytes):
                raise Kat1ProtocolError(f"{name}: truncated string")
            try:
                values[name] = variable_bytes[cursor:end].decode("utf-8")
            except UnicodeDecodeError as exc:
                raise Kat1ProtocolError(f"{name}: invalid UTF-8") from exc
            cursor = end
            continue

        if encoding == "repeated_embedded_record":
            if index != len(fields) - 1:
                raise Kat1ProtocolError(
                    "repeated_embedded_record must be the final variable field"
                )
            records: list[dict[str, Any]] = []
            while cursor < len(variable_bytes):
                if cursor + 8 > len(variable_bytes):
                    raise Kat1ProtocolError("truncated embedded record header")
                record_type, record_schema_version, body_length = struct.unpack_from(
                    "<HHI", variable_bytes, cursor
                )
                cursor += 8
                if body_length > int(field["max_bytes"]):
                    raise Kat1ProtocolError("embedded record exceeds max_bytes")
                end = cursor + body_length
                if end > len(variable_bytes):
                    raise Kat1ProtocolError("truncated embedded record body")
                records.append(
                    {
                        "record_type": record_type,
                        "schema_version": record_schema_version,
                        "body": variable_bytes[cursor:end],
                    }
                )
                cursor = end
            values[name] = records
            if "record_count" in values and values["record_count"] != len(records):
                raise Kat1ProtocolError("embedded record_count mismatch")
            continue

        if encoding == "repeated_len32_record":
            if index != len(fields) - 1:
                raise Kat1ProtocolError(
                    "repeated_len32_record must be the final variable field"
                )
            records: list[bytes] = []
            while cursor < len(variable_bytes):
                if cursor + 4 > len(variable_bytes):
                    raise Kat1ProtocolError("truncated len32 record header")
                body_length = struct.unpack_from("<I", variable_bytes, cursor)[0]
                cursor += 4
                if body_length > int(field["max_bytes"]):
                    raise Kat1ProtocolError("len32 record exceeds max_bytes")
                end = cursor + body_length
                if end > len(variable_bytes):
                    raise Kat1ProtocolError("truncated len32 record body")
                records.append(variable_bytes[cursor:end])
                cursor = end
            values[name] = records
            if (
                "discrepancy_count" in values
                and values["discrepancy_count"] != len(records)
            ):
                raise Kat1ProtocolError("discrepancy_count mismatch")
            continue

        raise Kat1ProtocolError(f"unsupported variable encoding: {encoding}")

    if cursor != len(variable_bytes):
        raise Kat1ProtocolError("unexpected variable payload bytes")


def _encode_variables(
    schema: Mapping[str, Any],
    values: Mapping[str, Any],
) -> bytes:
    output = bytearray()

    for index, field in enumerate(schema.get("variable_fields", ())):
        encoding = field["encoding"]
        name = field["name"]
        if name not in values:
            raise Kat1ProtocolError(f"missing variable field: {name}")
        value = values[name]

        if encoding == "u16_length_utf8":
            if not isinstance(value, str):
                raise Kat1ProtocolError(f"{name}: expected str")
            encoded = value.encode("utf-8")
            if len(encoded) > int(field["max_bytes"]):
                raise Kat1ProtocolError(f"{name}: exceeds max_bytes")
            output.extend(struct.pack("<H", len(encoded)))
            output.extend(encoded)
            continue

        if encoding == "repeated_embedded_record":
            if index != len(schema.get("variable_fields", ())) - 1:
                raise Kat1ProtocolError(
                    "repeated_embedded_record must be the final variable field"
                )
            if not isinstance(value, (list, tuple)):
                raise Kat1ProtocolError(f"{name}: expected record sequence")
            for record in value:
                record_type = int(record["record_type"])
                schema_version = int(record["schema_version"])
                body = record["body"]
                if isinstance(body, str):
                    try:
                        body = bytes.fromhex(body)
                    except ValueError as exc:
                        raise Kat1ProtocolError(
                            "embedded record body is not valid hex"
                        ) from exc
                if not isinstance(body, (bytes, bytearray)):
                    raise Kat1ProtocolError("embedded record body must be bytes")
                body = bytes(body)
                if len(body) > int(field["max_bytes"]):
                    raise Kat1ProtocolError("embedded record exceeds max_bytes")
                output.extend(
                    struct.pack("<HHI", record_type, schema_version, len(body))
                )
                output.extend(body)
            continue

        if encoding == "repeated_len32_record":
            if index != len(schema.get("variable_fields", ())) - 1:
                raise Kat1ProtocolError(
                    "repeated_len32_record must be the final variable field"
                )
            if not isinstance(value, (list, tuple)):
                raise Kat1ProtocolError(f"{name}: expected record sequence")
            for body in value:
                if isinstance(body, str):
                    try:
                        body = bytes.fromhex(body)
                    except ValueError as exc:
                        raise Kat1ProtocolError(
                            "len32 record body is not valid hex"
                        ) from exc
                if not isinstance(body, (bytes, bytearray)):
                    raise Kat1ProtocolError("len32 record body must be bytes")
                body = bytes(body)
                if len(body) > int(field["max_bytes"]):
                    raise Kat1ProtocolError("len32 record exceeds max_bytes")
                output.extend(struct.pack("<I", len(body)))
                output.extend(body)
            continue

        raise Kat1ProtocolError(f"unsupported variable encoding: {encoding}")

    return bytes(output)


class Kat1Codec:
    def __init__(self, catalog: SchemaCatalog) -> None:
        self._catalog = catalog

    def decode(self, raw: bytes) -> Kat1Frame:
        if len(raw) < HEADER_BYTES:
            raise Kat1ProtocolError("frame shorter than KAT1 header")
        if len(raw) > MAX_FRAME_BYTES:
            raise Kat1ProtocolError("frame exceeds KAT1 maximum")

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
        ) = _HEADER.unpack_from(raw)

        if magic != MAGIC:
            raise Kat1ProtocolError("bad KAT1 magic")
        if (wire_major, wire_minor) != (WIRE_MAJOR, WIRE_MINOR):
            raise Kat1ProtocolError("unsupported KAT1 wire version")
        if header_length != HEADER_BYTES:
            raise Kat1ProtocolError("invalid KAT1 header length")
        if flags & ~SUPPORTED_FLAGS:
            raise Kat1ProtocolError("unknown KAT1 frame flags")
        if frame_length != len(raw):
            raise Kat1ProtocolError("KAT1 frame length mismatch")
        if frame_length > MAX_FRAME_BYTES:
            raise Kat1ProtocolError("KAT1 frame exceeds maximum")

        schema = self._catalog.message(message_type, schema_version)
        expected_root = int(schema["root_bytes"])
        if block_length != expected_root:
            raise Kat1ProtocolError(
                f"unexpected root block length {block_length}, "
                f"expected {expected_root}"
            )

        schema_critical = bool(schema["critical"])
        flag_critical = bool(flags & CRITICAL_MESSAGE)
        if schema_critical != flag_critical:
            raise Kat1ProtocolError("critical flag/schema mismatch")
        if schema_critical and not (flags & CRC32C_PRESENT):
            raise Kat1ProtocolError("critical frame missing CRC32C")

        trailer_bytes = 4 if flags & CRC32C_PRESENT else 0
        payload_end = len(raw) - trailer_bytes
        if payload_end < HEADER_BYTES + block_length:
            raise Kat1ProtocolError("KAT1 payload shorter than root block")

        expected_crc: int | None = None
        if trailer_bytes:
            expected_crc = struct.unpack_from("<I", raw, payload_end)[0]
            actual_crc = crc32c(raw[:payload_end])
            if actual_crc != expected_crc:
                raise Kat1ProtocolError("CRC32C mismatch")

        payload = raw[HEADER_BYTES:payload_end]
        root = payload[:block_length]
        variable_bytes = payload[block_length:]

        values: dict[str, Any] = {}
        for field in schema.get("fields", ()):
            values[field["name"]] = _decode_fixed(
                field["type"],
                root,
                int(field["offset"]),
            )

        _decode_variables(schema, variable_bytes, values)

        header = Kat1Header(
            message_type=message_type,
            schema_version=schema_version,
            block_length=block_length,
            flags=flags,
            frame_length=frame_length,
            sequence=sequence,
            source_time_ns=source_time_ns,
            stream_id=stream_id,
            boot_id=boot_id,
            wire_major=wire_major,
            wire_minor=wire_minor,
            header_length=header_length,
        )
        return Kat1Frame(
            header=header,
            values=values,
            payload=payload,
            crc32c=expected_crc,
        )

    def encode(
        self,
        *,
        message_type: int,
        schema_version: int,
        sequence: int,
        source_time_ns: int,
        stream_id: int,
        boot_id: int,
        values: Mapping[str, Any],
        flags: int | None = None,
    ) -> bytes:
        schema = self._catalog.message(message_type, schema_version)
        root_bytes = int(schema["root_bytes"])
        critical = bool(schema["critical"])

        if flags is None:
            flags = CRC32C_PRESENT
            if critical:
                flags |= CRITICAL_MESSAGE
            if 10 <= message_type <= 14:
                flags |= SNAPSHOT_TRANSACTION

        if flags & ~SUPPORTED_FLAGS:
            raise Kat1ProtocolError("unknown KAT1 frame flags")
        if bool(flags & CRITICAL_MESSAGE) != critical:
            raise Kat1ProtocolError("critical flag/schema mismatch")
        if critical and not (flags & CRC32C_PRESENT):
            raise Kat1ProtocolError("critical frame requires CRC32C")

        root = bytearray(root_bytes)
        for field in schema.get("fields", ()):
            name = field["name"]
            if name in values:
                value = values[name]
            elif name.startswith("reserved"):
                value = 0
            else:
                raise Kat1ProtocolError(f"missing fixed field: {name}")
            encoded = _coerce_fixed_bytes(field["type"], value)
            offset = int(field["offset"])
            end = offset + len(encoded)
            if end > root_bytes:
                raise Kat1ProtocolError(f"{name}: exceeds root block")
            root[offset:end] = encoded

        variable = _encode_variables(schema, values)
        payload = bytes(root) + variable
        trailer_bytes = 4 if flags & CRC32C_PRESENT else 0
        frame_length = HEADER_BYTES + len(payload) + trailer_bytes
        if frame_length > MAX_FRAME_BYTES:
            raise Kat1ProtocolError("encoded frame exceeds KAT1 maximum")

        header = _HEADER.pack(
            MAGIC,
            WIRE_MAJOR,
            WIRE_MINOR,
            HEADER_BYTES,
            message_type,
            schema_version,
            root_bytes,
            flags,
            frame_length,
            sequence,
            source_time_ns,
            stream_id,
            boot_id,
        )
        frame = header + payload
        if trailer_bytes:
            frame += struct.pack("<I", crc32c(frame))
        return frame

    def reencode(self, frame: Kat1Frame) -> bytes:
        return self.encode(
            message_type=frame.header.message_type,
            schema_version=frame.header.schema_version,
            sequence=frame.header.sequence,
            source_time_ns=frame.header.source_time_ns,
            stream_id=frame.header.stream_id,
            boot_id=frame.header.boot_id,
            values=frame.values,
            flags=frame.header.flags,
        )
