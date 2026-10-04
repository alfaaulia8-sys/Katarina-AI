from __future__ import annotations

import random
import unittest

from katarina.contracts.runtime import EventEnvelope
from katarina.validation.engine import DataValidationEngine, ValidationDisposition


NOW = 2_000_000_000_000_000_000


class Stage08PropertyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.rng = random.Random(808)
        self.engine = DataValidationEngine()
        spec = {
            "instrument_id": 1,
            "spec_revision": 9,
            "digits": 2,
            "price_scale": 2,
            "volume_scale": 2,
            "point_units": 1,
            "tick_size_units": 5,
            "volume_min_units": 1,
            "volume_max_units": 10000,
            "volume_step_units": 1,
            "canonical_symbol": "XAUUSD",
            "broker_symbol": "XAUUSD.vx",
        }
        result = self.engine.validate(
            EventEnvelope(
                topic="symbol.spec",
                payload=spec,
                source="mt5",
                source_time_ns=NOW,
            ),
            now_ns=NOW,
        )
        self.assertTrue(result.accepted)

    def event(self, topic: str, payload):
        return EventEnvelope(
            topic=topic,
            payload=payload,
            source="mt5",
            source_time_ns=NOW,
        )

    def test_random_aligned_ticks_accept(self) -> None:
        for _ in range(1000):
            bid = self.rng.randint(10000, 1000000) * 5
            spread = self.rng.randint(0, 100) * 5
            payload = {
                "instrument_id": 1,
                "spec_revision": 9,
                "bid_units": bid,
                "ask_units": bid + spread,
            }
            result = self.engine.validate(self.event("market.tick", payload), now_ns=NOW)
            self.assertEqual(result.disposition, ValidationDisposition.ACCEPT)

    def test_random_crossed_ticks_reject(self) -> None:
        for _ in range(500):
            ask = self.rng.randint(10000, 1000000) * 5
            bid = ask + self.rng.randint(1, 100) * 5
            payload = {
                "instrument_id": 1,
                "spec_revision": 9,
                "bid_units": bid,
                "ask_units": ask,
            }
            result = self.engine.validate(self.event("market.tick", payload), now_ns=NOW)
            self.assertEqual(result.disposition, ValidationDisposition.REJECT)

    def test_random_off_grid_prices_reject(self) -> None:
        for _ in range(500):
            base = self.rng.randint(10000, 1000000) * 5
            payload = {
                "instrument_id": 1,
                "spec_revision": 9,
                "bid_units": base + 1,
                "ask_units": base + 6,
            }
            result = self.engine.validate(self.event("market.tick", payload), now_ns=NOW)
            self.assertEqual(result.disposition, ValidationDisposition.REJECT)

    def test_random_valid_ohlc_accept(self) -> None:
        for seq in range(1, 501):
            low = self.rng.randint(10000, 1000000) * 5
            high = low + self.rng.randint(0, 500) * 5
            open_units = self.rng.randrange(low, high + 5, 5)
            close_units = self.rng.randrange(low, high + 5, 5)
            payload = {
                "instrument_id": 1,
                "spec_revision": 9,
                "timeframe_minutes": 15,
                "bar_sequence": seq,
                "bar_open_time_ns": seq * 900_000_000_000,
                "open_units": open_units,
                "high_units": high,
                "low_units": low,
                "close_units": close_units,
            }
            result = self.engine.validate(self.event("market.bar", payload), now_ns=NOW)
            self.assertEqual(result.disposition, ValidationDisposition.ACCEPT)


if __name__ == "__main__":
    unittest.main()
