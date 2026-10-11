"""All-broker-symbol MT5 research, READ ONLY. Never sends an order."""
from pathlib import Path
from datetime import datetime,timezone
import numpy as np,json,time,traceback,math,os
try:
 import MetaTrader5 as mt5
except ImportError:
 mt5=None  # github-hosted offline regression only; real extraction requires Windows MT5
from numpy.lib.stride_tricks import sliding_window_view

OUT=Path(r"C:\KatarinaDev\massive-research-20261012") if os.name=="nt" else Path("build/offline-mega-research")
OUT.mkdir(parents=True,exist_ok=True)
HISTORY=OUT/"private_bars";HISTORY.mkdir(exist_ok=True)
CUT1=1767225600;CUT2=1780272000;END=1791590400
STOPS=(.9,1.3,1.8);RRS=(1.3,2.,3.);HOLDS=(8,16,32)
FAMS=("TREND_PULLBACK","TREND_DONCHIAN","TREND_MACD","TREND_FIB50","TREND_RSI50","TREND_ICHIMOKU",
"RANGE_BB","RANGE_RSI","RANGE_KELTNER","REVERSAL_EXHAUST","REVERSAL_SWING","VOL_BREAKOUT","LIQ_SWEEP","SQUEEZE_BREAKOUT")
CFMS=("NONE","BODY55","ENGULF","PIN")
def smooth(a,n,w=False):
 o=np.empty(len(a));o[0]=a[0];alpha=(1/n if w else 2/(n+1))
 for i in range(1,len(a)):o[i]=o[i-1]+alpha*(a[i]-o[i-1])
 return o
def roll(a,n,std=False):
 v=np.asarray(a,float);o=np.full(len(v),np.nan)
 if len(v)<n:return o
 cs=np.r_[0.,np.cumsum(v)];avg=(cs[n:]-cs[:-n])/n
 if not std:o[n-1:]=avg
 else:
  q=np.r_[0.,np.cumsum(v*v)];o[n-1:]=np.sqrt(np.maximum((q[n:]-q[:-n])/n-avg*avg,0))
 return o
def extremes(a,n,hi):
 o=np.full(len(a),np.nan)
 if len(a)>n:
  w=sliding_window_view(a,n);o[n:]=w[:-1].max(axis=1) if hi else w[:-1].min(axis=1)
 return o
def tf(b,x):
 if x==1:return b
 g=b["time"]//(900*x);beg=np.r_[0,np.flatnonzero(np.diff(g))+1];end=np.r_[beg[1:]-1,len(b)-1]
 o=np.empty(len(beg),dtype=b.dtype)
 o["time"]=b["time"][beg];o["open"]=b["open"][beg];o["close"]=b["close"][end]
 o["high"]=np.maximum.reduceat(b["high"],beg);o["low"]=np.minimum.reduceat(b["low"],beg)
 o["spread"]=b["spread"][end];o["tick_volume"]=np.add.reduceat(b["tick_volume"],beg)
 return o[1:-1]
