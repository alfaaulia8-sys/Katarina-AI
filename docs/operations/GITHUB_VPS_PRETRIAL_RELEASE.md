# GitHub-first VPS pretrial release

The existing private control repository is the transport for the existing VPS
agent. Do not create another agent, scheduler, public SSH port or competing queue.
Desktop Commander is a fallback when an operation is unavailable over that path.

`scripts/vps/Invoke-KatarinaPretrialRelease.ps1` provides three foreground actions:

| Mode | Effect |
|---|---|
| Audit | Read source identity, dirty state, runtime version/dependency availability and terminal installation presence; no broker connection |
| Sync | Fetch the approved public repository and fast-forward clean `main` to an exact expected commit; refuse dirty source or a running brain |
| Pretrial | Require the exact source SHA and Python 3.12/NumPy, then execute the synthetic acceptance in a separate per-release state directory |

Use only a commit whose GitHub gate passed. `Sync` refuses a moving main rather
than deploying a different version. It does not stash, reset, delete old source,
modify private trading state, install packages, activate a strategy, or start a
daemon. Runtime probes and acceptance children have bounded waits. Child logs
stay private; exported reports contain predefined diagnostic codes, not arbitrary
exception text. A successful sync does not prove Python, broker or model readiness.

The private control dispatcher may invoke an exact, reviewed copy of this script
with fixed VPS paths and a validated commit digest. Jobs require creation/expiry
times, a unique ID and a single allowlisted action. Do not add a generic command
or arbitrary-script job. Existing agent reloads vetted dispatcher functions on
each pull; no second connection or restart is necessary.

Example on the authorized Windows host:

```powershell
.\scripts\vps\Invoke-KatarinaPretrialRelease.ps1 -Mode Audit -ExpectedCommit APPROVED_SHA
.\scripts\vps\Invoke-KatarinaPretrialRelease.ps1 -Mode Sync -ExpectedCommit APPROVED_SHA
.\scripts\vps\Invoke-KatarinaPretrialRelease.ps1 -Mode Pretrial -ExpectedCommit APPROVED_SHA
```

Terminal presence and package importability do not prove incoming market data.
Real MT5 observation still needs the correct terminal/session, account binding,
disabled trading, sufficient causal price history and the existing strict sensor
check. Neither synthetic PASS nor this release tool authorizes live orders.

## Persistent read-only observation

The canonical observer CLI also accepts `--continuous --no-fetch`, a bound
`--connection-config`, and `--interval-seconds 60`. It retains one brain, one
ContextStore, one MemoryStore and the existing host lock for the entire process.
It creates no background worker. The existing host controller may supervise that
single foreground process in the Owner's interactive Windows session; signing
out or rebooting still requires that session and terminal to become available.

Reuse the real read-only state directory. Never point this process at synthetic
acceptance state. `continuous-status.json` contains redacted operational counters
and a run ID; `latest.json` and the databases remain private evidence. Counters
measure observations, not independent trades, alpha or profit. The process uses
no feed refreshes with `--no-fetch`; omit that flag to use the existing bounded
free news/calendar refresh path. Evidence quality and repeated/correlated samples
still need separate evaluation before any alpha claim.

Create `continuous.stop` in that state directory for graceful shutdown. The file
persists and blocks restart until the host operator explicitly clears it. Idle
stop response is within one second; an active bounded sensor pass finishes first.
The default pause is 60 seconds after each completed pass, with exponential
backoff capped at one hour. There are no overlapping passes or catch-up bursts.
`--max-cycles N` supports a bounded soak before long-running operation.

Identity/permission changes, integrity faults, missing dependencies, disk pressure
or unexpected errors stop the process with BLOCKED status. Transient connection
faults retry within configured route/attempt limits and then wait with backoff.
A status file alone is insufficient proof of liveness: check its timestamp, PID,
run ID and increasing successful-cycle count. Stop the process before source
synchronization. No live execution, manual-position mutation or strategy
activation is authorized by this mode.
