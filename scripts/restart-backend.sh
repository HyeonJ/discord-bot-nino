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
    COMMAND="claude --model claude-opus-4-6 --dangerously-skip-permissions --continue"
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

TMUX_TARGET="=$SESSION"
TMUX_PANE_TARGET="=$SESSION:"

if tmux has-session -t "$TMUX_TARGET" 2>/dev/null; then
  tmux respawn-pane -k -t "$TMUX_PANE_TARGET" "cd \"$BOT_DIR\" && $COMMAND"
  echo "[restart-backend] Restarted $BACKEND backend in tmux session: $SESSION"
else
  echo "[restart-backend] No $BACKEND session '$SESSION' found, starting fresh..."
  "$SCRIPT_DIR/start-backend.sh" "$BACKEND"
fi
