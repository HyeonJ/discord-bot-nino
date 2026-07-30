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
CLAUDE_BIN="${CLAUDE_BIN:-claude}"
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
ALERT=none           # none · sent · skip  (+expiry / +expiry_skip 접미)
EXPIRY=none          # ok · stale · skip · unknown
REMAIN=na            # 만료까지 남은 초 (음수면 이미 지났다)
NOTE=""

# 🔑 어떤 경로로 끝나도 로그 1줄. 이게 이 스크립트의 핵심이다.
emit_log() {
    local rc=$?
    printf '%s verdict=%s alert=%s expiry=%s remaining=%s rc=%s%s\n' \
        "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$VERDICT" "$ALERT" "$EXPIRY" "$REMAIN" "$rc" \
        "${NOTE:+ note=$NOTE}" >> "$LOG" 2>/dev/null || true
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
notify()     { "$DISCORD_SEND" "$ALERT_CHANNEL" "$1" >/dev/null 2>&1 || true; }

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
        notify "$MENTION Claude Code 인증이 만료됐어! tmux attach -t nino 후 /login 해줘"
        mark_alert "$LAST_ALERT_FILE"
        ALERT=sent
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
                    notify "$MENTION 니노 토큰이 $(( -REMAIN / 60 ))분 전에 만료됐는데 갱신이 안 되고 있어! tmux attach -t nino 후 /login 해줘"
                    mark_alert "$LAST_EXPIRY_FILE"
                    ALERT="${ALERT}+expiry"
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
