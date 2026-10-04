from __future__ import annotations

import math
import time
from collections.abc import Iterable, Mapping
from dataclasses import dataclass
from enum import Enum
from typing import Any, Callable

from katarina.contracts.runtime import EventEnvelope


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

    def __post_init__(self) -> None:
        if self.max_event_age_ns <= 0:
            raise ValueError("max_event_age_ns must be positive")
        if self.max_future_skew_ns < 0:
            raise ValueError("max_future_skew_ns must be non-negative")


@dataclass(frozen=True, slots=True)
class ValidationResult:
    event: EventEnvelope
    disposition: ValidationDisposition
    issues: tuple[ValidationIssue, ...]
    validated_at_ns: int

    @property
    def accepted(self) -> bool:
        return self.disposition is ValidationDisposition.ACCEPT


ValidationRule = Callable[
    [EventEnvelope, int],
    Iterable[ValidationIssue],
]


class DataValidationEngine:
    """Fail-closed semantic validation after transport/protocol decoding.

    Stage 08 owns data quality only. It does not make trading decisions,
    arm execution, size risk, persist state, or submit broker orders.
    """

    def __init__(self, policy: ValidationPolicy | None = None) -> None:
        self.policy = policy or ValidationPolicy()
        self._rules: dict[str, list[ValidationRule]] = {}
        self.register("market.tick", self._validate_tick)
        self.register("market.bar", self._validate_bar)

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

        return ValidationResult(
            event=event,
            disposition=self._disposition(issues),
            issues=tuple(issues),
            validated_at_ns=observed_ns,
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
        if age_ns > self.policy.max_event_age_ns:
            return (
                ValidationIssue(
                    code="STALE_DATA",
                    severity=ValidationSeverity.CRITICAL,
                    message="source data is older than the freshness budget",
                    field="source_time_ns",
                ),
            )
        return ()

    def _validate_finite_payload(
        self,
        payload: Any,
    ) -> tuple[ValidationIssue, ...]:
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
        for field in ("symbol", "bid", "ask"):
            if field not in payload:
                found.append(
                    ValidationIssue(
                        code="MISSING_REQUIRED_FIELD",
                        severity=ValidationSeverity.ERROR,
                        message=f"market.tick requires {field}",
                        field=f"payload.{field}",
                    )
                )

        symbol = payload.get("symbol")
        if symbol is not None and (
            not isinstance(symbol, str) or not symbol.strip()
        ):
            found.append(
                ValidationIssue(
                    code="INVALID_SYMBOL",
                    severity=ValidationSeverity.ERROR,
                    message="symbol must be a non-empty string",
                    field="payload.symbol",
                )
            )

        bid = payload.get("bid")
        ask = payload.get("ask")
        if self._is_number(bid) and self._is_number(ask):
            if bid <= 0 or ask <= 0:
                found.append(
                    ValidationIssue(
                        code="NON_POSITIVE_PRICE",
                        severity=ValidationSeverity.CRITICAL,
                        message="bid/ask must be positive",
                    )
                )
            if ask < bid:
                found.append(
                    ValidationIssue(
                        code="CROSSED_MARKET",
                        severity=ValidationSeverity.CRITICAL,
                        message="ask is below bid",
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
        required = ("symbol", "open", "high", "low", "close")
        for field in required:
            if field not in payload:
                found.append(
                    ValidationIssue(
                        code="MISSING_REQUIRED_FIELD",
                        severity=ValidationSeverity.ERROR,
                        message=f"market.bar requires {field}",
                        field=f"payload.{field}",
                    )
                )

        prices = {
            name: payload.get(name)
            for name in ("open", "high", "low", "close")
        }
        if all(self._is_number(value) for value in prices.values()):
            values = [float(value) for value in prices.values()]
            if any(value <= 0 for value in values):
                found.append(
                    ValidationIssue(
                        code="NON_POSITIVE_PRICE",
                        severity=ValidationSeverity.CRITICAL,
                        message="OHLC prices must be positive",
                    )
                )
            high = float(prices["high"])
            low = float(prices["low"])
            if high < max(values) or low > min(values) or high < low:
                found.append(
                    ValidationIssue(
                        code="INVALID_OHLC_ORDER",
                        severity=ValidationSeverity.CRITICAL,
                        message="OHLC range is internally inconsistent",
                    )
                )
        return tuple(found)

    @staticmethod
    def _is_number(value: Any) -> bool:
        return (
            isinstance(value, (int, float))
            and not isinstance(value, bool)
            and (not isinstance(value, float) or math.isfinite(value))
        )

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
