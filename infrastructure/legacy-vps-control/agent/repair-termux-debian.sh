#!/data/data/com.termux/files/usr/bin/bash
# KATARINA: safe Termux + Debian recovery (no reinstall or data deletion).
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SESSION="katarina-bridge"
STATE="$HOME/.katarina-unified-bridge"
LOG="$STATE/termux-agent.log"
mkdir -p "$STATE"
printf '\n[KATARINA] Termux / Debian recovery\n'
if [[ "${PREFIX:-}" != *"/com.termux/files/usr"* ]]; then
  echo '[ERROR] Run this script in the main Termux shell, not inside Debian.'
  exit 2
fi
for tool in git python tmux; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "[ERROR] Missing $tool. Install with: pkg install git python tmux"
    exit 2
  fi
done
if [ ! -d "$ROOT/.git" ]; then
  echo '[ERROR] Expected existing Katarina-VPS-Control Git checkout.'
  exit 2
fi
cd "$ROOT" || exit 2
echo '[1/5] Checking GitHub access'
if ! git ls-remote --exit-code origin refs/heads/main >/dev/null 2>&1; then
  echo '[ERROR] GitHub access not ready. In Termux use: gh auth login'
  echo 'Then run: gh auth setup-git'
  echo 'Never share login tokens or codes in ChatGPT.'
  exit 3
fi
echo '[2/5] Stopping only the named KATARINA bridge session'
if tmux has-session -t "=$SESSION" 2>/dev/null; then
  tmux kill-session -t "=$SESSION" || { echo '[ERROR] Could not stop named session'; exit 3; }
  echo '[OK] Old katarina-bridge session stopped'
else
  echo '[OK] No old katarina-bridge tmux session'
fi
echo '[3/5] Synchronizing safely (preserve local changes)'
# A run first publishes pending owned results; never reset or clean the repo.
if ! python agent/TermuxAgent.py --once; then
  echo '[ERROR] One-shot bridge failed; check Git authentication and local changes.'
  echo 'Diagnostics: git status --short'
  exit 4
fi
if ! git pull --ff-only origin main; then
  echo '[ERROR] Fast-forward pull unavailable. Local files left untouched.'
  echo 'Diagnostics: git status --short'
  exit 4
fi
# New agent has an OS file lock to prevent parallel command processors.
if command -v termux-wake-lock >/dev/null 2>&1; then
  termux-wake-lock >/dev/null 2>&1 || true
fi
echo '[4/5] Starting exactly one bridge session'
if ! tmux new-session -d -s "$SESSION" "cd \"$ROOT\" && exec python agent/TermuxAgent.py >> \"$LOG\" 2>&1"; then
  echo '[ERROR] Cannot start the KATARINA bridge tmux session'
  exit 5
fi
sleep 3
if ! tmux has-session -t "=$SESSION" 2>/dev/null; then
  echo '[ERROR] Bridge exited; inspect ~/.katarina-unified-bridge/termux-agent.log'
  exit 5
fi
echo '[OK] KATARINA bridge active; logs remain on this phone'
echo '[5/5] Checking existing Debian installation, read-only'
if ! command -v proot-distro >/dev/null 2>&1; then
  echo '[DEBIAN] proot-distro is not available; to add tool: pkg install proot-distro'
elif proot-distro login katarina-debian -- /bin/sh -c "test -f /etc/debian_version && printf 'DEBIAN_READY'" 2>/dev/null | grep -q '^DEBIAN_READY$'; then
  echo '[DEBIAN] Existing Debian entered successfully'
else
  echo '[DEBIAN] Not ready or not installed; run: proot-distro list'
  echo 'No Debian files were removed or reinstalled.'
fi
echo '[DONE] Recheck status/termux.json and results/termux-debian-health-20261009.termux.json on GitHub.'
