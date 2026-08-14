#!/bin/bash

# 🤝 자동 발신엔 `[감시]` 를 붙인다 — 셔틀이 이 변수를 보고 «모든» 전송에 태그한다.
#    호출 자리마다 붙이지 않는 이유: 새 전송을 추가해도 자동으로 태그되게(환경에 건다).
export NINO_AUTOSEND=1
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
# 🔑 마지막으로 **알린** 판정. 「마지막 판정」이 아니다 — 못 보낸 회차는 여기 안 들어온다.
STATE="${CHECK_USAGE_STATE:-$BOT_DIR/logs/check-usage-verdict.state}"
# 🔑 **축이 둘이라 상태 파일도 둘이다.** verdict 는 «감시가 살아 있나»(상태 축), band 는
#   «값이 높나»(수준 축)다. 한 파일에 담으면 한쪽 전이가 다른 쪽 기준선을 지운다.
#   유래: 룬드 계약 — *「게이트는 도구마다가 아니라 «축»마다 정한다」*(2026-08-10).
BAND_STATE="${CHECK_USAGE_BAND_STATE:-$BOT_DIR/logs/check-usage-band.state}"
# 🔴 **높은 구간이 «지속되는 동안»에도 운다.** 전이에만 울면 200% 가 세 시간 이어져도 조용한데,
#   Darren 값이 *「조용히 안 오는 쪽이 시끄럽게 틀리는 쪽보다 나쁘다」*라 그 반대다.
#   ⇒ 전이 + 지속 반복. 주기 120분은 **Darren 이 정했다**(2026-08-10 M:juia 「b로하고 두시간」).
#   ⚠️ 이 값을 코드 판단으로 바꾸지 말 것 — 사람 값이다.
BAND_REPEAT_MIN="${CHECK_USAGE_BAND_REPEAT_MIN:-120}"
# 🔴 **401 은 «사람을 부를 일»이 아니다** — `accessToken` 은 lazy refresh 라 «쓰는 순간»
#   자가회복한다. 감시기가 401 을 봐도 대부분 정상이다(실측 12/12 자가회복).
#   그렇다고 무음이면 진짜 만료(`refreshToken` 쪽)를 놓친다 ⇒ **로그엔 남기고 발신만 억제하되,
#   유예를 넘겨 «지속»하면 부른다.** 처방은 Darren 승인(2026-08-14 `M:h89h` 「고쳐」).
# ⚠️ **이 유예 값은 «추정»이다.** 진짜 만료 대조군이 **0/26** 이라 재서 나온 값이 아니다 —
#   관측된 자가회복 최장 26분과 자가회복 0 이었던 52분 사이를 가르려고 60분을 골랐다.
#   ⇒ 그래서 알림 «본문»에도 추정이라고 적는다(받는 사람이 이 수를 믿지 않게).
AUTH_STATE="${CHECK_USAGE_401_STATE:-$BOT_DIR/logs/check-usage-401.state}"
AUTH_GRACE_SEC="${CHECK_USAGE_401_GRACE_SEC:-3600}"
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
ALERT=none           # none · sent · send_failed · dry_run · suppressed
BAND=na              # ok · 100-149 · 150-199 · 200+ (경계는 사람 값)
MAX_PROJ=na          # 두 창 중 가장 높은 예상치
# 🔑 **억제도 로그에 남긴다.** 「안 보냈다」가 「안 걸렸다」인지 「걸렸는데 참았다」인지
#   구별이 안 되면, 억제기가 고장 났을 때 그게 «조용한 정상»과 같은 얼굴이 된다.
BAND_REASON=na
# 🔑 **칸을 시각 둘로 둔다.** 하나면 「전이가 언제 났나」와 「언제 알렸나」가 안 갈리는데,
#   그 둘의 «간격»이 정확히 도달 지연의 관측값이다 — 룬드 실측: 복구는 32초, 복구 «알림»은 30분 5초.
#   ⚠️ 알림 줄로 구간 길이를 재면 **cron 주기만큼 부풀려진다.** 두 칸이 그 부풀림을 드러낸다.
VERDICT_CHANGED_AT=na   # 판정이 직전 «알린» 값과 달라진 시각
NOTIFIED_AT=na          # 그 변화를 실제로 알린 시각 · dry_run · send_failed
NOTE=""

