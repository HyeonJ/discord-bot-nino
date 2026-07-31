#!/bin/bash
# nino-watchdog.sh — 2분마다 crontab으로 실행, tmux/Claude 죽으면 자동 재시작 + 디코 알림
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SESSION="nino"
LOG="$BOT_DIR/logs/watchdog.log"

# ── 감시자 자신의 관측 가능성 ────────────────────────────────────────────────
# 🔴 2026-07-30: check-auth 는 cron 이 4.6일 · 약 1,340회 실행으로 기록하는 동안
#    **한 번도 안 돌았다**(syslog CMD 50건 vs 자기 로그 0줄). `sh -c "source … && X"`
#    는 `&&` 앞이 끊겨도 cron 이 성공으로 센다 ⇒ **스케줄러 기록은 실행을 증명하지 않는다.**
#    워치독은 정상이면 완전히 침묵하는 설계라 같은 사각에 있었다(35분 공백을 실제로 오독했다).
# 🔑 파일 하나로 재는 이유는 **판별법이 기계 독립이어야 하기 때문**(룬드 M:yrne):
#    launchd 는 `runs` 카운터로 기동을 보증하지만 cron 에는 그런 값이 없다.
# 🔑 진입과 완주를 **한 파일에서** 가른다 — 진입 즉시 `rc=running`, 종료 시 trap 이 실제 rc.
#    ⚠️ SIGKILL 은 trap 도 못 돌므로 `rc=running` 이 남는다: "죽었다"와 "지금 돌고 있다"가
#      한 tick 동안 겹친다. 2분 주기라 다음 tick 이 갱신하니 실무상 문제는 없지만,
#      **완벽히 갈리지는 않는다**는 걸 적어둔다(이걸 "돈다"의 증거로 쓰면 안 되는 유일한 창).
WD_HEARTBEAT="${NINO_WD_HEARTBEAT:-$BOT_DIR/logs/watchdog.heartbeat}"
mkdir -p "$(dirname "$WD_HEARTBEAT")" 2>/dev/null || true
wd_beat() { printf '%s rc=%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$1" > "$WD_HEARTBEAT" 2>/dev/null || true; }
# 🔴 trap 을 **먼저** 건다 — 반대로 하면 `wd_beat running` 과 trap 설치 사이의 구간이
#    사각이 된다(그 창에서 죽으면 rc=running 이 남아 "지금 돌고 있다"로 오독된다).
#    시험이 이 순서를 잡았다: 변이 사본이 rc=3 대신 rc=running 을 남겼다.
trap 'wd_beat "$?"' EXIT
wd_beat running

# 🔴 `source … || true` 로 쓰면 **bash 3.2 에서 `|| true` 가 source 실패를 못 잡고 죽는다.**
#    (룬드 맥 실측 2026-07-29 · 니노 bash 5.2 대조 확인 — 5.x 는 안 죽는다 = 버전 차이)
#    죽으면 **실패 신호가 셋 다 없다**: stderr 없음 · 종료코드만 1 · log() 정의 전이라 로그도 없음.
#    ⚠️ 같은 줄에서 **같은 클래스가 두 번째다** — 위 10행 주석의 `jq` 건도 여기였다.
#    조건문은 `set -e` 면제라 이 형태가 정본. (이 줄이 파일 마지막이면 rc 가 1이 되니 주의)
[ -f "$BOT_DIR/.env" ] && source "$BOT_DIR/.env"

# 🔴 **알림 자리의 첫 줄은 주입점이어야 한다** (2026-07-31 룬드 실사고에서 옮겨온 규칙).
#    그의 check-usage-alert 는 전송 경로가 하드코딩이라 **시험이 형 채널로 84건을 실제로 쐈다**
#    (06:28:08~06:32:12). 나중에 빼면 이미 한 번 쏜 뒤고, **알림은 되돌릴 수 없다.**
# 🔸 여기는 지금도 안 샌다 — 시험이 가짜 `$BOT_DIR` 트리를 깔아 스텁을 물린다. 다만 그건
#    *BOT_DIR 을 돌릴 수 있다는 간접 안전*이라, 누가 시험을 실제 BOT_DIR 로 돌리는 순간 샌다.
#    ⇒ 안전을 **경로 조작에 기대지 말고 명시적 주입점**으로 옮긴다.
# ⚠️ 채널도 같이 뺀다 — 경로만 빼면 스텁을 안 물린 시험이 **실채널 인자**로 나간다(룬드도 둘 다 뺐다).
# 🔴🔴 **기본값을 주변 환경에서 끌어오지 않는다.** 2026-07-31 06:46, 내가 여기에
#    `${DISCORD_SEND_BIN:-…}` 한 겹을 끼웠다가 **현인-업무로 41건을 실제로 쐈다(79초)**.
#    `DISCORD_SEND_BIN` 은 `.env` 에 있고 **내 tmux 셸의 주변 환경에 이미 떠 있어서**,
#    시험이 가짜 `$BOT_DIR` 를 깔아도 그 한 겹이 **실물 경로로 되돌려놨다.**
# 🔑 교훈: 주입점은 *시험이 값을 넣는 자리*지 *환경이 값을 넣는 자리*가 아니다.
#    폴백 사슬을 늘리면 늘린 칸마다 **시험이 모르는 입력구**가 하나씩 생긴다.
#    ⇒ 사슬은 두 칸까지. 명시 주입(시험) → 이 파일의 리터럴 기본값(운영). 그 사이는 비운다.
# 🔴 `.env` **뒤**에 둔다 — 앞에 두면 `.env` 가 같은 이름을 정의하는 순간 주입이 조용히 덮인다.
DISCORD_SEND="${DISCORD_SEND:-$BOT_DIR/src/discord-send}"
# jq 미설치 + set -e 조합으로 워치독이 여기서 죽어 자동 재시작이 동작하지 않았다(2026-07-25 발견).
ALERT_CHANNEL="${ALERT_CHANNEL:-현인-업무}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"; }

