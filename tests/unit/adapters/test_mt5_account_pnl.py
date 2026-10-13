"""Read-only MT5 P/L collector: no terminal, credentials, or live orders."""
import unittest
from types import SimpleNamespace as NS

from katarina.adapters.mt5_account_pnl import Mt5ReadOnlyPnLAdapter


BEFORE = 1_700_000_000_000_000_000
AFTER = BEFORE + 10_000_000_000
DEAL_MS = BEFORE // 1_000_000 + 1000


def position(identifier=22, reason=0, magic=0, profit=0.0, swap=0.0):
    return NS(identifier=identifier, reason=reason, magic=magic,
              profit=profit, swap=swap)


def deal(ticket=101, position_id=22, typ=0, reason=0, magic=0,
         profit=0.0, commission=0.0, fee=0.0, swap=0.0, time_msc=DEAL_MS):
    return NS(ticket=ticket, position_id=position_id, type=typ, reason=reason,
              magic=magic, profit=profit, commission=commission, fee=fee,
              swap=swap, time_msc=time_msc)


class FakeMt5:
    POSITION_REASON_CLIENT = 0
    POSITION_REASON_MOBILE = 1
    POSITION_REASON_WEB = 2
    POSITION_REASON_EXPERT = 3
    DEAL_REASON_CLIENT = 0
    DEAL_REASON_MOBILE = 1
    DEAL_REASON_WEB = 2
    DEAL_REASON_EXPERT = 3
    DEAL_TYPE_BUY = 0
    DEAL_TYPE_SELL = 1
    DEAL_TYPE_BALANCE = 2

    def __init__(self):
        self.login = 55
        self.equity = 10000.0
        self.positions = [position()]
        self.deals = []
        self.calls = []

    def account_info(self):
        self.calls.append("account_info")
        return NS(login=self.login, equity=self.equity)

    def positions_get(self):
        self.calls.append("positions_get")
        return self.positions

    def history_deals_get(self, begin, end):
        self.calls.append("history_deals_get")
        return self.deals


