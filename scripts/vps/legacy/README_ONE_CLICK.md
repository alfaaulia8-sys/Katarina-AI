# KATARINA AI One-Click VPS Bootstrap v1.2.2

Target: **Windows Server 2012 R2 x64**

## Install

1. Pull or download the latest `main` branch.
2. Open:
   `scripts\vps\legacy\`
3. Double-click:
   `INSTALL_KATARINA.cmd`
4. Approve Administrator permission.
5. Paste the GitHub Fine-Grained PAT once when requested.

Required PAT scope:

- Repository: `alfaaulia-katarina/Katarina-AI`
- Repository permission: **Contents = Read and write**

Do not paste the PAT into ChatGPT.

## v1.2.2 behavior

- Connects to GitHub **before** preflight.
- Uploads installer/bootstrap diagnostics to:
  `ops/vps/bootstrap/<agent>/<session>/`
- Installs the persistent agent only after preflight passes.
- Installer waits for agent health and, if it does not reach ONLINE, automatically uploads Task Scheduler status, `startup_state.json`, and `last_error.json` to the bootstrap session folder.
- Agent publishes runtime health to:
  `ops/vps/health/<agent>/status.json`
- Agent continues polling:
  `ops/vps/requests/legacy/`
- Task results are returned to:
  `ops/vps/results/<agent>/<request>/`

After installation, normal troubleshooting should not require screenshots. In ChatGPT, use commands such as:

- `cek koneksi VPS`
- `cek error VPS`
- `ambil log MT5 terbaru`


## Upgrade behavior

v1.2.2 stops any previously running `KatarinaVPSAgent` Scheduled Task before replacing the agent script, removes stale startup/error diagnostic state, recreates the task, and then waits for fresh `ONLINE` health.
