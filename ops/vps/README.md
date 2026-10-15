# Katarina VPS Operations Queue

This directory is the repository-side relay for controlled VPS testing and telemetry.

Queues:

- `requests/legacy/` — Windows Server 2012 R2 PowerShell agent.
- `requests/actions/` — modern Windows GitHub Actions self-hosted runner.
- `results/` — text evidence returned by the legacy agent.

Do not place passwords, PATs, RDP credentials, API keys, or broker credentials here.

Requests contain only an allowlisted task ID, target agent, expiry, ref, and task arguments.
## Active operating rule (2026-10-10)

GitHub Actions is the default development/test environment. This path exists only for **explicitly justified VPS-only verification** following a validated GitHub commit. Old request payloads and historical bootstrap logs were removed from the source tree; they remain recoverable from pre-cleanup Git history. Do not enqueue or replay older commands. See [GitHub-First Development](../../docs/operations/GITHUB_FIRST_DEVELOPMENT.md) and [Cleanup record](../../docs/operations/REPOSITORY_CLEANUP_2026-10-10.md).

## Runtime health snapshots

`health/<agent>/status.json` is runtime telemetry, not a checked-in health assertion.
The four stale October 4–8 snapshots were removed on 2026-10-15.
An absent snapshot means UNKNOWN, not ONLINE or ERROR. Obtain fresh, timestamped
evidence through the existing verification gate before describing VPS health.
