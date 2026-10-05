#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
export PYTHONPATH="$ROOT/src"

echo "[1/5] Python compile"
python -m compileall -q src

echo "[2/5] Unit regression"
python -m unittest discover -s tests/unit -p 'test_*.py'

echo "[3/5] Stage 10 local audit"
python scripts/stage10/audit_stage10_final.py   --repo-root .   --output build/stage10/stage10_local_final_clearance.json   >/dev/null

echo "[4/5] Stage 11-40 framework audit"
python scripts/body/audit_body_framework.py   --repo-root .   --output build/body/body_framework_audit.json   >/dev/null

echo "[5/5] Stage 10-40 functional body audit"
python scripts/body/audit_functional_body.py   --repo-root .   --output build/body/katarina_body_local_clearance.json

echo "PASS_KATARINA_BODY_VERIFY"
