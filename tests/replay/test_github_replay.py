"""Regression checks for the deterministic GitHub replay laboratory."""
import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
SPEC=importlib.util.spec_from_file_location("gh_replay",ROOT/"scripts"/"research"/"github_replay.py")
R=importlib.util.module_from_spec(SPEC);sys.modules[SPEC.name]=R;SPEC.loader.exec_module(R)

class TestReplay(unittest.TestCase):
    def bars(self,n=50):
        return [dict(symbol="TEST",time=1750000000+i*900,open=100.,high=100.5,low=99.5,close=100.,spread=2.,point=.01) for i in range(n)]
    def test_buy_stop_before_target_on_same_bar(self):
        b=self.bars();b[2].update(high=105.,low=95.)
        r,j,why=R.simulate_trade(b,1,1,1.,.8,2.,8)
        self.assertEqual((j,why),(2,"STOP"));self.assertLess(r,-1.0)
    def test_sell_stop_before_target_on_same_bar(self):
        b=self.bars();b[2].update(high=105.,low=95.)
        r,j,why=R.simulate_trade(b,1,-1,1.,.8,2.,8)
        self.assertEqual((j,why),(2,"STOP"));self.assertLess(r,-1.0)
    def test_entry_uses_next_open_with_spread(self):
        b=self.bars();b[1]["close"]=200;b[2].update(open=100.,high=101.8,low=100.)
        r,j,why=R.simulate_trade(b,1,1,1.,.8,2.,8)
        self.assertEqual(why,"TARGET");self.assertAlmostEqual(r,1.95)
    def test_features_do_not_use_future_bars(self):
        b=self.bars(150);before=R.features(b)
        b[100].update(close=300.,high=300.)
        after=R.features(b)
        for key in ("atr","e20","e50","adx","rsi"):
            self.assertAlmostEqual(before[key][99],after[key][99],places=10)
    def test_csv_is_deterministic(self):
        with tempfile.TemporaryDirectory() as t:
            a=Path(t)/"a.csv";b=Path(t)/"b.csv"
            R.generate_fixture(a,120);R.generate_fixture(b,120)
            self.assertEqual(a.read_bytes(),b.read_bytes())
            self.assertEqual(len(R.read_csv(a)),4)
    def test_output_remains_research_only(self):
        data=R.read_csv(ROOT/"tests"/"fixtures"/"ohlc"/"synthetic_regimes.csv")
        report=R.evaluation(data,min_trades=2)
        self.assertEqual(report["dataset_type"],"synthetic")
        self.assertFalse(report["live_execution_authorized"])
        self.assertTrue(report["research_only"])
        self.assertGreater(report["configurations_evaluated"],100)
if __name__=="__main__":unittest.main()