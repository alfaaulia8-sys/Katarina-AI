"""KATARINA intraday research: closed-bar confluence with tick replay; no orders."""
from __future__ import annotations
import sys,json
from datetime import datetime,timedelta,timezone
from pathlib import Path
ROOT=Path(r"C:\KatarinaDev\github-main")
sys.path.insert(0,str(ROOT/"scripts"/"research"))
from backtest_brain_v2_from_2025 import load_bars,aggregate,build_frames,frame_last,getframe,MT5PATH,AUDIT
from intraday_session_2025 import candidates
from intraday_tool_method_matrix_2025 import features,meets
from xau_intraday_real_tick_path_2025 import replay_ticks
from audit_xau_intraday_robustness_2025 import metrics
import MetaTrader5 as mt5
FILTERS=("RAW","ADX20","ADX20_FIBO","TICK_VOLUME_1P2","VOL_BODY")
RRS=(2.,3.)
COSTS=(("BASE",1,.03),("STRESS_3_TICKS",3,.05))
def run():
 if not mt5.initialize(path=MT5PATH,timeout=15000):raise RuntimeError(mt5.last_error())
 results=[]
 try:
  si=mt5.symbol_info("XAUUSD.vx")
  tick=float(si.trade_tick_size or si.point)
  bars,_=load_bars("XAUUSD.vx")
  h1=frame_last(build_frames(aggregate(bars,3600),3600))
  h4=frame_last(build_frames(aggregate(bars,14400),14400))
  d1=frame_last(build_frames(aggregate(bars,86400),86400))
  base=[s for s in candidates(bars,h1,h4) if s[2]=="OR_TREND_BREAK" and s[3]==6]
  print("BASE_EVENTS",len(base),flush=True)
  for z,(j,side,mode,hour,atr) in enumerate(base):
    i=j-1
    asof=bars[i].time+300
    feats=features(bars,i,side,getframe(h1,asof),getframe(h4,asof),getframe(d1,asof))
    if feats is None:continue
    filters=[n for n in FILTERS if meets(n,feats)]
    start=datetime.fromtimestamp(bars[j].time,tz=timezone.utc)
    end=start+timedelta(hours=6)
    arr=mt5.copy_ticks_range("XAUUSD.vx",start,end,mt5.COPY_TICKS_ALL)
    for rr in RRS:
      for cost,slip,fee in COSTS:
        trade,error=replay_ticks("XAUUSD.vx",arr,int(start.timestamp()*1000),
           int(end.timestamp()*1000),side,atr,tick,rr,slip,fee)
        if error:
          print("TICK_MISSING",start.isoformat(),error,flush=True)
          continue
        results.append({"start_time":bars[j].time,"year":str(start.year),
           "month":start.strftime("%Y-%m"),"week":f"{start.isocalendar().year}-W{start.isocalendar().week:02d}",
           "time":bars[j].time,"side":side,"atr":atr,"R":trade["R"],
           "cost":cost,"rr":rr,"exit":trade["reason"],"filters":filters,
           "adx_h1":feats["adx"],"fibo_pos":feats["fibo_pos"],
           "tick_volume_rel":feats["volume_relative"],"body_ratio":feats["body"]})
    if z%25==0:print("PROGRESS",z,len(base),flush=True)
 finally:mt5.shutdown()
 summaries=[]
 for f in FILTERS:
  for rr in RRS:
   for cost,_,_ in COSTS:
    yrs={}
    for yr in ("2025","2026"):
     xs=[x for x in results if f in x["filters"] and x["year"]==yr and x["rr"]==rr and x["cost"]==cost]
     yrs[yr]=metrics(xs)
    summaries.append({"filter":f,"rr":rr,"cost":cost,"2025":yrs["2025"],"2026":yrs["2026"]})
    print("FILTER",f,rr,cost,"2025",yrs["2025"].get("n"),yrs["2025"].get("avg_R"),
         "2026",yrs["2026"].get("n"),yrs["2026"].get("avg_R"),flush=True)
 final={"kind":"KATARINA_XAU_INTRADAY_METHOD_CONFLUENCE_TICK_ABLATION",
    "source":"ValetaxIntl-Live2 broker Bid/Ask real tick path",
    "method":"OR_TREND_BREAK UTC06, H1 H4 alignment, next M5 open, .55 H1 ATR stop, 6h max",
    "filters":FILTERS,"RRS":RRS,"costs":COSTS,
    "2026_was_previously_inspected":True,"no_clean_OOS_claim":True,
    "no_actual_broker_fill":True,"live_execution":False,
    "risk_governor_unchanged":True,"individual_event_outcomes":results,"summary":summaries}
 out=AUDIT/"katarina_xau_method_tick_ablation_2025_2026.json"
 out.write_text(json.dumps(final,indent=2)+"\n",encoding="utf-8")
 print("FILE",str(out),"events",len(results),flush=True)
if __name__=="__main__":run()
