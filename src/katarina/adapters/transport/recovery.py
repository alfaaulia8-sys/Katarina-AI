from __future__ import annotations

from dataclasses import dataclass
from enum import Enum

from katarina.adapters.transport.kat1_codec import Kat1Codec, Kat1Frame, crc32c


SNAPSHOT_REQUEST = 10
SNAPSHOT_BEGIN = 11
SNAPSHOT_CHUNK = 12
SNAPSHOT_COMMIT = 13
SNAPSHOT_ABORT = 14
RECONCILE_REQUEST = 312
RECONCILE_REPORT = 313

RECOVERY_READY = 2


class RecoveryState(str, Enum):
    IDLE = "idle"
    WAITING_SNAPSHOT_BEGIN = "waiting_snapshot_begin"
    SNAPSHOT_ACTIVE = "snapshot_active"
    WAITING_RECONCILE = "waiting_reconcile"
    COMPLETE = "complete"
    FAULTED = "faulted"


class RecoveryFault(RuntimeError):
    pass


@dataclass(frozen=True, slots=True)
class SnapshotRecord:
    record_type: int
    schema_version: int
    body: bytes


@dataclass(frozen=True, slots=True)
class SnapshotSummary:
    snapshot_id: str
    base_sequence: int
    sequence_watermark: int
    account_revision: int
    record_mask: int
    chunk_count: int
    record_count: int
    total_payload_bytes: int
    aggregate_crc32c: int


