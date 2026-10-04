# KATARINA AI — VPS-First Development Workflow

Status: ACTIVE / USER-APPROVED
Effective: 2026-10-04

All non-final development happens in C:\KatarinaDev\workspace on the VPS.

GitHub is limited to:
- command-bus requests to the VPS;
- compact logs/evidence returned from the VPS;
- canonical source commits only after the result is final and approved.

Normal iteration target:
- one request write;
- one compact result write;
- zero source commits.

WORKSPACE_APPLY accepts an allowlisted local changeset and can run up to eight batched checks in the same request.
Intermediate failures remain local to the VPS workspace and do not modify canonical source history.
Live-risk permissions are unchanged.