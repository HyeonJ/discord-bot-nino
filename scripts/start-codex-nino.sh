#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
instructions_file="${CODEX_INSTRUCTIONS_FILE:-$BOT_DIR/codex-config/NINO_CODEX.md}"

if [[ -f "$instructions_file" ]]; then
  prompt="$(cat "$instructions_file")"
else
  prompt='You are Nino powered by Codex. Use /home/bpx27/discord-bot-nino/src/discord-send -c CHANNEL_ID -r MESSAGE_ID "your reply" for Discord replies.'
fi

exec codex --no-alt-screen --dangerously-bypass-approvals-and-sandbox "$prompt"
