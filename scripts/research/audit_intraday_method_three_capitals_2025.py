"""Consistency audit for method matrix / true tick / three-capital model."""
import json,hashlib
from pathlib import Path
A=Path(r"C:\KatarinaDev\artifacts\historical-brain")
names=("katarina_intraday_tool_matrix_2025_2026.json",
  "katarina_xau_method_tick_ablation_2025_2026.json",
  "katarina_intraday_three_capitals_adaptive_2025_2026.json",
  "katarina_cent_extra_execution_cost_sensitivity_2025_2026.json")
files=[A/x for x in names]
matrix,ticks,capital,cost=[json.loads(x.read_text(encoding="utf-8")) for x in files]
assert len(matrix["symbols"])==7
assert all("error" not in z for z in matrix["symbols"])
assert sum(x["configurations_evaluated"] for x in matrix["symbols"])==2800
assert len(ticks["individual_event_outcomes"])==516
sel=[x for x in ticks["summary"] if x["filter"]=="ADX20" and x["rr"]==2 and x["cost"]=="BASE"]
assert len(sel)==1
r=sel[0]
assert (r["2025"]["n"],r["2026"]["n"])==(49,50)
assert r["2025"]["avg_R"]>0 and r["2026"]["avg_R"]>0
assert len(capital["model_results"])==12
for s in capital["model_results"]:
 assert s["executed"]+s["skipped_minimum_volume"]+s["blocked_by_governor"]==99
 amount=sum(row["net_usd"] for row in s["monthly"].values())
 assert abs(amount-s["net_usd"])<=.01,(s["scenario_id"],amount,s["net_usd"])
 assert s["peak_to_valley_realized_balance_dd_pct"]<=20
 assert s["compounding_milestones"]==0
 assert s["reserve_usd"]==0
assert all(x["pct"]<=10000 for x in cost["results"])
report={"kind":"KATARINA_INTRADAY_METHOD_RISK_AUDIT_2025_2026",
 "audited_files":{name:hashlib.sha256(path.read_bytes()).hexdigest() for name,path in zip(names,files)},
 "configuration_count":2800,"broker_tick_event_scenarios":516,
 "symbol_count":7,"risk_scenarios":12,
 "year_splits":("2025","2026_partial_through_2026_10_09"),
 "selected_candidate":"XAUUSD UTC06 H1_H4 OR breakout ADX20, SL0.55 H1 ATR RR2 6h",
 "true_tick_samples":{"2025":49,"2026_partial":50},
 "cent_broker_specs_verified":False,
 "actual_fee_and_fills_verified":False,
 "fresh_unseen_out_of_sample":False,
 "scalping_return_assumed":0,
 "other_pair_profit_assumed":0,
 "real_money_execution_approved":False,
 "checks_passed":True}
out=A/"katarina_intraday_method_risk_audit_20261011.json"
out.write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
print(json.dumps(report,indent=2))
