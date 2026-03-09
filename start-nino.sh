#!/usr/bin/env bash
# 니노 봇 시작 스크립트 (WSL용)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SESSION_NAME="nino"
LOG_DIR="$SCRIPT_DIR/logs"

mkdir -p "$LOG_DIR"

# tmux 세션이 이미 있으면 종료
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
  echo "[start] Existing session found, killing..."
  tmux kill-session -t "$SESSION_NAME"
fi

# tmux 세션 생성 + Claude Code 실행
tmux new-session -d -s "$SESSION_NAME" -c "$SCRIPT_DIR"
tmux send-keys -t "$SESSION_NAME" "claude --model claude-sonnet-4-6 --dangerously-skip-permissions" C-m

# nvm 로드 (nvm으로 설치한 node 경로 활성화)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

# relay 시작 (백그라운드)
sleep 2
cd "$SCRIPT_DIR"
nohup node discord-relay.js > "$LOG_DIR/nino-relay.log" 2>&1 &
echo $! > "$LOG_DIR/nino-relay.pid"

# Claude Code가 준비될 때까지 대기 후 초기 메시지 전송
sleep 8
TODAY=$(TZ=Asia/Seoul date +%Y-%m-%d)
HISTORY_FILE="$SCRIPT_DIR/memory/discord-history/$TODAY.jsonl"
if [[ -f "$HISTORY_FILE" ]]; then
  tmux send-keys -t "$SESSION_NAME" "새 세션 시작됐어. memory/discord-history/$TODAY.jsonl 읽고 못 봤던 대화 파악해줘." C-m
else
  tmux send-keys -t "$SESSION_NAME" "새 세션 시작됐어. memory/current-tasks.md 읽고 이어서 진행해줘." C-m
fi

echo "[start] 니노 시작 완료! tmux session: $SESSION_NAME"
echo "[start] relay PID: $(cat "$LOG_DIR/nino-relay.pid")"
