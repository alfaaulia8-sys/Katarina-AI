from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
from pathlib import Path


def read_log(path: Path) -> str:
    raw=path.read_bytes()
    for enc in ("utf-16-le","utf-8-sig","utf-8","cp1252"):
        try:
            text=raw.decode(enc)
            if "Result:" in text or "error" in text.lower() or "warning" in text.lower():
                return text
        except UnicodeDecodeError:
            pass
    return raw.decode("utf-8",errors="replace")


def sha256(path: Path) -> str:
    h=hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda:f.read(1024*1024),b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> int:
    ap=argparse.ArgumentParser()
    ap.add_argument("--terminal-data",required=True)
    ap.add_argument("--metaeditor",required=True)
    args=ap.parse_args()

    root=Path(__file__).resolve().parents[2]
    data=Path(args.terminal_data)
    meta=Path(args.metaeditor)
    if not data.is_dir() or not meta.is_file():
        raise SystemExit("terminal data or MetaEditor missing")

    include_src=root/"mt5"/"Include"/"Katarina"
    include_dst=data/"MQL5"/"Include"/"Katarina"
    expert_src=root/"mt5"/"Experts"/"KatarinaBridgeMultiSymbolExtensionEA.mq5"
    expert_dst=data/"MQL5"/"Experts"/expert_src.name
    mql_root=data/"MQL5"
    if not include_src.is_dir() or not expert_src.is_file():
        raise SystemExit("multi-symbol extension source missing")

    include_dst.mkdir(parents=True,exist_ok=True)
    shutil.copytree(include_src,include_dst,dirs_exist_ok=True)
    expert_dst.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(expert_src,expert_dst)

    ex5=expert_dst.with_suffix(".ex5")
    log=root/"build"/"mt5"/"KatarinaBridgeMultiSymbolExtensionEA.compile.log"
    log.parent.mkdir(parents=True,exist_ok=True)
    if ex5.exists(): ex5.unlink()
    if log.exists(): log.unlink()

    cmd=[
        str(meta),
        f"/compile:{expert_dst}",
        f"/inc:{mql_root}",
        f"/log:{log}",
    ]
    proc=subprocess.run(cmd,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=120)
    text=read_log(log) if log.exists() else ""
    passed=log.exists() and ex5.exists() and "0 errors, 0 warnings" in text
    proof={
        "schema_version":1,
        "proof_type":"KATARINA_MULTI_SYMBOL_EXTENSION_EA_COMPILE",
        "source":str(expert_src),
        "staged_source":str(expert_dst),
        "metaeditor":str(meta),
        "process_exit_code":proc.returncode,
        "log_exists":log.exists(),
        "ex5_exists":ex5.exists(),
        "ex5_sha256":sha256(ex5) if ex5.exists() else None,
        "result":"PASS_0_ERRORS_0_WARNINGS" if passed else "FAIL",
        "log_tail":text[-3000:],
    }
    print(json.dumps(proof,sort_keys=True))
    return 0 if passed else 1


if __name__=="__main__":
    raise SystemExit(main())
