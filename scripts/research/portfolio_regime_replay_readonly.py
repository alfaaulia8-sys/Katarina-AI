"""Research-only multi-asset portfolio replay. NO broker connection, NO orders.
Uses already inspected tick-replay observations; all results post-hoc diagnostics.
"""
from __future__ import annotations
import csv, json, itertools, math, pathlib, heapq, datetime, hashlib, os
from collections import defaultdict
P = pathlib.Path(os.environ.get("KATARINA_RESEARCH_INPUT_DIR", "./private-research")).resolve()
OUT = pathlib.Path(os.environ.get("KATARINA_RESEARCH_OUTPUT_DIR", "./artifacts/research/portfolio-regime")).resolve()
OUT.mkdir(parents=True, exist_ok=True)
SRC = P / "katarina_shortlist_true_tick_20261011.json"
RAW = SRC.read_bytes()
obj = json.loads(RAW)
rules = {v["rule"]: v for v in obj["results"]}
xau = [r for r in rules if r.startswith("XAUUSD.")]
jpn = [r for r in rules if r.startswith("JPN225.")]
costs = ["BASE", "STRESS", "EXTRA_10PCT_R"]
def tsdt(sec):
    return datetime.datetime.fromtimestamp(float(sec), tz=datetime.timezone.utc)
def trades(name, cost):
    evs = [e for e in rules[name]["events"] if e["cost"] == cost]
    # Dataset may contain entries for multiple replay cost conditions; use one cost per candidate.
    res = []
    for e in evs:
        ex = int(e["exit_timestamp_ms"]) / 1000
        if ex < float(e["time"]) or not math.isfinite(float(e["R"])):
            raise ValueError("bad event chronology or risk outcome")
        res.append(dict(symbol=e["symbol"], rule=name, side=e["side"],
                        entry=float(e["time"]), exit=ex, R=float(e["R"]), cost=cost))
    return sorted(res,key=lambda e:(e["entry"],e["symbol"],e["rule"]))
def simulate(gold, index, cost="BASE", risk=0.005, slots=1,
             day_stop=0.015, max_dd=0.10, streak_limit=3, capital=10000):
    cand = []
    if gold: cand += trades(gold,cost)
    if index: cand += trades(index,cost)
    cand.sort(key=lambda e:(e["entry"],e["symbol"],e["rule"]))
    bal = float(capital)
    peak = bal
    dd_max=0.0
    active=[]
    closed=[]
    accepted=[]
    skip=defaultdict(int)
    day=None
    day_open_balance=bal
    loss_streak=0
    stopped_day=False
    stopped_global=False
    count_in_day=0
    def close_until(t):
        nonlocal bal,peak,dd_max,loss_streak,stopped_global,stopped_day
        while active and active[0][0]<=t:
            _,idx,ticket=heapq.heappop(active)
            # stake is frozen at time of opening
            pnl=ticket["stake"]*ticket["R"]
            bal += pnl
            peak=max(peak,bal)
            dd_max=max(dd_max,1-bal/peak)
            ticket["pnl"]=pnl
            ticket["balance_after"]=bal
            closed.append(ticket)
            if ticket["R"]<0: loss_streak+=1
            else: loss_streak=0
            if dd_max >= max_dd: stopped_global=True
            if bal <= day_open_balance * (1-day_stop) or loss_streak>=streak_limit:
                stopped_day=True
    for e in cand:
        close_until(e["entry"])
        key=tsdt(e["entry"]).date()
        if day!=key:
            day=key
            day_open_balance=bal
            loss_streak=0
            stopped_day=False
            count_in_day=0
        if stopped_global: skip["total_dd_guard"]+=1;continue
        if stopped_day:skip["daily_or_streak_guard"]+=1;continue
        if len(active)>=slots:skip["simultaneous_cap"]+=1;continue
        if any(x[2]["symbol"]==e["symbol"] for x in active):
            skip["symbol_lock"]+=1;continue
        # max aggregate planned risk of 1%; with 2 positions each at <=0.5% typically
        aggregate = sum(x[2]["stake"] for x in active)
        stake=bal*risk
        if stake<=0 or stake+aggregate>0.01*bal+0.000001:
            skip["risk_budget"]+=1;continue
        t=dict(e,stake=stake)
        accepted.append(t)
        heapq.heappush(active,(e["exit"],len(accepted),t))
        count_in_day+=1
    close_until(float("inf"))
    realized=sum(x["pnl"] for x in closed)
    if abs((capital+realized)-bal)>0.01:
        raise AssertionError("ledger reconciliation failed")
    pos=sum(t["pnl"] for t in closed if t["pnl"]>0)
    neg=-sum(t["pnl"] for t in closed if t["pnl"]<0)
    return dict(gold=gold,index=index,cost=cost,risk=risk,slots=slots,
        day_stop=day_stop,max_dd_guard=max_dd,streak_limit=streak_limit,
        capital=capital,final=round(bal,2),pnl=round(realized,2),
        return_pct=round(100*realized/capital,3),max_closed_dd_pct=round(dd_max*100,3),
        trades=len(closed),wins=sum(x["R"]>0 for x in closed),
        pf=round(pos/neg,4) if neg>0 else None,
        halted_total_dd=stopped_global, skipped=dict(skip), ledger=closed)
