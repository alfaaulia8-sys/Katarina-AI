# Katarina AI ChatOps Contract

**Status:** ACTIVE
**Primary legacy agent:** `katarina-vps-2012r2-01`
**Repository:** `alfaaulia-katarina/Katarina-AI`

## Goal

The owner can issue a natural-language command in ChatGPT. ChatGPT translates it into one allowlisted VPS request in GitHub, the VPS executes it, returns redacted evidence to GitHub, and ChatGPT reads and explains the result.

## Natural-language command mapping

| Owner says in chat | VPS task |
|---|---|
| `cek VPS`, `cek koneksi VPS`, `cek environment VPS` | `HOST_INVENTORY` |
| `jalankan test repository`, `test Katarina` | `REPO_STATIC_TESTS` |
| `cek Stage 06 host` | `STAGE06_HOST_CHECK` |
| `compile Stage 06`, `cek compile MT5` | `STAGE06_COMPILE_PROOF` |
| `jalankan clearance Stage 06` | `STAGE06_CLEARANCE` |
| `test Stage 07`, `test komunikasi Python` | `STAGE07_PYTHON_TESTS` |
| `ambil log MT5`, `cek log MT5 terbaru` | `COLLECT_MT5_LOGS` |

## Execution flow

```text
Owner in ChatGPT
  -> ChatGPT creates one request JSON
  -> ops/vps/requests/legacy/
  -> Katarina VPS Agent polls GitHub over outbound HTTPS
  -> fixed allowlisted task runs on VPS
  -> result files are redacted
  -> ops/vps/results/<agent>/<request>/
  -> ChatGPT reads evidence
  -> ChatGPT reports findings and can patch GitHub code if needed
```

## Safety boundaries

- No arbitrary PowerShell supplied by chat.
- No VPS/RDP password in GitHub or ChatGPT.
- No GitHub PAT in GitHub or ChatGPT.
- No broker password in results.
- Production broker mutation is disabled for the current Stage-06 validation path.
- Every request expires.
- Each request must target the configured agent ID.
- Result files are text-only and secret-redacted.

## Operating rule for ChatGPT

For any supported diagnostic/testing command, ChatGPT should:
1. create a fresh request JSON with a unique request ID;
2. target `katarina-vps-2012r2-01` unless the owner specifies another registered agent;
3. use the current `main` ref unless a different ref is explicitly needed;
4. read the matching result folder when available;
5. use returned evidence rather than guessing VPS state;
6. never request or expose the VPS password, GitHub PAT, broker password, or private API secrets.
