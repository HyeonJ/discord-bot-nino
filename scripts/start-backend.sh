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
    ;;
  codex)
    SESSION="${CODEX_TMUX_SESSION:-nino-codex}"
    COMMAND="\"$SCRIPT_DIR/start-codex-nino.sh\""
    ;;
  *)
    usage
    exit 2
    ;;
esac

if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "[start-backend] Existing $BACKEND session '$SESSION' found, killing..."
  tmux kill-session -t "$SESSION"
fi

tmux new-session -d -s "$SESSION" -c "$BOT_DIR" -e "ALARM_TOOL_SESSION=$SESSION"
tmux send-keys -t "$SESSION" "$COMMAND" C-m

echo "[start-backend] Started $BACKEND backend in tmux session: $SESSION"
