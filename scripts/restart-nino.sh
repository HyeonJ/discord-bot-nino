#!/usr/bin/env bash
# 니노 봇 재시작 스크립트
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SESSION_NAME="nino"

# 중단 시각 기록 — 재시작 후 "얼마나 못 봤나"를 계산하는 유일한 근거다.
# 이게 없으면 catchup-hint가 기본 창으로 떨어지고, 실제 중단 시간과 창이 어긋난 걸 아무도 모른다.
mkdir -p "$BOT_DIR/logs"
date -u +%Y-%m-%dT%H:%M:%SZ > "$BOT_DIR/logs/last-stop-utc"

# relay 일시정지 (경합 방지)
export XDG_RUNTIME_DIR=/run/user/$(id -u)
systemctl --user stop nino-relay.service 2>/dev/null && echo "[restart] relay paused" || true

# Claude Code 세션 재시작
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
  tmux respawn-pane -k -t "$SESSION_NAME" "cd $BOT_DIR && source ~/.nvm/nvm.sh && claude --model opus --dangerously-skip-permissions --continue"
  echo "[restart] Claude Code restarted"
else
  echo "[restart] No session found, starting fresh..."
  "$SCRIPT_DIR/start-nino.sh"
  exit 0
fi

# relay 재개
sleep 2
systemctl --user start nino-relay.service 2>/dev/null && echo "[restart] relay resumed" || true

# Claude Code가 준비될 때까지 대기 후 따라잡기 트리거
# 지시문은 catchup-hint.sh가 만든다(조회 정본=CLI, 중단 시각 기반 창, 폴백까지 한 곳에서).
# 예전엔 여기와 start-nino.sh에 지시문 사본이 두 벌 있었다 → 갈릴 자리를 없앴다.
sleep 5
NOTIFY_FILE="$BOT_DIR/logs/pending-restart-notify.txt"
if [[ -f "$NOTIFY_FILE" ]]; then
  HINT="$("$SCRIPT_DIR/catchup-hint.sh" --reboot)"
else
  HINT="$("$SCRIPT_DIR/catchup-hint.sh")"
fi
tmux send-keys -t "$SESSION_NAME" "$HINT" C-m

echo "[restart] 니노 재시작 완료!"
