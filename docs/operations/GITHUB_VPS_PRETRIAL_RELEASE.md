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
