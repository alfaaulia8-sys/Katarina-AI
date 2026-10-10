"""Run one auditable, read-only brain observation or a bounded/continuous loop."""
import argparse,json,sys,time
from pathlib import Path
from datetime import datetime,timezone
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/"src"))
from katarina.intelligence.brain import KatarinaAIBrain
from katarina.intelligence.forward_outcomes import ForwardOutcomes
from katarina.intelligence.public_context import ContextStore,SOURCES
from katarina.intelligence.multi_market_brain import collect,screen,save_observation

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--terminal",required=True)
    p.add_argument("--state-dir",required=True)
    p.add_argument("--cycles",type=int,default=1,help="0 keeps observing until stopped")
    p.add_argument("--interval",type=int,default=300)
    a=p.parse_args()
    if a.cycles<0 or a.interval<60: p.error("invalid cycles/interval")
    directory=Path(a.state_dir);directory.mkdir(parents=True,exist_ok=True)
    # OS file lock is released on crashes; duplicate workers cannot share state.
    lock=open(directory/"worker.lock","a+b")
    if sys.platform=="win32":
        import msvcrt
        lock.seek(0);lock.write(b"0");lock.flush();lock.seek(0)
        msvcrt.locking(lock.fileno(),msvcrt.LK_NBLCK,1)
    else:
        import fcntl
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
    import MetaTrader5 as mt5
    store=ContextStore(directory/"brain.sqlite3")
    cycle=0
    try:
        while a.cycles==0 or cycle<a.cycles:
            statuses=store.refresh(datetime.now(timezone.utc))
            try:
                rows=collect(mt5,a.terminal)
                now=datetime.now(timezone.utc)
                result=KatarinaAIBrain().survey_markets(rows,context_store=store,now_utc=now)
            except Exception as exc:
                now=datetime.now(timezone.utc)
                result=dict(as_of_utc=now.isoformat(),decision="SAFE_MODE",
                            live_execution_enabled=False,symbols_scanned=0,
                            research_watchlist=[],error=type(exc).__name__)
            result["feeds"]={name:{k:v for k,v in store.latest(name,now).items() if k!="payload"} for name in SOURCES}
            observation_id=save_observation(store,result)
            result["forward_evaluation"]=ForwardOutcomes(store.db).process(observation_id,result)
            temp=directory/"latest.tmp"
            temp.write_text(json.dumps(result,indent=2,allow_nan=False)+"\n",encoding="utf-8")
            temp.replace(directory/"latest.json")
            print(json.dumps({k:result[k] for k in ("as_of_utc","decision","symbols_scanned","research_watchlist")}),flush=True)
            cycle+=1
            if a.cycles==0 or cycle<a.cycles: time.sleep(a.interval)
    finally:
        store.db.close();lock.close()

if __name__=="__main__":main()
