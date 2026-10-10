# KATARINA Unified Control (VPS + Termux)

This is the **existing** private control-plane repository for KATARINA. It now holds **one shared connection** for two separate runtimes: the existing Windows VPS and a future Android Termux device.

## Single connection
- `connection.json` — one file naming the same repository, polling cadence, and both devices.
- `jobs/` — one shared queue. Each job declares `target: "vps"` or `target: "termux"`. Legacy un-targeted jobs remain VPS-only.
- `results/` — responses for each job.
- `status/vps.json` and `status/termux.json` — independent heartbeats.

## Agents
- `agent/KatarinaVPSAgent.ps1` — Windows VPS agent, launched by the existing `KatarinaVPSControlAgent` scheduled task.
- `agent/TermuxAgent.py` — Android Termux agent, install directions at [TERMUX-CONNECTION.md](TERMUX-CONNECTION.md).

Both agents read **the same** `connection.json`. No second bridge, VPS agent, or public SSH port is needed. Each device authenticates to GitHub separately.

## Safety model
- No passwords, API tokens, private keys, or session cookies are committed.
- Only explicitly supported/allowlisted operations are executable.
- The agents **do not run shell commands taken from job files**.
- Existing VPS recovery methods remain available independently.
- Remote Chrome debugging stays local to the device and requires user pairing.
- Job automation on websites must comply with platform rules.

## Connection status
VPS: connected (existing).
Termux: prepared but **not connected until it authenticates and publishes `status/termux.json`**.