# ── 인자 계약 (코어 cli-guard) ────────────────────────────────────────────────
# 🔴 2026-07-31 09:50 사고의 형태: 진단하려고 모르는 플래그로 불렀는데 파싱이 없어
#    조용히 무시되고 **평소 동작이 통째로** 돌았다. 여기서 그게 나면 발송만이 아니라
#    **니노를 실제로 재시작한다** — 진단 한 번이 대화 맥락을 날린다.
#    ⇒ 이 파일의 `--dry-run` 은 발송과 복구를 **둘 다** 막는다. 한쪽만 막으면
#      "부작용 없음"이라 믿고 부르는데 더 큰 쪽이 열려 있다.
# 🔑 `trap` 뒤에 둔다 — 거절되면 EXIT trap 이 하트비트에 실제 rc(2)를 남긴다.
#    거절이 하트비트에 안 남으면 *"안 돌았다"* 와 *"잘못 불렀다"* 가 같은 모습이 된다.
cli_guard_usage() {
    echo "usage: $(basename "$0") [--dry-run] [-h|--help]"
    echo "  --dry-run   검사는 하되 Discord 발송·재시작은 하지 않는다 (진단용)"
}
cli_guard_reject_log() { log "CLI-GUARD-REJECT: $1 — 인자를 거절했다(발송·복구 없음)"; }
CLI_GUARD_ON_REJECT=cli_guard_reject_log
# shellcheck source=scripts/lib/cli-guard-boot.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/cli-guard-boot.sh"
cli_guard_boot "$@"

# ── 복구 목 ──────────────────────────────────────────────────────────────────
# 발송에 `wd_send` 가 있듯 복구엔 여기 하나. 세 곳(start·restart×2)이 전부 지난다.
wd_restart() {   # $@ = 복구 명령
    if [ "$CLI_DRY_RUN" = "1" ]; then
        log "DRY-RUN-RESTART: 복구를 실행하지 않았다 → $*"
        return 0
    fi
    "$@" >> "$LOG" 2>&1
}

# ── 발송 목 ──────────────────────────────────────────────────────────────────
# 🔴 경보 발송은 **여기 한 곳**만 지난다. 예전엔 네 곳에 흩어져 있었는데, 그러면
#    가드든 로깅이든 3곳만 덮었을 때 **덮인 3곳이 안 덮인 1곳을 가린다** — 시험은
#    초록인데 한 갈래만 실채널로 샌다. 목이 하나면 덮었나/안 덮었나가 셀 수 있는 값이 된다.
# 🔴 그리고 예전 네 곳은 전부 `2>/dev/null || true` 였다. 발송이 실패하면
#    **stderr 없음 · rc 영향 없음 · 로그 없음** — 실패 신호가 셋 다 없었다.
#    ⇒ *"경보가 안 왔다"* 와 *"경보를 보냈는데 실패했다"* 가 사람 눈에 같은 값이었다.
#    조용한 게 정상인 감시 장치라 아무도 안 물어본다. 그래서 실패를 로그로 남긴다.
# ⚠️ 그래도 rc 는 항상 0 이다 — **경보 실패가 감시를 멈추면 안 된다**(`set -e` 아래다).
# ⚠️ stderr 는 계속 버린다: 여기 나오는 건 discord-send 의 진단문이고 cron 이 그걸 메일로
#    돌린다. 사실 자체는 로그에 남으니 잃는 게 없다 — 버리는 건 문구이지 신호가 아니다.
wd_send() {   # $@ = 본문. 채널은 $ALERT_CHANNEL 고정
    local rc=0
    # 🔴 dry-run 이어도 **여기서 return 하지 않는다.** 억제를 두 벌로 두면 뒤엣것
    #   (`cli_guard_send`)이 가려져 시험이 안 닿고, 변이를 걸어도 안 죽는다(#103 M2).
    #   ⇒ 보이게 하는 일(로그)만 여기서 하고, 막는 일은 코어 계약에 맡긴다.
    if [ "$CLI_DRY_RUN" = "1" ]; then
        log "DRY-RUN-SEND: 경보를 보내지 않았다"
    fi
    cli_guard_send $DISCORD_SEND "$ALERT_CHANNEL" "$@" 2>/dev/null || rc=$?
    if [ "$rc" -ne 0 ]; then
        log "SEND-FAILED: 경보를 못 보냈다 rc=$rc — 이 줄이 없으면 '안 왔다'와 구별이 안 된다"
    fi
    return 0
}

# 🔸 이름 충돌 경고 — **읽지는 않는다**(룬드 `#93` 리뷰 제안).
#    시험이 "`.env` 가 이 두 이름을 안 쓴다"를 계약으로 잡지만, **사람이 `.env` 를 손으로 고치고
#    시험을 안 돌리면** 그 계약은 아무 말도 안 한다. 그 창을 런타임에서 메운다.
#    🔑 값을 *쓰지* 않는 게 핵심이다 — 쓰면 폴백 사슬이 한 칸 늘고, 그게 06:46 사고였다.
# 🔴 **`log()` 정의 아래**에 둔다. 처음엔 대입 바로 옆(52행)에 뒀는데, `log` 은 65행에서야
#    정의되므로 `set -e` 아래에서 rc=127 로 **워치독이 통째로 죽는다** — 이 파일 34행 주석이
#    증언하는 2026-07-25 `jq` 사고와 **같은 형태**다. 죽으면 감시가 조용히 사라진다.
# ⚠️ `grep` rc 를 갈라 본다. `if grep …; then` 만 쓰면 grep 이 죽었을 때(rc=2) 조건이 거짓이 되어
#    **가드가 실패하면서 열린다** — 내가 코어 `#106` 에서 지적한 그 형태다.
if [ -f "$BOT_DIR/.env" ]; then
    _clash_rc=0
    grep -qE '^[[:space:]]*(export[[:space:]]+)?(DISCORD_SEND|ALERT_CHANNEL)=' "$BOT_DIR/.env" || _clash_rc=$?
    case "$_clash_rc" in
        0) log "ENV-NAME-CLASH: .env 가 DISCORD_SEND/ALERT_CHANNEL 을 정의한다 — 주입점을 조용히 덮는다(값은 안 읽었다)" ;;
        1) : ;;   # 충돌 없음 = 정상
        *) log "ENV-NAME-CLASH-UNKNOWN: .env 를 못 읽어 이름 충돌을 **판정 못 했다**(grep rc=$_clash_rc)" ;;
    esac
