#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

REPO="alfaaulia-katarina/Katarina-AI"
ROOT="$HOME/.katarina-ai"
PROJECT="$ROOT/project/katarina-ai"
PREFIX_BIN="${PREFIX:-/data/data/com.termux/files/usr}/bin"

echo "[1/6] Install dependencies"
pkg install -y python git gh curl nodejs >/dev/null

echo "[2/6] Check GitHub authentication"
if ! gh auth status >/dev/null 2>&1; then
  echo "AUTH_REQUIRED"
  echo "Run: gh auth login"
  echo "Then run this installer again."
  exit 3
fi

echo "[3/6] Prepare local KATARINA AI workspace"
mkdir -p "$ROOT/project" "$ROOT/bridge/run" "$ROOT/bridge/logs" "$ROOT/bridge/state"
if [ -d "$PROJECT/.git" ]; then
  git -C "$PROJECT" fetch origin main
  git -C "$PROJECT" checkout main
  git -C "$PROJECT" pull --ff-only origin main
else
  rm -rf "$PROJECT"
  gh repo clone "$REPO" "$PROJECT"
fi

echo "[4/6] Install bridge command"
chmod +x "$PROJECT/ops/bridge/katarina-bridge.sh" "$PROJECT/ops/bridge/katarina_agent.py"
ln -sf "$PROJECT/ops/bridge/katarina-bridge.sh" "$PREFIX_BIN/katarina-bridge"

echo "[5/6] Start bridge"
termux-wake-lock >/dev/null 2>&1 || true
katarina-bridge restart

echo "[6/6] Verify"
sleep 2
katarina-bridge status
echo "KATARINA_BRIDGE_READY"
