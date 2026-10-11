"""The independent M5/M15 research pathway must preserve closed-bar timing."""
import sys
import unittest
from datetime import datetime,timedelta,timezone
from pathlib import Path

SCRIPTS=Path(__file__).resolve().parents[3]/"scripts"/"research"
sys.path.insert(0,str(SCRIPTS))
from historical_m5_m15_shadow import scan_symbol

NOW=datetime(2026,10,8,12,tzinfo=timezone.utc)
UTC=timezone.utc


class FakeMT5:
    TIMEFRAME_M5=5
    TIMEFRAME_M15=15
    COPY_TICKS_ALL=0

    def __init__(self):
        self.count=0
        self.data={}
        for timeframe,seconds,length in ((5,300,250),(15,900,140)):
            end=int(NOW.timestamp())-seconds
            rows=[]
            for i in range(length):
                p=100+i*.2
                o,h,l,c=p-.1,p+.15,p-.15,p+.10
                volume=100
                if timeframe==5 and i==length-1:
                    o,h,l,c=p+.12,p+.9,p+.05,p+.84
                    volume=500
                rows.append(dict(time=end-(length-1-i)*seconds,
                                 open=o,high=h,low=l,close=c,tick_volume=volume))
            self.data[timeframe]=rows

    def symbol_info(self,symbol):
        return type("Info",(),{"trade_mode":4})()

    def symbol_select(self,symbol,enable):
        return True

    def copy_rates_range(self,symbol,tf,start,end):
        return self.data[tf]

    def copy_ticks_range(self,symbol,start,end,flags):
        self.count+=1
        timestamp=start.timestamp()+.3
        return [dict(time_msc=round(timestamp*1000),
                     bid=150.64+(0.2 if self.count%2==0 else 0),
                     ask=150.66+(0.2 if self.count%2==0 else 0))]


class M5ShadowTests(unittest.TestCase):
    def test_closed_m15_context_and_real_quote_timing(self):
        broker=FakeMT5()
        data=scan_symbol(broker,"TEST",NOW-timedelta(hours=1),
                         NOW+timedelta(minutes=1),50)
        self.assertEqual(len(data["signals"]),1)
        s=data["signals"][0]
        self.assertEqual(s["signal_bar_close_utc"],NOW.isoformat())
        self.assertEqual(s["context_bar_close_utc"],NOW.isoformat())
        self.assertEqual(s["family"],"trend_impulse_break_m5_m15_v1")
        self.assertEqual(s["side"],"BUY")
        self.assertLessEqual(s["entry_spread_atr"],.15)
        self.assertTrue(s["cost_screen_pass"])
        self.assertGreater(s["quoted_markout_bps"],0)
        self.assertFalse(s["live_risk_authorized"])
        self.assertFalse(s["is_realized_pnl"])

    def test_missing_exit_cannot_be_assumed_profitable(self):
        class Missing(FakeMT5):
            def copy_ticks_range(self,symbol,start,end,flags):
                if start.timestamp() >= NOW.timestamp()+900:
                    return []
                return super().copy_ticks_range(symbol,start,end,flags)
        data=scan_symbol(Missing(),"TEST",NOW-timedelta(hours=1),
                         NOW+timedelta(minutes=1),50)
        self.assertEqual(data["signals"],[])
        self.assertEqual(data["counts"].get("exit_quote_unavailable"),1)


if __name__=="__main__":
    unittest.main()
