"""Gold intraday exit A/B/C comparison on observed broker bid/ask tick paths.

Single entry, initial hard SL and no loss-averaging. These are test hypotheses,
not active trade instructions. In 2026 the history is previously inspected.
"""
from __future__ import annotations
import sys,json
from pathlib import Path
from datetime import datetime,timedelta,timezone
ROOT=Path(r"C:\KatarinaDev\github-main")
sys.path.insert(0,str(ROOT/"scripts"/"research"))
from backtest_brain_v2_from_2025 import load_bars,aggregate,build_frames,frame_last,getframe,MT5PATH,AUDIT
from intraday_session_2025 import candidates
from intraday_tool_method_matrix_2025 import features,meets
from xau_intraday_real_tick_path_2025 import replay_ticks
from audit_xau_intraday_robustness_2025 import metrics
import MetaTrader5 as mt5

EXITS=("FIXED_2R","BE_TRAIL_3R","PARTIAL_TRAIL_3R")
COSTS=(("BASE",1,.03),("STRESS",3,.05))
def simulate(ticks,start_ms,end_ms,side,atr,tick_size,style,slippage,fees):
 valid=ticks[(ticks["time_msc"]>=start_ms)&(ticks["time_msc"]<end_ms)&
  (ticks["bid"]>0)&(ticks["ask"]>=ticks["bid"])]
 if len(valid)<3 or valid[0]["time_msc"]-start_ms>120000:
  return None,"invalid_history_or_entry_delay"
 distance=atr*.55
 if distance<=2.5*(valid[0]["ask"]-valid[0]["bid"]) or distance<=4*tick_size:
  return None,"spread_invalid"
 entry=float(valid[0]["ask"])+slippage*tick_size if side==1 else (
       float(valid[0]["bid"])-slippage*tick_size)
 stop_level=-1.
 max_fav=-1e9;remaining=1.;realized=0.
 first_tp_done=False;exit_reason="TIME"
 for t in valid:
  px=float(t["bid"] if side==1 else t["ask"])
  progress=side*(px-entry)/distance
  max_fav=max(max_fav,progress)
  if style=="BE_TRAIL_3R" and max_fav>=1.:
    stop_level=max(stop_level,.1,max_fav-.8)
  if style=="PARTIAL_TRAIL_3R":
    if not first_tp_done and progress>=1.:
       # Profit capped at the planned threshold; avoid favorable gap windfall.
       realized+=.5*(1.-slippage*tick_size/distance)
       remaining=.5;first_tp_done=True
    if max_fav>=1.5:
       stop_level=max(stop_level,.1,max_fav-1.)
  if progress<=stop_level:
    # Stops may gap unfavorably. Selling/buying into market at actual tick.
    realized+=remaining*(progress-slippage*tick_size/distance)
    exit_reason="SL" if stop_level==-1. else "TRAIL"
    remaining=0.
    break
  objective=2. if style=="FIXED_2R" else 3.
  if progress>=objective:
    realized+=remaining*(objective-slippage*tick_size/distance)
    exit_reason="TP"
    remaining=0.
    break
 if remaining:
  if end_ms-valid[-1]["time_msc"]>120000:
   return None,"stale_exit"
  px=float(valid[-1]["bid"] if side==1 else valid[-1]["ask"])
  realized+=remaining*(side*(px-entry)/distance-slippage*tick_size/distance)
 return {"R":float(realized-fees),"exit":exit_reason,
  "partial":first_tp_done,"n_ticks":len(valid)},None
