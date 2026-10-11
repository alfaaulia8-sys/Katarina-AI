"""Reconstruct broker XAUUSD.vx M1 closed bars from cached true Bid/Ask ticks.

2025-01-01 to 2026-10-10 exclusive. Research-only: no MT5 writes/orders.
Each bar is closed with exact minute bucket and median observed spread.
"""
from __future__ import annotations
import csv,json,hashlib
from datetime import datetime,timedelta,timezone
from pathlib import Path
import numpy as np
import MetaTrader5 as mt5
START=datetime(2025,1,1,tzinfo=timezone.utc)
END=datetime(2026,10,10,tzinfo=timezone.utc)
OUT=Path(r"C:\KatarinaDev\artifacts\historical-brain")
dest=OUT/"xauusd_vx_m1_tick_2025_2026.csv"
summary={"source":"MT5.copy_ticks_range ValetaxIntl-Live2 XAUUSD.vx COPY_TICKS_ALL",
 "window": [START.isoformat(),END.isoformat()],"months":{},"total_valid_ticks":0,
 "total_m1_bars":0,"days_failed":[], "live_trading":False}
if not mt5.initialize(path=r"C:\Program Files\MetaTrader 5 ALFA\terminal64.exe",timeout=15000):
 raise RuntimeError(str(mt5.last_error()))
try:
 si=mt5.symbol_info("XAUUSD.vx")
 assert si is not None
 point=si.point
 with dest.open("w",newline="",encoding="utf-8") as stream:
  writer=csv.writer(stream)
  writer.writerow(("time","open","high","low","close","spread","tick_volume"))
  t=START
  while t<END:
   month=t.strftime("%Y-%m")
   state=summary["months"].setdefault(month,{"valid_ticks":0,"m1_bars":0,"days_present":0})
   ticks=mt5.copy_ticks_range("XAUUSD.vx",t,t+timedelta(days=1)-timedelta(milliseconds=1),mt5.COPY_TICKS_ALL)
   if ticks is None:
     summary["days_failed"].append({"utc_day":t.isoformat(),"mt5_error":str(mt5.last_error())})
   elif len(ticks)>0:
     valid=(ticks["bid"]>0)&(ticks["ask"]>=ticks["bid"])
     tx=ticks[valid]
     stamps=tx["time_msc"]//60000*60
     unique,start_idx,counts=np.unique(stamps,return_index=True,return_counts=True)
     for sec,i,n in zip(unique,start_idx,counts):
       bid=tx["bid"][i:i+n];ask=tx["ask"][i:i+n]
       med=int(round(float(np.median((ask-bid)/point))))
       writer.writerow((int(sec),float(bid[0]),float(bid.max()),float(bid.min()),
                        float(bid[-1]),med,int(n)))
     state["valid_ticks"]+=len(tx);state["m1_bars"]+=len(unique);state["days_present"]+=1
     summary["total_valid_ticks"]+=len(tx);summary["total_m1_bars"]+=len(unique)
   if t.day==1:
     print("MONTH",month,state["valid_ticks"],state["m1_bars"],flush=True)
   t+=timedelta(days=1)
finally:mt5.shutdown()
h=hashlib.sha256()
with dest.open("rb") as stream:
 while True:
  chunk=stream.read(8*1024*1024)
  if not chunk:break
  h.update(chunk)
summary["csv_sha256"]=h.hexdigest()
summary["csv_bytes"]=dest.stat().st_size
summary["path"]=str(dest)
path=OUT/"xauusd_m1_tick_2025_2026_audit.json"
path.write_text(json.dumps(summary,indent=2)+"\n",encoding="utf-8")
print("RESULT",json.dumps({"ticks":summary["total_valid_ticks"],"bars":summary["total_m1_bars"],
 "failed_days":len(summary["days_failed"]),"bytes":summary["csv_bytes"],"sha256":summary["csv_sha256"]}),flush=True)
