"""Read-only adaptive risk tier audit: USD vs cent normalization and stops.

No order placement, no live model promotion, no governor hard-cap increase.
"""
from __future__ import annotations
import json,sys,hashlib
from pathlib import Path

ROOT=Path(r"C:\KatarinaDev\github-main")
sys.path.insert(0,str(ROOT/"src"))
from katarina.engines.risk import RiskGovernor,RiskRequest,RiskAction
from katarina.engines.sizing import PositionSizingEngine

risk_path=ROOT/"config"/"risk_governor_v2.json"
gov=RiskGovernor.from_config(risk_path)
assert gov.adaptive_profile is not None
balance_samples=(100,250,500,1000,2500,10000,50000,100000,250000)
data=[]
for v in balance_samples:
    usd=gov.adaptive_profile.quote(active_capital_native=float(v),account_currency="USD")
    usc=gov.adaptive_profile.quote(active_capital_native=float(v*100),account_currency="USC")
    assert abs(usc.fraction-usd.fraction)<1e-12
    assert abs(usc.risk_cash_native-usd.risk_cash_native*100)<1e-7
    req=RiskRequest(None,0,0,.1,2,True,True,0,
       risk_capital=float(v),risk_reference_capital=float(v),account_currency="USD")
    dec=gov.evaluate(req)
    assert dec.action is RiskAction.APPROVE
    assert abs(dec.approved_fraction-usd.fraction)<1e-12
    data.append({"balance_usd":v,"risk_pct":round(100*dec.approved_fraction,4),
       "budget_usd":round(usd.risk_cash_native,4),"budget_usc":round(usc.risk_cash_native,4)})
small=PositionSizingEngine().size_active(
    active_balance=100,current_equity=100,risk_fraction=.02,
    stop_distance=10,value_per_price_unit_per_lot=100,
    volume_min=.01,volume_max=50,volume_step=.01)
cent_proxy=PositionSizingEngine().size_active(
    active_balance=10000,current_equity=10000,risk_fraction=.02,
    stop_distance=10,value_per_price_unit_per_lot=100,
    volume_min=.01,volume_max=50,volume_step=.01)
assert small.valid is False
assert cent_proxy.valid is True
report={"kind":"KATARINA_ADAPTIVE_RISK_TIER_AUDIT",
  "config_hash":hashlib.sha256(risk_path.read_bytes()).hexdigest(),
  "risk_schedule":data,
  "standard_usd100_minlot_0p01_xau_10usd_stop":{"can_trade":small.valid,"reason":small.reason},
  "illustrative_USC10000_contract_one_oz_per_lot_xau_10usd_stop":{
    "can_trade":cent_proxy.valid,"suggested_volume_without_cost_buffer":cent_proxy.volume,
    "note":"NOT a verified cent broker specification, tick/fee/spread costs not included"},
  "fixed_safety_limits":{"max_per_order":gov.hard_per_trade,"max_open_risk":gov.max_open_risk,
       "daily_dd":gov.max_daily_drawdown,"total_dd":gov.max_drawdown},
  "model_opt_in_only":True,"live_execution_authorized":False,
  "no_broker_order_sent":True,"tests_passed":True}
out=Path(r"C:\KatarinaDev\artifacts\historical-brain")/"adaptive_risk_profile_audit_20261011.json"
out.write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
print(json.dumps(report,indent=2))
