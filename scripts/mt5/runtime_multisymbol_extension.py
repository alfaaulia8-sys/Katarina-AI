from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path


EVIDENCE="Katarina_Stage07_multi_symbol_extension_result.txt"


def ps_quote(value:str)->str:
    return "'" + value.replace("'","''") + "'"


def main()->int:
    ap=argparse.ArgumentParser()
    ap.add_argument("--terminal",required=True)
    ap.add_argument("--terminal-data",required=True)
    args=ap.parse_args()

    root=Path(__file__).resolve().parents[2]
    terminal=Path(args.terminal)
    data=Path(args.terminal_data)
    if not terminal.is_file() or not data.is_dir():
        raise SystemExit("terminal or terminal-data missing")

    # Never launch a second copy of the exact target terminal.
    check=(
        "$p=@(Get-WmiObject Win32_Process -Filter \"Name='terminal64.exe'\" "
        "-ErrorAction SilentlyContinue | Where-Object {$_.ExecutablePath -and "
        f"[string]::Equals($_.ExecutablePath,{ps_quote(str(terminal))},"
        "[StringComparison]::OrdinalIgnoreCase)}); "
        "Write-Output $p.Count"
    )
    probe=subprocess.run(
        ["powershell.exe","-NoProfile","-Command",check],
        capture_output=True,text=True,timeout=30
    )
    running=int((probe.stdout or "0").strip().splitlines()[-1] or 0)
    if running:
        print(json.dumps({"result":"REFUSED_TARGET_TERMINAL_RUNNING","running":running}))
        return 2

    profile_marker="\\AppData\\Roaming\\MetaQuotes\\Terminal\\"
    raw=str(data)
    idx=raw.lower().find(profile_marker.lower())
    if idx<=0:
        raise SystemExit("unable to derive profile root")
    profile_root=Path(raw[:idx])
    expected_user=profile_root.name
    common=profile_root/"AppData"/"Roaming"/"MetaQuotes"/"Terminal"/"Common"/"Files"
    common.mkdir(parents=True,exist_ok=True)
    evidence=common/EVIDENCE
    if evidence.exists():
        evidence.unlink()

    compiled=data/"MQL5"/"Scripts"/"KatarinaStage07MultiSymbolExtensionTest.ex5"
    if not compiled.is_file():
        raise SystemExit("compiled multi-symbol runtime test missing")

    build=root/"build"/"mt5"
    build.mkdir(parents=True,exist_ok=True)
    config=build/"runtime_multisymbol_extension.ini"
    config.write_text(
        "[Experts]\n"
        "AllowLiveTrading=0\n"
        "AllowDllImport=0\n"
        "Enabled=1\n"
        "Account=0\n"
        "Profile=0\n\n"
        "[StartUp]\n"
        "Script=KatarinaStage07MultiSymbolExtensionTest\n"
        "Period=H1\n"
        "ShutdownTerminal=1\n",
        encoding="ascii",
    )

    launcher=root/"scripts"/"vps"/"Invoke-KatarinaInteractiveMt5.ps1"
    launch_out=build/"runtime_multisymbol_interactive.json"
    cmd=[
        "powershell.exe","-NoProfile","-ExecutionPolicy","Bypass",
        "-File",str(launcher),
        "-TerminalPath",str(terminal),
        "-ConfigPath",str(config),
        "-ExpectedUser",expected_user,
        "-TimeoutSeconds","60",
        "-OutputPath",str(launch_out),
    ]
    proc=subprocess.run(cmd,capture_output=True,text=True,timeout=90)
    if proc.returncode!=0:
        print(json.dumps({
            "result":"LAUNCH_FAIL",
            "returncode":proc.returncode,
            "stdout":proc.stdout[-2000:],
            "stderr":proc.stderr[-2000:],
        }))
        return 1
    if not evidence.is_file():
        print(json.dumps({"result":"EVIDENCE_MISSING","launch":str(launch_out)}))
        return 1

    text=evidence.read_text(encoding="utf-16",errors="ignore")
    if "result=PASS" not in text:
        # FileWrite TXT may be ANSI depending on terminal settings.
        text=evidence.read_text(encoding="cp1252",errors="ignore")
    required=[
        "stage=07",
        "proof_type=MULTI_SYMBOL_EXTENSION",
        "execution_mutation=DISABLED_IN_TEST",
        "result=PASS",
    ]
    missing=[x for x in required if x not in text]
    proof={
        "schema_version":1,
        "proof_type":"KATARINA_MULTI_SYMBOL_RUNTIME_SAFE",
        "allow_live_trading":False,
        "allow_dll_import":False,
        "script":"KatarinaStage07MultiSymbolExtensionTest",
        "evidence":str(evidence),
        "missing":missing,
        "result":"PASS" if not missing else "FAIL",
    }
    print(json.dumps(proof,sort_keys=True))
    return 0 if not missing else 1


if __name__=="__main__":
    raise SystemExit(main())
