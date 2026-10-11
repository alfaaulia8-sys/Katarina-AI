"""Offline synthetic invariants for KATARINA mega multi-market research."""
import sys,unittest
from pathlib import Path
import numpy as np
SRC=Path(__file__).resolve().parents[2]/"scripts"/"research"
sys.path.insert(0,str(SRC))
import mega_multi_asset_v2 as M
import massive_risk_report as A

class MegaTests(unittest.TestCase):
 def bars(self,n=380):
  dt=[("time","<i8"),("open","<f8"),("high","<f8"),("low","<f8"),("close","<f8"),("spread","<i4"),("tick_volume","<i8")]
  b=np.zeros(n,dtype=dt)
  b["time"]=1750000000+np.arange(n)*900
  b["open"]=100;b["close"]=100;b["high"]=100.4;b["low"]=99.6
  b["spread"]=2;b["tick_volume"]=100
  return b
 def test_stops_first_in_same_bar(self):
  b=self.bars(40);b["high"][6]=105;b["low"][6]=95
  for direction in (1,-1):
   rv,exitidx=M.simulate(b,np.array([5]),np.array([direction]),np.ones(40),.01,1.,3.,8)
   self.assertEqual(int(exitidx[0]),6)
   self.assertAlmostEqual(float(rv[0]),-1.05,places=5)
 def test_next_bar_open_and_ask_spread(self):
  b=self.bars(40);b["close"][5]=200.;b["high"][6]=103.
  v,e=M.simulate(b,np.array([5]),np.array([1]),np.ones(40),.01,1.,2.,8)
  self.assertEqual(int(e[0]),6);self.assertAlmostEqual(float(v[0]),1.95)
 def test_features_dont_look_ahead(self):
  b=self.bars()
  before=M.signal_data(b,.01)
  b["close"][350]=350;b["high"][350]=350
  after=M.signal_data(b,.01)
  self.assertAlmostEqual(float(before[0][340]),float(after[0][340]),places=10)
  for key in M.FAMS:
   for direction in (0,1):
    self.assertEqual(bool(before[1][key][direction][340]),bool(after[1][key][direction][340]))
 def test_time_gating_min_sample(self):
  b=self.bars()
  result=M.search_tf(b,.01,"SYNTHETIC","M15")
  self.assertIsNone(result["champ"])
 def test_risk_closed_only_and_no_automatic_live(self):
  ev=[dict(symbol="SYNTHETIC",category="FOREX",entry=1750000000,
    exit=1750001800,side=1,R=-1.05,window="train")]
  r=A.portfolio(ev,risk=.005,slots=1,extra_cost=.15)
  self.assertEqual(r["closed_trades"],1)
  self.assertLess(r["closed_return_pct"],0)
  self.assertNotIn("order_send(",Path(SRC/"mega_multi_asset_v2.py").read_text())

if __name__=="__main__":unittest.main()