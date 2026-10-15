# Repository cleanup and source synchronization — 2026-10-15

Scope: `alfaauliau-katarinaAI/Katarina-AI`, based on main
`76392ee7c099fb63c9bdec09ed4c000f0e924b5f`. This is a source audit,
not a current VPS health or deployment assertion.

## Findings and changes

- Audited all 1,139 tracked files before editing. Repository hygiene and local
  dependency audits passed: 578 Python files, 145 JSON files, 261 internal
  Python imports, 105 MQL includes and 319 website links.
- Corrected the old `alfaaulia8-sys/Katarina-AI` repository default in project
  identity, Termux bridge, VPS workspace/remote recovery tasks, and legacy
  installers. The canonical owner is now `alfaauliau-katarinaAI` everywhere
  in executable source and configuration. Existing explicit environment or
  installation overrides are preserved; no installer or bridge was run.
- Deleted four committed VPS status snapshots dated October 4–8. Three said
  ONLINE and one ERROR; none represented current health. Absent telemetry is
  UNKNOWN. Ignore rules and the repository hygiene guard prevent recommitting
  these heartbeat paths. A dedicated regression covers this boundary.
- Moved the unchanged historical chat checkpoint into
  `docs/handoff/KATARINA_START_NEXT_CHAT_20261013.md`, updating its two known
  references. Moved the unchanged Cloudflare setup guide into
  `docs/deployment/CLOUDFLARE_PAGES_SETUP.md`. README links locate both.
- Added a source consistency regression covering canonical repository identity
  and all seven installer/bridge source files with explicit defaults.

## Preserved intentionally

The legacy VPS agent is still referenced by recovery/workspace tasks and static
regressions. It is not dead code. Research outputs, fixtures, models and
strategy modules are retained: filenames or apparently unused imports do not
prove these are disposable. Two pairs of byte-identical research CSVs remain
as separately named experiment evidence.

The preceding guarded branch cleanup removed 10 strict ancestors and retained
42 divergent branches, two branches identical to main, and main itself. Its
closing dry-run had no candidates. No unique branch history is overwritten or
merged as part of this file cleanup.

No edits to trading strategies, Risk Governor, execution authorization, broker
settings, live orders, hosting, or running VPS services. No new queue request,
agent, scheduled task or workflow is activated by this change.

## Validation and synchronization boundary

Run Python compilation, unit/static/integration regression suites, repository
hygiene, dependency links, unified registry, Constitution Guard, Stage 10,
Stage 11–40 framework/functional audits, and KATARINA Body CI on the change.
Inspect actual CI on the PR before merging. Local results and hosted run URLs
are recorded in the pull request.

A clean checkout can be synchronized with the resulting main commit. An
existing private VPS checkout is not declared synchronized without checking
its actual HEAD, local changes, deployment paths, and running process source.
