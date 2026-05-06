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

send_codex_bootstrap() {
  local prompt
  prompt="$(cat <<'EOF'
You are Nino's Codex backend inside a tmux session.

Discord relay messages arrive as payloads that may include [C:CHANNEL_ID] and [M:MESSAGE_ID].
When a user asks you to respond in Discord, send the response with:

src/discord-send -c CHANNEL_ID -r MESSAGE_ID "your reply"

Use the CHANNEL_ID from [C:...] when present. If [C:...] is absent, use the default channel by omitting -c.
Use the MESSAGE_ID from [M:...] with -r so the Discord reply threads correctly.
Do not only print the answer in tmux when the user clearly expects a Discord response.
EOF
)"
  sleep "${CODEX_BOOTSTRAP_DELAY_SECONDS:-3}"
  tmux send-keys -t "$SESSION" -- "$prompt"
  sleep "${CODEX_BOOTSTRAP_SUBMIT_DELAY_SECONDS:-5}"
  tmux send-keys -t "$SESSION" C-m
}

case "$BACKEND" in
  claude)
    SESSION="${CLAUDE_TMUX_SESSION:-${TMUX_SESSION:-nino}}"
    COMMAND="claude --model claude-opus-4-6 --dangerously-skip-permissions"
    ;;
  codex)
    SESSION="${CODEX_TMUX_SESSION:-nino-codex}"
    COMMAND="codex --no-alt-screen --dangerously-bypass-approvals-and-sandbox"
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

if [[ "$BACKEND" == "codex" ]]; then
  send_codex_bootstrap
fi

echo "[start-backend] Started $BACKEND backend in tmux session: $SESSION"
