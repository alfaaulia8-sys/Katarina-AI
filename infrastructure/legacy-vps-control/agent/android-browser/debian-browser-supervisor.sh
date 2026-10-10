#!/data/data/com.termux/files/usr/bin/bash
# Read-only liveness guard for the existing Debian GUI/browser.
# Never modifies the Chrome profile, credentials or browser debug bind.
set -u
BASE="$HOME/.katarina-ai/browser-worker"
RUN="$BASE/gui-in-debian.sh"
LOG="$BASE/debian-browser-supervisor.log"
SESSION="katarina-debian-browser"
mkdir -p "$BASE"
if ! command -v tmux >/dev/null 2>&1 || ! command -v proot-distro >/dev/null 2>&1; then
  echo "Missing tmux or proot-distro" >&2
  exit 2
fi
echo "$(date -Iseconds) supervisor started pid=$$" >> "$LOG"
while true; do
  if tmux has-session -t "=$SESSION" 2>/dev/null; then
    if ! curl -fsS --max-time 4 http://127.0.0.1:9223/json/version >/dev/null 2>&1; then
      echo "$(date -Iseconds) browser session exists, but CDP not responding; NOT restarting active session" >> "$LOG"
    fi
  else
    if [ -f "$RUN" ] && [ -f "$HOME/Katarina-VPS-Control/agent/TermuxAgent.py" ]; then
      echo "$(date -Iseconds) restarting missing Debian browser session" >> "$LOG"
      tmux new-session -d -s "$SESSION" "proot-distro login katarina-debian -- /bin/bash \"$RUN\" >> \"$BASE/gui-session.log\" 2>&1" ||
        echo "$(date -Iseconds) browser start failed" >> "$LOG"
    else
      echo "$(date -Iseconds) browser launch script missing; leaving profile untouched" >> "$LOG"
    fi
  fi
  sleep 300
done
