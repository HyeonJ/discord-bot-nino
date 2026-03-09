#!/usr/bin/env bash
# 니노 봇 시작 스크립트 (WSL용)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SESSION_NAME="nino"

# tmux 세션이 이미 있으면 종료
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
  echo "[start] Existing session found, killing..."
  tmux kill-session -t "$SESSION_NAME"
fi

# tmux 세션 생성 + Claude Code 실행
tmux new-session -d -s "$SESSION_NAME" -c "$SCRIPT_DIR"
tmux send-keys -t "$SESSION_NAME" "claude --model claude-sonnet-4-6 --dangerously-skip-permissions" C-m

# relay 시작 (백그라운드)
sleep 2
cd "$SCRIPT_DIR"
nohup node discord-relay.js > /tmp/nino-relay.log 2>&1 &
echo $! > /tmp/nino-relay.pid

echo "[start] 니노 시작 완료! tmux session: $SESSION_NAME"
echo "[start] relay PID: $(cat /tmp/nino-relay.pid)"