fi


# ── 재시작 알림의 억제 ────────────────────────────────────────────────────────
# 🔴 2026-07-31 실측: 전송 6곳 중 **셋(재시작 알림)에 억제가 없었다.** 2분 주기라
#   재시작이 계속 실패하면 **시간당 30건이 천장 없이** 나간다. 같은 새벽에 79초 41건을
#   겪고서 *"막을 게 아무것도 없다"* 를 룬드와 같이 짚은 자리다.
# 🔑 그런데 **조용히 만들면 안 된다** — 재시작이 반복 실패하는 건 진짜 장애다.
#   ⇒ 억제가 아니라 **접기**다: 첫 건은 즉시, 이후 창 안의 반복은 세었다가
#     다음 알림에 **몇 번이었는지 실어** 보낸다. 30줄이 1줄이 되고 정보는 늘어난다.
# 🔸 원인별로 **다른 파일**을 쓴다(다른 축과 같은 관례) — 세션 사망이 얼어붙음을 침묵시키면 안 된다.
RESTART_BACKOFF=${NINO_RESTART_BACKOFF:-3600}

# restart_notify <원인표지> <사람이 읽을 문구>
#   창 안이면 조용히 세기만 하고 rc=1. 보낼 때는 누적 횟수를 문구에 붙인다.
restart_notify() {
    local cause="$1" msg="$2"
    local state="$BOT_DIR/logs/watchdog-restart-${cause}-next"
    local count="$BOT_DIR/logs/watchdog-restart-${cause}-count"
    local now next n
    now=$(date +%s)
    next=$(cat "$state" 2>/dev/null || echo 0)
    case "$next" in ''|*[!0-9]*) next=0 ;; esac
    n=$(cat "$count" 2>/dev/null || echo 0)
    case "$n" in ''|*[!0-9]*) n=0 ;; esac
    n=$((n + 1))
    if [ "$now" -lt "$next" ]; then
        printf '%s' "$n" > "$count" 2>/dev/null || true
        log "${cause}-SUPPRESSED: 창 안 ${n}번째 — 다음 알림에 합쳐 보낸다"
        return 1
    fi
    # 🔸 2회 이상일 때만 횟수를 붙인다 — 1회에 "1번째"는 소음이다
    [ "$n" -ge 2 ] && msg="$msg

🔸 최근 $((RESTART_BACKOFF / 60))분 동안 **${n}번째** 재시작이야. 반복되면 자동 복구로는 안 되는 상태일 수 있어."
    wd_send "$msg"
    printf '%s' "$((now + RESTART_BACKOFF))" > "$state" 2>/dev/null || true
    printf '0' > "$count" 2>/dev/null || true
    return 0
}

# Check 1: tmux 세션 살아있는지
if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    log "DEAD-SESSION: tmux session '$SESSION' not found. Restarting..."
    wd_restart "$SCRIPT_DIR/start-nino.sh"
    restart_notify DEAD-SESSION "니노가 죽어서 자동 재시작했어! (tmux 세션 없음)" || true
    exit 0
fi

# Check 2: tmux pane 안에 프로세스가 살아있는지
PANE_PID=$(tmux list-panes -t "$SESSION" -F '#{pane_pid}' 2>/dev/null | head -1)
if [ -z "$PANE_PID" ] || ! kill -0 "$PANE_PID" 2>/dev/null; then
    log "DEAD-PROC: pane process gone (PID: $PANE_PID). Respawning..."
    wd_restart "$SCRIPT_DIR/restart-nino.sh"
    restart_notify DEAD-PROC "니노 프로세스가 죽어서 자동 재시작했어! (pane 프로세스 없음)" || true
    exit 0
fi

# Check 3: Claude 프로세스가 D state(uninterruptible sleep)인지
CLAUDE_PID=$(pgrep -P "$PANE_PID" -f "claude" 2>/dev/null | head -1 || true)
if [ -n "$CLAUDE_PID" ]; then
    STATE=$(awk '/^State:/{print $2}' /proc/$CLAUDE_PID/status 2>/dev/null || echo "?")
    if [ "$STATE" = "D" ]; then
        log "FROZEN: Claude PID $CLAUDE_PID in D state. Restarting..."
        wd_restart "$SCRIPT_DIR/restart-nino.sh"
        restart_notify FROZEN "니노가 얼어서 자동 재시작했어! (프로세스 D state)" || true
        exit 0
    fi
fi

# 🔑 로그 표지는 **원인마다 고유해야 한다** (2026-07-29, Darren 승인 M:wdb9)
#   `DEAD:` 하나를 tmux 세션 사망과 pane 프로세스 사망에 같이 썼다. Discord 문구는 갈려 있었지만
#   **로그로 사후 집계**할 때 두 원인이 한 칸으로 뭉쳤다 — *"뭐 때문에 죽었나"* 를 못 센다.
#   ⇒ DEAD-SESSION / DEAD-PROC 로 분리. 겹침은 시험이 구조로 잠근다(새 표지를 늘려도 걸린다).