def signal_data(b,point):
 c=b["close"].astype(float);o=b["open"].astype(float);hi=b["high"].astype(float);lo=b["low"].astype(float)
 prev=np.r_[c[0],c[:-1]];tr=np.maximum.reduce([hi-lo,abs(hi-prev),abs(lo-prev)])
 atr=smooth(tr,14,True);ema20=smooth(c,20);ema50=smooth(c,50)
 mac=smooth(c,12)-smooth(c,26);macsig=smooth(mac,9)
 mov=np.diff(c,prepend=c[0]);gain=smooth(np.maximum(mov,0),14,True);loss=smooth(np.maximum(-mov,0),14,True)
 rsi=100*gain/np.maximum(gain+loss,1e-10)
 up=np.r_[0,hi[1:]-hi[:-1]];dn=np.r_[0,lo[:-1]-lo[1:]]
 pdm=smooth(np.where((up>dn)&(up>0),up,0),14,True)
 mdm=smooth(np.where((dn>up)&(dn>0),dn,0),14,True)
 plus=pdm/np.maximum(atr,point);minus=mdm/np.maximum(atr,point)
 adx=smooth(100*np.abs(plus-minus)/np.maximum(plus+minus,1e-10),14,True)
 slope=(ema20-ema50)/np.maximum(atr,point)
 trendbuy=(adx>=22)&(slope>.18)&(plus>minus)&(c>ema50)
 trendsell=(adx>=22)&(slope<-.18)&(minus>plus)&(c<ema50)
 vol=(atr>1.3*roll(atr,48))&(adx>=17)
 rng=(adx<22)&(np.abs(slope)<.42)&~vol
 uncertain=~(trendbuy|trendsell|rng|vol)
 H20=extremes(hi,20,True);L20=extremes(lo,20,False)
 H10=extremes(hi,10,True);L10=extremes(lo,10,False)
 H5=extremes(hi,5,True);L5=extremes(lo,5,False)
 bmean=roll(c,20);std=roll(c,20,True)
 tenkan=(extremes(hi,9,True)+extremes(lo,9,False))/2
 kijun=(extremes(hi,26,True)+extremes(lo,26,False))/2
 fib=(c-L20)/np.maximum(H20-L20,point)
 bull=c>o;bear=c<o
 prsi=np.r_[rsi[0],rsi[:-1]];pmac=np.r_[mac[0],mac[:-1]];pms=np.r_[macsig[0],macsig[:-1]]
 fam={
 "TREND_PULLBACK":(trendbuy&(lo<ema20)&(c>ema20)&bull,trendsell&(hi>ema20)&(c<ema20)&bear),
 "TREND_DONCHIAN":(trendbuy&(c>H20),trendsell&(c<L20)),
 "TREND_MACD":(trendbuy&(pmac<=pms)&(mac>macsig),trendsell&(pmac>=pms)&(mac<macsig)),
 "TREND_FIB50":(trendbuy&(fib>.4)&(fib<.72)&bull&(lo<ema20),trendsell&(fib>.28)&(fib<.6)&bear&(hi>ema20)),
 "TREND_RSI50":(trendbuy&(prsi<=50)&(rsi>50),trendsell&(prsi>=50)&(rsi<50)),
 "TREND_ICHIMOKU":(trendbuy&(c>tenkan)&(tenkan>kijun)&(lo<=tenkan),trendsell&(c<tenkan)&(tenkan<kijun)&(hi>=tenkan)),
 "RANGE_BB":(rng&(lo<bmean-1.6*std)&(c>bmean-1.4*std)&bull,rng&(hi>bmean+1.6*std)&(c<bmean+1.4*std)&bear),
 "RANGE_RSI":(rng&(prsi<35)&(rsi>=35)&bull,rng&(prsi>65)&(rsi<=65)&bear),
 "RANGE_KELTNER":(rng&(lo<ema20-1.3*atr)&(c>ema20-1.25*atr)&bull,rng&(hi>ema20+1.3*atr)&(c<ema20+1.25*atr)&bear),
 "REVERSAL_EXHAUST":((rng|vol)&(rsi<38)&(lo<L5)&bull,(rng|vol)&(rsi>62)&(hi>H5)&bear),
 "REVERSAL_SWING":((rng|vol)&bull&(lo<L20)&(c>L20),(rng|vol)&bear&(hi>H20)&(c<H20)),
 "VOL_BREAKOUT":(vol&(c>H10)&bull,vol&(c<L10)&bear),
 "LIQ_SWEEP":((rng|vol)&(lo<L20)&(c>L20)&bull,(rng|vol)&(hi>H20)&(c<H20)&bear),
 "SQUEEZE_BREAKOUT":((std<.65*roll(std,48))&(c>bmean+1.5*std)&bull,(std<.65*roll(std,48))&(c<bmean-1.5*std)&bear)}
 width=np.maximum(hi-lo,point);body=np.abs(c-o)/width
 lower=(np.minimum(c,o)-lo)/width;upper=(hi-np.maximum(c,o))/width
 po=np.r_[o[0],o[:-1]];pc=np.r_[c[0],c[:-1]]
 cf={"NONE":(np.ones(len(c),bool),np.ones(len(c),bool)),
 "BODY55":(bull&(body>=.55)&(upper<.25),bear&(body>=.55)&(lower<.25)),
 "ENGULF":(bull&(pc<po)&(o<=pc)&(c>=po),bear&(pc>po)&(o>=pc)&(c<=po)),
 "PIN":(bull&(lower>=.5)&(upper<.25),bear&(upper>=.5)&(lower<.25))}
 regimes={"TREND_BUY":trendbuy,"TREND_SELL":trendsell,"SIDEWAYS":rng,"VOLATILE":vol,"NO_CONCLUSION":uncertain}
 return atr,fam,cf,regimes
