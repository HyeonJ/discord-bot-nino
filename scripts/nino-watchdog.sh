#!/usr/bin/env bash
# nino-watchdog.sh - cron watchdog for enabled backend tmux sessions.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG="$BOT_DIR/logs/watchdog.log"
DISCORD_SEND="$BOT_DIR/src/discord-send"
ALERT_CHANNEL="1479813609499394171"

source "$BOT_DIR/.env" 2>/dev/null || true

CLAUDE_ENABLED="${CLAUDE_ENABLED:-true}"
CODEX_ENABLED="${CODEX_ENABLED:-false}"
CLAUDE_SESSION="${CLAUDE_TMUX_SESSION:-${TMUX_SESSION:-nino}}"
CODEX_SESSION="${CODEX_TMUX_SESSION:-nino-codex}"
LEGACY_CLAUDE_SESSION="${TMUX_SESSION:-nino}"

log() {
  mkdir -p "$(dirname "$LOG")"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"
}

is_enabled() {
  case "$1" in
    true|TRUE|True) return 0 ;;
    *) return 1 ;;
  esac
}

alert() {
  local message="$1"
  $DISCORD_SEND -c "$ALERT_CHANNEL" "$message" 2>/dev/null || true
}

restart_backend() {
  local backend="$1"

  if [ "$backend" = "claude" ] && [ "$CLAUDE_SESSION" = "$LEGACY_CLAUDE_SESSION" ]; then
    "$SCRIPT_DIR/restart-nino.sh" >> "$LOG" 2>&1
  else
    "$SCRIPT_DIR/restart-backend.sh" "$backend" >> "$LOG" 2>&1
  fi
}

check_backend() {
  local backend="$1"
  local session="$2"

  if ! tmux has-session -t "$session" 2>/dev/null; then
    log "DEAD: $backend tmux session '$session' not found. Restarting..."
    restart_backend "$backend"
    alert "$backend backend restarted automatically (tmux session missing)"
    return 1
  fi

  local pane_pid
  pane_pid=$(tmux list-panes -t "$session" -F '#{pane_pid}' 2>/dev/null | head -1)
  if [ -z "$pane_pid" ] || ! kill -0 "$pane_pid" 2>/dev/null; then
    log "DEAD: $backend pane process gone (PID: $pane_pid). Respawning..."
    restart_backend "$backend"
    alert "$backend backend restarted automatically (pane process missing)"
    return 1
  fi

  return 0
}

check_claude_d_state() {
  local session="$1"
  local pane_pid
  pane_pid=$(tmux list-panes -t "$session" -F '#{pane_pid}' 2>/dev/null | head -1)
  if [ -z "$pane_pid" ]; then
    return 0
  fi

  local claude_pid
  claude_pid=$(pgrep -P "$pane_pid" -f "claude" 2>/dev/null | head -1 || true)
  if [ -n "$claude_pid" ]; then
    local state
    state=$(awk '/^State:/{print $2}' /proc/$claude_pid/status 2>/dev/null || echo "?")
    if [ "$state" = "D" ]; then
      log "FROZEN: Claude PID $claude_pid in D state. Restarting..."
      restart_backend "claude"
      alert "claude backend restarted automatically (process D state)"
      return 1
    fi
  fi

  return 0
}

if is_enabled "$CLAUDE_ENABLED"; then
  check_backend "claude" "$CLAUDE_SESSION" || exit 0
  check_claude_d_state "$CLAUDE_SESSION" || exit 0
fi

if is_enabled "$CODEX_ENABLED"; then
  check_backend "codex" "$CODEX_SESSION" || exit 0
fi

exit 0
