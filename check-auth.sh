#!/usr/bin/env bash
# Claude Code 인증 상태 체크 (cron 5분 간격, 알림 1시간 간격)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAST_ALERT_FILE="/tmp/nino-auth-last-alert"
ALERT_INTERVAL=3600

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
  "$SCRIPT_DIR/discord-send" -c 1480479067881865347 "Claude Code 인증이 만료됐어! Darren이 재로그인 해줘야 해. tmux attach -t nino 후 claude auth login 실행!"
  echo "$NOW" > "$LAST_ALERT_FILE"
fi
