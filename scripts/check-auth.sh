#!/usr/bin/env bash
# Claude Code 인증 감지기 (cron 5분 간격)
#
# 🔑 목적은 두 개다 — 판정하는 것과 **판정했다는 사실을 남기는 것**.
#    후자가 없으면 감지기가 죽어도 아무도 모른다(= 고장이 조용하다).
#
# 🔴 배경 (2026-07-25 사고): `jq` 가 없어서 `set -e` 로 **즉사**했고, 그 결과 인증 만료
#    알림이 한 번도 안 나갔다. 증상(jq 의존)만 고치고 *"죽은 걸 아무도 모른다"* 는 안 고쳐서
#    07-30 까지 그대로였다(실측: 로그 0줄 · 경보 발송 기록 0건 ⇒ 5분마다 돈다고 믿을 근거가
#    crontab 한 줄뿐이었다).
#
# 🔑 **로그가 남는 이유는 아래 `trap emit_log EXIT` 이다** — `set -e` 를 안 쓰는 것이 아니다.
#    실측(07-30): `set -euo` + `|| true` 제거로 rc=127 즉사시켜도 trap 이 로그를 남겼다.
#    ⇒ `set -e` 를 피하는 실제 이유는 다른 것이다: 즉사하면 **뒤의 만료 판정까지 못 간다.**
#      로그는 남지만 판정이 반쪽이 된다(status 가 깨져도 만료 판정은 계속돼야 한다 — 시험 ⑤).
#
# 🔴 만료 판정은 **만료 전 60분**이 아니라 **만료 후 미갱신**을 본다 (2026-07-30 변경):
#    refresh 는 자동이고 만료 시점에 돈다 ⇒ *"60분 뒤 만료됨"* 은 사람이 할 일이 없어
#    **항상 거짓 경보**다. 반대로 **만료가 지났는데도 갱신이 안 된 것**이 진짜 사고이고
#    (룬드 2026-07-30: 8시간 27분 먹통), 옛 코드는 그 갈래를 아예 안 봤다.
#    🔑 이 판정은 `claude auth status` 와 **독립**이다 — status 는 저장소만 읽어서
#      만료 토큰에도 loggedIn:true 를 주는 거짓 음성이 있다. 파일의 expiresAt 은 그걸 우회한다.
#
# 🔴 상태 파일을 `/tmp` 에 두지 않는다 — 재부팅이 지워서 사고 다음 날 못 읽는다.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# 주입 가능한 값들 — 시험이 실제 Discord·실제 claude·실제 자격증명을 건드리지 않게 한다.
STATE_DIR="${CHECK_AUTH_STATE_DIR:-$BOT_DIR/logs}"
LOG="${CHECK_AUTH_LOG:-$STATE_DIR/check-auth.log}"
CREDENTIALS="${CHECK_AUTH_CREDENTIALS:-$HOME/.claude/.credentials.json}"
# 🔴 cron 의 PATH 는 `/usr/bin:/bin` 뿐이라 nvm 에 설치된 `claude` 가 안 보인다.
#    그래서 crontab 이 `source ~/.nvm/nvm.sh && ...` 였는데 **cron 의 sh(dash)엔 `source` 가
#    없어서** `&&` 가 끊겼고, 이 감지기가 **한 번도 안 불렸다**(2026-07-30 실측: 새로 붙인
#    로그가 tick 두 번을 지나도 0줄 → cron 쪽을 재서 갈렸다).
#    ⇒ 해석을 스크립트 안으로 가져와 crontab 을 단순하게 만든다(레포 관례: 다른 10줄은
#      스크립트를 직접 부른다). 자리마다 절대경로를 박지 않는다 — nvm 버전이 바뀌면 다 깨진다.
# shellcheck source=scripts/lib/resolve-bin.sh
. "$SCRIPT_DIR/lib/resolve-bin.sh" 2>/dev/null || true
# 🔴 명시적으로 준 CLAUDE_BIN 은 **그대로 쓴다.** 없는 경로를 받았을 때 조용히 실물로
#    갈아타면 (ⓐ)시험의 주입이 무력화되고 (ⓑ)운영에서도 *"지정한 게 없는데 다른 걸 썼다"* 가
#    된다 — 그건 판정 불가로 남아야 하는 상황이다(2026-07-30: 폴백을 붙였다가 시험 ⑤가 잡았다).
if [ -n "${CLAUDE_BIN:-}" ]; then
    :
elif command -v resolve_bin >/dev/null 2>&1; then
    CLAUDE_BIN="$(resolve_bin claude || printf 'claude')"
else
    CLAUDE_BIN=claude
fi
DISCORD_SEND="${DISCORD_SEND:-$BOT_DIR/src/discord-send}"
ALERT_CHANNEL="${CHECK_AUTH_CHANNEL:-현인-업무}"
ALERT_INTERVAL="${CHECK_AUTH_ALERT_INTERVAL:-3600}"     # 같은 경보 재발송 간격
EXPIRY_GRACE="${CHECK_AUTH_EXPIRY_GRACE:-1800}"         # 만료 직후 이 시간은 "갱신 중"으로 본다
MENTION="${CHECK_AUTH_MENTION:-<@353914579929268226>}"

