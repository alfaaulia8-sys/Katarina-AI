import unittest
from datetime import datetime,timezone

from katarina.adapters.mt5_ticks import MT5TickSource


class _Row(dict):
    dtype=None


class FakeMT5:
    COPY_TICKS_ALL=0
    def initialize(self,**kwargs):return True
    def last_error(self):return (0,"ok")
    def shutdown(self):pass
    def symbol_select(self,symbol,value):return True
    def copy_ticks_range(self,symbol,start,end,mode):
        return [
            _Row(time_msc=1000,bid=2000.0,ask=2000.2),
            _Row(time_msc=1001,bid=0.0,ask=0.0),
            _Row(time_msc=1002,bid=2000.1,ask=2000.3),
        ]


class MT5TickSourceTests(unittest.TestCase):
    def test_copy_range_converts_and_filters_ticks(self):
        src=MT5TickSource(FakeMT5())
        self.assertTrue(src.initialize("x").initialized)
        ticks=src.copy_range("XAUUSD",datetime(2026,1,1,tzinfo=timezone.utc),datetime(2026,1,2,tzinfo=timezone.utc))
        self.assertEqual(len(ticks),2)
        self.assertEqual(ticks[0].timestamp_ns,1_000_000_000)
        self.assertAlmostEqual(ticks[0].ask,2000.2)


if __name__=="__main__":unittest.main()
