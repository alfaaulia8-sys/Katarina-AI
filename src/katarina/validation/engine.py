from __future__ import annotations

import math
import time
from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Callable

from katarina.contracts.runtime import EventEnvelope
from katarina.core.readiness import ReadinessGate, ReadinessSignal


class ValidationSeverity(str, Enum):
    INFO = "info"
    WARNING = "warning"
    ERROR = "error"
    CRITICAL = "critical"


class ValidationDisposition(str, Enum):
    ACCEPT = "accept"
    QUARANTINE = "quarantine"
    REJECT = "reject"


@dataclass(frozen=True, slots=True)
class ValidationIssue:
    code: str
    severity: ValidationSeverity
    message: str
    field: str | None = None


@dataclass(frozen=True, slots=True)
class ValidationPolicy:
    max_event_age_ns: int = 5_000_000_000
    max_future_skew_ns: int = 1_000_000_000
    require_external_source_time: bool = True
    reject_non_finite_numbers: bool = True
    freshness_by_topic_ns: Mapping[str, int] = field(
        default_factory=lambda: {
            "market.tick": 2_000_000_000,
            "market.bar": 10_000_000_000,
            "symbol.spec": 3_600_000_000_000,
            "account.state": 5_000_000_000,
            "position.state": 5_000_000_000,
            "order.state": 5_000_000_000,
        }
    )

    def __post_init__(self) -> None:
        if self.max_event_age_ns <= 0:
            raise ValueError("max_event_age_ns must be positive")
        if self.max_future_skew_ns < 0:
            raise ValueError("max_future_skew_ns must be non-negative")
        for topic, budget in self.freshness_by_topic_ns.items():
            if not topic or budget <= 0:
                raise ValueError("freshness topic/budget must be positive")


@dataclass(frozen=True, slots=True)
class ValidationResult:
    event: EventEnvelope
    disposition: ValidationDisposition
    issues: tuple[ValidationIssue, ...]
    validated_at_ns: int

    @property
    def accepted(self) -> bool:
        return self.disposition is ValidationDisposition.ACCEPT


@dataclass(frozen=True, slots=True)
class SymbolSpecSnapshot:
    instrument_id: int
    spec_revision: int
    digits: int
    price_scale: int
    volume_scale: int
    point_units: int
    tick_size_units: int
    volume_min_units: int
    volume_max_units: int
    volume_step_units: int
    canonical_symbol: str
    broker_symbol: str


@dataclass(frozen=True, slots=True)
class HistoryRequirement:
    instrument_id: int
    spec_revision: int
    timeframe_minutes: int
    min_bars: int

    def __post_init__(self) -> None:
        if self.instrument_id <= 0:
            raise ValueError("instrument_id must be positive")
        if self.spec_revision <= 0:
            raise ValueError("spec_revision must be positive")
        if self.timeframe_minutes <= 0:
            raise ValueError("timeframe_minutes must be positive")
        if self.min_bars <= 0:
            raise ValueError("min_bars must be positive")


@dataclass(frozen=True, slots=True)
class HistoryValidationResult:
    requirement: HistoryRequirement
    issues: tuple[ValidationIssue, ...]
    observed_bars: int

    @property
    def complete(self) -> bool:
        return not any(
            issue.severity in {ValidationSeverity.ERROR, ValidationSeverity.CRITICAL}
            for issue in self.issues
        )


@dataclass(frozen=True, slots=True)
class ValidationGateResult:
    validation: ValidationResult
    promoted_event: EventEnvelope | None

    @property
    def promoted(self) -> bool:
        return self.promoted_event is not None


ValidationRule = Callable[[EventEnvelope, int], Iterable[ValidationIssue]]


