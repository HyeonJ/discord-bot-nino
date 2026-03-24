#!/usr/bin/env bash
# 니노 봇 재시작 스크립트
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SESSION_NAME="nino"

# relay 일시정지 (경합 방지)
export XDG_RUNTIME_DIR=/run/user/$(id -u)
systemctl --user stop nino-relay.service 2>/dev/null && echo "[restart] relay paused" || true

# Claude Code 세션 재시작
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
  tmux respawn-pane -k -t "$SESSION_NAME" "cd $BOT_DIR && claude --model claude-opus-4-6 --dangerously-skip-permissions --continue"
  echo "[restart] Claude Code restarted"
else
  echo "[restart] No session found, starting fresh..."
  "$SCRIPT_DIR/start-nino.sh"
  exit 0
fi

# relay 재개
sleep 2
systemctl --user start nino-relay.service 2>/dev/null && echo "[restart] relay resumed" || true

# Claude Code가 준비될 때까지 대기 후 히스토리 트리거
sleep 5
TODAY=$(TZ=Asia/Seoul date +%Y-%m-%d)
HISTORY_FILE="$BOT_DIR/memory/discord-history/$TODAY.jsonl"

# 재부팅 알림 파일 확인
NOTIFY_FILE="$BOT_DIR/logs/pending-restart-notify.txt"
if [[ -f "$NOTIFY_FILE" ]]; then
  tmux send-keys -t "$SESSION_NAME" "재부팅했어. logs/pending-restart-notify.txt 있으니까 처리해줘. 그리고 memory/discord-history/$TODAY.jsonl 읽고 못 봤던 대화 파악해줘." C-m
elif [[ -f "$HISTORY_FILE" ]]; then
  tmux send-keys -t "$SESSION_NAME" "재시작됐어. memory/discord-history/$TODAY.jsonl 읽고 못 봤던 대화 있으면 파악해줘." C-m
fi

echo "[restart] 니노 재시작 완료!"
