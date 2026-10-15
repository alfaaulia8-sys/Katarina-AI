#!/usr/bin/env python3
from __future__ import annotations
import base64, json, os, re, shlex, signal, subprocess, sys, time, traceback
from pathlib import Path

HOME=Path.home()
ROOT=HOME/".katarina-ai"
PROJECT=ROOT/"project"/"katarina-ai"
VM=ROOT/"windows-vm"
STATE=ROOT/"bridge"/"state"
LOGS=ROOT/"bridge"/"logs"
REPO=os.environ.get("KATARINA_GITHUB_REPO","alfaauliau-katarinaAI/Katarina-AI")
ISSUE=int(os.environ.get("KATARINA_CONTROL_ISSUE","1"))
BRANCH=os.environ.get("KATARINA_CONTROL_BRANCH","katarina-control")
POLL=max(3,int(os.environ.get("KATARINA_POLL_SEC","5")))
CURSOR=STATE/"last_comment_id"
LOCK=STATE/"agent.lock"
STOP=False

def log(s):
    LOGS.mkdir(parents=True,exist_ok=True)
    line=time.strftime("[%Y-%m-%d %H:%M:%S] ")+str(s)
    print(line,flush=True)
    with (LOGS/"agent.log").open("a",encoding="utf-8") as f:f.write(line+"\n")

def run(argv,cwd=None,timeout=90,input_text=None):
    return subprocess.run(argv,cwd=str(cwd) if cwd else None,input=input_text,text=True,
        stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=timeout,check=False)

def shell(cmd,timeout=90):
    return run(["bash","-lc",cmd],timeout=timeout)

def gh(endpoint,method="GET",payload=None,timeout=60):
    a=["gh","api",endpoint,"--method",method]
    inp=None
    if payload is not None:
        a+=["--input","-"]; inp=json.dumps(payload,separators=(",",":"))
    p=run(a,timeout=timeout,input_text=inp)
    if p.returncode: raise RuntimeError(p.stdout[-4000:])
    return json.loads(p.stdout) if p.stdout.strip() else None

def comments():
    ep=f"repos/{REPO}/issues/{ISSUE}/comments?per_page=100"
    p=run(["gh","api","--paginate","--slurp",ep],timeout=60)
    if p.returncode: raise RuntimeError(p.stdout[-4000:])
    pages=json.loads(p.stdout) if p.stdout.strip() else []
    return [c for page in pages for c in page] if isinstance(pages,list) else []

def post(obj):
    body=json.dumps(obj,ensure_ascii=False,separators=(",",":"))
    if len(body)>63000:
        obj=dict(obj); obj["data"]={"truncated":True}; body=json.dumps(obj,ensure_ascii=False)
    gh(f"repos/{REPO}/issues/{ISSUE}/comments","POST",{"body":body})

def parse_job(body):
    try:
        x=json.loads(body.strip())
        return x if isinstance(x,dict) and x.get("kind")=="katarina.job" else None
    except Exception:return None

def cursor_get():
    try:return int(CURSOR.read_text().strip())
    except Exception:return None

def cursor_set(n):
    STATE.mkdir(parents=True,exist_ok=True); CURSOR.write_text(str(n))

def qstatus():
    p=shell("command -v katarina-status >/dev/null 2>&1 && katarina-status || true",30)
    return p.stdout.strip() or "katarina-status unavailable"

def novnc_status():
    p=shell("pgrep -af '[n]ovnc-gateway/server.mjs' || true",10).stdout.strip()
    h=shell("curl -s -o /dev/null -w '%{http_code}' --max-time 3 http://127.0.0.1:6080/vnc.html || true",10).stdout.strip()
    return {"process":p,"http":h}

def novnc_start():
    s=novnc_status()
    if s["process"]:return s
    g=VM/"novnc-gateway"/"server.mjs"
    if not g.exists():raise FileNotFoundError(str(g))
    (VM/"logs").mkdir(parents=True,exist_ok=True); (VM/"run").mkdir(parents=True,exist_ok=True)
    shell("nohup node "+shlex.quote(str(g))+" >"+shlex.quote(str(VM/"logs"/"novnc.log"))+" 2>&1 & echo $! > "+shlex.quote(str(VM/"run"/"novnc.pid")),10)
    for _ in range(10):
        time.sleep(0.5)
        s=novnc_status()
        if s.get("http")=="200": return s
    return novnc_status()

def hmp(mode,value):
    s=VM/"scripts"/"winvm-hmp.py"
    if not s.exists():raise FileNotFoundError(str(s))
    p=run([sys.executable,str(s),mode,value],timeout=60)
    if p.returncode:raise RuntimeError(p.stdout)
    return p.stdout.strip()

def capture(name):
    safe=re.sub(r"[^A-Za-z0-9_.-]+","-",name)[:70] or "capture"
    hmp("capture",safe)
    p=VM/"evidence"/(safe+".png")
    if not p.exists():
        xs=sorted(VM.rglob("*.png"),key=lambda z:z.stat().st_mtime,reverse=True)
        if not xs:raise RuntimeError("capture produced no PNG")
        p=xs[0]
    return p

def remote_sha(path):
    p=run(["gh","api",f"repos/{REPO}/contents/{path}?ref={BRANCH}"],timeout=30)
    if p.returncode:return None
    try:return json.loads(p.stdout).get("sha")
    except Exception:return None