def simulate(b,idx,side,atr,point,stop_mul,rr,hold):
 wid=idx[:,None]+np.arange(1,hold+1)[None,:]
 buy=side==1
 spread=np.maximum(b["spread"][idx+1].astype(float)*point,point)
 entry=b["open"][idx+1].astype(float)+buy*spread
 stop=np.maximum(atr[idx]*stop_mul,3*spread)
 sl=entry-side*stop;tp=entry+side*rr*stop
 hi=b["high"][wid];lo=b["low"][wid]
 asksp=b["spread"][wid].astype(float)*point
 stops=np.where(buy[:,None],lo<=sl[:,None],hi+asksp>=sl[:,None])
 targets=np.where(buy[:,None],hi>=tp[:,None],lo+asksp<=tp[:,None])
 j=np.arange(hold)[None,:];slid=np.where(stops,j,hold).min(axis=1);tpid=np.where(targets,j,hold).min(axis=1)
 st=(slid<=tpid)&(slid<hold);tg=(tpid<slid)&(tpid<hold)
 exitidx=idx+1+np.where(st,slid,np.where(tg,tpid,hold-1))
 exitopen=b["open"][exitidx].astype(float)+np.where(buy,0,b["spread"][exitidx].astype(float)*point)
 stopfill=np.where(buy,np.minimum(sl,exitopen),np.maximum(sl,exitopen))
 endclose=b["close"][exitidx].astype(float)+np.where(buy,0,b["spread"][exitidx].astype(float)*point)
 raw=np.where(st,side*(stopfill-entry)/stop,np.where(tg,rr,side*(endclose-entry)/stop))
 return raw-.05,exitidx
def measure(R,t):
 n=len(R)
 if n==0:return dict(n=0,meanR=0.,PF=0.,DD=0.,months=0,win=0.,sumR=0.)
 path=np.r_[0,np.cumsum(R)]
 dd=np.max(np.maximum.accumulate(path)-path)
 pos=np.maximum(R,0).sum();neg=np.maximum(-R,0).sum()
 months=len({datetime.fromtimestamp(int(x),timezone.utc).strftime("%Y-%m") for x in t})
 return dict(n=int(n),meanR=round(float(R.mean()),5),PF=round(float(pos/neg),3) if neg else None,
             DD=round(float(dd),3),months=months,win=round(float((R>0).mean())*100,1),sumR=round(float(R.sum()),3))