mkdir -p "$(dirname "$LOG")" 2>/dev/null

# 🔑 어떤 경로로 끝나도 로그 1줄. 중간에 죽어도 남는다.
#    check-auth.sh 가 같은 형태로 *"죽은 걸 아무도 모른다"* 를 막았다(2026-07-25 사고).
emit_log() {
    local rc=$?
    # 🔴 **알림을 여기 둔다.** 아래 판정 갈래는 전부 `exit 2` 라 스크립트 끝의 알림 블록에
    #   **한 번도 닿지 못했다** — 401 이 30분마다 나도 조용했다(2026-08-03 실측).
    #   갈래마다 알림을 붙이면 «새 갈래가 생길 때 또 빠진다» ⇒ 모든 경로가 지나는 자리는 여기뿐이다.
    #   🔑 trap 이 있다는 것이 «알린다»는 뜻이 아니었다 — 그릇은 있고 내용물이 반쪽이었다.
    verdict_transition
    printf '%s verdict=%s code=%s retry_after_s=%s alert=%s rc=%s verdict_changed_at=%s notified_at=%s band=%s max_projected=%s band_reason=%s%s\n' \
        "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$VERDICT" "$CODE" "$RETRY_AFTER" "$ALERT" "$rc" \
        "$VERDICT_CHANGED_AT" "$NOTIFIED_AT" "$BAND" "$MAX_PROJ" "$BAND_REASON" \
        "${NOTE:+ note=$NOTE}" >> "$LOG" 2>/dev/null || true
    # 🔑 임시파일 뒤처리도 여기에 둔다 — **조기 종료가 뒤처리를 건너뛰는** 자리를 없앤다.
    #    ⚠️ `trap 'rm …' EXIT` 를 따로 걸면 안 된다: bash 는 EXIT trap 을 **덮어쓴다**(실측).
    #    위의 emit_log 가 조용히 사라진다. 뒤처리가 여럿이면 **한 trap 안에** 모은다.
    rm -f ${HDR:+"$HDR"} ${PARSE_ERR:+"$PARSE_ERR"} ${TMP_PY:+"$TMP_PY"}
    return 0
}
# 🔑 **알림은 사실이 아니라 «변화»에 운다.** 401 이 이어지는 동안 매 회차 울면 그건 소음이고,
#   소음은 곧 무시된다 — 지금 30분마다 오는 사용량 경고가 그 형태다(같은 값 아홉 번).
#   ⇒ 전이에만 운다. **복구도 전이다** — 빼면 「울다 멈춘 것」과 「고쳐진 것」이 같은 모양이 된다.
# 🔑 **시계는 «전이와 무관하게» 돈다** — 전이 게이트 뒤에 두면 `ok`→`ok` 회차에서 early return
#   되어 **복구해도 시계가 안 지워진다**. 그러면 다음 401 이 「이미 오래 지속」으로 읽혀 즉시 울고,
#   억제가 «한 번 쓰고 죽는다». 시험 ⑦-e 가 그 자리다.
# 반환: 0 = 억제해라 · 1 = 보내라
auth_grace_gate() {
    if [ "$VERDICT" != http_error ] || [ "$CODE" != 401 ]; then
        rm -f "$AUTH_STATE" 2>/dev/null || true
        return 1
    fi
    local since now
    since="$(cat "$AUTH_STATE" 2>/dev/null)"
    # 🔑 «숫자가 아닌 것»은 없는 것으로 본다 — 손상된 상태가 「경과 0」이나 「경과 무한」으로
    #   조용히 읽히면 억제가 영영 걸리거나 영영 안 걸린다.
    case "$since" in ''|*[!0-9]*) since="" ;; esac
    now="$(date +%s)"
    if [ -z "$since" ]; then
        printf '%s\n' "$now" > "$AUTH_STATE" 2>/dev/null || true
        return 0
    fi
    [ "$(( now - since ))" -ge "$AUTH_GRACE_SEC" ] && return 1
    return 0
}
verdict_transition() {
    # 🔴 `notify` 는 아래에서 정의된다. 인자 가드가 부트에서 끊으면 **아직 없다** —
    #   없는 함수를 부르면 trap 안에서 죽어 **로그 한 줄까지 같이 사라진다**(고치려던 것이 재발).
    declare -f notify >/dev/null 2>&1 || return 0
    local prev nrc msg suppress=0
    # 🔴 전이 판정 «앞»에서 부른다 — 위 주석의 이유.
    auth_grace_gate && suppress=1
    prev="$(cat "$STATE" 2>/dev/null)"
    # 🔑 상태가 없으면 **ok 로 본다.** 「모른다」로 두면 첫 회차가 비정상이어도 조용하다 —
    #   배포 직후가 정확히 그 자리다. ok 를 가정하면 **엄격한 쪽으로 틀린다**(비정상이면 운다).
    [ -n "$prev" ] || prev=ok
    [ "$prev" = "$VERDICT" ] && return 0
    VERDICT_CHANGED_AT="$(date '+%Y-%m-%dT%H:%M:%S%z')"
    if [ "$VERDICT" = ok ]; then
        # 🔑 변수 뒤에 비ASCII 가 붙으면 **중괄호로 닫는다**(repo-hygiene 계약). 여기선 `」` 가 바로 뒤라
        #   bash 는 우연히 옳게 읽지만, 그 「우연히」에 기대는 것이 이 계약이 막으려는 것이다.
        msg="✅ **사용량 감시 복구** — 판정이 「${prev}」 → 「ok」 로 돌아왔어."
    else
        msg="🔴 **사용량 감시 이상** — 판정이 「${prev}」 → 「${VERDICT}」. 사용량을 못 재고 있어."
        [ "$CODE" != na ] && msg="$msg (HTTP $CODE)"
        if [ "$CODE" = 401 ]; then
            msg="${msg}\n🔑 401 이 $(( AUTH_GRACE_SEC / 60 ))분 넘게 이어졌어 — accessToken 은 보통 «쓰는 순간» 자가회복하는데 그게 안 됐다는 뜻이야. refreshToken 쪽 만료면 사람이 tmux attach -t nino 후 /login 해야 해."
            msg="${msg}\n⚠️ 이 「$(( AUTH_GRACE_SEC / 60 ))분」은 **추정**이야 — 진짜 만료 대조군이 0/26 이라 재서 나온 값이 아니야."
        fi
    fi
    # 🔴 억제는 «발신»만 막는다 — 판정도 로그도 그대로 남는다. 그리고 «억제했다»는 사실 자체를
    #   표지로 남긴다: 안 남기면 「안 울렸다」와 「안 돌았다」가 로그에서 같은 모양이 된다.
    if [ "$suppress" = 1 ]; then
        NOTIFIED_AT=suppressed_401_grace
        return 0
    fi
    notify "$msg"; nrc=$?
    case "$nrc" in
        0) NOTIFIED_AT="$(date '+%Y-%m-%dT%H:%M:%S%z')" ;;
        3) NOTIFIED_AT=dry_run ;;
        *) NOTIFIED_AT=send_failed ;;
    esac
    # 🔴 **보낸 것만 기준선이 된다.** 실패·dry-run 에도 갱신하면 그 전이는 «영구히» 묻힌다 —
    #   `#147` 에서 밟은 자리 그대로다. 특히 dry-run: 진단 한 번이 진짜 알림을 먹는다.
    [ "$nrc" -eq 0 ] && printf '%s\n' "$VERDICT" > "$STATE" 2>/dev/null
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
# 🔴 heredoc 을 `$(…)` 안에 두지 않는다 — 맥 bash 3.2 는 치환 안 heredoc 본문을 **재스캔**해서
#   인용 heredoc 이어도 **짝 안 맞는 백틱**이 생기는 순간 syntax error 로 죽는다.
#   ⚠️ 죽는 조건은 «백틱 유무»가 아니라 «짝»이다 — 짝수면 3.2 도 통과하고 실행도 안 된다(08-02 대조군).
#   bash 5 는 둘 다 통과하므로 `bash -n` 으로는 이 기계에서 영영 안 보인다 ⇒ **형태로만** 미리 막힌다.
#   이 본문은 백틱 2개(짝수, 아래 주석 안)라 «우연히» 통과 중이었다 — 다음 편집 한 번이 지뢰다.
#   같은 결함의 세 번째 사본이었다(코어 #133 · 룬드 레포 4c5a173 · 여기). inbox #154
TMP_PY="$(mktemp "${TMPDIR:-/tmp}/check-usage-parse.XXXXXX")"
cat > "$TMP_PY" <<'PYEOF'
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
# 🔴 0 으로 시작한다 — 「못 잰 창」과 「0% 인 창」을 여기서 안 가른다.
#   못 잰 것은 위 `no-known-buckets` 가 이미 rc=3 으로 끊고, 여기 도달했으면 «잰 것»이다.
max_projected = 0.0

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
    # 🔑 구간은 «창 하나»가 아니라 «가장 높은 창»으로 정한다 — 한쪽이 풀려도 다른 쪽이
    #   남아 있으면 구간이 내려가면 안 된다. (룬드 구현과 같은 문면: max_projected)
    max_projected = max(max_projected, projected)

    if projected >= 100:
        reset_h = int(hours_until_reset)
        reset_m = int((hours_until_reset - reset_h) * 60)
        alerts.append(
            f"🔴 **{label}**: {util:.0f}% 사용 중 "
            f"(리셋까지 {reset_h}시간 {reset_m}분) — "
            f"이 속도면 **{projected:.0f}%** 도달 예상"
        )

