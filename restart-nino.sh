#!/usr/bin/env bash
# 니노 봇 재시작 스크립트
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SESSION_NAME="nino"
RELAY_PID_FILE="$SCRIPT_DIR/logs/nino-relay.pid"

# relay 일시정지 (경합 방지)
if [[ -f "$RELAY_PID_FILE" ]]; then
  RELAY_PID=$(cat "$RELAY_PID_FILE")
  if kill -0 "$RELAY_PID" 2>/dev/null; then
    kill -STOP "$RELAY_PID"
    echo "[restart] relay paused (PID: $RELAY_PID)"
  fi
fi

# Claude Code 세션 재시작
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
  tmux respawn-pane -k -t "$SESSION_NAME" "cd $SCRIPT_DIR && claude config set autoCompact true 2>/dev/null; claude --model claude-sonnet-4-6 --dangerously-skip-permissions"
  echo "[restart] Claude Code restarted"
else
  echo "[restart] No session found, starting fresh..."
  "$SCRIPT_DIR/start-nino.sh"
  exit 0
fi

# relay 재개
sleep 2
if [[ -f "$RELAY_PID_FILE" ]]; then
  RELAY_PID=$(cat "$RELAY_PID_FILE")
  if kill -0 "$RELAY_PID" 2>/dev/null; then
    kill -CONT "$RELAY_PID"
    echo "[restart] relay resumed"
  fi
fi

echo "[restart] 니노 재시작 완료!"
