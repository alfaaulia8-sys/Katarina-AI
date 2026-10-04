from __future__ import annotations

import unittest

from katarina.contracts.runtime import EventEnvelope
from katarina.validation.engine import DataValidationEngine, ValidationDisposition


NOW = 2_000_000_000_000_000_000
ACCOUNT_ID = bytes.fromhex("00112233445566778899aabbccddeeff")


class Stage08StateSemanticTests(unittest.TestCase):
    def setUp(self) -> None:
        self.engine = DataValidationEngine()
        self.engine.validate(
            self.event(
                "symbol.spec",
                {
                    "instrument_id": 1,
                    "spec_revision": 5,
                    "digits": 2,
                    "price_scale": 2,
                    "volume_scale": 2,
                    "point_units": 1,
                    "tick_size_units": 10,
                    "volume_min_units": 1,
                    "volume_max_units": 1000,
                    "volume_step_units": 1,
                    "canonical_symbol": "XAUUSD",
                    "broker_symbol": "XAUUSD.vx",
                },
            ),
            now_ns=NOW,
        )

    def event(self, topic: str, payload):
        return EventEnvelope(
            topic=topic,
            payload=payload,
            source="mt5",
            source_time_ns=NOW,
        )

    def account(self):
        return {
            "account_id": ACCOUNT_ID,
            "account_revision": 10,
            "balance_units": 100000,
            "equity_units": 101000,
            "credit_units": 0,
            "profit_units": 1000,
            "margin_units": 10000,
            "free_margin_units": 91000,
            "leverage": 500,
            "account_mode": 1,
            "trade_mode": 3,
            "account_currency_digits": 2,
            "account_unit_profile_revision": 1,
        }

    def position(self):
        return {
            "account_id": ACCOUNT_ID,
            "position_ticket": 1001,
            "position_identifier": 9001,
            "instrument_id": 1,
            "spec_revision": 5,
            "position_revision": 3,
            "open_time_ns": NOW - 1000,
            "update_time_ns": NOW,
            "volume_units": 10,
            "open_price_units": 265000,
            "current_price_units": 265100,
            "sl_units": 264000,
            "tp_units": 267000,
            "change_kind": 1,
            "side": 1,
            "origin_class": 1,
        }

    def order(self):
        return {
            "account_id": ACCOUNT_ID,
            "broker_order_ticket": 2001,
            "instrument_id": 1,
            "spec_revision": 5,
            "order_revision": 4,
            "create_time_ns": NOW - 1000,
            "update_time_ns": NOW,
            "volume_initial_units": 10,
            "volume_current_units": 10,
            "price_open_units": 265000,
            "stop_limit_units": 0,
            "sl_units": 264000,
            "tp_units": 267000,
            "change_kind": 1,
            "side": 1,
            "entry_type": 2,
            "origin_class": 1,
            "normalized_order_state": 2,
            "time_in_force": 0,
            "filling_policy": 0,
        }

    def test_valid_account_accepts(self):
        result = self.engine.validate(self.event("account.state", self.account()), now_ns=NOW)
        self.assertEqual(result.disposition, ValidationDisposition.ACCEPT)

    def test_unknown_account_enum_rejects(self):
        payload = self.account()
        payload["account_mode"] = 0
        result = self.engine.validate(self.event("account.state", payload), now_ns=NOW)
        self.assertEqual(result.disposition, ValidationDisposition.REJECT)
        self.assertIn("UNKNOWN_ENUM_VALUE", {i.code for i in result.issues})

    def test_valid_position_accepts(self):
        result = self.engine.validate(self.event("position.state", self.position()), now_ns=NOW)
        self.assertEqual(result.disposition, ValidationDisposition.ACCEPT)

    def test_position_volume_out_of_range_rejects(self):
        payload = self.position()
        payload["volume_units"] = 2000
        result = self.engine.validate(self.event("position.state", payload), now_ns=NOW)
        self.assertEqual(result.disposition, ValidationDisposition.REJECT)
        self.assertIn("VOLUME_OUT_OF_RANGE", {i.code for i in result.issues})

    def test_position_stale_spec_rejects(self):
        payload = self.position()
        payload["spec_revision"] = 4
        result = self.engine.validate(self.event("position.state", payload), now_ns=NOW)
        self.assertEqual(result.disposition, ValidationDisposition.REJECT)
        self.assertIn("STALE_SYMBOL_SPEC", {i.code for i in result.issues})

    def test_valid_order_accepts(self):
        result = self.engine.validate(self.event("order.state", self.order()), now_ns=NOW)
        self.assertEqual(result.disposition, ValidationDisposition.ACCEPT)

    def test_stop_limit_reserved_rejects(self):
        payload = self.order()
        payload["entry_type"] = 4
        result = self.engine.validate(self.event("order.state", payload), now_ns=NOW)
        self.assertEqual(result.disposition, ValidationDisposition.REJECT)
        self.assertIn("UNKNOWN_ENUM_VALUE", {i.code for i in result.issues})

    def test_order_current_volume_cannot_exceed_initial(self):
        payload = self.order()
        payload["volume_current_units"] = 11
        result = self.engine.validate(self.event("order.state", payload), now_ns=NOW)
        self.assertEqual(result.disposition, ValidationDisposition.REJECT)
        self.assertIn("INVALID_ORDER_VOLUME", {i.code for i in result.issues})


if __name__ == "__main__":
    unittest.main()
