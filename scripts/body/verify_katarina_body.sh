#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
export PYTHONPATH="$ROOT/src"

echo "[1/11] Python compile"
python -m compileall -q src

echo "[2/11] Unit regression"
python -m unittest discover -s tests/unit -p 'test_*.py'

echo "[3/11] Stage 10 local audit"
python scripts/stage10/audit_stage10_final.py --repo-root . --output build/stage10/stage10_local_final_clearance.json >/dev/null

echo "[4/11] Constitution Guard"
python scripts/governance/audit_constitution_guard.py --repo-root . --output build/governance/constitution_guard.json >/dev/null

echo "[5/11] Stage 11-40 framework audit"
python scripts/body/audit_body_framework.py --repo-root . --output build/body/body_framework_audit.json >/dev/null

echo "[6/11] Stage 10-40 functional body audit"
python scripts/body/audit_functional_body.py --repo-root . --output build/body/katarina_body_local_clearance.json

echo "[7/11] Cross-stage fail-closed audit"
python scripts/body/audit_cross_stage_pipeline.py

echo "[8/11] Stage 35 headless tester static audit"
python -m unittest -q tests.static.test_stage35_tester_runner

echo "[9/11] QEMU Windows postinstall static audit"
python -m unittest -q tests.static.test_qemu_windows_postinstall

echo "[10/11] Stage 36 live-environment preflight static audit"
python -m unittest -q tests.static.test_stage36_live_preflight

echo "[11/11] Windows error-supervisor static audit"
python -m unittest -q tests.static.test_windows_error_supervisor

echo "PASS_KATARINA_BODY_VERIFY"
