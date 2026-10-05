#!/data/data/com.termux/files/usr/bin/bash
set -u
ROOT="$HOME/.katarina-ai"
PROJECT="${KATARINA_PROJECT_DIR:-$ROOT/project/katarina-ai}"
BRIDGE="$ROOT/bridge"
RUN="$BRIDGE/run"
LOGS="$BRIDGE/logs"
STATE="$BRIDGE/state"
AGENT="$PROJECT/ops/bridge/katarina_agent.py"
PIDFILE="$RUN/agent.pid"
WATCHPID="$RUN/watchdog.pid"
WATCHLOG="$LOGS/watchdog.log"
mkdir -p "$RUN" "$LOGS" "$STATE"

agent_alive() {
  [ -f "$PIDFILE" ] || return 1
  p="$(cat "$PIDFILE" 2>/dev/null || true)"
  [ -n "$p" ] && kill -0 "$p" 2>/dev/null
}

watch_alive() {
  [ -f "$WATCHPID" ] || return 1
  p="$(cat "$WATCHPID" 2>/dev/null || true)"
  [ -n "$p" ] && kill -0 "$p" 2>/dev/null
}

start_agent_once() {
  if agent_alive; then return 0; fi
  rm -f "$STATE/agent.lock"
  nohup python "$AGENT" >>"$LOGS/agent-supervisor.log" 2>&1 &
  echo $! > "$PIDFILE"
}

watch_loop() {
  termux-wake-lock >/dev/null 2>&1 || true
  while true; do
    if ! agent_alive; then
      printf '[%s] restarting agent\n' "$(date -Iseconds)" >>"$WATCHLOG"
      start_agent_once
    fi
    sleep 15
  done
}

case "${1:-status}" in
  start)
    if [ ! -f "$AGENT" ]; then echo "Agent not found: $AGENT"; exit 2; fi
    if ! gh auth status >/dev/null 2>&1; then
      echo "AUTH_REQUIRED"
      echo "Run: gh auth login"
      exit 3
    fi
    start_agent_once
    if ! watch_alive; then
      nohup "$0" _watch >>"$WATCHLOG" 2>&1 &
      echo $! > "$WATCHPID"
    fi
    sleep 1
    "$0" status
    ;;
  _watch)
    watch_loop
    ;;
  stop)
    if watch_alive; then kill "$(cat "$WATCHPID")" 2>/dev/null || true; fi
    if agent_alive; then kill "$(cat "$PIDFILE")" 2>/dev/null || true; fi
    rm -f "$WATCHPID" "$PIDFILE" "$STATE/agent.lock"
    termux-wake-unlock >/dev/null 2>&1 || true
    echo "KATARINA bridge stopped"
    ;;
  restart)
    "$0" stop
    sleep 1
    "$0" start
    ;;
  status)
    if agent_alive; then echo "AGENT=RUNNING PID=$(cat "$PIDFILE")"; else echo "AGENT=STOPPED"; fi
    if watch_alive; then echo "WATCHDOG=RUNNING PID=$(cat "$WATCHPID")"; else echo "WATCHDOG=STOPPED"; fi
    echo "PROJECT=$PROJECT"
    echo "LOG=$LOGS/agent.log"
    ;;
  logs)
    tail -n "${2:-80}" "$LOGS/agent.log" 2>/dev/null || true
    ;;
  *)
    echo "Usage: katarina-bridge {start|stop|restart|status|logs}"
    exit 2
    ;;
esac