# 🔑 **구간(band) 을 첫 줄로 «따로» 낸다.** 셸이 메시지 본문을 파싱해서 구간을 «되짚으면»
#   문구를 고칠 때마다 억제기가 조용히 깨진다 — 값은 값으로 넘긴다.
#   경계는 Tim 이 정하고 Darren 이 「룬드 것 그대로」로 승인한 값이다(2026-08-10 M:juia).
#   ⚠️ 여기 숫자를 바꾸는 것은 **사람 값을 바꾸는 것**이다. 코드 판단으로 고치지 말 것.
def band_of(p):
    if p >= 200:
        return "200+"
    if p >= 150:
        return "150-199"
    if p >= 100:
        return "100-149"
    return "ok"

print("BAND\t%s\t%.0f" % (band_of(max_projected), max_projected))
if alerts:
    print("⚠️ **니노 사용량 경고**\n" + "\n".join(alerts))
PYEOF
ALERT_MSG="$(RESPONSE="$RESPONSE" python3 "$TMP_PY" 2>"$PARSE_ERR")"
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

# ── 3.5 구간을 첫 줄에서 «값으로» 떼어낸다 ───────────────────────────────────
# 🔴 파이썬이 못 낸 경우를 정상으로 접지 않는다 — 첫 줄이 BAND 가 아니면 계약이 깨진 것이다.
BAND_LINE="$(printf '%s\n' "$ALERT_MSG" | head -n 1)"
case "$BAND_LINE" in
    BAND$'\t'*)
        BAND="$(printf '%s' "$BAND_LINE" | cut -f2)"
        MAX_PROJ="$(printf '%s' "$BAND_LINE" | cut -f3)"
        ALERT_MSG="$(printf '%s\n' "$ALERT_MSG" | tail -n +2)"
        ;;
    *)
        VERDICT=parse-no-band
        NOTE="${NOTE:+$NOTE,}band-line-missing"
        exit 2
        ;;
