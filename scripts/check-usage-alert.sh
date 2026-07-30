#!/bin/bash
# Claude Code 사용량 모니터링 + Discord 경고 (cron 30분 간격)
#
# 로직: 사용률 ÷ 경과시간 = 시간당 소비율 → 윈도우 끝까지 유지하면 100% 넘는지 판단
# 예: 5시간 윈도우에서 1시간 경과, 20% 사용 → 시간당 20% → 5시간이면 100% → 경고
#
# 🔴 2026-07-31 이전엔 **이 검사가 429 를 볼 수 없었다.**
#    `curl -s …` 에 `-w` 도 `-f` 도 없어 상태코드를 안 봤고, 로그 파일이 아예 없었다.
#    429 본문은 `json.loads` 를 통과하고 버킷이 없어 **조용히 exit 0** 이 된다.
#    ⇒ *"내 로그에 429 없었다"* 는 증거가 아니라 **침묵**이었다. 30분마다 맞고 있었어도 흔적 0.
#
# 🔑 왜 관측이 먼저인가 (룬드 2026-07-31):
#    `…/api/oauth/usage` 를 여러 소비자가 친다(이 검사 30분 · check-usage.sh · 조사용 수동 호출).
#    **백오프는 자기 호출만 멈추고 rate limit 은 계정 단위**라 조율(공유 백오프)이 필요한데,
#    조율을 설계하려면 *누가 얼마나 쓰는지*가 먼저 보여야 한다. 룬드가 소비자 구조를 찾은 근거도 로그였다.
#    ⇒ 이 변경은 **소비자를 줄이지 않는다. 보이게 만든다.** 그게 다음 단계의 선결이다.
#
# 🔸 토큰 출처 해석(env → ~/.secrets → credentials.json)은 **별 PR** 이다. 여기선 경로 override 만 둔다.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# jq 미설치 환경에서 set -e로 즉시 종료됐던 줄 — 코어가 채널명을 해석하므로 조회 자체가 불필요(2026-07-25).
DISCORD_CHANNEL="현인-다용도"

CREDENTIALS="${CHECK_USAGE_CREDENTIALS:-$HOME/.claude/.credentials.json}"
LOG="${CHECK_USAGE_LOG:-$BOT_DIR/logs/check-usage-alert.log}"
DISCORD_SEND="${DISCORD_SEND:-$BOT_DIR/src/discord-send}"
API_URL="${USAGE_API_URL:-https://api.anthropic.com/api/oauth/usage}"

VERDICT=unknown      # ok · no_token · http_error · unparseable · network
CODE=na              # HTTP 상태코드
RETRY_AFTER=na       # 429 일 때 서버가 준 값 — 공유 백오프 설계의 근거가 된다
ALERT=none           # none · sent · send_failed
NOTE=""

mkdir -p "$(dirname "$LOG")" 2>/dev/null

# 🔑 어떤 경로로 끝나도 로그 1줄. 중간에 죽어도 남는다.
#    check-auth.sh 가 같은 형태로 *"죽은 걸 아무도 모른다"* 를 막았다(2026-07-25 사고).
emit_log() {
    local rc=$?
    printf '%s verdict=%s code=%s retry_after=%s alert=%s rc=%s%s\n' \
        "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$VERDICT" "$CODE" "$RETRY_AFTER" "$ALERT" "$rc" \
        "${NOTE:+ note=$NOTE}" >> "$LOG" 2>/dev/null || true
}
trap emit_log EXIT

# 🔴 발송 실패를 삼키지 않는다 — 실패했는데 `sent` 로 남으면 알림 경로가 조용히 죽는다(#88 과 같은 계약).
notify() {
    local err rc
    err="$("$DISCORD_SEND" "$DISCORD_CHANNEL" "$1" 2>&1 >/dev/null)"
    rc=$?
    [ "$rc" -eq 0 ] && return 0
    NOTE="${NOTE:+$NOTE,}discord-send-failed(rc=$rc)"
    [ -n "$err" ] && NOTE="$NOTE"
    return 1
}

# ── 1. OAuth 토큰 ────────────────────────────────────────────────────────────
TOKEN="$(CRED="$CREDENTIALS" python3 -c "
import json, os
try:
    d = json.load(open(os.environ['CRED']))
    print(d['claudeAiOauth']['accessToken'])
except Exception:
    pass" 2>/dev/null)"

if [ -z "$TOKEN" ]; then
    # 🔴 옛 코드는 여기서 `exit 1` 이 전부였다 — 로그도 알림도 없이 사라졌다.
    VERDICT=no_token
    NOTE="${NOTE:+$NOTE,}credentials-unreadable"
    exit 1
fi

# ── 2. API 호출 — **상태코드와 헤더를 본다** ─────────────────────────────────
HDR="$(mktemp)"
RAW="$(curl -s -D "$HDR" -w '%{http_code}' \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -H "User-Agent: claude-code/2.1.5" \
    -H "anthropic-beta: oauth-2025-04-20" \
    "$API_URL")"
CURL_RC=$?

# 🔑 `-w '%{http_code}'` 는 본문 **뒤에** 코드를 붙인다 ⇒ 마지막 3자가 코드, 나머지가 본문이다.
CODE="$(printf '%s' "$RAW" | tail -c 3)"
RESPONSE="${RAW%???}"

# retry-after 는 429 조율의 유일한 **서버측** 근거다. 없으면 na 로 둔다(추측하지 않는다).
if [ -f "$HDR" ]; then
    RA="$(tr -d '\r' < "$HDR" | awk 'tolower($1) == "retry-after:" { print $2; exit }')"
    [ -n "$RA" ] && RETRY_AFTER="$RA"
fi
rm -f "$HDR"

# 🔑 **네트워크 실패와 HTTP 오류를 같은 칸에 넣지 않는다** — 조치가 다르다.
#    못 쟀다(network) vs 서버가 거절했다(http_error). 뭉치면 429 가 "가끔 실패한다"로 묻힌다.
if [ "$CURL_RC" -ne 0 ]; then
    VERDICT=network
    NOTE="${NOTE:+$NOTE,}curl-rc=$CURL_RC"
    exit 2
fi

if [ "$CODE" != "200" ]; then
    VERDICT=http_error
    exit 1
fi

# ── 3. 현재 속도로 리셋 전 한도 도달하는지 판단 ──────────────────────────────
ALERT_MSG="$(RESPONSE="$RESPONSE" python3 << 'PYEOF'
import json, os, sys
from datetime import datetime, timezone

response_str = os.environ.get("RESPONSE", "")
if not response_str:
    sys.exit(3)

try:
    data = json.loads(response_str)
except json.JSONDecodeError:
    sys.exit(3)

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
)"
PARSE_RC=$?

# 🔴 파싱 실패를 정상으로 접지 않는다 — 옛 코드는 `sys.exit(0)` 이라 200 인데 조용히 끝났다.
if [ "$PARSE_RC" -eq 3 ]; then
    VERDICT=unparseable
    exit 1
fi

VERDICT=ok

# ── 4. 경고 메시지가 있으면 Discord로 전송 ───────────────────────────────────
if [ -n "$ALERT_MSG" ]; then
    if notify "$ALERT_MSG"; then
        ALERT=sent
    else
        ALERT=send_failed
    fi
fi

exit 0