class ReadOnlyMt5PnLTests(unittest.TestCase):
    def setUp(self):
        self.broker = FakeMt5()
        self.adapter = Mt5ReadOnlyPnLAdapter(self.broker, katarina_magic=99001)

    def test_manual_floating_loss_reconciles_but_never_authorizes_live(self):
        previous = self.adapter.capture(captured_utc_ns=BEFORE)
        self.broker.equity = 8000
        self.broker.positions = [position(profit=-2000)]
        current = self.adapter.capture(captured_utc_ns=AFTER)
        result = self.adapter.reconcile(previous, current)
        self.assertTrue(result.attribution.balanced)
        self.assertEqual(result.attribution.owner_loss_cash, 2000)
        self.assertFalse(result.broker_history_complete_verified)
        self.assertFalse(result.server_trading_day_authenticated)
        self.assertFalse(result.live_execution_authorized)
        self.assertEqual(self.broker.calls, [
            "account_info", "positions_get", "account_info",
            "positions_get", "history_deals_get", "account_info",
        ])

    def test_closing_existing_manual_loss_does_not_double_count_floating(self):
        self.broker.equity = 9800
        self.broker.positions = [position(profit=-200)]
        previous = self.adapter.capture(captured_utc_ns=BEFORE)
        self.broker.positions = []
        self.broker.deals = [deal(profit=-200)]
        current = self.adapter.capture(captured_utc_ns=AFTER)
        result = self.adapter.reconcile(previous, current)
        self.assertTrue(result.attribution.balanced)
        self.assertEqual(result.attribution.owner_loss_cash, 0)

    def test_realized_new_closed_manual_trade_with_fees(self):
        self.broker.positions = []
        previous = self.adapter.capture(captured_utc_ns=BEFORE)
        self.broker.equity = 8900
        self.broker.deals = [deal(profit=-1000, commission=-80, fee=-20)]
        current = self.adapter.capture(captured_utc_ns=AFTER)
        result = self.adapter.reconcile(previous, current)
        self.assertTrue(result.attribution.balanced)
        self.assertEqual(result.attribution.owner_loss_cash, 1100)

    def test_deposit_is_external_flow_not_owner_pnl(self):
        previous = self.adapter.capture(captured_utc_ns=BEFORE)
        self.broker.equity = 11000
        self.broker.deals = [deal(typ=self.broker.DEAL_TYPE_BALANCE, profit=1000)]
        current = self.adapter.capture(captured_utc_ns=AFTER)
        result = self.adapter.reconcile(previous, current)
        self.assertEqual(result.external_cash_flow, 1000)
        self.assertTrue(result.attribution.balanced)
        self.assertEqual(result.attribution.owner_loss_cash, 0)

    def test_unknown_or_foreign_broker_source_blocks_owner_attribution(self):
        previous = self.adapter.capture(captured_utc_ns=BEFORE)
        self.broker.positions = [position(reason=3, magic=77, profit=-400)]
        self.broker.equity = 9600
        current = self.adapter.capture(captured_utc_ns=AFTER)
        with self.assertRaisesRegex(ValueError, "position_origin_changed"):
            self.adapter.reconcile(previous, current)

    def test_katarina_magic_not_confused_with_owner_loss(self):
        self.broker.positions = [position(reason=3, magic=99001)]
        before = self.adapter.capture(captured_utc_ns=BEFORE)
        self.broker.positions = [position(reason=3, magic=99001, profit=-800)]
        self.broker.equity = 9200
        after = self.adapter.capture(captured_utc_ns=AFTER)
        result = self.adapter.reconcile(before, after)
        self.assertTrue(result.attribution.balanced)
        self.assertEqual(result.attribution.owner_loss_cash, 0)
        self.assertEqual(result.attribution.katarina_loss_cash, 800)

    def test_missing_fee_and_history_fail_closed(self):
        prior = self.adapter.capture(captured_utc_ns=BEFORE)
        self.broker.equity = 9000
        self.broker.deals = [deal(profit=-1000, fee=None)]
        after = self.adapter.capture(captured_utc_ns=AFTER)
        with self.assertRaisesRegex(ValueError, "invalid_deal_fee"):
            self.adapter.reconcile(prior, after)
        self.broker.deals = None
        with self.assertRaisesRegex(RuntimeError, "history_unavailable"):
            self.adapter.reconcile(prior, after)

    def test_unsupported_ledger_operation_refused(self):
        prior = self.adapter.capture(captured_utc_ns=BEFORE)
        self.broker.deals = [deal(typ=9, profit=-100)]
        after = self.adapter.capture(captured_utc_ns=AFTER)
        with self.assertRaisesRegex(ValueError, "unsupported_mt5_ledger"):
            self.adapter.reconcile(prior, after)

    def test_duplicate_deal_and_account_switch_rejected(self):
        prior = self.adapter.capture(captured_utc_ns=BEFORE)
        self.broker.equity = 9000
        self.broker.deals = [deal(), deal()]
        after = self.adapter.capture(captured_utc_ns=AFTER)
        with self.assertRaisesRegex(ValueError, "duplicate_mt5"):
            self.adapter.reconcile(prior, after)
        self.broker.login = 66
        after = self.adapter.capture(captured_utc_ns=AFTER)
        with self.assertRaisesRegex(ValueError, "account_or_capture"):
            self.adapter.reconcile(prior, after)

    def test_account_switch_during_history_read_refuses_attribution(self):
        prior = self.adapter.capture(captured_utc_ns=BEFORE)
        after = self.adapter.capture(captured_utc_ns=AFTER)
        original = self.broker.history_deals_get
        def switch_account(begin, end):
            items = original(begin, end)
            self.broker.login = 99
            return items
        self.broker.history_deals_get = switch_account
        with self.assertRaisesRegex(RuntimeError, "account_changed"):
            self.adapter.reconcile(prior, after)

    def test_absent_positions_or_invalid_ticks_rejected(self):
        self.broker.positions = None
        with self.assertRaisesRegex(RuntimeError, "snapshot_unavailable"):
            self.adapter.capture(captured_utc_ns=BEFORE)
        self.broker.positions = [position(profit=float("nan"))]
        with self.assertRaisesRegex(ValueError, "invalid_floating_profit"):
            self.adapter.capture(captured_utc_ns=BEFORE)


if __name__ == "__main__":
    unittest.main()
