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
#
# 🔑 종료코드 계약 (2026-07-28 — 양봇 규약. 룬드 check-usage-alert.sh 와 **같은 문면**):
#   0  정상        쟀다(경고를 보냈든 안 보냈든)
#   1  실패        — 이 스크립트엔 없다. 판정과 조치가 분리돼 있어서
#   2  판정 불가   토큰이 없거나 API 가 답을 안 했다. **못 쟀다** 를 실패로도 정상으로도 접지 않는다
#
# 🔴 2026-07-31 04:0x — 여기가 **갈려 있었다**. network 는 2, http_error·no_token·unparseable 은 1.
#    넷 다 *못 쟀다* 인데 칸이 달랐고, 시험이 `rc -ne 0` 이라 **1이든 2든 초록**이라 안 보였다.
#    ⇒ 계약은 사본이 두 벌이면 갈린다. **그래서 문면을 링크가 아니라 사본으로 옮겨 적는다** —
#      링크면 상대가 고쳐도 내 쪽이 안 따라오고, 사본이면 최소한 갈린 것이 눈에 보인다.

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
# 🔑 필드명에 **단위를 박는다**(`_s` = 초). HTTP `Retry-After` 는 초지만 로그만 봐서는 모른다.
#   ⚠️ 2026-07-31 05:5x 실사고: 룬드 하트비트 표지가 `STALE 725` 였고 **바로 옆 괄호에 "30분 주기"**
#     가 있어서 내가 725 를 분으로 읽었다(실제로는 725**시간**). 12시간 장애로 오판했다.
#     🔑 **표지에 단위가 없으면 읽는 쪽이 채운다** — 그리고 옆에 있는 단위를 집는다.
#   🔸 지금 이 로그를 읽는 프로그램이 0곳이라 이름을 바꾸는 게 **공짜다.**
#     단위를 넣을 마지막 기회는 **읽는 쪽이 생기기 전**이다.
RETRY_AFTER=na       # 429 일 때 서버가 준 값(초) — 공유 백오프 설계의 근거가 된다
ALERT=none           # none · sent · send_failed · dry_run
NOTE=""

mkdir -p "$(dirname "$LOG")" 2>/dev/null

# 🔑 어떤 경로로 끝나도 로그 1줄. 중간에 죽어도 남는다.
#    check-auth.sh 가 같은 형태로 *"죽은 걸 아무도 모른다"* 를 막았다(2026-07-25 사고).
emit_log() {
    local rc=$?
    printf '%s verdict=%s code=%s retry_after_s=%s alert=%s rc=%s%s\n' \
        "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$VERDICT" "$CODE" "$RETRY_AFTER" "$ALERT" "$rc" \
        "${NOTE:+ note=$NOTE}" >> "$LOG" 2>/dev/null || true
    # 🔑 임시파일 뒤처리도 여기에 둔다 — **조기 종료가 뒤처리를 건너뛰는** 자리를 없앤다.
    #    ⚠️ `trap 'rm …' EXIT` 를 따로 걸면 안 된다: bash 는 EXIT trap 을 **덮어쓴다**(실측).
    #    위의 emit_log 가 조용히 사라진다. 뒤처리가 여럿이면 **한 trap 안에** 모은다.
    rm -f ${HDR:+"$HDR"} ${PARSE_ERR:+"$PARSE_ERR"}
    return 0
}
trap emit_log EXIT