def metrics(tape):
    if not tape:return {"n":0}
    xs=[v["R"] for v in tape]
    pos=sum(v for v in xs if v>0)
    neg=-sum(v for v in xs if v<0)
    return {"n":len(xs),"R_total":round(sum(xs),3),"R_mean":round(sum(xs)/len(xs),4),
            "PF":round(pos/neg,3) if neg else None,
            "win_pct":round(100*sum(v>0 for v in xs)/len(xs),2)}
def overview():
    rows=[]
    for name in rules:
        row={"rule":name}
        for c in costs:
            vals=trades(name,c)
            row[c]=metrics(vals)
            row[c+"_2025"]=metrics([v for v in vals if tsdt(v["entry"]).year==2025])
            row[c+"_2026"]=metrics([v for v in vals if tsdt(v["entry"]).year==2026])
            row[c+"_months"]=len(set(tsdt(v["entry"]).strftime("%Y-%m") for v in vals))
        rows.append(row)
    return rows
# Predeclare modest risk/cap sweep. Historical 2025 scores only; no 2026 selection.
grid=[]
for g,j,risk,slots,day_stop,max_dd in itertools.product(
        xau,[None]+jpn,[0.0025,0.005,0.0075],[1,2],[0.01,0.015],[0.06,0.10]):
    if slots==2 and risk>0.005:continue
    # true-tick replay portfolio; equity DD only close-based
    train=simulate(g,j,"STRESS",risk,slots,day_stop,max_dd)
    test=simulate(g,j,"EXTRA_10PCT_R",risk,slots,day_stop,max_dd)
    # 2025 training of 2025 data only; take 2025 realized P&L and DD based a re-run
    t2025=simulate(g,j,"STRESS",risk,slots,day_stop,max_dd)
    grid.append((g,j,risk,slots,day_stop,max_dd,train,test))
# Robust selection: separate 2025 vs 2026 outcomes without inadvertently allowing 2026 into selection.
def annual_simulate(g,j,cost,risk,slots,day_stop,max_dd,year):
    # temporarily reuse event lists via local monkey-patch constrained to year; read-only.
    original=globals()["trades"]
    def dated(name,c):
        return [v for v in original(name,c) if tsdt(v["entry"]).year==year]
    globals()["trades"]=dated
    try:return simulate(g,j,cost,risk,slots,day_stop,max_dd)
    finally:globals()["trades"]=original
scored=[]
for g,j,risk,slots,day_stop,max_dd,_,__ in grid:
    tr=annual_simulate(g,j,"STRESS",risk,slots,day_stop,max_dd,2025)
    val=annual_simulate(g,j,"EXTRA_10PCT_R",risk,slots,day_stop,max_dd,2026)
    # Retain 2025 trade count minimum and positive stress profit; select by return-to-DD,
    # penalize strategies halted at loss limit. 2026 may NOT enter optimization score.
    eligible=tr["trades"]>=35 and tr["pnl"]>0 and not tr["halted_total_dd"]
    score=(tr["return_pct"]/max(2.0,tr["max_closed_dd_pct"])) if eligible else -999
    scored.append({"gold":g,"index":j,"risk_pct":risk*100,"slots":slots,
                   "daily_stop_pct":day_stop*100,"total_stop_pct":max_dd*100,
                   "training_2025":{k:v for k,v in tr.items() if k!="ledger"},
                   "diagnostic_2026_10pct_extra_cost":{k:v for k,v in val.items() if k!="ledger"},
                   "training_score":round(score,4),"eligible_training":eligible})
scored.sort(key=lambda x:(x["training_score"],x["training_2025"]["trades"]),reverse=True)
if not scored or scored[0]["training_score"]<0:raise RuntimeError("No eligible training portfolios")
best=scored[0]
g,j=best["gold"],best["index"]
p=dict(risk=best["risk_pct"]/100,slots=best["slots"],
       day_stop=best["daily_stop_pct"]/100,max_dd=best["total_stop_pct"]/100)
# Replay the FULL previously inspected sample for user-requested monthly combined ledger.
base=simulate(g,j,"BASE",**p)
stress=simulate(g,j,"STRESS",**p)
extra=simulate(g,j,"EXTRA_10PCT_R",**p)
months=sorted(set(tsdt(v["entry"]).strftime("%Y-%m") for v in trades(g,"BASE")+
              (trades(j,"BASE") if j else [])))
