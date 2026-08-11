#!/bin/bash
# auto-approve-claude.sh — tmux에서 .claude/ 수정 프롬프트 자동 승인
# LaunchAgent로 실행. 5초마다 tmux 화면 감시.

TMUX_SESSION="${TMUX_SESSION:-nino}"
PANE="${TMUX_SESSION}:0.0"
LOG="/tmp/nino-auto-approve.log"

while true; do
  CONTENT=$(tmux capture-pane -t "$PANE" -p 2>/dev/null | sed '/^$/d' | tail -1)
  if echo "$CONTENT" | grep -q 'Esc to cancel'; then
    tmux send-keys -t "$PANE" '2'
    echo "[$(date '+%H:%M:%S')] Auto-approved .claude/ edit prompt" >> "$LOG"
    sleep 10  # 화면 갱신 대기
  fi
  sleep 5
done
