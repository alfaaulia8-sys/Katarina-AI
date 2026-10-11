"""Research only: extra R cost on cent broker price-path proxy."""
import json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/"scripts"/"research"))
from simulate_three_capitals_adaptive_2025 import simulate,SOURCE,AUDIT
base=[x for x in SOURCE["individual_event_outcomes"] if x["rr"]==2
      and x["cost"]=="BASE" and "ADX20" in x["filters"]]
res=[]
for additional in (0.,.05,.1,.2,.3,.4):
 adjusted=[{**x,"R":x["R"]-additional} for x in base]
 for starting in (100.,1000.,10000.):
  r=simulate(adjusted,starting,"USC",1.,.01,.01,50.,"BASE",1,.03+additional)
  res.append({"extra_R_per_trade":additional,"initial_usd":starting,
      "profit_usd":r["net_usd"],"pct":r["pct"],"executed":r["executed"],
      "skipped":r["skipped_minimum_volume"],
      "dd_pct":r["peak_to_valley_realized_balance_dd_pct"]})
  print("CENT_COST",additional,starting,r["net_usd"],r["pct"],flush=True)
out=AUDIT/"katarina_cent_extra_execution_cost_sensitivity_2025_2026.json"
out.write_text(json.dumps({"experimental_only":True,
 "cost":"additional fixed R debit per XAU ADX20 trade",
 "pricing_source":"Valetax standard Bid Ask, cent contract hypothetical",
 "no_real_cent_broker_historical_quotes":True,"results":res},indent=2)+"\n",encoding="utf-8")
print("FILE",str(out),flush=True)