def search_tf(b,point,name,tfname):
 t=b["time"].astype(np.int64);atr,fam,conf,regimes=signal_data(b,point)
 eligible=(np.arange(len(t))>=240)&(np.arange(len(t))<len(t)-36)&(t>=1735689600)&(t<END)&np.isfinite(atr)&(atr>point)&(b["spread"]*point<=.22*atr)
 sessions={"ALL":np.ones(len(t),bool),"EU_US":((t//3600)%24>=6)&((t//3600)%24<=20)}
 counts=dict(theoretical=0,evaluated=0,qualified=0,positive_train=0)
 candidates=[]
 for fn,(B,S) in fam.items():
  for candle,(Cb,Cs) in conf.items():
   for session,sess in sessions.items():
    bbase=B&Cb&eligible&sess;sbase=S&Cs&eligible&sess
    for direction in ("BOTH","BUY","SELL"):
     bm=bbase if direction!="SELL" else np.zeros(len(t),bool)
     sm=sbase if direction!="BUY" else np.zeros(len(t),bool)
     ii=np.flatnonzero(bm^sm)
     counts["theoretical"]+=len(STOPS)*len(RRS)*len(HOLDS)
     if len(ii)<38 or np.sum(t[ii]<CUT1)<30:continue
     side=np.where(bm[ii],1,-1)
     for stop in STOPS:
      for rr in RRS:
       for hold in HOLDS:
        counts["evaluated"]+=1
        idx=ii[ii+hold<len(t)];sd=side[:len(idx)]
        Rs,exitidx=simulate(b,idx,sd,atr,point,stop,rr,hold)
        keep=np.zeros(len(idx),bool);last=-1
        for j in range(len(idx)):
         if idx[j]>last:keep[j]=True;last=int(exitidx[j])
        idx=idx[keep];ex=exitidx[keep];rv=Rs[keep]
        train=(t[idx]<CUT1)&(t[ex]<CUT1)
        if train.sum()<28:continue
        stats=measure(rv[train],t[idx[train]])
        if stats["months"]<4:continue
        counts["qualified"]+=1
        if stats["meanR"]>0:counts["positive_train"]+=1
        if stats["meanR"]<=.04 or (stats["PF"] is not None and stats["PF"]<1.06):continue
        score=stats["meanR"]-.018*stats["DD"]-.30/math.sqrt(stats["n"])
        valid=(t[idx]>=CUT1)&(t[idx]<CUT2)&(t[ex]<CUT2)
        holdout=(t[idx]>=CUT2)&(t[idx]<END)&(t[ex]<END)
        v=measure(rv[valid],t[idx[valid]]);h=measure(rv[holdout],t[idx[holdout]])
        candidates.append(dict(symbol=name,timeframe=tfname,family=fn,candle=candle,session=session,
          direction=direction,stop_atr=stop,rr=rr,hold=hold,score=round(score,5),
          train=stats,validation=v,diagnostic=h,validation_stress_meanR=round(v["meanR"]-.15,5) if v["n"] else None,
          diagnostic_stress_meanR=round(h["meanR"]-.15,5) if h["n"] else None))
 candidates.sort(key=lambda a:a["score"],reverse=True)
 return dict(bars=len(b),counts=counts,regimes={k:round(float(v[240:].mean()*100),2) for k,v in regimes.items()},
             shortlist=candidates[:15],champ=candidates[0] if candidates else None)
def execute():
 if mt5 is None:raise RuntimeError("MT5 is required for broker history; GitHub-hosted CI runs pure simulation unit tests only")
 if not mt5.initialize():raise RuntimeError(f"MT5 unavailable: {mt5.last_error()}")
 terminal=mt5.terminal_info()
 if terminal.trade_allowed:raise RuntimeError("Refuse to research on live-enabled terminal")
 names=[s.name for s in mt5.symbols_get() if s.trade_mode!=mt5.SYMBOL_TRADE_MODE_DISABLED]
 print("START",len(names),"symbols, live execution",terminal.trade_allowed,flush=True);started=time.time()
 for index,name in enumerate(names):
  path=OUT/(name.replace(".","_")+".json")
  if path.exists():print("SKIP_EXISTING",index+1,name,flush=True);continue
  try:
   info=mt5.symbol_info(name);mt5.symbol_select(name,True);point=float(info.point)
   cache=HISTORY/(name.replace(".","_")+".npz")
   if cache.exists():bars=np.load(cache)["bars"];source="cached"
   else:
    bars=mt5.copy_rates_from_pos(name,mt5.TIMEFRAME_M15,1,50000)
    if bars is None or len(bars)<1500:raise ValueError("insufficient M15 data")
    bars=np.sort(bars,order="time")
    bars=bars[(bars["time"]>=1735689600)&(bars["time"]<END)]
    np.savez_compressed(cache,bars=bars);source="MT5"
   per={}
   for factor in (1,2,4,16):
    bb=tf(bars,factor)
    if len(bb)<800:continue
    name_tf=f"M{15*factor}" if factor<4 else f"H{factor//4}"
    per[name_tf]=search_tf(bb,point,name,name_tf)
   allw=[v["champ"] for v in per.values() if v["champ"]]
   win=max(allw,key=lambda c:c["score"]) if allw else None
   out=dict(symbol=name,source=source,history_start=int(bars["time"][0]),history_end=int(bars["time"][-1]),
            n_m15=len(bars),point=point,timeframes=per,selected=win,not_live=True)
   path.write_text(json.dumps(out,ensure_ascii=False),encoding="utf-8")
   print("PAIR",index+1,"/",len(names),name,"bars",len(bars),"evaluated",sum(v["counts"]["evaluated"] for v in per.values()),
         "selected",None if win is None else (win["timeframe"],win["family"],win["train"]["meanR"],win["validation"]["meanR"],win["diagnostic"]["meanR"]),
         "elapsed",round(time.time()-started,1),flush=True)
  except Exception as e:
   print("ERROR",name,str(e),flush=True)
   (OUT/(name.replace(".","_")+".err.txt")).write_text(traceback.format_exc(),encoding="utf-8")
 mt5.shutdown();print("COMPLETE",len(names),"elapsed",round(time.time()-started,1),flush=True)
if __name__=="__main__":execute()