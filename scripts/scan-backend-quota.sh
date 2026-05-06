#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
backend="${1:-}"
session="${2:-}"
until="${QUOTA_COOLDOWN_UNTIL:-}"
patterns="${BACKEND_QUOTA_PATTERNS:-usage limit reached|rate limit|quota exceeded|limit reached|try again later|too many requests|insufficient_quota}"

usage() {
  echo "Usage: $0 <backend> <tmux-session>" >&2
}

if [[ -z "$backend" || -z "$session" ]]; then
  usage
  exit 2
fi

if ! tmux has-session -t "$session" 2>/dev/null; then
  exit 0
fi

captured="$(tmux capture-pane -t "$session" -p -S -120 2>/dev/null || true)"
if echo "$captured" | grep -Eiq "$patterns"; then
  "$SCRIPT_DIR/backend-status.sh" set "$backend" quota_exhausted "quota pattern detected in tmux session $session" "$until"
  exit 1
fi

exit 0