def monthly(replay):
    agg=defaultdict(lambda:defaultdict(float))
    for t in replay["ledger"]:
        entry_mon=tsdt(t["entry"]).strftime("%Y-%m")
        exit_mon=tsdt(t["exit"]).strftime("%Y-%m")
        agg[entry_mon]["entries"]+=1
        agg[entry_mon][t["symbol"]+"_entries"]+=1
        agg[exit_mon]["closed"]+=1
        agg[exit_mon]["pnl"]+=t["pnl"]
        agg[exit_mon]["R"]+=t["R"]
        agg[exit_mon]["wins"]+=t["R"]>0
        agg[exit_mon]["losses"]+=t["R"]<=0
    return agg
bm,sm,em=map(monthly,[base,stress,extra])
monthly_rows=[]
for m in months:
    row={"month":m,"base_entries":int(bm[m]["entries"])}
    row["gold_entries"]=int(bm[m].get("XAUUSD.vx_entries",0))
    row["jpn225_entries"]=int(bm[m].get("JPN225.vx_entries",0))
    for k,v in [("base",bm),("stress",sm),("extra_10pctR",em)]:
        row[k+"_entries"]=int(v[m]["entries"])
        row[k+"_closed"]=int(v[m]["closed"])
        row[k+"_wins"]=int(v[m]["wins"])
        row[k+"_losses"]=int(v[m]["losses"])
        row[k+"_net_R"]=round(v[m]["R"],4)
        row[k+"_model_usd"]=round(v[m]["pnl"],2)
    monthly_rows.append(row)
assert sum(row["base_entries"] for row in monthly_rows)==base["trades"]
assert abs(sum(row["base_model_usd"] for row in monthly_rows)-base["pnl"])<0.5
def clipped(x):
    return {k:v for k,v in x.items() if k!="ledger"}
report={"project":"KATARINA_AI_RESEARCH_ONLY_PORTFOLIO_DIAGNOSTIC",
        "run_date":"2026-10-11","tick_replay_source":str(SRC),
        "sha256":hashlib.sha256(RAW).hexdigest(),
        "warning":"Previously inspected 2025-2026 data, post hoc only, NOT an unseen OOS or a broker account statement.",
        "limitations":["Only six pre-generated XAUUSD and JPN225 candidates; other markets were not portfolio replayed here.",
                       "No broker volume normalization, broker native margin, actual fills, swaps/commissions or currency conversion.",
                       "R from historical tick replay; fractional virtual risk and realized close-based drawdown only.",
                       "Intratrade floating drawdown, margin/liquidation and news effects not modeled.",
                       "2026 was already inspected in previous work: diagnostic is NOT a clean holdout.",
                       "Portfolio settings sweep selected on 2025 only; total parameter search still creates overfit risk.",
                       "No automatic change to trading risk policy, stages 35/36/38 or live permissions."],
        "source_rule_metrics":overview(),
        "grid_candidates_count":len(scored),
        "ranked_by_2025_stress_only_top10":scored[:10],
        "selected_model_2025_training_only":best,
        "combined_full_sample_BASE":clipped(base),
        "combined_full_sample_STRESS":clipped(stress),
        "combined_full_sample_EXTRA_10PCT_R":clipped(extra),
        "monthly":monthly_rows}
(OUT/"research_report.json").write_text(json.dumps(report,indent=2),encoding="utf8")
with (OUT/"combined_portfolio_monthly_2025_2026.csv").open("w",newline="",encoding="utf-8-sig") as f:
    w=csv.DictWriter(f,fieldnames=list(monthly_rows[0]));w.writeheader();w.writerows(monthly_rows)
with (OUT/"combined_portfolio_all_entries_2025_2026.csv").open("w",newline="",encoding="utf-8-sig") as f:
    cols=["symbol","rule","side","entry_UTC","exit_UTC","R","risk_cash_USD","pnl_USD","cost_profile"]
    w=csv.DictWriter(f,fieldnames=cols);w.writeheader()
    for t in sorted(base["ledger"],key=lambda x:x["entry"]):
        w.writerow({"symbol":t["symbol"],"rule":t["rule"],"side":"BUY" if t["side"]==1 else "SELL",
                    "entry_UTC":tsdt(t["entry"]).isoformat(),"exit_UTC":tsdt(t["exit"]).isoformat(),
                    "R":round(t["R"],6),"risk_cash_USD":round(t["stake"],5),
                    "pnl_USD":round(t["pnl"],5),"cost_profile":"BASE"})
print("SOURCE",report["sha256"])
print("RULES",len(rules),"GRID",len(scored))
print("BEST",json.dumps(best,ensure_ascii=False))
print("FULL",json.dumps({k:report[k] for k in ("combined_full_sample_BASE","combined_full_sample_STRESS","combined_full_sample_EXTRA_10PCT_R")},ensure_ascii=False)[:4000])
print("MONTHLY",json.dumps(monthly_rows,ensure_ascii=False))
print("OUTPUT",str(OUT))
