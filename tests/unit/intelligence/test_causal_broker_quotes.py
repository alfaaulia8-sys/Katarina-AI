"""Quote-clock regression: broker server latest tick != causal UTC quote.

No MT5 connection: fake broker exposes actual copy_ticks_range UTC schema.
"""
import unittest
from datetime import datetime,timezone,timedelta

from katarina.intelligence.causal_broker_quotes import (
    last_past_quote,due_window_quote,MAX_TICKS_PER_QUERY,
)

NOW=datetime(2026,10,12,16,30,12,tzinfo=timezone.utc)


def row(time,bid=4200.,ask=4200.3):
    return {"time_msc":int(time*1000),"bid":bid,"ask":ask}


class FakeMT5:
    COPY_TICKS_INFO=1
    def __init__(self,rows):
        self.rows=rows
        self.requests=[]

    def copy_ticks_range(self,symbol,start,end,mode):
        self.requests.append((symbol,start,end,mode))
        return list(self.rows)


class CausalBrokerQuotesTests(unittest.TestCase):
    def test_last_tick_ignores_15second_future_server_lead(self):
        t=NOW.timestamp()
        broker=FakeMT5([row(t-2),row(t+14),row(t-3)])
        last=last_past_quote(broker,"XAUUSD.vx",NOW)
        self.assertEqual(last[2],t-2)
        self.assertLessEqual(last[2],t)
        self.assertEqual(broker.requests[0][1].tzinfo,timezone.utc)

    def test_refuse_only_future_or_stale_quotes(self):
        t=NOW.timestamp()
        self.assertIsNone(last_past_quote(FakeMT5([row(t+9)]),"XAUUSD.vx",NOW))
        self.assertIsNone(last_past_quote(FakeMT5([row(t-170)]),"XAUUSD.vx",NOW))

    def test_due_tick_replayed_after_scheduled_cycle(self):
        due=NOW.timestamp()-200
        tick=due+1.5
        f=FakeMT5([row(due-1),row(due+140),row(tick)])
        found=due_window_quote(f,"AUDJPY.vx",due,NOW.timestamp())
        self.assertAlmostEqual(found[2],tick,places=2)
        self.assertEqual(f.requests[0][1].timestamp(),due)
        self.assertEqual(f.requests[0][2].timestamp(),due+120)

    def test_no_future_or_out_of_window_marks(self):
        due=NOW.timestamp()-10
        f=FakeMT5([row(due+11),row(due+121)])
        self.assertIsNone(due_window_quote(f,"XAUUSD.vx",due,NOW.timestamp()))
        self.assertIsNone(due_window_quote(f,"XAUUSD.vx",NOW.timestamp()+1,NOW.timestamp()))

    def test_naive_clock_and_oversized_query_blocked(self):
        with self.assertRaises(ValueError):
            last_past_quote(FakeMT5([]),"XAUUSD.vx",NOW.replace(tzinfo=None))
        self.assertIsNone(last_past_quote(
            FakeMT5([row(NOW.timestamp())]*(MAX_TICKS_PER_QUERY+1)),
            "XAUUSD.vx",NOW))

    def test_bad_bid_ask_does_not_become_evidence(self):
        t=NOW.timestamp()
        f=FakeMT5([row(t-1,4201.,4200.)])
        self.assertIsNone(last_past_quote(f,"XAUUSD.vx",NOW))


if __name__=="__main__":
    unittest.main()