# ── 인자 계약 (코어 cli-guard) ───────────────────────────────────────────────
# 🔴 2026-07-31 09:50 사고: 진단하려고 `--report` 로 불렀다. 그런 플래그는 **없었고**
#   인자 파싱 자체가 없어 조용히 무시된 뒤 **평소 검사(=발송 포함)** 가 돌았다.
#   `rc=0` · stdout 0바이트라 *"아무 일도 안 났다"* 로 읽혔는데 Discord 로 두 방이 나간 뒤였다.
#   같은 날 룬드도 자기 감시기를 진단으로 두 번 돌려 알림 두 건을 냈다(10:44·10:48).
#   🔑 **고칠 것은 습관이 아니라 형태다** — 양봇 다 *조심하려다* 밟았다.
#
# 🔑 **왜 `trap` 뒤에 두나** — 거절도 로그 1줄로 남기기 위해서다.
#   cron 은 stderr 를 버린다. 거절이 로그에 안 남으면 crontab 을 잘못 고친 순간
#   이 감시기는 **아무 흔적 없이 멈춘다** — 감시기가 조용히 죽는 그 형태 그대로다.
#   ⇒ 거절은 stderr(부른 사람용) + 로그 1줄(사후용) **양쪽**에 남긴다.
# 🔸 `unknown` 에 섞지 않고 `bad_args`/`bad_env` 로 따로 센다. 셋 다 *못 쟀다*지만
#   **고칠 곳이 다르다** — API 가 답을 안 한 것(서버)과 잘못 부른 것(부른 쪽)은 다른 일이다.
# 🔑 배선은 `scripts/lib/cli-guard-boot.sh` **한 벌**만 쓴다. 여기 사본으로 두면
#   코어 후보 순서·거절 판정 같은 규칙이 스크립트마다 갈린다. 실제로 이 파일의 옛 사본은
#   코어를 `$HOME` **하나로만** 찾았고, 그건 cron 환경(HOME 이 다르다)에서 못 찾는다 —
#   `check-auth` 의 FAKEHOME 시험이 그 형태를 잡아서 부트 쪽은 자기 위치를 먼저 본다.
#   ⇒ 사본을 남겨두면 **고친 곳과 안 고친 곳이 생기고, 안 고친 쪽은 조용하다.**
cli_guard_usage() {
    echo "usage: $(basename "$0") [--dry-run] [-h|--help]"
    echo "  --dry-run   판정까지 하되 Discord 발송은 하지 않는다 (진단용)"
}
# 🔴 가드가 없으면 **가드 없이 돌지 않는다.** 붙였다고 믿는 채로 안 붙은 상태는
#   붙이기 전보다 나쁘다 — 믿음이 생기면 아무도 다시 안 본다. (부트가 exit 2 로 끊는다)
# 🔑 거절 사유를 VERDICT 에 실어 **EXIT trap 의 로그 1줄**로 내보낸다. cron 은 stderr 를
#   버리므로, 이 한 줄이 없으면 crontab 을 잘못 고친 순간 감시기가 흔적 없이 멈춘다.
cli_guard_reject_log() { VERDICT="$1"; }
CLI_GUARD_ON_REJECT=cli_guard_reject_log
# shellcheck source=scripts/lib/cli-guard-boot.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/cli-guard-boot.sh"
cli_guard_boot "$@"

# 🔴 발송 실패를 삼키지 않는다 — 실패했는데 `sent` 로 남으면 알림 경로가 조용히 죽는다(#88 과 같은 계약).
notify() {
    local err rc
    # 🔴 dry-run 을 **여기서 먼저 가른다.** 감싸기만 하면 안 된다:
    #   `cli_guard_send` 는 안내를 stderr 로 내고 rc=0 을 주는데, 아래 `2>&1 >/dev/null` 이
    #   그 안내를 `err` 로 삼키고 rc=0 이라 **안 보냈는데 `alert=sent`** 로 남는다.
    #   🔑 코어 계약이 덮는 범위는 *발송 억제*까지고 **기록을 고치는 것은 소비자 몫**이다.
    #     (계약 ② 머리말: "이 범위 밖은 약속하지 않는다" — 그 경계가 정확히 여기다.)
    if [ "$CLI_DRY_RUN" = "1" ]; then
        cli_guard_send "$DISCORD_SEND" "$DISCORD_CHANNEL" "$1"
        return 3
    fi
    err="$(cli_guard_send "$DISCORD_SEND" "$DISCORD_CHANNEL" "$1" 2>&1 >/dev/null)"
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
    exit 2
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

# 🔸 HDR·PARSE_ERR 뒤처리는 emit_log(EXIT trap) 안에 있다 — 여기서 손으로 지우면
#    "지금은 exit 이 아래에 없다" 에 기대게 되고, 그건 **안 새는 게 아니라 아직 안 닿은 것**이다.
# retry-after 는 429 조율의 유일한 **서버측** 근거다. 없으면 na 로 둔다(추측하지 않는다).
if [ -f "$HDR" ]; then
    RA="$(tr -d '\r' < "$HDR" | awk 'tolower($1) == "retry-after:" { print $2; exit }')"
    [ -n "$RA" ] && RETRY_AFTER="$RA"
fi

# 🔑 **네트워크 실패와 HTTP 오류를 같은 칸에 넣지 않는다** — 조치가 다르다.
#    못 쟀다(network) vs 서버가 거절했다(http_error). 뭉치면 429 가 "가끔 실패한다"로 묻힌다.
if [ "$CURL_RC" -ne 0 ]; then
    VERDICT=network
    NOTE="${NOTE:+$NOTE,}curl-rc=$CURL_RC"
    exit 2
fi

if [ "$CODE" != "200" ]; then
    VERDICT=http_error
    exit 2
fi

# ── 3. 현재 속도로 리셋 전 한도 도달하는지 판단 ──────────────────────────────
PARSE_ERR="$(mktemp)"
ALERT_MSG="$(RESPONSE="$RESPONSE" python3 2>"$PARSE_ERR" << 'PYEOF'
import json, os, sys
from datetime import datetime, timezone

# 🔑 **이유를 이름으로 stderr 에 보내고 종료코드는 3 하나** (룬드 #37 구조를 따름).
#    갈래마다 종료코드를 새로 배정하면 갈래가 늘 때 파이썬도 셸도 같이 바뀐다.
#    이름으로 보내면 **확장 지점이 파이썬 한 곳**뿐이다.
def unreadable(why):
    print(why, file=sys.stderr)
    sys.exit(3)

response_str = os.environ.get("RESPONSE", "")
if not response_str:
    unreadable("empty-body")

try:
    data = json.loads(response_str)
except json.JSONDecodeError:
    unreadable("json-decode")

# 🔴 **JSON 이 맞다고 잰 게 아니다** — null·[]·{"unexpected":1} 이 전부 rc=0 ok 로 접히고 있었다(실측).
#    빈 alerts 는 *임계 미달* 과 구별되지 않아 스키마가 바뀌면 *못 쟀다* 가 *재보니 낮다* 로 접힌다.
if not isinstance(data, dict):
    unreadable("not-object")

# 🔸 여기 있던 `if not isinstance(data, dict): sys.exit(4)` 를 지웠다 — **위에서 이미 걸러
#   도달 불가**였고, 종료코드 4 는 지금 계약(이유는 stderr·코드는 3 하나)에도 안 맞는다.
#   🔑 구조를 바꾸면 **바뀌기 전 판의 잔해**가 남는다. 남아 있으면 다음 사람이 그 코드가
#     의미 있다고 읽는다(계약이 두 벌로 보인다).
now = datetime.now(timezone.utc)
alerts = []

# 윈도우 크기 (시간)
windows = {
    "five_hour": ("5시간 롤링", 5),
    "seven_day": ("7일 전체", 7 * 24),
}

# 아는 칸이 하나라도 응답에 있었는지 — 없으면 이 응답으로는 **아무것도 못 쟀다**.
# ⚠️ 경계: *키는 있는데 값이 전부 못 쓰는* 경우는 여기서 안 가른다(#91 이 소유한 칸이다).
#    그 칸도 사실상 못 잰 것이라 별건으로 남긴다 — 안 잰 것을 여기서 몰래 바꾸지 않는다.
# 🔴 **키 존재만 보면 값의 타입을 안 본다** (룬드 대조 실측). {"five_hour": null} 은 키가 있어
#    통과하고 뒤에서 continue 되어 alerts 가 비어 rc=0 "임계 미달" 이 됐다 — 고치려던 그 문장 그대로.
if not any(isinstance(data.get(k), dict) for k in windows):
    unreadable("no-known-buckets")

for key, (label, window_hours) in windows.items():
    bucket = data.get(key)
    if not isinstance(bucket, dict) or bucket.get("utilization") is None:
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
# 이유는 파이썬이 이름으로 준다. 아는 이름이 아니면 unknown — 트레이스백을 이유로 착각하지 않는다.
PARSE_WHY="$(tr -d '\r\n' < "$PARSE_ERR" 2>/dev/null)"
case "$PARSE_WHY" in
    empty-body|json-decode|not-object|no-known-buckets) : ;;
    *) PARSE_WHY=unknown ;;