class Kat1RecoveryGate:
    """Atomic Stage-07 snapshot/reconciliation admission gate.

    This gate owns communication recovery only. It never grants live-risk
    readiness. Snapshot record bodies remain opaque to Stage 07; transaction
    integrity and reconciliation cleanliness are what gate communication READY.
    """

    def __init__(
        self,
        *,
        codec: Kat1Codec,
        stream_id: int,
        boot_id: int,
        account_id: str,
    ) -> None:
        if stream_id <= 0 or boot_id <= 0:
            raise ValueError("stream_id and boot_id must be positive")
        if len(account_id) != 32:
            raise ValueError("account_id must be 16-byte hex")
        try:
            self._account_id_bytes = bytes.fromhex(account_id)
        except ValueError as exc:
            raise ValueError("account_id must be valid hex") from exc

        self._codec = codec
        self._stream_id = stream_id
        self._boot_id = boot_id
        self._state = RecoveryState.IDLE

        self._snapshot_request_id: bytes | None = None
        self._reconcile_request_id: bytes | None = None
        self._snapshot_id: str | None = None
        self._base_sequence = 0
        self._account_revision = 0
        self._record_mask = 0
        self._expected_chunk_count = 0
        self._expected_record_count = 0
        self._expected_total_payload_bytes = 0
        self._chunks: list[bytes] = []
        self._records: list[SnapshotRecord] = []
        self._record_count = 0
        self._snapshot_summary: SnapshotSummary | None = None

    @property
    def state(self) -> RecoveryState:
        return self._state

    @property
    def communication_ready(self) -> bool:
        return self._state is RecoveryState.COMPLETE

    @property
    def live_risk_ready(self) -> bool:
        return False

    @property
    def snapshot_summary(self) -> SnapshotSummary | None:
        return self._snapshot_summary

    @property
    def snapshot_records(self) -> tuple[SnapshotRecord, ...]:
        if self._state not in (RecoveryState.WAITING_RECONCILE, RecoveryState.COMPLETE):
            return ()
        return tuple(self._records)

    def start(self, *, snapshot_request_id: bytes) -> None:
        self._require_id128(snapshot_request_id, "snapshot_request_id")
        if self._state is RecoveryState.FAULTED:
            raise RecoveryFault("faulted recovery gate cannot restart")
        self._reset_transaction()
        self._snapshot_request_id = bytes(snapshot_request_id)
        self._state = RecoveryState.WAITING_SNAPSHOT_BEGIN

    def build_snapshot_request(
        self,
        *,
        sequence: int,
        source_time_ns: int,
        requested_record_mask: int,
        after_execution_cursor: int,
        max_chunk_bytes: int = 60_000,
    ) -> bytes:
        if self._state is not RecoveryState.WAITING_SNAPSHOT_BEGIN:
            raise RecoveryFault("snapshot request is not expected in current state")
        if self._snapshot_request_id is None:
            raise RecoveryFault("snapshot_request_id is not initialized")
        if not 1 <= max_chunk_bytes <= 60_000:
            raise ValueError("max_chunk_bytes must be between 1 and 60000")

        return self._codec.encode(
            message_type=SNAPSHOT_REQUEST,
            schema_version=1,
            sequence=sequence,
            source_time_ns=source_time_ns,
            stream_id=self._stream_id,
            boot_id=self._boot_id,
            values={
                "request_id": self._snapshot_request_id,
                "requested_record_mask": requested_record_mask,
                "after_execution_cursor": after_execution_cursor,
                "max_chunk_bytes": max_chunk_bytes,
            },
        )

    def build_reconcile_request(
        self,
        *,
        sequence: int,
        source_time_ns: int,
        request_id: bytes,
        after_event_cursor: int,
        scope_flags: int,
    ) -> bytes:
        if self._state is not RecoveryState.WAITING_RECONCILE:
            raise RecoveryFault("reconcile request is not expected in current state")
        if self._snapshot_summary is None:
            raise RecoveryFault("accepted snapshot is required before reconciliation")
        self._require_id128(request_id, "request_id")
        self._reconcile_request_id = bytes(request_id)

        return self._codec.encode(
            message_type=RECONCILE_REQUEST,
            schema_version=1,
            sequence=sequence,
            source_time_ns=source_time_ns,
            stream_id=self._stream_id,
            boot_id=self._boot_id,
            values={
                "request_id": request_id,
                "account_id": self._account_id_bytes,
                "snapshot_id": bytes.fromhex(self._snapshot_summary.snapshot_id),
                "after_event_cursor": after_event_cursor,
                "scope_flags": scope_flags,
            },
        )

    def observe_raw(self, raw: bytes) -> None:
        self.observe(self._codec.decode(raw))

    def observe(self, frame: Kat1Frame) -> None:
        if self._state is RecoveryState.FAULTED:
            raise RecoveryFault("recovery gate is faulted")
        if self._state is RecoveryState.IDLE:
            raise RecoveryFault("recovery gate has not started")

        self._validate_binding(frame)
        message_type = frame.header.message_type

        if message_type == SNAPSHOT_BEGIN:
            self._on_snapshot_begin(frame)
            return
        if message_type == SNAPSHOT_CHUNK:
            self._on_snapshot_chunk(frame)
            return
        if message_type == SNAPSHOT_COMMIT:
            self._on_snapshot_commit(frame)
            return
        if message_type == SNAPSHOT_ABORT:
            self._fault("snapshot transaction aborted")
        if message_type == RECONCILE_REPORT:
            self._on_reconcile_report(frame)
            return

    def _on_snapshot_begin(self, frame: Kat1Frame) -> None:
        if self._state is not RecoveryState.WAITING_SNAPSHOT_BEGIN:
            self._fault("SNAPSHOT_BEGIN received outside expected state")

        values = frame.values
        snapshot_id = str(values["snapshot_id"])
        expected_chunks = int(values["expected_chunk_count"])
        expected_records = int(values["expected_record_count"])
        expected_bytes = int(values["expected_total_payload_bytes"])

        if len(snapshot_id) != 32:
            self._fault("SNAPSHOT_BEGIN snapshot_id is invalid")
        if expected_chunks < 0 or expected_records < 0 or expected_bytes < 0:
            self._fault("SNAPSHOT_BEGIN contains invalid negative counts")

        self._snapshot_id = snapshot_id
        self._base_sequence = int(values["base_sequence"])
        self._account_revision = int(values["account_revision"])
        self._record_mask = int(values["record_mask"])
        self._expected_chunk_count = expected_chunks
        self._expected_record_count = expected_records
        self._expected_total_payload_bytes = expected_bytes
        self._chunks = []
        self._records = []
        self._record_count = 0
        self._state = RecoveryState.SNAPSHOT_ACTIVE

    def _on_snapshot_chunk(self, frame: Kat1Frame) -> None:
        if self._state is not RecoveryState.SNAPSHOT_ACTIVE:
            self._fault("SNAPSHOT_CHUNK received outside active snapshot")

        values = frame.values
        if str(values["snapshot_id"]) != self._snapshot_id:
            self._fault("SNAPSHOT_CHUNK snapshot_id mismatch")

        chunk_index = int(values["chunk_index"])
        if chunk_index != len(self._chunks):
            self._fault("SNAPSHOT_CHUNK index is not contiguous")

        records = values["records"]
        record_count = int(values["record_count"])
        if record_count != len(records):
            self._fault("SNAPSHOT_CHUNK record_count mismatch")

        variable_bytes = frame.payload[frame.header.block_length :]
        declared_bytes = int(values["chunk_payload_bytes"])
        if declared_bytes != len(variable_bytes):
            self._fault("SNAPSHOT_CHUNK payload byte count mismatch")

        declared_crc = int(values["payload_crc32c"])
        actual_crc = crc32c(variable_bytes)
        if declared_crc != actual_crc:
            self._fault("SNAPSHOT_CHUNK payload CRC32C mismatch")

        if len(self._chunks) >= self._expected_chunk_count:
            self._fault("SNAPSHOT_CHUNK exceeds expected chunk count")

        parsed_records: list[SnapshotRecord] = []
        for record in records:
            record_type = int(record["record_type"])
            schema_version = int(record["schema_version"])
            body = bytes(record["body"])
            if record_type < 1 or record_type > 7:
                self._fault("SNAPSHOT_CHUNK contains unknown snapshot record_type")
            if schema_version <= 0:
                self._fault("SNAPSHOT_CHUNK contains invalid record schema_version")
            parsed_records.append(
                SnapshotRecord(
                    record_type=record_type,
                    schema_version=schema_version,
                    body=body,
                )
            )

        self._chunks.append(bytes(variable_bytes))
        self._records.extend(parsed_records)
        self._record_count += record_count

    def _on_snapshot_commit(self, frame: Kat1Frame) -> None:
        if self._state is not RecoveryState.SNAPSHOT_ACTIVE:
            self._fault("SNAPSHOT_COMMIT received outside active snapshot")

        values = frame.values
        if str(values["snapshot_id"]) != self._snapshot_id:
            self._fault("SNAPSHOT_COMMIT snapshot_id mismatch")

        chunk_count = int(values["chunk_count"])
        record_count = int(values["record_count"])
        total_payload_bytes = int(values["total_payload_bytes"])

        if chunk_count != self._expected_chunk_count or chunk_count != len(self._chunks):
            self._fault("SNAPSHOT_COMMIT chunk_count mismatch")
        if record_count != self._expected_record_count or record_count != self._record_count:
            self._fault("SNAPSHOT_COMMIT record_count mismatch")

        actual_total = sum(len(chunk) for chunk in self._chunks)
        if (
            total_payload_bytes != self._expected_total_payload_bytes
            or total_payload_bytes != actual_total
        ):
            self._fault("SNAPSHOT_COMMIT total payload bytes mismatch")

        account_revision = int(values["account_revision"])
        if account_revision != self._account_revision:
            self._fault("SNAPSHOT_COMMIT account revision mismatch")

        aggregate = b"".join(self._chunks)
        actual_crc = crc32c(aggregate)
        declared_crc = int(values["aggregate_crc32c"])
        if declared_crc != actual_crc:
            self._fault("SNAPSHOT_COMMIT aggregate CRC32C mismatch")

        sequence_watermark = int(values["sequence_watermark"])
        if sequence_watermark < self._base_sequence:
            self._fault("SNAPSHOT_COMMIT sequence watermark precedes base sequence")

        self._snapshot_summary = SnapshotSummary(
            snapshot_id=self._snapshot_id,
            base_sequence=self._base_sequence,
            sequence_watermark=sequence_watermark,
            account_revision=account_revision,
            record_mask=self._record_mask,
            chunk_count=chunk_count,
            record_count=record_count,
            total_payload_bytes=total_payload_bytes,
            aggregate_crc32c=declared_crc,
        )
        self._state = RecoveryState.WAITING_RECONCILE

    def _on_reconcile_report(self, frame: Kat1Frame) -> None:
        if self._state is not RecoveryState.WAITING_RECONCILE:
            self._fault("RECONCILE_REPORT received outside expected state")
        if self._reconcile_request_id is None:
            self._fault("RECONCILE_REPORT received before RECONCILE_REQUEST")
        if self._snapshot_summary is None:
            self._fault("RECONCILE_REPORT received without accepted snapshot")

        values = frame.values
        if str(values["request_id"]) != self._reconcile_request_id.hex():
            self._fault("RECONCILE_REPORT request_id mismatch")
        if str(values["snapshot_id"]) != self._snapshot_summary.snapshot_id:
            self._fault("RECONCILE_REPORT snapshot_id mismatch")

        first_cursor = int(values["first_event_cursor"])
        last_cursor = int(values["last_event_cursor"])
        if last_cursor < first_cursor:
            self._fault("RECONCILE_REPORT event cursor range is invalid")

        discrepancies = values["discrepancies"]
        if int(values["discrepancy_count"]) != 0 or len(discrepancies) != 0:
            self._fault("RECONCILE_REPORT contains discrepancies")

        if int(values["recovery_state"]) != RECOVERY_READY:
            self._fault("RECONCILE_REPORT is not recovery READY")

        self._state = RecoveryState.COMPLETE

    def _validate_binding(self, frame: Kat1Frame) -> None:
        if frame.header.stream_id != self._stream_id:
            self._fault("recovery frame stream_id mismatch")
        if frame.header.boot_id != self._boot_id:
            self._fault("recovery frame boot_id mismatch")

    def _reset_transaction(self) -> None:
        self._reconcile_request_id = None
        self._snapshot_id = None
        self._base_sequence = 0
        self._account_revision = 0
        self._record_mask = 0
        self._expected_chunk_count = 0
        self._expected_record_count = 0
        self._expected_total_payload_bytes = 0
        self._chunks = []
        self._records = []
        self._record_count = 0
        self._snapshot_summary = None

    @staticmethod
    def _require_id128(value: bytes, name: str) -> None:
        if not isinstance(value, (bytes, bytearray)) or len(value) != 16:
            raise ValueError(f"{name} must be exactly 16 bytes")

    def _fault(self, message: str) -> None:
        self._state = RecoveryState.FAULTED
        raise RecoveryFault(message)