esac

# ── 4. 구간 게이트 — «전이» 또는 «높은 구간 지속 N분» 일 때만 보낸다 ─────────
# 🔑 이 함수가 답하는 것은 「값이 높나」가 아니라 **「지금 울 차례인가」**다.
#   두 질문을 한 곳에 두면 문구를 고칠 때 억제 규칙이 같이 흔들린다.
# 🔴 기준선은 **보낸 것만** 갱신한다 — 실패·dry-run 에 갱신하면 그 회차가 영구히 묻힌다
#   (`#147` 과 같은 자리. verdict 쪽 :110 과 같은 계약).
band_should_notify() {   # 0 = 보낸다 · 1 = 억제
    local prev_band prev_at now_epoch age_min
    # 🔑 상태가 없으면 **ok 로 본다.** 「모른다」로 두면 배포 직후 첫 회차가 높아도 조용하다 —
    #   ok 를 가정하면 «엄격한 쪽»으로 틀린다(높으면 운다).
    prev_band="$(cut -f1 "$BAND_STATE" 2>/dev/null)"; [ -n "$prev_band" ] || prev_band=ok
    prev_at="$(cut -f2 "$BAND_STATE" 2>/dev/null)"
    [ "$BAND" != "$prev_band" ] && { BAND_REASON="전이 ${prev_band}→${BAND}"; return 0; }
    # 같은 구간이 이어질 때: ok 는 조용히, 높은 구간은 주기마다 한 번 더.
    [ "$BAND" = ok ] && { BAND_REASON=suppressed_ok; return 1; }
    case "$prev_at" in ''|*[!0-9]*) BAND_REASON="지속(직전 시각 없음)"; return 0 ;; esac
    now_epoch="$(date +%s)"
    age_min=$(( (now_epoch - prev_at) / 60 ))
    if [ "$age_min" -ge "$BAND_REPEAT_MIN" ]; then
        BAND_REASON="지속 ${age_min}분 ≥ ${BAND_REPEAT_MIN}"
        return 0
    fi
    BAND_REASON="suppressed_repeat(${age_min}/${BAND_REPEAT_MIN}분)"
    return 1
}