class DataValidationEngine:
    """Fail-closed semantic validation after KAT1 decoding.

    Stage 08 owns data quality only. It does not make trading decisions,
    arm execution, size risk, persist broker state, or submit broker orders.
    """

    def __init__(self, policy: ValidationPolicy | None = None) -> None:
        self.policy = policy or ValidationPolicy()
        self._rules: dict[str, list[ValidationRule]] = {}
        self._symbol_specs: dict[int, SymbolSpecSnapshot] = {}
        self.register("symbol.spec", self._validate_symbol_spec)
        self.register("market.tick", self._validate_tick)
        self.register("market.bar", self._validate_bar)

    @property
    def symbol_specs(self) -> Mapping[int, SymbolSpecSnapshot]:
        return dict(self._symbol_specs)

    def register(self, topic: str, rule: ValidationRule) -> None:
        if not topic:
            raise ValueError("topic must be non-empty")
        self._rules.setdefault(topic, []).append(rule)

    def validate(
        self,
        event: EventEnvelope,
        *,
        now_ns: int | None = None,
    ) -> ValidationResult:
        observed_ns = time.time_ns() if now_ns is None else now_ns
        if observed_ns < 0:
            raise ValueError("now_ns must be non-negative")

        issues: list[ValidationIssue] = []
        issues.extend(self._validate_freshness(event, observed_ns))
        if self.policy.reject_non_finite_numbers:
            issues.extend(self._validate_finite_payload(event.payload))

        for rule in self._rules.get(event.topic, ()):
            try:
                issues.extend(rule(event, observed_ns))
            except Exception as exc:
                issues.append(
                    ValidationIssue(
                        code="VALIDATION_RULE_EXCEPTION",
                        severity=ValidationSeverity.CRITICAL,
                        message=f"validation rule failed closed: {exc}",
                    )
                )

        disposition = self._disposition(issues)
        result = ValidationResult(
            event=event,
            disposition=disposition,
            issues=tuple(issues),
            validated_at_ns=observed_ns,
        )

        if event.topic == "symbol.spec" and result.accepted:
            payload = self._require_mapping(event.payload)
            spec = self._symbol_spec_from_payload(payload)
            previous = self._symbol_specs.get(spec.instrument_id)
            if previous is None or spec.spec_revision >= previous.spec_revision:
                self._symbol_specs[spec.instrument_id] = spec

        return result

    def validate_history(
        self,
        bars: Sequence[EventEnvelope],
        requirement: HistoryRequirement,
        *,
        now_ns: int | None = None,
    ) -> HistoryValidationResult:
        observed_ns = time.time_ns() if now_ns is None else now_ns
        issues: list[ValidationIssue] = []

        if len(bars) < requirement.min_bars:
            issues.append(
                ValidationIssue(
                    code="HISTORY_INCOMPLETE",
                    severity=ValidationSeverity.ERROR,
                    message=(
                        f"required {requirement.min_bars} bars, "
                        f"received {len(bars)}"
                    ),
                )
            )

        previous_sequence: int | None = None
        previous_open_time: int | None = None
        for index, event in enumerate(bars):
            if event.topic != "market.bar":
                issues.append(
                    ValidationIssue(
                        code="HISTORY_WRONG_TOPIC",
                        severity=ValidationSeverity.CRITICAL,
                        message="history input contains a non-bar event",
                        field=f"bars[{index}]",
                    )
                )
                continue

            result = self.validate(event, now_ns=observed_ns)
            issues.extend(result.issues)
            payload = self._mapping_or_none(event.payload)
            if payload is None:
                continue

            if payload.get("instrument_id") != requirement.instrument_id:
                issues.append(
                    ValidationIssue(
                        code="HISTORY_INSTRUMENT_MISMATCH",
                        severity=ValidationSeverity.CRITICAL,
                        message="bar instrument_id differs from requirement",
                        field=f"bars[{index}].instrument_id",
                    )
                )
            if payload.get("spec_revision") != requirement.spec_revision:
                issues.append(
                    ValidationIssue(
                        code="HISTORY_SPEC_REVISION_MISMATCH",
                        severity=ValidationSeverity.CRITICAL,
                        message="bar spec_revision differs from requirement",
                        field=f"bars[{index}].spec_revision",
                    )
                )
            if payload.get("timeframe_minutes") != requirement.timeframe_minutes:
                issues.append(
                    ValidationIssue(
                        code="HISTORY_TIMEFRAME_MISMATCH",
                        severity=ValidationSeverity.CRITICAL,
                        message="bar timeframe differs from requirement",
                        field=f"bars[{index}].timeframe_minutes",
                    )
                )

            sequence = payload.get("bar_sequence")
            if self._is_int(sequence):
                if previous_sequence is not None and sequence != previous_sequence + 1:
                    issues.append(
                        ValidationIssue(
                            code="HISTORY_SEQUENCE_GAP",
                            severity=ValidationSeverity.CRITICAL,
                            message="bar_sequence is not contiguous",
                            field=f"bars[{index}].bar_sequence",
                        )
                    )
                previous_sequence = int(sequence)

            open_time = payload.get("bar_open_time_ns")
            if self._is_int(open_time):
                if previous_open_time is not None and open_time <= previous_open_time:
                    issues.append(
                        ValidationIssue(
                            code="HISTORY_TIME_NOT_INCREASING",
                            severity=ValidationSeverity.CRITICAL,
                            message="bar_open_time_ns must strictly increase",
                            field=f"bars[{index}].bar_open_time_ns",
                        )
                    )
                previous_open_time = int(open_time)

        return HistoryValidationResult(
            requirement=requirement,
            issues=tuple(issues),
            observed_bars=len(bars),
        )

    def _validate_freshness(
        self,
        event: EventEnvelope,
        now_ns: int,
    ) -> tuple[ValidationIssue, ...]:
        if event.source == "internal":
            return ()

        if event.source_time_ns is None:
            if not self.policy.require_external_source_time:
                return ()
            return (
                ValidationIssue(
                    code="MISSING_SOURCE_TIME",
                    severity=ValidationSeverity.ERROR,
                    message="external data is missing source_time_ns",
                    field="source_time_ns",
                ),
            )

        age_ns = now_ns - event.source_time_ns
        if age_ns < -self.policy.max_future_skew_ns:
            return (
                ValidationIssue(
                    code="SOURCE_TIME_IN_FUTURE",
                    severity=ValidationSeverity.CRITICAL,
                    message="source timestamp exceeds allowed future clock skew",
                    field="source_time_ns",
                ),
            )

        budget = self.policy.freshness_by_topic_ns.get(
            event.topic,
            self.policy.max_event_age_ns,
        )
        if age_ns > budget:
            return (
                ValidationIssue(
                    code="STALE_DATA",
                    severity=ValidationSeverity.CRITICAL,
                    message=(
                        f"source data age {age_ns} exceeds topic budget {budget}"
                    ),
                    field="source_time_ns",
                ),
            )
        return ()

    def _validate_finite_payload(self, payload: Any) -> tuple[ValidationIssue, ...]:
        issues: list[ValidationIssue] = []

        def walk(value: Any, path: str) -> None:
            if isinstance(value, float):
                if not math.isfinite(value):
                    issues.append(
                        ValidationIssue(
                            code="NON_FINITE_NUMBER",
                            severity=ValidationSeverity.CRITICAL,
                            message="payload contains NaN or infinity",
                            field=path,
                        )
                    )
                return
            if isinstance(value, Mapping):
                for key, child in value.items():
                    walk(child, f"{path}.{key}" if path else str(key))
                return
            if isinstance(value, (list, tuple)):
                for index, child in enumerate(value):
                    walk(child, f"{path}[{index}]")

        walk(payload, "payload")
        return tuple(issues)

    def _validate_symbol_spec(
        self,
        event: EventEnvelope,
        now_ns: int,
    ) -> tuple[ValidationIssue, ...]:
        del now_ns
        payload, issues = self._mapping_payload(event)
        if payload is None:
            return issues

        found = list(issues)
        required = (
            "instrument_id",
            "spec_revision",
            "digits",
            "price_scale",
            "volume_scale",
            "point_units",
            "tick_size_units",
            "volume_min_units",
            "volume_max_units",
            "volume_step_units",
            "canonical_symbol",
            "broker_symbol",
        )
        found.extend(self._required_fields(payload, required, event.topic))

        for name in ("instrument_id", "spec_revision", "point_units", "tick_size_units",
                     "volume_min_units", "volume_max_units", "volume_step_units"):
            value = payload.get(name)
            if value is not None and (not self._is_int(value) or int(value) <= 0):
                found.append(
                    ValidationIssue(
                        code="INVALID_SYMBOL_SPEC_VALUE",
                        severity=ValidationSeverity.CRITICAL,
                        message=f"{name} must be a positive integer",
                        field=f"payload.{name}",
                    )
                )

        for name in ("digits", "price_scale", "volume_scale"):
            value = payload.get(name)
            if value is not None and (
                not self._is_int(value) or int(value) < 0 or int(value) > 18
            ):
                found.append(
                    ValidationIssue(
                        code="INVALID_SYMBOL_SPEC_SCALE",
                        severity=ValidationSeverity.CRITICAL,
                        message=f"{name} must be an integer in 0..18",
                        field=f"payload.{name}",
                    )
                )

        for name in ("canonical_symbol", "broker_symbol"):
            value = payload.get(name)
            if value is not None and (
                not isinstance(value, str) or not value.strip()
            ):
                found.append(
                    ValidationIssue(
                        code="INVALID_SYMBOL_IDENTITY",
                        severity=ValidationSeverity.CRITICAL,
                        message=f"{name} must be a non-empty string",
                        field=f"payload.{name}",
                    )
                )

        vmin = payload.get("volume_min_units")
        vmax = payload.get("volume_max_units")
        vstep = payload.get("volume_step_units")
        if all(self._is_int(v) for v in (vmin, vmax, vstep)):
            if int(vmin) > int(vmax):
                found.append(
                    ValidationIssue(
                        code="INVALID_VOLUME_RANGE",
                        severity=ValidationSeverity.CRITICAL,
                        message="volume_min_units exceeds volume_max_units",
                    )
                )

        instrument = payload.get("instrument_id")
        revision = payload.get("spec_revision")
        if self._is_int(instrument) and self._is_int(revision):
            previous = self._symbol_specs.get(int(instrument))
            if previous is not None and int(revision) < previous.spec_revision:
                found.append(
                    ValidationIssue(
                        code="SYMBOL_SPEC_REVISION_ROLLBACK",
                        severity=ValidationSeverity.CRITICAL,
                        message="SymbolSpec revision cannot decrease",
                        field="payload.spec_revision",
                    )
                )
        return tuple(found)

    def _validate_tick(
        self,
        event: EventEnvelope,
        now_ns: int,
    ) -> tuple[ValidationIssue, ...]:
        del now_ns
        payload, issues = self._mapping_payload(event)
        if payload is None:
            return issues

        found = list(issues)
        required = ("instrument_id", "spec_revision", "bid_units", "ask_units")
        found.extend(self._required_fields(payload, required, event.topic))
        spec = self._bound_spec(payload, found)

        bid = payload.get("bid_units")
        ask = payload.get("ask_units")
        if self._is_int(bid) and self._is_int(ask):
            if int(bid) <= 0 or int(ask) <= 0:
                found.append(
                    ValidationIssue(
                        code="NON_POSITIVE_PRICE",
                        severity=ValidationSeverity.CRITICAL,
                        message="bid_units/ask_units must be positive",
                    )
                )
            if int(ask) < int(bid):
                found.append(
                    ValidationIssue(
                        code="CROSSED_MARKET",
                        severity=ValidationSeverity.CRITICAL,
                        message="ask_units is below bid_units",
                    )
                )
            if spec is not None:
                found.extend(
                    self._price_quantization_issues(
                        {
                            "bid_units": int(bid),
                            "ask_units": int(ask),
                        },
                        spec,
                    )
                )
        return tuple(found)

    def _validate_bar(
        self,
        event: EventEnvelope,
        now_ns: int,
    ) -> tuple[ValidationIssue, ...]:
        del now_ns
        payload, issues = self._mapping_payload(event)
        if payload is None:
            return issues

        found = list(issues)
        required = (
            "instrument_id",
            "spec_revision",
            "timeframe_minutes",
            "bar_sequence",
            "bar_open_time_ns",
            "open_units",
            "high_units",
            "low_units",
            "close_units",
        )
        found.extend(self._required_fields(payload, required, event.topic))
        spec = self._bound_spec(payload, found)

        timeframe = payload.get("timeframe_minutes")
        if timeframe is not None and (
            not self._is_int(timeframe) or int(timeframe) <= 0
        ):
            found.append(
                ValidationIssue(
                    code="INVALID_TIMEFRAME",
                    severity=ValidationSeverity.CRITICAL,
                    message="timeframe_minutes must be positive",
                    field="payload.timeframe_minutes",
                )
            )

        prices = {
            name: payload.get(name)
            for name in ("open_units", "high_units", "low_units", "close_units")
        }
        if all(self._is_int(value) for value in prices.values()):
            values = [int(value) for value in prices.values()]
            if any(value <= 0 for value in values):
                found.append(
                    ValidationIssue(
                        code="NON_POSITIVE_PRICE",
                        severity=ValidationSeverity.CRITICAL,
                        message="OHLC units must be positive",
                    )
                )
            high = int(prices["high_units"])
            low = int(prices["low_units"])
            if high < max(values) or low > min(values) or high < low:
                found.append(
                    ValidationIssue(
                        code="INVALID_OHLC_ORDER",
                        severity=ValidationSeverity.CRITICAL,
                        message="OHLC range is internally inconsistent",
                    )
                )
            if spec is not None:
                found.extend(
                    self._price_quantization_issues(
                        {name: int(value) for name, value in prices.items()},
                        spec,
                    )
                )
        return tuple(found)

    def _bound_spec(
        self,
        payload: Mapping[str, Any],
        issues: list[ValidationIssue],
    ) -> SymbolSpecSnapshot | None:
        instrument = payload.get("instrument_id")
        revision = payload.get("spec_revision")
        if not self._is_int(instrument) or not self._is_int(revision):
            return None

        spec = self._symbol_specs.get(int(instrument))
        if spec is None:
            issues.append(
                ValidationIssue(
                    code="UNKNOWN_SYMBOL_SPEC",
                    severity=ValidationSeverity.CRITICAL,
                    message="no accepted SymbolSpec exists for instrument",
                    field="payload.instrument_id",
                )
            )
            return None
        if spec.spec_revision != int(revision):
            issues.append(
                ValidationIssue(
                    code="STALE_SYMBOL_SPEC",
                    severity=ValidationSeverity.CRITICAL,
                    message="event spec_revision is not the active SymbolSpec revision",
                    field="payload.spec_revision",
                )
            )
            return None
        return spec

    @staticmethod
    def _price_quantization_issues(
        prices: Mapping[str, int],
        spec: SymbolSpecSnapshot,
    ) -> tuple[ValidationIssue, ...]:
        issues: list[ValidationIssue] = []
        for field_name, value in prices.items():
            if value % spec.tick_size_units != 0:
                issues.append(
                    ValidationIssue(
                        code="PRICE_OFF_TICK_GRID",
                        severity=ValidationSeverity.CRITICAL,
                        message=(
                            f"{field_name} is not aligned to tick_size_units "
                            f"{spec.tick_size_units}"
                        ),
                        field=f"payload.{field_name}",
                    )
                )
        return tuple(issues)

    @staticmethod
    def _required_fields(
        payload: Mapping[str, Any],
        names: Sequence[str],
        topic: str,
    ) -> tuple[ValidationIssue, ...]:
        return tuple(
            ValidationIssue(
                code="MISSING_REQUIRED_FIELD",
                severity=ValidationSeverity.ERROR,
                message=f"{topic} requires {name}",
                field=f"payload.{name}",
            )
            for name in names
            if name not in payload
        )

    @staticmethod
    def _mapping_payload(
        event: EventEnvelope,
    ) -> tuple[Mapping[str, Any] | None, tuple[ValidationIssue, ...]]:
        if not isinstance(event.payload, Mapping):
            return None, (
                ValidationIssue(
                    code="PAYLOAD_NOT_MAPPING",
                    severity=ValidationSeverity.ERROR,
                    message=f"{event.topic} payload must be a mapping",
                    field="payload",
                ),
            )
        return event.payload, ()

    @staticmethod
    def _mapping_or_none(payload: Any) -> Mapping[str, Any] | None:
        return payload if isinstance(payload, Mapping) else None

    @staticmethod
    def _require_mapping(payload: Any) -> Mapping[str, Any]:
        if not isinstance(payload, Mapping):
            raise TypeError("payload must be a mapping")
        return payload

    @staticmethod
    def _symbol_spec_from_payload(payload: Mapping[str, Any]) -> SymbolSpecSnapshot:
        return SymbolSpecSnapshot(
            instrument_id=int(payload["instrument_id"]),
            spec_revision=int(payload["spec_revision"]),
            digits=int(payload["digits"]),
            price_scale=int(payload["price_scale"]),
            volume_scale=int(payload["volume_scale"]),
            point_units=int(payload["point_units"]),
            tick_size_units=int(payload["tick_size_units"]),
            volume_min_units=int(payload["volume_min_units"]),
            volume_max_units=int(payload["volume_max_units"]),
            volume_step_units=int(payload["volume_step_units"]),
            canonical_symbol=str(payload["canonical_symbol"]),
            broker_symbol=str(payload["broker_symbol"]),
        )

    @staticmethod
    def _is_int(value: Any) -> bool:
        return isinstance(value, int) and not isinstance(value, bool)

    @staticmethod
    def _disposition(
        issues: Iterable[ValidationIssue],
    ) -> ValidationDisposition:
        severities = {issue.severity for issue in issues}
        if ValidationSeverity.CRITICAL in severities:
            return ValidationDisposition.REJECT
        if ValidationSeverity.ERROR in severities:
            return ValidationDisposition.QUARANTINE
        return ValidationDisposition.ACCEPT