# ── 🔴 Check 5: 인증 축 — 401 은 침묵으로 **원리적으로** 안 잡힌다 ────────────
#   (Check 4 보다 **앞**에 둔다. 4 는 조용한 밤·긴 턴에서 exit 0 으로 빠지는데,
#    401 은 바로 그때 나기 때문이다 — 뒤에 두면 건너뛴다.)
#
# 🔴 왜 새 축이 필요한가 (2026-07-29, Tim 질문에서 발견 · Darren 승인 M:wh7t):
#   401 은 "멈춤"이 아니라 **에러를 뱉고 턴을 끝내는 것**이다.
#     ⇒ Stop 훅이 계속 돌아 하트비트가 신선하게 유지된다 ⇒ Check 4 에 안 걸린다.
#     ⇒ 도구 호출도 계속되므로 활동 축(#71)에도 안 걸린다.
#   내 실측(7/17 에피소드): 44분 35초 · 401 21건 · 간격 중앙 110초 · **60분 초과 간격 0건**
#     ⇒ 에피소드가 임계(60분)보다 짧아 **침묵 감시로는 못 잡는다.** 임계를 낮추면 오탐이 는다.
#   ⇒ 자원·산출·활동 어디에도 없는 축이라 새로 만든다.
#
# 🔑 조회는 **구조적 플래그**로 한다 — `isApiErrorMessage: true`.
#   문자열 grep 은 **내가 401 을 주제로 쓴 글까지 센다**(실측: 49건 중 진짜 0건).
# ⚠️ `API Error: 401` 로 잡으면 소켓 끊김(`401 The socket connection was closed`)까지 걸려 오탐.
#   세 변종에 공통이면서 안전한 건 `Please run /login`.
# ⚠️ 529·502 는 **서버측 일시 장애**라 사람이 할 일이 없다 — 안 센다.
# 🔴 **복구하지 않는다.** 401 에 재시작·`/clear` 를 쏘면 인증은 그대로고 맥락만 날아간다(Tim M:s2um).
SESSION_LOG_DIR="${NINO_SESSION_LOG_DIR:-$HOME/.claude/projects/-home-bpx27-discord-bot-nino}"
AUTH_STATE="$BOT_DIR/logs/watchdog-auth-next"      # 침묵 축과 **다른 파일** — 서로 침묵시키지 않게
AUTH_MIN_COUNT=${NINO_AUTH_MIN_COUNT:-3}           # 1~2건은 재시도로 지나간다
AUTH_WINDOW=${NINO_AUTH_WINDOW:-3600}              # 이 창 안의 건수만 센다(지난 사고로 영원히 부르지 않게)

# 최근 창 안의 인증 에러 건수. 셀 수 없으면 "unknown".
auth_errors_recent() {
    [ -d "$SESSION_LOG_DIR" ] || { printf 'unknown'; return 0; }
    local n
    n=$(python3 - "$SESSION_LOG_DIR" "$AUTH_WINDOW" <<'PYEOF' 2>/dev/null || true
import sys, os, json, glob, datetime, time
d, win = sys.argv[1], int(sys.argv[2])
files = glob.glob(os.path.join(d, "*.jsonl"))
if not files:
    raise SystemExit(1)
# 🔴 파일 선택은 **개수가 아니라 mtime 창**으로 (2026-07-29, Darren 승인 M:48kb)
#   사고 중 재시작되면 새 파일이 생기고 **직전 증거는 옛 파일에 남는다** — 최신 하나만 보면 못 본다.
#   그렇다고 `ls -t | head -N` 로 N 을 고르면 그 N 의 근거가 *관측*이지 계약이 아니게 된다
#   (룬드는 "재시작해도 파일이 안 바뀌더라"로 2개를 골랐는데, 그건 `--continue` 가 성공한 관측이다.
#    나는 모델 교체 때 fresh 세션이 필요해 **파일이 바뀌는 경로가 정상 운영 안에 있다**).
#
# 🔑 원리: **창 안에 안 쓰인 파일은 창 안의 레코드를 가질 수 없다.**
#   append-only 라 mtime 이 곧 그 파일의 최신 레코드 시각이기 때문. ⇒ N 이 필요 없고
#   재시작이 몇 번 연달아 나도 자동으로 맞는다. 시간 창이 타임스탬프로 또 거르므로 오탐도 안 는다.
# ⚠️ 여유 5분 — mtime 과 레코드 시각 사이의 오차·시계 흔들림을 흡수한다.
cutoff = time.time() - (win + 300)
sel = [p for p in files if os.path.getmtime(p) >= cutoff]
# 🟡 하나도 없으면 **최근 에러 0건**이지 판정 불가가 아니다(파일 자체는 있으니 조회는 성공했다).
now = datetime.datetime.now(datetime.timezone.utc)
n = 0
for path in sel:
  with open(path, errors="replace") as f:
    for line in f:
        if "isApiErrorMessage" not in line:      # 선필터 — 70MB 전수도 0.14초
            continue
        try:
            r = json.loads(line)
        except Exception:
            continue
        if not r.get("isApiErrorMessage"):
            continue
        c = r.get("message", {}).get("content")
        t = c if isinstance(c, str) else json.dumps(c, ensure_ascii=False)
        if "Please run /login" not in t:          # 529·502·소켓끊김은 안 센다
            continue
        ts = r.get("timestamp", "")
        try:
            when = datetime.datetime.fromisoformat(ts.replace("Z", "+00:00"))
        except Exception:
            continue
        if (now - when).total_seconds() <= win:
            n += 1
print(n)
PYEOF
)
    case "${n:-}" in ''|*[!0-9]*) printf 'unknown' ;; *) printf '%s' "$n" ;; esac
}

AUTH_N=$(auth_errors_recent)
if [ "$AUTH_N" = "unknown" ]; then
    log "AUTH-UNKNOWN: 세션 로그($SESSION_LOG_DIR)를 못 읽었다 — 인증 상태를 가릴 수 없다."
elif [ "$AUTH_N" -ge "$AUTH_MIN_COUNT" ]; then
    AUTH_NEXT=$(cat "$AUTH_STATE" 2>/dev/null || echo 0)
    case "$AUTH_NEXT" in ''|*[!0-9]*) AUTH_NEXT=0 ;; esac
    if [ "$(date +%s)" -ge "$AUTH_NEXT" ]; then
        log "AUTH: 최근 $((AUTH_WINDOW / 60))분 안에 인증 에러 ${AUTH_N}건. 사람 호출(복구 안 함)."
        wd_send "<@353914579929268226> 🔴 니노 **로그인이 풀린 것 같아.** 최근 $((AUTH_WINDOW / 60))분 동안 인증 에러가 **${AUTH_N}건** 났어.

이건 조용히 죽는 게 아니라 **에러를 뱉으면서 계속 도는 상태**라, 겉보기엔 멀쩡해 보여도 실제로는 아무 일도 못 하고 있어.

