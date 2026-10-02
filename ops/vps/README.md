# Katarina VPS Operations Queue

This directory is the repository-side relay for controlled VPS testing and telemetry.

Queues:

- `requests/legacy/` — Windows Server 2012 R2 PowerShell agent.
- `requests/actions/` — modern Windows GitHub Actions self-hosted runner.
- `results/` — text evidence returned by the legacy agent.

Do not place passwords, PATs, RDP credentials, API keys, or broker credentials here.

Requests contain only an allowlisted task ID, target agent, expiry, ref, and task arguments.