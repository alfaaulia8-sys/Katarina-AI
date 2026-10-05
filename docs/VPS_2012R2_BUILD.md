# KATARINA VPS 2012 R2 bridge

This branch is the bootstrap/control plane for the Windows Server 2012 R2 VPS.

## Design

- `main`: stable source. The VPS bridge never pushes here.
- `vps-control`: read-only control plane from ChatGPT to the VPS.
- `vps-reports`: the VPS writes only important build results/errors here.
- VPS source changes stay local until the user explicitly approves the final push.

The bridge polls `vps-control` every 120 seconds by default. Polling is read-only.
There are no heartbeat commits. A normal build publishes at most one report commit.

## One-time VPS setup

Clone the **vps-control** branch including the `.git` directory:

```bat
git clone -b vps-control https://github.com/alfaaulia8-sys/Katarina-AI.git C:\Users\Administrator\Desktop\Katarina-AI
```

Then double-click:

```text
VPS_KATARINA_SETUP.bat
```

Runtime state stays in `C:\KatarinaRuntime`.

Requirements:
- Windows Server 2012 R2 x64
- PowerShell 5.1 recommended
- Git for Windows available as `git.exe`
- Python 3 (3.12 recommended)
- MetaTrader 5 / MetaEditor for MQL5 compile/runtime testing

Stage 35 real-tick testing is disabled until `C:\KatarinaRuntime\vps-local.json`
contains a valid terminal path, expert, broker symbol and date range.

## Bridge commands

`vps_bridge/control.json` supports `IDLE`, `RUN_BUILD`, `APPLY_PATCH_AND_BUILD`, and `STOP`.
Before a patch is applied, the VPS runs `git apply --check`. The patch is committed only
to the VPS-local branch and is not pushed to `main`.

## Reports

The VPS publishes only meaningful results to:

```text
vps-reports:vps_bridge/reports/
  latest.json
  latest.log
  latest.diff
```

`latest.diff` is the cumulative local source diff against `origin/main`, allowing
ChatGPT to inspect VPS-local fixes without pushing the source branch.

## Safety

`live_risk_ready=false` and `live_execution_enabled=false` remain mandatory.
Final source publication is intentionally not automated.


## Windows Server 2012 R2 Python runtime

The VPS harness does not require a system-wide Python installation. When Python is
missing, it bootstraps the official CPython 3.8.10 embeddable x64 distribution into:

`C:\KatarinaRuntime\python`

Pip is bootstrapped with the Python-3.8-specific get-pip endpoint. Server-2012
dependencies are pinned separately in `requirements-vps2012.txt` so the stable
`main` requirements remain untouched during VPS validation.