확인: WSL에서 \`tmux attach -t nino\` → \`/login\`. 브라우저 인증이라 내가 못 해.

재시작은 안 했어 — 토큰 문제라 재시작해도 그대로고 지금까지 맥락만 날아가거든."
        echo "$(( $(date +%s) + 1800 ))" > "$AUTH_STATE"   # 30분 뒤에 다시 부를 수 있다
    fi
    exit 0
else
    [ -f "$AUTH_STATE" ] && rm -f "$AUTH_STATE"            # 회복 — 다음 사고에 즉시 부른다
fi

# ── 🔴 Check 4: 산출 축 — "살아 있나"가 아니라 "말을 하고 있나" ────────────
#   2026-07-29 실사고(룬드): 세션이 **살아 있는 채로** 9시간 50분 침묵했다.
#     tmux · claude 프로세스 · relay 전부 정상 / 응답만 401 × 21회 / 9시 기상 알람 실패
#   위 Check 1~3 은 전부 *자원*(있나)을 본다. "살아서 401만 뱉는 상태"는 그 밖이다.
#   ⇒ 자원 축은 원인마다 분기가 필요해 **새 원인마다 또 뚫린다.**
#     산출 축 하나면 만료·한도소진·얼어붙음이 전부 걸린다. (Darren 승인 M:53qr)
#
# 🔑 앵커는 Stop 훅 하트비트다 — **세션만이 쓸 수 있다.**
#   `last-seen --author 니노` 로 대신하면 안 된다: 니노 이름으로 말하는 cron 이 7개라
#   침묵 중에도 앵커가 "지금"이 되어 **영영 안 걸린다**(#63 이 고친 그 오염).
#
# 🔑 복구하지 않는다. **사람을 부른다.**
#   401 은 재시작으로 안 풀리고(새 세션도 같은 토큰으로 401), 살아 있는 맥락만 날린다.
#
# 🔴 본문은 **원인 셋을 다 열고, 각각 할 일을 갈라 적는다** (2026-07-29, Darren 승인 M:5egf)
#   이 축은 산출이 멎은 것만 안다 — **어느 원인인지 구분하지 못한다.**
#   실측(내 API 에러 전수 36건): 인증 21 · **한도 소진 10** · 서버측 5.
#   한도 소진은 `Please run /login` 이 없어(인증 문제가 아니다) 인증 축이 안 세는데,
#   그동안 발화가 없으니 **이 축엔 걸린다.** 그때 본문이 로그인만 가리키면
#   Darren 이 **필요 없는 `/login` 을 친다** — 한도는 리셋되면 저절로 낫는다.
#   ⇒ 가능성만 나열하는 걸로는 부족하다. **화면에 뭐가 보이면 뭘 하라**까지 적는다.
#   🔸 룬드도 같은 줄을 갖고 있다 — 겪어서가 아니라 *이 상태가 될 수 있는 경로*를 나열해서.
#     표본 귀납보다 경로 나열이 먼저다(룬드 M:rp00). 문구를 맞춰 양쪽을 같게 둔다.
#
# 🔴 그런데 하트비트만으로는 **조용한 밤과 먹통을 구별하지 못한다** (2026-07-29 발견)
#   하트비트는 Stop 훅이라 *턴이 끝날 때* 갱신된다. 아무도 말을 안 걸면 턴 자체가 없다.
#   ⇒ "건강"이 아니라 **"마지막 대화 종료 시각"** 이다. DB 실측(최근 400발화):
#       07-27 16:02→17:31 89분 · 17:31→18:38 67분 · 20:04→21:15 71분
#       07-28 18:15→19:15 · 21:15→22:15 · 22:15→23:15  (정시 간격 = 그 사이 턴 없음)
#     정상 운영 중에 60분 초과 공백이 7건이다 — 임계값 바로 위라 **매일 밤 걸린다.**
#   🔑 거짓 호출이 반복되면 사람이 알림을 끈다. 그러면 진짜가 왔을 때 오늘과 같은 결과다 —
#     이 기능의 존재 이유를 스스로 무너뜨리는 방향이라 그냥 두면 안 된다.
#
# 🔑 축을 하나 더 쓴다: **응답할 것이 있었나.**
#   수신은 relay 가 DB 에 적는다 — **세션과 별개 프로세스라 401 침묵 중에도 계속 쌓였다.**
#   (yaksu-history 도움말이 앵커의 *함정*으로 적어둔 그 성질이 여기선 **신호**다.)
#     수신 없음 + 턴 없음 → 조용함  ✅ 안 부른다
#     수신 있음 + 턴 없음 → 먹통    🔴 부른다   (9시간 50분 사고는 그대로 걸린다)
#   ⚠️ 니노 **자기 발화는 수신으로 세지 않는다** — cron 발신자 7개가 니노 이름으로 말한다.
#     세면 cron 이 앵커를 오염시키던 #63 과 같은 함정이 판정 쪽에서 재현된다.
SILENCE_LIMIT=${NINO_SILENCE_LIMIT:-3600}          # 기본 60분
HEARTBEAT_FILE="$BOT_DIR/logs/session-heartbeat-utc"
# 🔴 활동 축 — "살아 있다"는 흔적. 원천이 **둘**이다(activity_age 머리말 참조):
#   ① 도구 호출마다 갱신되는 파일(PostToolUse 훅)  ② 세션 기록 jsonl 의 마지막 시각(턴 시작 포함)
#   하트비트와 **파일이 달라야 한다**: 하트비트는 재시작 따라잡기 앵커라
#   의미를 바꾸면 catchup 이 깨진다(#63). 자세한 배경·계약은 hooks/session-activity.sh 머리말.
ACTIVITY_FILE="$BOT_DIR/logs/session-activity-utc"
SILENCE_STATE="$BOT_DIR/logs/watchdog-silence-next"
# 🔴 절대경로로 박으면 **시험이 실물 DB 를 읽는다.** 주입 seam 을 둔다(기본값은 실물과 동일).
HISTORY_CLI="${NINO_HISTORY_CLI:-$HOME/.local/bin/yaksu-history}"

# 세션이 마지막으로 **살아 있다는 흔적**을 남긴 뒤 몇 초 지났나. 아무 데서도 못 읽으면 "unknown".
# 🔴 부재·손상은 **정지가 아니라 판정 불가**다. 이 값으로 알림을 *막을 수만* 있고
#   이 값 때문에 알림이 *나가지는* 않는다(억제기 전용 — 부르는 쪽은 하트비트가 정한다).
#
# 🔴 원천이 **둘**인 이유 (2026-07-29 룬드 실오탐 #2):
#   훅(PostToolUse)은 **도구를 부를 때만** 찍는다. 그래서 *도구를 하나도 안 부르는 긴 턴*은
#   여전히 죽어 보인다 — 룬드가 21:21 에 61분 턴으로 맞았다(5분 뒤 재개).
#   턴 *시작* 신호가 필요한데, **세션 기록(jsonl)에 이미 남아 있다**:
#   턴이 도는 중에 user 레코드가 먼저 flush 된다(2026-07-29 21:53 실측 —
#   assistant 산출이 아직 없는 시점에 그 턴의 user 레코드가 디스크에 있었다).
#   ⇒ 훅을 하나 더 달지 않고 덮는다. 덤으로 훅 계약의 약점도 준다:
#     jsonl 은 내 훅이 아니라 Claude Code 가 쓰므로, **훅이 죽어도 원천 하나가 남는다.**
activity_age() {
    local now e
    now=$(date +%s)
    e=$(python3 - "$ACTIVITY_FILE" "$SESSION_LOG_DIR" "$now" <<'PYEOF' 2>/dev/null || true
import sys, os, re, glob, datetime

now = int(sys.argv[3])
best = None


def stamp(s):
    try:
        t = int(datetime.datetime.fromisoformat(s.strip().replace("Z", "+00:00")).timestamp())
    except Exception:
        return None
    # 🔴 미래 시각은 버린다. 깨진 값 하나가 억제를 **영구히** 걸어 감시를 조용히 끄는 자리다
    #   (incoming_since 에서 '조회 실패가 0건이 되어 눈이 머는' 것과 같은 형태).
    return None if t > now + 300 else t


# ① 도구 호출 — 훅이 남긴 시각
try:
    best = stamp(open(sys.argv[1]).read())
except Exception:
    pass

# ② 턴 시작 — 세션 기록의 마지막 시각. 꼬리만 읽는다(파일이 수십 MB 이고 2분마다 돈다).
try:
    newest = max(glob.glob(os.path.join(sys.argv[2], "*.jsonl")), key=os.path.getmtime)
    with open(newest, "rb") as f:
        f.seek(0, 2)
        f.seek(max(0, f.tell() - 65536))
        tail = f.read().decode("utf-8", "replace")
    # 잘린 줄이 섞여도(append 중 꼬리 손상) 성한 줄은 그대로 읽힌다 — 줄 단위 JSON 파싱을 안 한다.
    for m in re.finditer(r'"timestamp"\s*:\s*"([^"]+)"', tail):
        t = stamp(m.group(1))
        if t is not None and (best is None or t > best):
            best = t
except Exception:
    pass

if best is not None:
    print(best)
PYEOF
)
    case "${e:-}" in ''|*[!0-9]*) printf 'unknown'; return 0 ;; esac
    printf '%s' "$(( now - e ))"
}

# 하트비트 이후 **니노 외** 작성자의 메시지 건수. 셀 수 없으면 "unknown".
incoming_since() {
    [ -x "$HISTORY_CLI" ] || { printf 'unknown'; return 0; }
    local n
    # 🔴 **이 함수의 정확성은 3행의 `pipefail` 한 단어에 걸려 있다.**
    #   파이프라인 rc 는 마지막 명령(python) 것이라, pipefail 이 없으면 CLI 가 rc=1 이어도
    #   python 은 0줄을 읽고 `0` 을 찍는다 ⇒ **조회 실패가 "0건"이 되고, 0건은 조용함이라
    #   워치독이 영영 안 부른다**(조용히 눈이 먼다). 실측:
    #       set -euo pipefail → FAILED(=unknown, 부르는 쪽)   set -eu → 0  🔴
    #   시험이 잡긴 하지만(제거 시 30 pass·1 fail) **보이지 않는 결합**이라 여기 적어둔다.
    #   🔸 룬드는 같은 판정을 `if OUT="$(cli)"; then` 으로 rc 를 명시해서 갈랐다(assistant#28).
    #     그쪽이 결합이 드러나서 낫다 — 코어로 옮길 때 그 형태로 통일할 것.
    n=$("$HISTORY_CLI" --after "$1" --limit 200 2>/dev/null | python3 -c '
import sys, json
n = 0
for line in sys.stdin:
    line = line.strip()
    if not line.startswith("{"):
        continue          # 첫 줄은 사람이 읽는 요약이라 JSON 이 아니다
    try:
        if json.loads(line).get("author_name") != "니노":
            n += 1
    except Exception:
        pass
print(n)
' 2>/dev/null) || n=""
    case "$n" in ''|*[!0-9]*) printf 'unknown' ;; *) printf '%s' "$n" ;; esac
}

# 🔴 이 워치독은 **cron 2분 주기**다(룬드는 상주 루프). 재알림 백오프를 셸 변수에 두면
#   매 tick 초기화돼 2분마다 사람을 부르게 된다 — 그래서 **파일**에 남긴다.
if [ -r "$HEARTBEAT_FILE" ]; then
    HB_EPOCH=$(python3 -c '
import sys, datetime
try:
    s = open(sys.argv[1]).read().strip()
    print(int(datetime.datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()))
except Exception:
    pass
' "$HEARTBEAT_FILE" 2>/dev/null || true)

    if [ -n "${HB_EPOCH:-}" ]; then
        NOW_EPOCH=$(date +%s)
        SILENT=$(( NOW_EPOCH - HB_EPOCH ))

        # 미래 시각(시계 어긋남)은 침묵으로 읽지 않는다 — 음수는 통째로 버린다
        if [ "$SILENT" -ge "$SILENCE_LIMIT" ]; then
            NEXT=$(cat "$SILENCE_STATE" 2>/dev/null || echo "$SILENCE_LIMIT")
            case "$NEXT" in ''|*[!0-9]*) NEXT=$SILENCE_LIMIT ;; esac
            # 🔴 수신 축 — 조용한 밤을 먹통으로 읽지 않는다
            HB_RAW=$(head -n1 "$HEARTBEAT_FILE" 2>/dev/null || true)
            INCOMING=$(incoming_since "$HB_RAW")
            if [ "$INCOMING" = "0" ]; then
                # 아무도 안 불렀으니 턴이 없는 게 정상이다. 로그만 남기고 사람은 안 부른다.
                log "QUIET: 턴 종료 ${SILENT}초 전이지만 그 뒤 수신이 0건이다 — 조용한 것이지 먹통이 아니다."
                exit 0
            fi
            # 🟡 셀 수 없으면(CLI 부재·실패) **부르는 쪽으로 넘어간다.**
            #   못 부른 사고(9시간 50분)가 헛부름보다 비싸고, 조치가 "화면 봐줘"라 무해하다.
            #   대신 확인 못 했다는 걸 본문에 적어 사람이 판단할 수 있게 한다.
            # 🔴 활동 축 — **긴 턴을 먹통으로 읽지 않는다** (2026-07-29 룬드 실오탐 회귀)
            #   하트비트는 턴이 *끝날 때만* 찍히므로, 한 턴이 임계를 넘으면
            #   **가장 활발히 일할 때가 가장 죽어 보인다.** 도구 호출이 최근에 있었다면
            #   세션은 응답을 만들고 있는 중이다 — 사람을 부를 일이 아니다.
            #   ⚠️ 억제 전용: 활동이 멈췄다는 사실만으로는 여기서 아무것도 안 한다.
            ACT_AGE=$(activity_age)
            case "$ACT_AGE" in
                unknown)
                    # 부재·손상 = 판정 불가. 억제를 **못 할 뿐** 이전 동작으로 돌아간다.
                    # 감시 구멍이 조용히 생기지 않게 로그에 남기고, 본문에도 적는다.
                    log "ACTIVITY-UNKNOWN: 활동 파일($ACTIVITY_FILE)도 세션 기록($SESSION_LOG_DIR)도 못 읽었다 — 긴 턴인지 가릴 수 없다. 훅(PostToolUse) 설치·세션 로그 경로 확인 필요."
                    ACTIVITY_NOTE="
⚠️ 활동 축을 확인 못 했어(도구 호출 기록도 세션 기록도 없어) — 긴 작업 중인 건지 가릴 수가 없었어."
                    ;;
                *)
                    if [ "$ACT_AGE" -lt "$SILENCE_LIMIT" ]; then
                        log "WORKING: 턴 종료 ${SILENT}초 전이지만 ${ACT_AGE}초 전에 활동 흔적이 있다(도구 호출 또는 턴 시작) — 긴 턴이지 정지가 아니다."
                        exit 0
                    fi
                    ACTIVITY_NOTE="
도구 호출도 턴 시작도 $((ACT_AGE / 60))분째 없어 — 긴 작업 중인 것도 아니야."
                    ;;
            esac
            if [ "$INCOMING" = "unknown" ]; then
                INCOMING_NOTE="
⚠️ 수신 건수를 확인 못 했어(yaksu-history 를 못 돌렸어) — 그냥 조용한 시간대일 수도 있어."
            else
                INCOMING_NOTE="
그 사이 **${INCOMING}건이 들어왔는데 하나도 못 받았어** — 조용한 시간대가 아니야."
            fi
            if [ "$SILENT" -ge "$NEXT" ]; then
                log "SILENT: 세션이 살아 있는데 ${SILENT}초($((SILENT / 60))분) 동안 턴을 못 끝냈다(수신 ${INCOMING}건 · 활동 ${ACT_AGE}). 사람 호출(복구 안 함)."
                wd_send "<@353914579929268226> 🔴 니노가 **살아 있는데 $((SILENT / 60))분째 응답을 못 만들고 있어.** tmux랑 프로세스는 멀쩡해서 기존 감시엔 안 걸려 — **인증 만료(401)·사용량 소진·얼어붙음** 중 하나야.
$INCOMING_NOTE
$ACTIVITY_NOTE

확인: WSL에서 \`tmux attach -t nino\` 로 화면 봐줘. 화면에 뭐가 떠 있냐로 갈려:
· **401 / Please run /login** → 로그인 필요. 그건 내가 못 해(브라우저 인증이라).
· **session limit / 리셋 시각** → 한도 소진이야. **로그인 칠 필요 없어** — 그 시각 지나면 저절로 돌아와.
· 둘 다 아니면 얼어붙은 거라 재시작이 답이야.

이건 자동 재시작 안 했어 — 재시작해도 토큰 문제면 그대로고 지금까지 맥락만 날아가거든."
                # 재알림 간격 2배 — 같은 상태로 2분마다 부르지 않는다
                echo $(( SILENT * 2 )) > "$SILENCE_STATE"
            fi
        else
            # 회복 — 다음 사고에 즉시 부를 수 있게 상태를 지운다
            if [ -f "$SILENCE_STATE" ]; then
                log "RECOVERED: 산출 재개 (마지막 턴 종료 ${SILENT}초 전)"
                rm -f "$SILENCE_STATE"
            fi
        fi
    fi
fi

# ── 🔴 Check 6: 감지기 축 — **감지기가 죽었는지는 누가 보나** ─────────────────
#   (맨 뒤에 둔다 — 앞의 축들이 발동하면 이건 안 본다. 인증이 *실제로* 죽은 것보다
#    감지기 고장은 덜 급하고, 알림이 겹치면 무엇이 울렸는지가 안 갈린다.)
#
# 🔴 왜 필요한가 (2026-07-30 실측):
#   `check-auth.sh` 가 cron 5분으로 등록돼 있는데 **로그가 한 줄도 없었다** ⇒ 도는 것과
#   안 도는 것이 같은 모습. 2026-07-25 에 실제로 `jq` 부재로 즉사해 "인증 만료 알림이
#   한 번도 안 나간" 사고가 있었고 **아무도 몰랐다.** 감지기가 하트비트를 찍게 했으니(#83)
#   그걸 보는 눈이 여기다. 안 보면 로그만 쌓이고 그건 감지 포기와 같다.
#
# 🔑 부재를 접지 않는다 — 세 상태다:
#     신선      → ok
#     오래됨    → 감지기가 멈췄다 → 부른다
#     아예 없음 → **첫 관측은 조용하다**(배포 직후엔 정상적으로 없다). 처음 본 시각을
#                 적고 그때부터 잰다. "정상"으로 접으면 cron 미등록을 영구히 놓치고,
#                 "죽었다"로 접으면 배포마다 오탐이 난다.
# 🔸 부재 기록을 `logs/` 에 두는 이유: `/tmp` 는 재부팅이 지운다. 지워지면 타이머가 매번
#   리셋돼 **부재가 계속돼도 임계를 영구히 못 넘긴다**(오탐이 아니라 미탐 쪽으로 샌다).
DETECTOR_HB="${NINO_DETECTOR_HEARTBEAT:-$BOT_DIR/logs/check-auth-heartbeat}"
DETECTOR_LIMIT=${NINO_DETECTOR_STALE_LIMIT:-1200}     # 20분 = cron 5분 주기의 4배
DETECTOR_BACKOFF=${NINO_DETECTOR_BACKOFF:-3600}
DETECTOR_ABSENT="$BOT_DIR/logs/watchdog-detector-absent-since"
DETECTOR_STATE="$BOT_DIR/logs/watchdog-detector-next"  # 다른 축과 **다른 파일** — 서로 침묵시키지 않게

detector_alert() {   # $1 = 사람이 읽는 사유
    local next
    next=$(cat "$DETECTOR_STATE" 2>/dev/null || echo 0)
    case "$next" in ''|*[!0-9]*) next=0 ;; esac
    [ "$(date +%s)" -lt "$next" ] && return 0          # 백오프 중
    log "DETECTOR: $1 — 사람 호출(복구 안 함)."
    wd_send "<@353914579929268226> 🟡 니노 **인증 감지기(check-auth)가 멈춘 것 같아.**

$1

이건 지금 당장 뭐가 고장난 건 아니야 — **인증이 끊겼을 때 알려줄 장치가 없는 상태**라는 뜻이야(감시의 사각). 2026-07-25 에 이 감지기가 죽은 채로 있어서 만료 알림이 한 번도 안 나간 적이 있어.

확인: \`tail -3 ~/discord-bot-nino/logs/check-auth.log\` 랑 \`crontab -l | grep check-auth\`"
    echo "$(( $(date +%s) + DETECTOR_BACKOFF ))" > "$DETECTOR_STATE"
}
detector_recovered() {
    # 🔴 조건이 백오프 파일($DETECTOR_STATE)뿐이면 **경보를 보낸 부재만** 해소가 남는다.
    #    부재 첫 관측은 *조용히 기록만* 하므로 백오프 파일이 없고 → 해소도 조용했다.
    #    그러면 로그 마지막 줄이 영원히 `DETECTOR-ABSENT` 로 남아 나중에 읽는 사람은
    #    **아직 부재 중**으로 읽는다(2026-07-30 15:42 부재 → 16:05 회복이 안 닫혔다).
    # 🔑 조용히 시작한 상태 전이도 **해소는 남긴다** — 안 그러면 조용한 시작이 조용한 거짓으로 굳는다.
    if [ -f "$DETECTOR_STATE" ] || [ -f "$DETECTOR_ABSENT" ]; then
        log "DETECTOR-RECOVERED: 감지기 하트비트 정상"
    fi
    rm -f "$DETECTOR_STATE" "$DETECTOR_ABSENT"
    return 0
}

DET_NOW=$(date +%s)
if [ -f "$DETECTOR_HB" ]; then
    # ⚠️ `stat -c` 는 GNU 전용, BSD 는 `-f %m`. 폴백이 없으면 룬드 맥에서 이 축이
    #   **조용히 죽는다**(mtime 이 늘 빈 값 → 영원히 판정 불가 → 감지기 감시가 없는 것과 같다).
    #   시험으로 실측했다(BSD 흉내 PATH): 폴백 전 2 fail → 후 0 fail.
    DET_M=$(stat -c %Y "$DETECTOR_HB" 2>/dev/null || stat -f %m "$DETECTOR_HB" 2>/dev/null || echo "")
    case "$DET_M" in
        ''|*[!0-9]*)
            # 🔴 판정 불가를 "정상"으로도 "고장"으로도 접지 않는다 — 로그에만 남긴다.
            log "DETECTOR-UNKNOWN: 하트비트 mtime 을 못 읽었다($DETECTOR_HB) — 감지기 상태를 가릴 수 없다." ;;
        *)
            DET_AGE=$(( DET_NOW - DET_M ))
            if [ "$DET_AGE" -gt "$DETECTOR_LIMIT" ]; then
                rm -f "$DETECTOR_ABSENT"
                detector_alert "check-auth 하트비트가 $((DET_AGE / 60))분째 안 움직였어(임계 $((DETECTOR_LIMIT / 60))분). cron 은 5분마다 돌아야 해."
            else
                detector_recovered
            fi ;;
    esac
else
    DET_SINCE=$(cat "$DETECTOR_ABSENT" 2>/dev/null || echo "")
    case "$DET_SINCE" in
        ''|*[!0-9]*)
            echo "$DET_NOW" > "$DETECTOR_ABSENT"
            log "DETECTOR-ABSENT: 하트비트 파일이 없다 — **첫 관측이라 조용히 기록만** 한다(배포 직후일 수 있다)." ;;
        *)
            if [ $(( DET_NOW - DET_SINCE )) -gt "$DETECTOR_LIMIT" ]; then
                detector_alert "check-auth 하트비트 파일이 $(( (DET_NOW - DET_SINCE) / 60 ))분째 **아예 없어**. 감지기가 한 번도 안 돌았거나 cron 이 안 걸려 있어."
            fi ;;
    esac
fi

# 정상
exit 0
