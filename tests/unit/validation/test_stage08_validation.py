from __future__ import annotations

import math
import unittest

from katarina.contracts.runtime import EventEnvelope
from katarina.validation.engine import (
    DataValidationEngine,
    ValidationDisposition,
    ValidationIssue,
    ValidationPolicy,
    ValidationSeverity,
)


NOW = 10_000_000_000


class Stage08DataValidationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.engine = DataValidationEngine(
            ValidationPolicy(
                max_event_age_ns=5_000_000_000,
                max_future_skew_ns=1_000_000_000,
            )
        )

    def event(
        self,
        topic: str,
        payload,
        *,
        source: str = "mt5",
        source_time_ns: int | None = NOW,
    ) -> EventEnvelope:
        return EventEnvelope(
            topic=topic,
            payload=payload,
            source=source,
            source_time_ns=source_time_ns,
            sequence=1,
        )

    def test_valid_tick_is_accepted(self) -> None:
        result = self.engine.validate(
            self.event(
                "market.tick",
                {"symbol": "XAUUSD", "bid": 2650.1, "ask": 2650.3},
            ),
            now_ns=NOW,
        )
        self.assertTrue(result.accepted)
        self.assertEqual(result.disposition, ValidationDisposition.ACCEPT)

    def test_missing_external_timestamp_is_quarantined(self) -> None:
        result = self.engine.validate(
            self.event(
                "market.tick",
                {"symbol": "XAUUSD", "bid": 1.0, "ask": 1.1},
                source_time_ns=None,
            ),
            now_ns=NOW,
        )
        self.assertEqual(result.disposition, ValidationDisposition.QUARANTINE)
        self.assertIn("MISSING_SOURCE_TIME", {i.code for i in result.issues})

    def test_internal_event_does_not_require_timestamp(self) -> None:
        result = self.engine.validate(
            self.event(
                "internal.note",
                {"value": 1},
                source="internal",
                source_time_ns=None,
            ),
            now_ns=NOW,
        )
        self.assertEqual(result.disposition, ValidationDisposition.ACCEPT)

    def test_stale_external_data_is_rejected(self) -> None:
        result = self.engine.validate(
            self.event(
                "market.tick",
                {"symbol": "XAUUSD", "bid": 1.0, "ask": 1.1},
                source_time_ns=1,
            ),
            now_ns=NOW,
        )
        self.assertEqual(result.disposition, ValidationDisposition.REJECT)
        self.assertIn("STALE_DATA", {i.code for i in result.issues})

    def test_future_clock_skew_is_rejected(self) -> None:
        result = self.engine.validate(
            self.event(
                "unknown",
                {"value": 1},
                source_time_ns=NOW + 2_000_000_000,
            ),
            now_ns=NOW,
        )
        self.assertEqual(result.disposition, ValidationDisposition.REJECT)
        self.assertIn("SOURCE_TIME_IN_FUTURE", {i.code for i in result.issues})

    def test_nested_nan_is_rejected(self) -> None:
        result = self.engine.validate(
            self.event("unknown", {"nested": [{"value": math.nan}]}),
            now_ns=NOW,
        )
        self.assertEqual(result.disposition, ValidationDisposition.REJECT)
        self.assertIn("NON_FINITE_NUMBER", {i.code for i in result.issues})

    def test_crossed_market_is_rejected(self) -> None:
        result = self.engine.validate(
            self.event(
                "market.tick",
                {"symbol": "XAUUSD", "bid": 2651.0, "ask": 2650.0},
            ),
            now_ns=NOW,
        )
        self.assertEqual(result.disposition, ValidationDisposition.REJECT)
        self.assertIn("CROSSED_MARKET", {i.code for i in result.issues})

    def test_missing_tick_field_is_quarantined(self) -> None:
        result = self.engine.validate(
            self.event("market.tick", {"symbol": "XAUUSD", "bid": 2650.0}),
            now_ns=NOW,
        )
        self.assertEqual(result.disposition, ValidationDisposition.QUARANTINE)
        self.assertIn("MISSING_REQUIRED_FIELD", {i.code for i in result.issues})

    def test_valid_bar_is_accepted(self) -> None:
        result = self.engine.validate(
            self.event(
                "market.bar",
                {
                    "symbol": "XAUUSD",
                    "open": 2649.0,
                    "high": 2652.0,
                    "low": 2648.0,
                    "close": 2651.0,
                },
            ),
            now_ns=NOW,
        )
        self.assertEqual(result.disposition, ValidationDisposition.ACCEPT)

    def test_invalid_ohlc_is_rejected(self) -> None:
        result = self.engine.validate(
            self.event(
                "market.bar",
                {
                    "symbol": "XAUUSD",
                    "open": 2649.0,
                    "high": 2648.0,
                    "low": 2647.0,
                    "close": 2651.0,
                },
            ),
            now_ns=NOW,
        )
        self.assertEqual(result.disposition, ValidationDisposition.REJECT)
        self.assertIn("INVALID_OHLC_ORDER", {i.code for i in result.issues})

    def test_unknown_finite_topic_is_accepted(self) -> None:
        result = self.engine.validate(
            self.event(
                "account.state",
                {"balance": 100.0, "equity": 99.5},
            ),
            now_ns=NOW,
        )
        self.assertEqual(result.disposition, ValidationDisposition.ACCEPT)

    def test_rule_exception_fails_closed(self) -> None:
        def broken_rule(event: EventEnvelope, now_ns: int):
            del event, now_ns
            raise RuntimeError("boom")

        self.engine.register("custom", broken_rule)
        result = self.engine.validate(
            self.event("custom", {"value": 1}),
            now_ns=NOW,
        )
        self.assertEqual(result.disposition, ValidationDisposition.REJECT)
        self.assertIn(
            "VALIDATION_RULE_EXCEPTION",
            {i.code for i in result.issues},
        )

    def test_custom_error_rule_quarantines(self) -> None:
        def rule(event: EventEnvelope, now_ns: int):
            del event, now_ns
            return (
                ValidationIssue(
                    code="CUSTOM_ERROR",
                    severity=ValidationSeverity.ERROR,
                    message="custom error",
                ),
            )

        self.engine.register("custom-error", rule)
        result = self.engine.validate(
            self.event("custom-error", {"value": 1}),
            now_ns=NOW,
        )
        self.assertEqual(result.disposition, ValidationDisposition.QUARANTINE)


if __name__ == "__main__":
    unittest.main()
