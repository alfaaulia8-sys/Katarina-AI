# Repository security and unified-brain source audit — 2026-10-15

Source baseline: `cb0c66da41c53168c337b18fb0f8fde4f5c7543e`.
Scope is the public GitHub repository and the tested development checkout.
Public visibility permits reading/forking; it does not grant upstream write access.

## Account settings verified in GitHub

- Zero additional collaborators; only the repository owner has direct access.
- Issue and PR creation restricted to collaborators. Existing installed apps
  retain their authorized scopes; no external account was granted new access.
- Main branch protection: PR required, GitHub Actions `body` check required,
  branch up to date, conversations resolved, administrator enforcement enabled,
  force pushes and deletions disabled. Zero independent approvals are required
  because the sole owner cannot approve their own PR. CODEOWNERS identifies the
  actual owner, not the former account name.
- Default workflow token read-only; workflow PR creation/approval disabled;
  all external fork contributors require approval.
- Remote Actions allowlist: checkout, setup-python, upload-artifact,
  download-artifact and ai-inference from actions/*. Workflow source pins all
  five to full commit SHAs resolved from their official upstream Git tags.
- Private vulnerability reporting, dependency graph, Dependabot alerts,
  Secret Protection and push protection enabled. Detection does not certify that
  the repository or its history contains no vulnerabilities or exposed secrets.

## Workflow corrections

Retain stage/research workflows as manual diagnostics: several are referenced by
regression tests and are not proven obsolete. Remove two redundant workflow
sub-dispatches from Body CI and its `actions: write` permission. The existing
inventory job performs its read-only audit directly. Required Body CI runs on
every PR, including documentation-only changes, to avoid pending required checks.

All workflows explicitly default to contents-read, all checkout steps drop
persisted credentials, and all external Actions are pinned. Scheduled news
continues fetching public sources but stores an artifact for reviewed publication
instead of pushing directly to protected main. No actor receives a bypass token.

Guarded cleanup is serialized, manual-main-only, capped at ten deletions, and
rechecks SHA, protection, ancestry and active PR head/base branches immediately
before deletion. All branch pages are collected before deletion to avoid mutable
pagination skipping branches. Unique/divergent branches remain unmerged and are
not force-synchronized or discarded.

## Unified brain boundary

`config/katarina_unified_v1.json` remains the canonical ten-component registry.
`scripts/ai/verify_unified_katarina.py` successfully constructs and verifies the
existing offline stack and produces module SHA256 fingerprints. Source under
`src/`, `mt5/`, and risk/strategy configuration is unchanged by this hardening.
The ten fingerprints match the baseline; orders submitted = 0 and live execution
remains false. VPS deployed files, process source and private memory DB are not
verified by a GitHub-only run. No broker connection, service restart or live
activation occurs in this work.

Validation: full unit/static/integration suites plus hosted Body CI are required.
The PR and Actions receipts record actual check results and commit IDs. New
regressions cover pinned Actions, token restrictions, owner identity, active PR
protection, moved branch SHA and no-delete dry-run behavior.
