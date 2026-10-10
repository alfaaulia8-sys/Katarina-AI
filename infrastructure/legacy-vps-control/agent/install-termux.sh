#!/data/data/com.termux/files/usr/bin/bash
# Run after cloning Katarina-VPS-Control on Termux.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
command -v git >/dev/null || { echo 'Install git: pkg install git'; exit 1; }
command -v python >/dev/null || { echo 'Install python: pkg install python'; exit 1; }
git remote -v
python agent/TermuxAgent.py --once
echo
echo 'Start continuously when ready:'
echo "  cd '$ROOT' && tmux new-session -d -s katarina-bridge 'python agent/TermuxAgent.py'"
echo "Watch log in a tmux session: tmux attach -t katarina-bridge"
echo 'Requires valid GitHub authentication with write access to the private repository.'
