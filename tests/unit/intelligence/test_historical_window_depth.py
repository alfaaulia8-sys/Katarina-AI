"""Bounded earlier-window MT5 historical replay must be timestamp-safe."""
import unittest
from datetime import datetime,timedelta,timezone

from scripts.research.run_native_brain_causal_broker_replay import (
    requested_history_depth,
)
NOW=datetime(2026,10,13,0,tzinfo=timezone.utc)


class TestHistoricalWindowDepth(unittest.TestCase):
    def test_earlier_september_history_requests_all_three_timeframes(self):
        end=datetime(2026,9,25,21,tzinfo=timezone.utc)
        a=requested_history_depth(NOW,end,2000)
        self.assertGreater(a["M5"][0],2000)
        self.assertGreater(a["M15"][0],900)
        self.assertGreater(a["H1"][0],280)
        self.assertEqual(a["M5"][1],300)
        self.assertEqual(a["M15"][1],900)
        self.assertEqual(a["H1"][1],3600)
        current=requested_history_depth(NOW,NOW,2000)
        self.assertGreater(a["M5"][0],current["M5"][0])

    def test_future_naive_ancient_and_unbounded_rejected(self):
        values=(NOW+timedelta(minutes=1),NOW-timedelta(days=81),
                NOW.replace(tzinfo=None))
        for end in values:
            with self.assertRaises(ValueError):
                requested_history_depth(NOW,end,2000)
        with self.assertRaises(ValueError):
            requested_history_depth(NOW,NOW,4000)


if __name__=="__main__":unittest.main()