esac

# 🔴 파싱 실패를 정상으로 접지 않는다 — 옛 코드는 `sys.exit(0)` 이라 200 인데 조용히 끝났다.
# 🔑 갈래 이름은 룬드 check-usage-alert.sh 와 **같은 문면**이다(계약은 링크가 아니라 사본).
# 🔴 `-eq 3` 이었다 — 그래서 **파이썬이 예상 밖으로 죽으면(rc=1) 어느 분기에도 안 걸리고
#    verdict=ok 로 흘렀다.** 크래시가 정상으로 접히는 자리였다(2026-07-31 04:4x 실측).
#    ⇒ **이유를 모르는 실패도 못 쟀다** 다. 모른다고 정상으로 접지 않는다(parse-unknown).
if [ "$PARSE_RC" -ne 0 ]; then
    VERDICT="parse-$PARSE_WHY"
    # 🔑 이유를 모르면 **전문을 보여준다** (룬드 #38 에서 가져옴) —
    #    이름 한 줄로는 원인을 못 고친다. 아는 이유일 땐 이미 이름이 다 말한다.
    if [ "$PARSE_WHY" = unknown ] && [ -s "$PARSE_ERR" ]; then
        echo "⛔ 파서가 예기치 않게 죽었다 (python rc=$PARSE_RC):" >&2
        sed 's/^/     /' "$PARSE_ERR" >&2
    fi
    exit 2
fi

VERDICT=ok

# ── 4. 경고 메시지가 있으면 Discord로 전송 ───────────────────────────────────
if [ -n "$ALERT_MSG" ]; then
    notify "$ALERT_MSG"; nrc=$?
    # 🔸 `if notify` 두 갈래로는 **세 상태를 못 담는다.** dry-run 을 실패로 접으면
    #   `send_failed` 가 되고, 성공으로 접으면 `sent` 가 된다 — 둘 다 거짓이다.
    case "$nrc" in
        0) ALERT=sent ;;
        3) ALERT=dry_run ;;
        *) ALERT=send_failed ;;
    esac
fi

exit 0
