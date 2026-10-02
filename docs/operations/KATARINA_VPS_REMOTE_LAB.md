# Katarina VPS Remote Lab

**Status:** OPERATIONAL DESIGN / INSTALLATION REQUIRED ON VPS

## Goal

Give Katarina development a controlled way to request tests from a Windows VPS and retrieve logs, evidence, and machine facts through the private GitHub repository without exposing RDP, SSH, WinRM, or a public command port.

## Communication model

```text
ChatGPT / GitHub connector
        ↓ writes allowlisted request JSON
private GitHub repository
        ↓ outbound HTTPS poll / Actions job
authorized VPS
        ↓ runs fixed task ID only
test / collect / compile
        ↓
text evidence + logs
        ↓
private GitHub results / Actions artifacts
        ↓
ChatGPT can inspect the result
```

No inbound firewall port is required.

## Two execution paths

### A. Modern Windows — preferred

Use the official GitHub Actions self-hosted runner with labels:

```text
self-hosted
windows
x64
katarina-vps
```

The repository already contains:

```text
.github/workflows/katarina-vps-lab.yml
```

A request committed to `ops/vps/requests/*.json` starts the job. The job uses the allowlisted task runner and uploads the result as a GitHub Actions artifact.

### B. Windows Server 2012 R2 — legacy bridge

The current GitHub Actions self-hosted runner does not officially support Windows Server 2012 R2. For that machine Katarina uses a small PowerShell polling agent instead.

Files:

```text
scripts/vps/legacy/KatarinaVpsAgent.ps1
scripts/vps/legacy/Install-KatarinaVpsAgent.ps1
scripts/vps/Invoke-KatarinaRemoteTask.ps1
```

The legacy agent:

- uses outbound HTTPS to GitHub only;
- polls `ops/vps/requests`;
- accepts only a request whose `target_agent` equals its configured agent ID;
- rejects expired requests;
- rejects every task not on the allowlist;
- downloads a private repository snapshot for the requested ref;
- runs the fixed Katarina task runner;
- redacts common secret patterns;
- uploads text-only results to `ops/vps/results/<agent>/<request>/`;
- never opens a public shell listener.

## Allowed task IDs

```text
HOST_INVENTORY
REPO_STATIC_TESTS
STAGE06_HOST_CHECK
STAGE06_COMPILE_PROOF
STAGE06_CLEARANCE
STAGE07_PYTHON_TESTS
COLLECT_MT5_LOGS
```

Requests do not contain arbitrary PowerShell commands.

## Request format

Example:

```json
{
  "schema_version": 1,
  "request_id": "req-20261003-001",
  "target_agent": "katarina-vps-2012r2-01",
  "task": "HOST_INVENTORY",
  "created_utc": "2026-10-03T00:00:00Z",
  "expires_utc": "2026-10-03T01:00:00Z",
  "ref": "main",
  "args": {}
}
```

## Installation on Windows Server 2012 R2

1. Download or clone the private Katarina-AI repository onto the VPS.
2. Open PowerShell as Administrator.
3. Go to `scripts\vps\legacy`.
4. Run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\Install-KatarinaVpsAgent.ps1 -AgentId "katarina-vps-2012r2-01"
```

5. The installer asks for a GitHub fine-grained PAT locally on the VPS.
6. Do **not** paste that PAT into ChatGPT.
7. Limit the token to this single private repository.
8. Required repository permission: **Contents — Read and write**.
9. The token is encrypted with Windows DPAPI LocalMachine before storage.
10. The installer registers an automatic startup scheduled task named `KatarinaVPSAgent`.

After installation the machine needs outbound HTTPS/443 access to `github.com` and `api.github.com`.

## How ChatGPT will use it

When the owner says, for example:

```text
cek VPS
jalankan Stage 07 test di VPS
ambil log MT5 terbaru
cek apakah MetaEditor ada
```

the development flow is:

1. create one request JSON in the private repository;
2. the VPS agent executes the matching allowlisted task;
3. wait for the result folder or Actions artifact;
4. read the result through the GitHub connector;
5. use that evidence for the next code change;
6. never ask the owner to manually copy normal diagnostic logs unless the bridge itself is broken.

## Security rules

- No VPS password is committed to GitHub.
- No RDP password is shared in chat.
- No PAT is shared in chat.
- No arbitrary command string is accepted from request JSON.
- No inbound command port is opened.
- Result uploads are limited to JSON/TXT/LOG/CSV/MD and capped by policy.
- Stage-06 production broker mutation remains disabled.
- A failing task returns evidence; it does not silently retry broker actions.

Machine policy is defined in:

```text
config/vps_remote_lab_policy.json
```

## Modern Windows migration

When the VPS is upgraded to Windows Server 2016/2019/2022 or another supported modern Windows x64 baseline, remove the legacy polling dependency and register the official GitHub Actions self-hosted runner. The same allowlisted request/task format can remain.
