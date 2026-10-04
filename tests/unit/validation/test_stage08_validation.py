from __future__ import annotations

import math
import unittest

from katarina.contracts.runtime import EventEnvelope, RuntimeMode
from katarina.core.readiness import ReadinessGate, ReadinessSignal
from katarina.validation.engine import (
    DataValidationEngine,
    HistoryRequirement,
    ValidatedIngestGate,
    ValidationDisposition,
    ValidationIssue,
    ValidationPolicy,
    ValidationReadinessTracker,
    ValidationSeverity,
)


NOW = 20_000_000_000


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
        sequence: int = 1,
    ) -> EventEnvelope:
        return EventEnvelope(
            topic=topic,
            payload=payload,
            source=source,
            source_time_ns=source_time_ns,
            sequence=sequence,
        )

    def spec_payload(self, *, revision: int = 7, tick_size: int = 10):
        return {
            "instrument_id": 1,
            "spec_revision": revision,
            "digits": 2,
            "price_scale": 2,
            "volume_scale": 2,
            "point_units": 1,
            "tick_size_units": tick_size,
            "volume_min_units": 1,
            "volume_max_units": 10000,
            "volume_step_units": 1,
            "canonical_symbol": "XAUUSD",
            "broker_symbol": "XAUUSD.vx",
        }

    def install_spec(self, *, revision: int = 7, tick_size: int = 10):
        result = self.engine.validate(
            self.event(
                "symbol.spec",
                self.spec_payload(revision=revision, tick_size=tick_size),
            ),
            now_ns=NOW,
        )
        self.assertEqual(result.disposition, ValidationDisposition.ACCEPT)

    def tick_payload(
        self,
        *,
        revision: int = 7,
        bid: int = 265000,
        ask: int = 265010,
    ):
        return {
            "instrument_id": 1,
            "spec_revision": revision,
            "bid_units": bid,
            "ask_units": ask,
            "last_units": 0,
            "volume_units": 0,
            "tick_flags": 0,
            "presence_flags": 0,
        }

    def bar_payload(
        self,
        *,
        revision: int = 7,
        sequence: int = 1,
        open_time: int = 1_000_000_000,
        timeframe: int = 15,
        open_units: int = 265000,
        high_units: int = 265100,
        low_units: int = 264900,
        close_units: int = 265050,
    ):
        return {
            "instrument_id": 1,
            "spec_revision": revision,
            "timeframe_minutes": timeframe,
            "bar_state": 1,
            "bar_sequence": sequence,
            "bar_open_time_ns": open_time,
            "open_units": open_units,
            "high_units": high_units,
            "low_units": low_units,
            "close_units": close_units,
            "tick_volume": 100,
            "real_volume_units": 0,
            "spread_points": 10,
            "presence_flags": 0,
        }

    def test_symbol_spec_is_accepted_and_installed(self) -> None:
        self.install_spec()
        self.assertEqual(self.engine.symbol_specs[1].spec_revision, 7)

    def test_symbol_spec_revision_rollback_rejected(self) -> None:
        self.install_spec(revision=7)
        result = self.engine.validate(
            self.event("symbol.spec", self.spec_payload(revision=6)),
            now_ns=NOW,
        )
        self.assertEqual(result.disposition, ValidationDisposition.REJECT)
        self.assertIn("SYMBOL_SPEC_REVISION_ROLLBACK", {i.code for i in result.issues})

    def test_tick_requires_known_symbol_spec(self) -> None:
        result = self.engine.validate(
            self.event("market.tick", self.tick_payload()),
            now_ns=NOW,
        )
        self.assertEqual(result.disposition, ValidationDisposition.REJECT)
        self.assertIn("UNKNOWN_SYMBOL_SPEC", {i.code for i in result.issues})

    def test_valid_kat1_tick_is_accepted(self) -> None:
        self.install_spec()
        result = self.engine.validate(
            self.event("market.tick", self.tick_payload()),
            now_ns=NOW,
        )
        self.assertTrue(result.accepted)

    def test_stale_spec_revision_is_rejected(self) -> None:
        self.install_spec(revision=8)
        result = self.engine.validate(
            self.event("market.tick", self.tick_payload(revision=7)),
            now_ns=NOW,
        )
        self.assertEqual(result.disposition, ValidationDisposition.REJECT)
        self.assertIn("STALE_SYMBOL_SPEC", {i.code for i in result.issues})

    def test_crossed_market_is_rejected(self) -> None:
        self.install_spec()
        result = self.engine.validate(
            self.event("market.tick", self.tick_payload(bid=265020, ask=265010)),
            now_ns=NOW,
        )
        self.assertEqual(result.disposition, ValidationDisposition.REJECT)
        self.assertIn("CROSSED_MARKET", {i.code for i in result.issues})

    def test_price_off_tick_grid_is_rejected(self) -> None:
        self.install_spec(tick_size=10)
        result = self.engine.validate(
            self.event("market.tick", self.tick_payload(bid=265001, ask=265011)),
            now_ns=NOW,
        )
        self.assertEqual(result.disposition, ValidationDisposition.REJECT)
        self.assertIn("PRICE_OFF_TICK_GRID", {i.code for i in result.issues})

    def test_valid_bar_is_accepted(self) -> None:
        self.install_spec()
        result = self.engine.validate(
            self.event("market.bar", self.bar_payload()),
            now_ns=NOW,
        )
        self.assertEqual(result.disposition, ValidationDisposition.ACCEPT)

    def test_invalid_ohlc_is_rejected(self) -> None:
        self.install_spec()
        result = self.engine.validate(
            self.event(
                "market.bar",
                self.bar_payload(high_units=264900, close_units=265050),
            ),
            now_ns=NOW,
        )
        self.assertEqual(result.disposition, ValidationDisposition.REJECT)
        self.assertIn("INVALID_OHLC_ORDER", {i.code for i in result.issues})

    def test_topic_specific_freshness_is_applied(self) -> None:
        self.install_spec()
        result = self.engine.validate(
            self.event(
                "market.tick",
                self.tick_payload(),
                source_time_ns=NOW - 3_000_000_000,
            ),
            now_ns=NOW,
        )
        self.assertEqual(result.disposition, ValidationDisposition.REJECT)
        self.assertIn("STALE_DATA", {i.code for i in result.issues})

    def test_symbol_spec_longer_freshness_budget(self) -> None:
        result = self.engine.validate(
            self.event(
                "symbol.spec",
                self.spec_payload(),
                source_time_ns=NOW - 30_000_000_000,
            ),
            now_ns=NOW,
        )
        self.assertEqual(result.disposition, ValidationDisposition.ACCEPT)

    def test_missing_external_timestamp_is_quarantined(self) -> None:
        self.install_spec()
        result = self.engine.validate(
            self.event(
                "market.tick",
                self.tick_payload(),
                source_time_ns=None,
            ),
            now_ns=NOW,
        )
        self.assertEqual(result.disposition, ValidationDisposition.QUARANTINE)
        self.assertIn("MISSING_SOURCE_TIME", {i.code for i in result.issues})

    def test_future_clock_skew_is_rejected(self) -> None:
        result = self.engine.validate(
            self.event(
                "account.state",
                {"balance_units": 10000},
                source_time_ns=NOW + 2_000_000_000,
            ),
            now_ns=NOW,
        )
        self.assertEqual(result.disposition, ValidationDisposition.REJECT)
        self.assertIn("SOURCE_TIME_IN_FUTURE", {i.code for i in result.issues})

    def test_nested_nan_is_rejected(self) -> None:
        result = self.engine.validate(
            self.event("account.state", {"nested": [{"value": math.nan}]}),
            now_ns=NOW,
        )
        self.assertEqual(result.disposition, ValidationDisposition.REJECT)
        self.assertIn("NON_FINITE_NUMBER", {i.code for i in result.issues})

    def test_internal_event_does_not_require_source_timestamp(self) -> None:
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
        self.assertIn("VALIDATION_RULE_EXCEPTION", {i.code for i in result.issues})

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

    def test_complete_history_passes(self) -> None:
        self.install_spec()
        bars = [
            self.event(
                "market.bar",
                self.bar_payload(
                    sequence=n,
                    open_time=n * 900_000_000_000,
                ),
                sequence=n,
            )
            for n in range(1, 6)
        ]
        result = self.engine.validate_history(
            bars,
            HistoryRequirement(
                instrument_id=1,
                spec_revision=7,
                timeframe_minutes=15,
                min_bars=5,
            ),
            now_ns=NOW,
        )
        self.assertTrue(result.complete)

    def test_history_count_shortage_is_incomplete(self) -> None:
        self.install_spec()
        bars = [
            self.event(
                "market.bar",
                self.bar_payload(sequence=n, open_time=n * 1000),
            )
            for n in range(1, 4)
        ]
        result = self.engine.validate_history(
            bars,
            HistoryRequirement(1, 7, 15, 5),
            now_ns=NOW,
        )
        self.assertFalse(result.complete)
        self.assertIn("HISTORY_INCOMPLETE", {i.code for i in result.issues})

    def test_history_sequence_gap_is_rejected(self) -> None:
        self.install_spec()
        bars = [
            self.event("market.bar", self.bar_payload(sequence=1, open_time=1000)),
            self.event("market.bar", self.bar_payload(sequence=3, open_time=2000)),
        ]
        result = self.engine.validate_history(
            bars,
            HistoryRequirement(1, 7, 15, 2),
            now_ns=NOW,
        )
        self.assertFalse(result.complete)
        self.assertIn("HISTORY_SEQUENCE_GAP", {i.code for i in result.issues})

    def test_history_wrong_timeframe_is_rejected(self) -> None:
        self.install_spec()
        bars = [
            self.event(
                "market.bar",
                self.bar_payload(sequence=1, open_time=1000, timeframe=5),
            )
        ]
        result = self.engine.validate_history(
            bars,
            HistoryRequirement(1, 7, 15, 1),
            now_ns=NOW,
        )
        self.assertFalse(result.complete)
        self.assertIn("HISTORY_TIMEFRAME_MISMATCH", {i.code for i in result.issues})

    def test_ingest_gate_promotes_accept_only(self) -> None:
        self.install_spec()
        gate = ValidatedIngestGate(self.engine)
        good = gate.promote(
            self.event("market.tick", self.tick_payload()),
            now_ns=NOW,
        )
        bad = gate.promote(
            self.event("market.tick", self.tick_payload(bid=265020, ask=265010)),
            now_ns=NOW,
        )
        self.assertTrue(good.promoted)
        self.assertFalse(bad.promoted)

    def test_readiness_tracker_sets_only_data_fresh(self) -> None:
        self.install_spec()
        tracker = ValidationReadinessTracker(
            ("market.tick", "account.state"),
            freshness_ns=5_000_000_000,
        )
        gate = ValidatedIngestGate(self.engine, tracker)
        gate.promote(
            self.event("market.tick", self.tick_payload()),
            now_ns=NOW,
        )
        gate.promote(
            self.event("account.state", {"balance_units": 10000}),
            now_ns=NOW,
        )

        readiness = ReadinessGate(RuntimeMode.LIVE)
        self.assertTrue(tracker.apply(readiness, now_ns=NOW))
        self.assertTrue(readiness.is_set(ReadinessSignal.DATA_FRESH))
        self.assertFalse(readiness.is_set(ReadinessSignal.HEALTH))
        self.assertFalse(readiness.is_set(ReadinessSignal.RISK))
        self.assertFalse(readiness.is_set(ReadinessSignal.EXECUTION_ARMED))
        self.assertFalse(readiness.live_execution_ready)

    def test_rejected_required_topic_clears_data_fresh(self) -> None:
        self.install_spec()
        tracker = ValidationReadinessTracker(
            ("market.tick",),
            freshness_ns=5_000_000_000,
        )
        gate = ValidatedIngestGate(self.engine, tracker)
        gate.promote(
            self.event("market.tick", self.tick_payload()),
            now_ns=NOW,
        )
        readiness = ReadinessGate(RuntimeMode.LIVE)
        self.assertTrue(tracker.apply(readiness, now_ns=NOW))

        gate.promote(
            self.event(
                "market.tick",
                self.tick_payload(bid=265020, ask=265010),
            ),
            now_ns=NOW + 1,
        )
        self.assertFalse(tracker.apply(readiness, now_ns=NOW + 1))

    def test_readiness_ages_out(self) -> None:
        self.install_spec()
        tracker = ValidationReadinessTracker(
            ("market.tick",),
            freshness_ns=2_000_000_000,
        )
        gate = ValidatedIngestGate(self.engine, tracker)
        gate.promote(
            self.event("market.tick", self.tick_payload()),
            now_ns=NOW,
        )
        readiness = ReadinessGate(RuntimeMode.LIVE)
        self.assertFalse(
            tracker.apply(readiness, now_ns=NOW + 3_000_000_000)
        )


if __name__ == "__main__":
    unittest.main()
