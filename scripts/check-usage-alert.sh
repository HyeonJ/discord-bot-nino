#!/bin/bash
# Claude Code 사용량 모니터링 + Discord 경고
# 30분마다 실행하여 현재 속도로 리셋 전 한도 도달 예상 시 경고
#
# 로직: 사용률 ÷ 경과시간 = 시간당 소비율 → 윈도우 끝까지 유지하면 100% 넘는지 판단
# 예: 5시간 윈도우에서 1시간 경과, 20% 사용 → 시간당 20% → 5시간이면 100% → 경고
#
# 사용법: ./check-usage-alert.sh
# cron으로 30분마다 실행: */30 * * * * /path/to/check-usage-alert.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CHANNEL_MAP="$BOT_DIR/config/channel-map.json"
DISCORD_CHANNEL=$(python3 -c "import json; print(json.load(open('$CHANNEL_MAP'))['현인-다용도'])" 2>/dev/null || echo "1480593132511826092")

# 1. OAuth 토큰 추출
TOKEN=$(python3 -c "import json; d=json.load(open('$HOME/.claude/.credentials.json')); print(d['claudeAiOauth']['accessToken'])" 2>/dev/null)

if [ -z "$TOKEN" ]; then
  exit 1
fi

# 2. API 호출
RESPONSE=$(curl -s \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "User-Agent: claude-code/2.1.5" \
  -H "anthropic-beta: oauth-2025-04-20" \
  "https://api.anthropic.com/api/oauth/usage")

if [ -z "$RESPONSE" ]; then
  exit 1
fi

# 3. 현재 사용 속도로 리셋 전 한도 도달하는지 판단
ALERT_MSG=$(RESPONSE="$RESPONSE" python3 << 'PYEOF'
import json, os, sys
from datetime import datetime, timezone

response_str = os.environ.get("RESPONSE", "")
if not response_str:
    sys.exit(0)

try:
    data = json.loads(response_str)
except json.JSONDecodeError:
    sys.exit(0)

now = datetime.now(timezone.utc)
alerts = []

# 윈도우 크기 (시간)
windows = {
    "five_hour": ("5시간 롤링", 5),
    "seven_day": ("7일 전체", 7 * 24),
}

for key, (label, window_hours) in windows.items():
    bucket = data.get(key)
    if not bucket or bucket.get("utilization") is None:
        continue

    util = bucket["utilization"]
    resets_at_str = bucket.get("resets_at", "")
    if not resets_at_str or util <= 0:
        continue

    try:
        reset_dt = datetime.fromisoformat(resets_at_str)
    except (ValueError, TypeError):
        continue

    hours_until_reset = (reset_dt - now).total_seconds() / 3600
    if hours_until_reset <= 0:
        continue

    # 경과 시간 = 윈도우 전체 - 리셋까지 남은 시간
    elapsed_hours = window_hours - hours_until_reset
    if elapsed_hours <= 0:
        continue

    # 현재 속도로 윈도우 끝까지 사용하면 예상 사용률
    projected = util / elapsed_hours * window_hours

    if projected >= 100:
        reset_h = int(hours_until_reset)
        reset_m = int((hours_until_reset - reset_h) * 60)
        alerts.append(
            f"🔴 **{label}**: {util:.0f}% 사용 중 "
            f"(리셋까지 {reset_h}시간 {reset_m}분) — "
            f"이 속도면 **{projected:.0f}%** 도달 예상"
        )

if alerts:
    print("⚠️ **니노 사용량 경고**\n" + "\n".join(alerts))
PYEOF
)

# 4. 경고 메시지가 있으면 Discord로 전송
if [ -n "$ALERT_MSG" ]; then
  "$BOT_DIR/src/discord-send" -c "$DISCORD_CHANNEL" "$ALERT_MSG"
fi