mkdir -p "$STATE_DIR" 2>/dev/null || true
HEARTBEAT="$STATE_DIR/check-auth-heartbeat"
LAST_ALERT_FILE="$STATE_DIR/check-auth-last-alert"
LAST_EXPIRY_FILE="$STATE_DIR/check-auth-last-expiry-alert"

VERDICT=unknown      # ok · logged_out · unknown
ALERT=none           # none · sent · send_failed · skip  (+expiry / +expiry_failed / +expiry_skip 접미)
NOTIFY_RC=""         # 발송 실패 시 discord-send 의 rc
NOTIFY_ERR=""        # 발송 실패 시 stderr 첫 줄 (emit_log 가 별도 줄로 남긴다)
EXPIRY=none          # ok · stale · skip · unknown
REMAIN=na            # 만료까지 남은 초 (음수면 이미 지났다)
NOTE=""

# 🔑 어떤 경로로 끝나도 로그 1줄. 이게 이 스크립트의 핵심이다.
emit_log() {
    local rc=$?
    printf '%s verdict=%s alert=%s expiry=%s remaining=%s rc=%s%s\n' \
        "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$VERDICT" "$ALERT" "$EXPIRY" "$REMAIN" "$rc" \
        "${NOTE:+ note=$NOTE}" >> "$LOG" 2>/dev/null || true
    # 🔑 발송 실패 사유는 **버리지 않는다** — 한 줄 형식을 안 깨게 들여쓴 줄로 붙인다.
    #    (헤드라인 집계 `grep -cE '^[0-9]{4}-'` 를 그대로 두는 core-drift-cron 과 같은 방식)
    [[ -n "$NOTIFY_ERR" ]] && printf '    · discord-send: %s\n' "$NOTIFY_ERR" >> "$LOG" 2>/dev/null
    return 0
}
trap emit_log EXIT

# 🔑 판정보다 **먼저** 찍는다 — "돌긴 했다"와 "판정까지 갔다"는 다른 사실이다.
touch "$HEARTBEAT" 2>/dev/null || true

should_alert() {   # $1=상태파일  $2=간격  → 백오프가 지났으면 0
    local f="$1" iv="$2" last=0
    [[ -f "$f" ]] && last="$(cat "$f" 2>/dev/null || echo 0)"
    case "$last" in ''|*[!0-9]*) last=0 ;; esac
    [[ $(( $(date +%s) - last )) -ge $iv ]]
}
mark_alert() { date +%s > "$1" 2>/dev/null || true; }

# 🔴 예전엔 `… >/dev/null 2>&1 || true` 였고, 호출부는 **무조건** `ALERT=sent` + 백오프를 찍었다.
#    ⇒ discord-send 가 죽어도 로그엔 *보냈다*고 남고, 게다가 1시간 침묵했다.
#    인증이 진짜 끊긴 상황에서 이건 **유일한 복구 수단(사람 호출)이 조용히 사라지는 것**이다.
#    (룬드가 자기 check-auth 에서 먼저 밟고 고친 자리 — 같은 형태로 맞춘다)
# 🔑 성공/실패를 rc 로 돌려주고, **stderr 는 버리지 않는다** — 실패 사유가 유일한 단서다.
# ── 인자 계약 (코어 cli-guard) ───────────────────────────────────────────────
# 🔴 2026-07-31 09:50 사고: 진단하려고 감시기를 **없는 플래그**(`--report`)로 불렀다.
#   인자 파싱이 없어 조용히 무시된 뒤 평소 검사(=발송 포함)가 돌았고 Discord 로 두 방이 나갔다.
#   `rc=0` · stdout 0바이트라 *"아무 일도 안 났다"* 로 읽혔다. 룬드도 같은 날 같은 형태를 밟았다.
#   🔑 고칠 것은 습관이 아니라 **형태**다 — 양봇 다 *조심하려다* 밟았다.
# 🔑 거절도 로그 1줄로 남긴다. cron 은 stderr 를 버리므로, 안 남기면 crontab 오타 하나로
#   **5분마다 도는 이 감시기가 아무 표시 없이 멈춘다** — 그게 이 스크립트가 막으려는 바로 그것이다.
cli_guard_usage() {
    echo "usage: $(basename "$0") [--dry-run] [-h|--help]"
    echo "  --dry-run   판정까지 하되 Discord 발송은 하지 않는다 (진단용)"
}
cli_guard_reject_log() {
    printf '%s verdict=%s rc=2\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$1" >> "$LOG" 2>/dev/null || true
}
CLI_GUARD_ON_REJECT=cli_guard_reject_log
# shellcheck source=scripts/lib/cli-guard-boot.sh
. "$SCRIPT_DIR/lib/cli-guard-boot.sh"
cli_guard_boot "$@"

