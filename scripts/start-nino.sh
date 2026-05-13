#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$BOT_DIR/logs"
STARTUP_LOG="$LOG_DIR/startup.log"
LOCK_FILE="$LOG_DIR/start-nino.lock"

mkdir -p "$LOG_DIR"

exec 9>"$LOCK_FILE"
if command -v flock >/dev/null 2>&1; then
  if ! flock -n 9; then
    echo "[start] another start-nino run is already active"
    exit 0
  fi
fi

exec > >(while IFS= read -r line; do printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$line"; done | tee -a "$STARTUP_LOG") 2>&1

is_enabled() {
  case "${1:-}" in
    true|TRUE|True|1|yes|YES|Yes) return 0 ;;
    *) return 1 ;;
  esac
}

session_exists() {
  local session="$1"
  tmux has-session -t "=$session" 2>/dev/null
}

echo "[start] starting Nino from $BOT_DIR"

cd "$BOT_DIR"
find .git/objects -type f -empty -delete 2>/dev/null || true
if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
  echo "[start] uncommitted changes detected; skipping git pull"
else
  git pull --ff-only 2>&1 | tail -1 || echo "[start] git pull failed; continuing with current checkout"
fi
echo "[start] current commit: $(git log --oneline -1 2>/dev/null || echo unknown)"

if [[ -f "$BOT_DIR/.env" ]]; then
  set -a
  source "$BOT_DIR/.env"
  set +a
fi

CLAUDE_ENABLED="${CLAUDE_ENABLED:-true}"
CODEX_ENABLED="${CODEX_ENABLED:-false}"
CLAUDE_SESSION="${CLAUDE_TMUX_SESSION:-${TMUX_SESSION:-nino}}"
CODEX_SESSION="${CODEX_TMUX_SESSION:-nino-codex}"

CLAUDE_EXISTED=false
if session_exists "$CLAUDE_SESSION"; then
  CLAUDE_EXISTED=true
fi

if is_enabled "$CLAUDE_ENABLED"; then
  "$SCRIPT_DIR/start-backend.sh" claude
else
  echo "[start] Claude backend disabled"
fi

if is_enabled "$CODEX_ENABLED"; then
  "$SCRIPT_DIR/start-backend.sh" codex
else
  echo "[start] Codex backend disabled"
fi

sleep "${BACKEND_STARTUP_GRACE_SECONDS:-5}"

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if command -v systemctl >/dev/null 2>&1; then
  systemctl --user restart nino-relay.service
  echo "[start] relay restarted via systemd user service"
else
  echo "[start] systemctl not found; relay restart skipped"
fi

if is_enabled "$CLAUDE_ENABLED" && [[ "$CLAUDE_EXISTED" == "false" ]]; then
  sleep 3
  TODAY="$(TZ=Asia/Seoul date +%Y-%m-%d)"
  HISTORY_FILE="$BOT_DIR/memory/discord-history/$TODAY.jsonl"
  if [[ -f "$HISTORY_FILE" ]]; then
    tmux send-keys -t "=$CLAUDE_SESSION:" "새 세션 시작됐어. 봇-놀이터(1480479067881865347)에 '니노 재부팅했어' 보내줘. 그리고 memory/discord-history/$TODAY.jsonl 읽고 못 봤던 대화 파악해줘." C-m || true
  else
    tmux send-keys -t "=$CLAUDE_SESSION:" "새 세션 시작됐어. 봇-놀이터(1480479067881865347)에 '니노 재부팅했어' 보내줘. 그리고 memory/current-tasks.md 읽고 이어서 진행해줘." C-m || true
  fi
fi

echo "[start] Nino startup complete. claude=$CLAUDE_ENABLED codex=$CODEX_ENABLED"
