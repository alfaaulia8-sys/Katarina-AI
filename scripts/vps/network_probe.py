from __future__ import annotations
import json, socket, ssl, time, urllib.request
from statistics import mean

TARGETS=[
    ("api.github.com",443,"https://api.github.com"),
    ("github.com",443,"https://github.com"),
    ("pypi.org",443,"https://pypi.org/simple/pip/"),
]

def dns_probe(host):
    t0=time.perf_counter()
    try:
        rows=socket.getaddrinfo(host,None,type=socket.SOCK_STREAM)
        addrs=sorted({x[4][0] for x in rows})
        return {"ok":True,"ms":round((time.perf_counter()-t0)*1000,2),"addresses":addrs[:6]}
    except Exception as e:
        return {"ok":False,"ms":round((time.perf_counter()-t0)*1000,2),"error":repr(e)}

def tcp_probe(host,port,count=5,timeout=5.0):
    samples=[]; errors=[]
    for _ in range(count):
        t0=time.perf_counter()
        try:
            with socket.create_connection((host,port),timeout=timeout):
                samples.append((time.perf_counter()-t0)*1000)
        except Exception as e:
            errors.append(repr(e))
        time.sleep(0.05)
    return {
        "ok":len(samples)>0 and not errors,
        "successes":len(samples),
        "attempts":count,
        "avg_ms":round(mean(samples),2) if samples else None,
        "min_ms":round(min(samples),2) if samples else None,
        "max_ms":round(max(samples),2) if samples else None,
        "errors":errors[:3],
    }

def https_probe(url,count=3,timeout=8.0):
    samples=[]; statuses=[]; errors=[]
    ctx=ssl.create_default_context()
    headers={"User-Agent":"Katarina-VPS-Network-Probe/1.0"}
    for _ in range(count):
        req=urllib.request.Request(url,headers=headers,method="GET")
        t0=time.perf_counter()
        try:
            with urllib.request.urlopen(req,timeout=timeout,context=ctx) as r:
                r.read(256)
                statuses.append(int(r.status))
                samples.append((time.perf_counter()-t0)*1000)
        except Exception as e:
            errors.append(repr(e))
        time.sleep(0.05)
    return {
        "ok":len(samples)>0 and all(200 <= s < 500 for s in statuses),
        "successes":len(samples),
        "attempts":count,
        "statuses":statuses,
        "avg_ms":round(mean(samples),2) if samples else None,
        "min_ms":round(min(samples),2) if samples else None,
        "max_ms":round(max(samples),2) if samples else None,
        "errors":errors[:3],
    }

def main():
    started=time.time()
    results=[]
    for host,port,url in TARGETS:
        results.append({
            "host":host,
            "dns":dns_probe(host),
            "tcp443":tcp_probe(host,port),
            "https":https_probe(url),
        })
    github=next(x for x in results if x["host"]=="api.github.com")
    control_ok=github["dns"]["ok"] and github["tcp443"]["successes"]==5 and github["https"]["successes"]==3
    out={
        "proof_type":"KATARINA_VPS_NETWORK_PROBE_V1",
        "started_epoch":started,
        "completed_epoch":time.time(),
        "hostname":socket.gethostname(),
        "control_path_ok":control_ok,
        "targets":results,
    }
    print(json.dumps(out,sort_keys=True))

if __name__=="__main__":
    main()