notify() {
    local err
    # 🔴 **억제는 `cli_guard_send` 한 곳.** dry-run 갈래를 따로 두고 거기서 return 하면 억제
    #   기제가 두 벌이 되고, 뒤엣것은 갈래에 가려 **아무 시험도 안 밟는다**(`#103` 변이 M2 실측).
    err="$(cli_guard_send "$DISCORD_SEND" "$ALERT_CHANNEL" "$1" 2>&1 >/dev/null)"   # stderr 만 잡는다
    local rc=$?
    [[ $rc -eq 0 ]] && return 0
    NOTIFY_RC="$rc"
    # 로그 한 줄 형식을 안 깨게 첫 줄 · 120자로 자른다(원문은 아래 emit_log 가 별도 줄로 남긴다)
    NOTIFY_ERR="$(printf '%s' "$err" | head -1 | cut -c1-120)"
    return 1
}

# ── ① 로그인 상태 ────────────────────────────────────────────────────────────
# ⚠️ `claude auth status` 는 **저장소만 본다** — env 토큰(CLAUDE_CODE_OAUTH_TOKEN)으로
#    도는 환경에서는 정상인데 loggedIn:false 가 나온다(룬드 2026-07-30 14:38 거짓 DM).
#    근본 수정(실제 요청을 쳐서 200/401 로 가르는 능동 프로브)은 사용량 실측 후 별 PR.
STATUS="$("$CLAUDE_BIN" auth status 2>&1)" || true
LOGGED_IN="$(printf '%s' "$STATUS" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    print("unknown"); raise SystemExit(0)
v = d.get("loggedIn")
print("true" if v is True else ("false" if v is False else "unknown"))
' 2>/dev/null || echo unknown)"

case "$LOGGED_IN" in
    true)  VERDICT=ok ;;
    false) VERDICT=logged_out ;;
    *)     VERDICT=unknown; NOTE="auth-status-unreadable" ;;
esac

if [[ "$VERDICT" == "logged_out" ]]; then
    if should_alert "$LAST_ALERT_FILE" "$ALERT_INTERVAL"; then
        if notify "$MENTION Claude Code 인증이 만료됐어! tmux attach -t nino 후 /login 해줘"; then
            mark_alert "$LAST_ALERT_FILE"
            ALERT=sent
        else
            # 🔑 **백오프를 안 찍는다** — 찍으면 다음 기회를 스스로 지운다. 일시 장애였다면
            #    1시간이 통째로 사라지고, 그 사이 사람은 아무 신호도 못 받는다.
            ALERT=send_failed
            NOTE="${NOTE:+$NOTE,}discord-send-failed(rc=${NOTIFY_RC:-na})"
        fi
    else
        ALERT=skip
    fi
else
    # 🔸 회복되면 백오프를 초기화한다 — 다음 사고를 1시간 늦게 알리지 않게.
    rm -f "$LAST_ALERT_FILE" 2>/dev/null || true
fi

# ── ② 만료 후 미갱신 ─────────────────────────────────────────────────────────
if [[ -f "$CREDENTIALS" ]]; then
    REMAIN="$(python3 - "$CREDENTIALS" <<'PYEOF' 2>/dev/null || echo na
import sys, json, time
try:
    d = json.load(open(sys.argv[1]))
    print(int(d["claudeAiOauth"]["expiresAt"] / 1000 - time.time()))
except Exception:
    print("na")
PYEOF
)"
    case "$REMAIN" in
        ''|na|*[!0-9-]*)
            EXPIRY=unknown; NOTE="${NOTE:+$NOTE,}credentials-unreadable" ;;
        *)
            if [[ $REMAIN -lt $(( -EXPIRY_GRACE )) ]]; then
                EXPIRY=stale
                if should_alert "$LAST_EXPIRY_FILE" "$ALERT_INTERVAL"; then
                    # ⚠️ 호출부가 **둘**이다(로그아웃·여기). 한 자리만 고치면 다른 자리가 남고,
                    #    같은 계약이 여러 자리에 있으면 **한 자리만 덮고도 초록**이 된다(시험 ⑭).
                    if notify "$MENTION 니노 토큰이 $(( -REMAIN / 60 ))분 전에 만료됐는데 갱신이 안 되고 있어! tmux attach -t nino 후 /login 해줘"; then
                        mark_alert "$LAST_EXPIRY_FILE"
                        ALERT="${ALERT}+expiry"
                    else
                        ALERT="${ALERT}+expiry_failed"
                        NOTE="${NOTE:+$NOTE,}discord-send-failed(rc=${NOTIFY_RC:-na})"
                    fi
                else
                    ALERT="${ALERT}+expiry_skip"
                fi
            else
                EXPIRY=ok
                rm -f "$LAST_EXPIRY_FILE" 2>/dev/null || true
            fi ;;
    esac
else
    # 🔴 파일 부재를 "만료"로 접지 않는다 — env 토큰 방식이면 저장소가 원래 비어 있다.
    #    접으면 정상 동작하는 봇에 오보가 간다(룬드가 당한 거짓 양성의 형태).
    EXPIRY=skip; NOTE="${NOTE:+$NOTE,}no-credentials-file"
fi

exit 0
