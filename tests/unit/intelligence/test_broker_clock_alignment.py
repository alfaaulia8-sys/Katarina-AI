import unittest
from katarina.intelligence.broker_clock_alignment import infer_clock_shift

class TestClockAlignment(unittest.TestCase):
    def test_three_hour_broker_clock_detected_only_for_research(self):
        now=1_800_000_000.0
        ticks={"EURUSD":int(now+10800-2),"XAUUSD":int(now+10800-1),
               "US30":int(now+10800-3),"BTCUSD":int(now+10800-2)}
        v=infer_clock_shift(ticks,now)
        self.assertEqual(v.observed_hours_shift,3)
        self.assertTrue(v.suitable_for_readonly_snapshot)
        self.assertFalse(v.historical_dst_verified)
        self.assertFalse(v.live_execution_authorized)
    def test_utc_server_clock(self):
        now=1_800_000_000.0
        ticks={x:int(now-1) for x in ("EURUSD","XAUUSD","US30")}
        self.assertEqual(infer_clock_shift(ticks,now).observed_hours_shift,0)
    def test_weekend_stale_ticks_are_not_faked_fresh(self):
        now=1_800_000_000.0
        ticks={x:int(now-3600*48) for x in ("EURUSD","XAUUSD","US30")}
        self.assertFalse(infer_clock_shift(ticks,now).suitable_for_readonly_snapshot)
    def test_disagreeing_quotes_do_not_get_offset(self):
        now=1_800_000_000.0
        ticks={"A":int(now+10800),"B":int(now+10800),
               "C":int(now-7200),"D":int(now-7200)}
        self.assertFalse(infer_clock_shift(ticks,now).suitable_for_readonly_snapshot)
    def test_cannot_accept_only_one_symbol(self):
        now=1_800_000_000.0
        self.assertFalse(infer_clock_shift({"A":int(now+10800)},now).suitable_for_readonly_snapshot)
if __name__=="__main__":unittest.main()