def publish_png(p,job):
    dest="control/artifacts/latest.png"
    payload={"message":"control: VM capture "+job,"content":base64.b64encode(p.read_bytes()).decode(),"branch":BRANCH}
    s=remote_sha(dest)
    if s:payload["sha"]=s
    x=gh(f"repos/{REPO}/contents/{dest}","PUT",payload,120)
    return {"path":dest,"branch":BRANCH,"sha":((x or {}).get("content") or {}).get("sha")}

def inside(rel):
    if not rel or rel.startswith("/"):raise ValueError("relative path required")
    b=PROJECT.resolve(); p=(PROJECT/rel).resolve()
    if p!=b and b not in p.parents:raise ValueError("path escapes workspace")
    return p

def do(job):
    jid=str(job.get("job_id") or ("job-"+str(int(time.time()))))
    a=str(job.get("action") or "")
    x=job.get("args") if isinstance(job.get("args"),dict) else {}
    if a=="health.status":
        d={"qemu":qstatus(),"novnc":novnc_status(),"project":PROJECT.exists(),"vm":VM.exists()}
    elif a=="qemu.status":d={"status":qstatus()}
    elif a in ("qemu.start","qemu.install","qemu.stop","qemu.restart"):
        if a=="qemu.start":shell("katarina-on",60)
        elif a=="qemu.install":shell("katarina-install",60)
        elif a=="qemu.stop":shell("katarina-off",60)
        else:
            shell("katarina-off",60);time.sleep(2)
            shell("katarina-install" if x.get("mode")=="install" else "katarina-on",60)
        time.sleep(float(x.get("wait",2)));d={"status":qstatus()}
    elif a=="novnc.status":d=novnc_status()
    elif a=="novnc.start":d=novnc_start()
    elif a=="vm.key":d={"out":hmp("key",str(x.get("value","")))}
    elif a=="vm.text":d={"out":hmp("text",str(x.get("value","")))}
    elif a=="vm.capture":
        d=publish_png(capture(str(x.get("name") or jid)),jid)
    elif a=="vm.sequence":
        ops=x.get("ops",[])
        if not isinstance(ops,list) or len(ops)>50:raise ValueError("ops invalid")
        tr=[];art=None
        for i,o in enumerate(ops):
            t=str(o.get("type",""))
            if t=="key":hmp("key",str(o.get("value","")));tr.append(f"{i}:key")
            elif t=="text":hmp("text",str(o.get("value","")));tr.append(f"{i}:text")
            elif t=="sleep":time.sleep(min(60,max(0,float(o.get("seconds",1)))));tr.append(f"{i}:sleep")
            elif t=="capture":art=publish_png(capture(str(o.get("name") or jid)),jid);tr.append(f"{i}:capture")
            else:raise ValueError("bad op "+t)
        if x.get("capture_after"):art=publish_png(capture(jid),jid)
        d={"transcript":tr,"artifact":art}
    elif a=="workspace.status":
        d={"status":run(["git","status","--short","--branch"],PROJECT,30).stdout[-20000:]}
    elif a=="workspace.read":
        p=inside(str(x.get("path","")));raw=p.read_bytes();d={"path":str(p.relative_to(PROJECT)),"content":raw[:40000].decode("utf-8","replace"),"truncated":len(raw)>40000}
    elif a=="workspace.write":
        p=inside(str(x.get("path","")));data=base64.b64decode(str(x.get("content_b64","")),validate=True)
        if len(data)>2000000:raise ValueError("payload too large")
        p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data)
        d={"path":str(p.relative_to(PROJECT)),"bytes":len(data),"status":run(["git","status","--short"],PROJECT,30).stdout[-20000:]}
    elif a=="workspace.run":
        task=str(x.get("task",""))
        tasks={"git-status":["git","status","--short","--branch"],"python-compile":[sys.executable,"-m","compileall","-q","src"],"pytest":[sys.executable,"-m","pytest","-q"]}
        if task not in tasks:raise ValueError("task not allowed")
        p=run(tasks[task],PROJECT,min(900,max(10,int(x.get("timeout",180)))))
        d={"task":task,"returncode":p.returncode,"output":p.stdout[-40000:]}
    else:raise ValueError("unsupported action "+a)
    return {"kind":"katarina.result","job_id":jid,"action":a,"status":"ok","summary":"completed","data":d}

def sig(*_):
    global STOP;STOP=True

def main():
    STATE.mkdir(parents=True,exist_ok=True);LOGS.mkdir(parents=True,exist_ok=True)
    if run(["gh","auth","status"],timeout=20).returncode:
        log("AUTH_REQUIRED run: gh auth login");return 2
    signal.signal(signal.SIGTERM,sig);signal.signal(signal.SIGINT,sig)
    cur=cursor_get()
    if cur is None:
        cur=max([int(c.get("id",0)) for c in comments()] or [0]);cursor_set(cur)
    log(f"online repo={REPO} issue={ISSUE} cursor={cur}")
    wait=POLL
    while not STOP:
        try:
            for c in sorted([z for z in comments() if int(z.get("id",0))>cur],key=lambda z:int(z.get("id",0))):
                cid=int(c.get("id",0));j=parse_job(str(c.get("body","")))
                if j:
                    try:r=do(j)
                    except Exception as e:r={"kind":"katarina.result","job_id":str(j.get("job_id","")),"action":str(j.get("action","")),"status":"error","summary":str(e),"trace":traceback.format_exc()[-8000:]}
                    post(r)
                cur=max(cur,cid);cursor_set(cur)
            wait=POLL;time.sleep(POLL)
        except Exception as e:
            log("poll error "+str(e));time.sleep(wait);wait=min(60,wait*2)
    return 0

if __name__=="__main__":raise SystemExit(main())