def main():
 if not mt5.initialize(path=MT5PATH,timeout=15000):
  raise RuntimeError(mt5.last_error())
 trades=[];invalid=[]
 try:
  si=mt5.symbol_info("XAUUSD.vx")
  tick_size=float(si.trade_tick_size or si.point)
  bars,_=load_bars("XAUUSD.vx")
  h1=frame_last(build_frames(aggregate(bars,3600),3600))
  h4=frame_last(build_frames(aggregate(bars,14400),14400))
  d1=frame_last(build_frames(aggregate(bars,86400),86400))
  events=[x for x in candidates(bars,h1,h4) if x[2]=="OR_TREND_BREAK" and x[3]==6]
  chosen=[]
  for j,side,mode,hour,atr in events:
   x=features(bars,j-1,side,getframe(h1,bars[j-1].time+300),
              getframe(h4,bars[j-1].time+300),
              getframe(d1,bars[j-1].time+300))
   if x is not None and meets("ADX20",x):chosen.append((j,side,atr))
  print("SIGNALS_SELECTED",len(chosen),flush=True)
  for n,(j,side,atr) in enumerate(chosen):
   time=datetime.fromtimestamp(bars[j].time,tz=timezone.utc)
   stop=time+timedelta(hours=6)
   ts=mt5.copy_ticks_range("XAUUSD.vx",time,stop,mt5.COPY_TICKS_ALL)
   if ts is None or not len(ts):
    invalid.append((time.isoformat(),"missing_ticks"));continue
   sm=int(time.timestamp()*1000);em=int(stop.timestamp()*1000)
   for cost,slip,fee in COSTS:
    comparison,err=replay_ticks("XAUUSD.vx",ts,sm,em,side,atr,tick_size,2.,slip,fee)
    if err:
     invalid.append((time.isoformat(),err));continue
    for style in EXITS:
     v,error=simulate(ts,sm,em,side,atr,tick_size,style,slip,fee)
     if error:
      invalid.append((time.isoformat(),error));continue
     if style=="FIXED_2R" and abs(v["R"]-comparison["R"])>1e-7:
      raise AssertionError(("fixed_replay_disagreement",time.isoformat(),v,comparison))
     trades.append({"style":style,"cost":cost,"year":str(time.year),
      "month":time.strftime("%Y-%m"),"week":f"{time.isocalendar().year}-W{time.isocalendar().week:02d}",
      "time":bars[j].time,"R":v["R"],"exit":v["exit"],"partial":v["partial"]})
   if n%20==0:print("REPLAYED",n,len(chosen),flush=True)
 finally:mt5.shutdown()
 summary=[]
 for style in EXITS:
  for cost,slip,fee in COSTS:
   years={}
   for yr in ("2025","2026"):
    values=[x for x in trades if x["year"]==yr and x["cost"]==cost and x["style"]==style]
    years[yr]=metrics(values)
   summary.append({"exit":style,"cost":cost,"years":years})
   print("EXIT",style,cost,[(yr,years[yr].get("n"),years[yr].get("avg_R"),
                 years[yr].get("PF"),years[yr].get("sum_R_excluding_top_5")) for yr in ("2025","2026")],flush=True)
 report={"kind":"KATARINA_XAU_ADX20_THREE_EXIT_FAMILIES_TICK_REPLAY",
  "start":"2025-01-01","end":"2026-10-09",
  "method":"UTC06 OR breakout H1/H4 ADX20, initial stop 0.55 H1 ATR",
  "rules":{"FIXED_2R":"single full TP2R and initial SL -1R",
   "BE_TRAIL_3R":"after 1R highwater, trailing 0.8R gap and BE+0.1R floor, TP3R",
   "PARTIAL_TRAIL_3R":"50 pct at 1R, then trail remaining after 1.5R with 1R gap and BE+0.1R floor, TP3R",
   "max_hold_hours":6,"hard_sl_initial_R":-1},
  "execution_model":"genuine broker historical Bid Ask path; hypothetical adverse tick slippage and flat R fee",
  "2026_not_clean_unseen_validation":True,
  "no_broker_fills_or_order_acknowledgements":True,
  "no_real_orders":True,
  "summary":summary,"events":trades,"invalid":invalid}
 out=AUDIT/"katarina_xau_exit_three_way_tick_2025_2026.json"
 out.write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
 print("FILE",str(out),flush=True)
if __name__=="__main__":main()
