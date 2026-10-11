"""Historical replay tests: causal timestamps, genuine quotes and no order API."""
from datetime import datetime, timezone, timedelta
from pathlib import Path
import runpy
import unittest

ROOT=Path(__file__).resolve().parents[3]
TOOLS=runpy.run_path(str(ROOT/"scripts/research/historical_shadow_ticks.py"))
first_quote=TOOLS["first_quote"]
intact=TOOLS["intact"]
scan_symbol=TOOLS["scan_symbol"]
NOW=datetime(2026,10,8,12,tzinfo=timezone.utc)


class FakeMT5:
    COPY_TICKS_ALL=0
    TIMEFRAME_M1=1
    TIMEFRAME_M5=5

    def __init__(self):
        self.sent_orders=0
        self.rates={}
        for period,tf,n in ((60,1,200),(300,5,140)):
            end=int(NOW.timestamp())-period
            data=[]
            for i in range(n):
                p=100+i*.2
                o,c,h,l=p-.10,p+.10,p+.15,p-.15
                volume=100
                if period==60 and i==n-1:
                    o,c,h,l=p+.12,p+.84,p+.90,p+.05
                    volume=500
                data.append(dict(time=end-(n-1-i)*period,
                     open=o,high=h,low=l,close=c,tick_volume=volume))
            self.rates[tf]=data

    def symbol_info(self,symbol):
        return type("Info",(),{"trade_mode":4})()

    def symbol_select(self,symbol,value):
        return True

    def copy_rates_range(self,symbol,tf,start,end):
        return self.rates[tf]

    def copy_ticks_range(self,symbol,start,end,flags):
        stamp=start.timestamp()
        return [
            dict(time_msc=int((stamp-.01)*1000),bid=130,ask=130.02),
            dict(time_msc=int((stamp+.2)*1000),bid=130.0,ask=130.02),
        ]


class HistoricalTickTests(unittest.TestCase):
    def test_explicit_tick_after_signal_time(self):
        quote,error=first_quote(FakeMT5(),"TEST",NOW.timestamp(),90)
        self.assertIsNone(error)
        self.assertGreaterEqual(quote["time"],NOW.timestamp())
        self.assertLessEqual(quote["time"],NOW.timestamp()+90)

    def test_quote_missing_is_not_interpolated(self):
        class Missing(FakeMT5):
            def copy_ticks_range(self,*args):
                return []
        quote,error=first_quote(Missing(),"TEST",NOW.timestamp(),90)
        self.assertIsNone(quote)
        self.assertEqual(error,"quote_unavailable")

    def test_reject_bar_history_with_future_gaps(self):
        data=[dict(time=i*60) for i in range(120)]
        self.assertTrue(intact(data,60))
        data[60]["time"]+=600
        self.assertFalse(intact(data,60))

    def test_closed_bar_signal_requires_actual_quotes_and_never_orders(self):
        fake=FakeMT5()
        result=scan_symbol(fake,"TEST",NOW-timedelta(hours=1),
                           NOW+timedelta(minutes=1),50)
        self.assertEqual(len(result["signals"]),1)
        item=result["signals"][0]
        self.assertEqual(item["side"],"BUY")
        self.assertEqual(item["signal_bar_close_utc"],NOW.isoformat())
        self.assertTrue(item["cost_screen_pass"])
        self.assertFalse(item["is_realized_pnl"])
        self.assertFalse(item["live_risk_authorized"])
        self.assertEqual(item["historical_macro_context"],"UNAVAILABLE_POINT_IN_TIME")
        self.assertEqual(fake.sent_orders,0)

    def test_missing_ticks_never_become_wins(self):
        class Missing(FakeMT5):
            def copy_ticks_range(self,*args):
                return []
        result=scan_symbol(Missing(),"TEST",NOW-timedelta(hours=1),
                           NOW+timedelta(minutes=1),50)
        self.assertEqual(result["signals"],[])
        self.assertEqual(result["counts"].get("entry_quote_unavailable"),1)


if __name__=="__main__":
    unittest.main()