class ValidationReadinessTracker:
    """Owns only ReadinessSignal.DATA_FRESH.

    It intentionally cannot arm execution or set HEALTH/RISK.
    """

    def __init__(
        self,
        required_topics: Sequence[str],
        *,
        freshness_ns: int = 5_000_000_000,
    ) -> None:
        if not required_topics:
            raise ValueError("required_topics must be non-empty")
        if freshness_ns <= 0:
            raise ValueError("freshness_ns must be positive")
        self.required_topics = tuple(required_topics)
        self.freshness_ns = freshness_ns
        self._last_accepted_ns: dict[str, int] = {}
        self._invalid_topics: set[str] = set()

    def observe(self, result: ValidationResult) -> None:
        topic = result.event.topic
        if topic not in self.required_topics:
            return
        if result.accepted:
            self._last_accepted_ns[topic] = result.validated_at_ns
            self._invalid_topics.discard(topic)
        elif result.disposition is ValidationDisposition.REJECT:
            self._invalid_topics.add(topic)

    def data_fresh(self, *, now_ns: int) -> bool:
        if self._invalid_topics:
            return False
        for topic in self.required_topics:
            accepted_ns = self._last_accepted_ns.get(topic)
            if accepted_ns is None or now_ns - accepted_ns > self.freshness_ns:
                return False
        return True

    def apply(self, readiness: ReadinessGate, *, now_ns: int) -> bool:
        value = self.data_fresh(now_ns=now_ns)
        readiness.set(ReadinessSignal.DATA_FRESH, value)
        return value


class ValidatedIngestGate:
    """Promotes only ACCEPT data to the downstream state/cache boundary."""

    def __init__(
        self,
        engine: DataValidationEngine,
        tracker: ValidationReadinessTracker | None = None,
    ) -> None:
        self.engine = engine
        self.tracker = tracker

    def promote(
        self,
        event: EventEnvelope,
        *,
        now_ns: int | None = None,
    ) -> ValidationGateResult:
        result = self.engine.validate(event, now_ns=now_ns)
        if self.tracker is not None:
            self.tracker.observe(result)
        return ValidationGateResult(
            validation=result,
            promoted_event=event if result.accepted else None,
        )
