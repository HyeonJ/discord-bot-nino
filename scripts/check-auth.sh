#!/usr/bin/env bash
# Claude Code 인증 상태 체크 (cron 5분 간격, 알림 1시간 간격)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LAST_ALERT_FILE="/tmp/nino-auth-last-alert"
ALERT_INTERVAL=3600
CREDENTIALS="$HOME/.claude/.credentials.json"
# positional 전환 후엔 코어가 channel-map을 해석하므로 jq 조회가 불필요하다(§13.4 map miss=명시 에러).
# ⚠️ 이 줄이 원래 jq였고 이 환경엔 jq가 없어 set -e로 스크립트가 여기서 즉시 죽었다 = 인증 만료 알림이
#    한 번도 안 나갔다(2026-07-25 발견). 의존성 제거가 근본 해결.
ALERT_CHANNEL="현인-업무"

# 만료 전 경고: 1시간 이내 만료 시 미리 알림
if [[ -f "$CREDENTIALS" ]]; then
  EXPIRES_MS=$(python3 -c "import json; print(json.load(open('$CREDENTIALS'))['claudeAiOauth']['expiresAt'])" 2>/dev/null || echo "0")
  if [[ "$EXPIRES_MS" != "0" ]]; then
    NOW_MS=$(date +%s%3N)
    REMAINING_MS=$((EXPIRES_MS - NOW_MS))
    REMAINING_MIN=$((REMAINING_MS / 60000))
    # 60분 이내 만료 예정이면 경고
    if [[ $REMAINING_MIN -gt 0 && $REMAINING_MIN -le 60 ]]; then
      LAST_EXPIRY_ALERT=0
      [[ -f "/tmp/nino-auth-expiry-alert" ]] && LAST_EXPIRY_ALERT=$(cat /tmp/nino-auth-expiry-alert)
      NOW_S=$(date +%s)
      if [[ $((NOW_S - LAST_EXPIRY_ALERT)) -ge 1800 ]]; then
        "$BOT_DIR/src/discord-send" "$ALERT_CHANNEL" "<@353914579929268226> 니노 토큰이 ${REMAINING_MIN}분 후 만료돼! tmux attach -t nino 후 /login 해줘"
        echo "$NOW_S" > /tmp/nino-auth-expiry-alert
      fi
    fi
  fi
fi

STATUS=$(claude auth status 2>&1 || true)
LOGGED_IN=$(echo "$STATUS" | python3 -c "import sys,json; print(json.load(sys.stdin).get('loggedIn', False))" 2>/dev/null || echo "False")

if [[ "$LOGGED_IN" == "True" ]]; then
  rm -f "$LAST_ALERT_FILE"
  exit 0
fi

NOW=$(date +%s)
LAST_ALERT=0
[[ -f "$LAST_ALERT_FILE" ]] && LAST_ALERT=$(cat "$LAST_ALERT_FILE")
ELAPSED=$((NOW - LAST_ALERT))

if [[ $ELAPSED -ge $ALERT_INTERVAL ]]; then
  "$BOT_DIR/src/discord-send" "$ALERT_CHANNEL" "<@353914579929268226> Claude Code 인증이 만료됐어! tmux attach -t nino 후 /login 해줘"
  echo "$NOW" > "$LAST_ALERT_FILE"
fi