if band_should_notify; then
    # 🔑 구간이 ok 로 «내려간» 것도 전이다 — 빼면 「울다 멈춘 것」과 「내려간 것」이 같은 모양이 된다.
    #   창 리셋(util 0 → projected 0 → ok)도 이 경로로 나간다.
    [ -n "$ALERT_MSG" ] || ALERT_MSG="✅ **니노 사용량 정상** — 예상치가 **${MAX_PROJ}%** 로 내려왔어."
    ALERT_MSG="$ALERT_MSG
🔸 구간 「${BAND}」 · ${BAND_REASON}"
    notify "$ALERT_MSG"; nrc=$?
    # 🔸 `if notify` 두 갈래로는 **세 상태를 못 담는다.** dry-run 을 실패로 접으면
    #   `send_failed` 가 되고, 성공으로 접으면 `sent` 가 된다 — 둘 다 거짓이다.
    case "$nrc" in
        0) ALERT=sent ;;
        3) ALERT=dry_run ;;
        *) ALERT=send_failed ;;
    esac
    # 🔴 **보낸 것만 기준선이 된다.** dry-run 으로 진단 한 번 돌린 것이 진짜 알림을 먹으면 안 된다.
    [ "$nrc" -eq 0 ] && printf '%s\t%s\n' "$BAND" "$(date +%s)" > "$BAND_STATE" 2>/dev/null
else
    ALERT=suppressed
fi

exit 0
