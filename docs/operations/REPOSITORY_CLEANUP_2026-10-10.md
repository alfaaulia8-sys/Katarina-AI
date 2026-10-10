# Repository Cleanup — 2026-10-10

Scope: `alfaaulia8-sys/Katarina-AI`. GitHub-first development; no VPS operation was requested or executed for this cleanup.

## Baseline and rollback

- Pre-cleanup `main` commit: `5a51a58414945eb1c4be0ba7777d723e16a9e284`
- Baseline tracked files: **771**
- Deleted from current source tree: **239 files** (**165,379 bytes** of tracked blob content, not Git history).
- Git history remains intact. To restore a file, recover its original path from commit `5a51a58414945eb1c4be0ba7777d723e16a9e284` via a new review branch. This cleanup does **not** claim to erase data from public Git history.

## Deleted paths

| Category | Count | Reason |
| --- | ---: | --- |
| `ops/vps/requests/**/*.json` | 187 | Completed/old 2026-10-03–07 queue requests, no longer valid as active tasks |
| `ops/vps/bootstrap/**` | 22 | Generated installer logs, summaries, and error evidence; retained in Git history |
| `ops/vps/rescue/*.trigger` | 3 | One-off rescue triggers; automatic VPS workflow triggers were retired |
| `infrastructure/legacy-vps-control/**` | 25 | Duplicate source-reference import; canonical older control repository/history remains separately managed |
| `docs/operations/VPS_FIRST_DEVELOPMENT.md` | 1 | Contradicts active [GitHub-first operating policy](GITHUB_FIRST_DEVELOPMENT.md) |
| `ops/bridge/CONTROL_TEST.txt` | 1 | One-off connectivity probe marker |
| **Total** | **239** | |

## Explicitly retained

- Constitution, source code, `config/`, KAT1 protocol, MQL5, test suites and GitHub workflow definitions;
- reviewed architecture documents and Stage 01–40 evidence/freeze records;
- active adapter/bridge scripts (even if only used for optional external validation);
- `ops/vps/requests/*/README.md`, templates and `ops/vps/health/` operational status paths;
- `vps_bridge/control.json`, which legacy support tooling may still read;
- `oauth_gateway/` and root helper batch scripts pending separate integration review.

Nothing was deleted directly on any Windows VPS. Deleting source-tree copies from this **public** repository cannot retract already published files/paths from historical Git objects, archives or forks.

## Prevention

The GitHub-hosted `KATARINA Body CI` runs the repository-hygiene guard. It rejects obsolete artifacts, invalid/expired queued requests, and reintroduced legacy-import files. Valid new, explicitly reviewed requests can still be committed with a future expiration; normal activity must be cleaned from the canonical branch when finished.

Any further source/dependency cleanup should follow a separate PR and full CI regression, not guess whether a runtime module is unused.
