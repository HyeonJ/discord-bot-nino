#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BACKEND="${1:-}"

if [[ -f "$BOT_DIR/.env" ]]; then
  set -a
  source "$BOT_DIR/.env"
  set +a
fi

usage() {
  echo "Usage: $0 <claude|codex>" >&2
}

case "$BACKEND" in
  claude)
    SESSION="${CLAUDE_TMUX_SESSION:-${TMUX_SESSION:-nino}}"
    COMMAND="claude --model claude-opus-4-6 --dangerously-skip-permissions"
    EXPECTED_COMMANDS=("claude")
    EXPECTED_PATTERN="claude"
    ;;
  codex)
    SESSION="${CODEX_TMUX_SESSION:-nino-codex}"
    COMMAND="\"$SCRIPT_DIR/start-codex-nino.sh\""
    EXPECTED_COMMANDS=("codex" "node")
    EXPECTED_PATTERN="codex"
    ;;
  *)
    usage
    exit 2
    ;;
esac

TMUX_TARGET="=$SESSION"
TMUX_PANE_TARGET="=$SESSION:"

session_is_alive() {
  tmux has-session -t "$TMUX_TARGET" 2>/dev/null || return 1

  local pane_pid pane_command pane_args child_pid expected
  pane_pid="$(tmux list-panes -t "$TMUX_TARGET" -F '#{pane_pid}' 2>/dev/null | head -1)"
  pane_command="$(tmux list-panes -t "$TMUX_TARGET" -F '#{pane_current_command}' 2>/dev/null | head -1)"

  [[ -n "$pane_pid" ]] || return 1
  kill -0 "$pane_pid" 2>/dev/null || return 1

  for expected in "${EXPECTED_COMMANDS[@]}"; do
    if [[ "$pane_command" == "$expected" ]]; then
      return 0
    fi
  done

  pane_args="$(ps -p "$pane_pid" -o args= 2>/dev/null || true)"
  if [[ "$pane_args" == *"$EXPECTED_PATTERN"* ]]; then
    return 0
  fi

  child_pid="$(pgrep -P "$pane_pid" -f "$EXPECTED_PATTERN" 2>/dev/null | head -1 || true)"
  [[ -n "$child_pid" ]]
}

if tmux has-session -t "$TMUX_TARGET" 2>/dev/null; then
  if session_is_alive; then
    echo "[start-backend] $BACKEND backend already alive in tmux session: $SESSION"
    exit 0
  fi

  echo "[start-backend] Existing $BACKEND session '$SESSION' is not healthy, recreating..."
  tmux kill-session -t "$TMUX_TARGET"
fi

tmux new-session -d -s "$SESSION" -c "$BOT_DIR" -e "ALARM_TOOL_SESSION=$SESSION"
tmux send-keys -t "$TMUX_PANE_TARGET" "$COMMAND" C-m

echo "[start-backend] Started $BACKEND backend in tmux session: $SESSION"
