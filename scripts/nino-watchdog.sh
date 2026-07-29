#!/bin/bash
# nino-watchdog.sh — 2분마다 crontab으로 실행, tmux/Claude 죽으면 자동 재시작 + 디코 알림
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SESSION="nino"
LOG="$BOT_DIR/logs/watchdog.log"
DISCORD_SEND="$BOT_DIR/src/discord-send"
# jq 미설치 + set -e 조합으로 워치독이 여기서 죽어 자동 재시작이 동작하지 않았다(2026-07-25 발견).
ALERT_CHANNEL="현인-업무"

# 🔴 `source … || true` 로 쓰면 **bash 3.2 에서 `|| true` 가 source 실패를 못 잡고 죽는다.**
#    (룬드 맥 실측 2026-07-29 · 니노 bash 5.2 대조 확인 — 5.x 는 안 죽는다 = 버전 차이)
#    죽으면 **실패 신호가 셋 다 없다**: stderr 없음 · 종료코드만 1 · log() 정의 전이라 로그도 없음.
#    ⚠️ 같은 줄에서 **같은 클래스가 두 번째다** — 위 10행 주석의 `jq` 건도 여기였다.
#    조건문은 `set -e` 면제라 이 형태가 정본. (이 줄이 파일 마지막이면 rc 가 1이 되니 주의)
[ -f "$BOT_DIR/.env" ] && source "$BOT_DIR/.env"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"; }

# Check 1: tmux 세션 살아있는지
if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    log "DEAD-SESSION: tmux session '$SESSION' not found. Restarting..."
    "$SCRIPT_DIR/start-nino.sh" >> "$LOG" 2>&1
    $DISCORD_SEND "$ALERT_CHANNEL" "니노가 죽어서 자동 재시작했어! (tmux 세션 없음)" 2>/dev/null || true
    exit 0
fi

# Check 2: tmux pane 안에 프로세스가 살아있는지
PANE_PID=$(tmux list-panes -t "$SESSION" -F '#{pane_pid}' 2>/dev/null | head -1)
if [ -z "$PANE_PID" ] || ! kill -0 "$PANE_PID" 2>/dev/null; then
    log "DEAD-PROC: pane process gone (PID: $PANE_PID). Respawning..."
    "$SCRIPT_DIR/restart-nino.sh" >> "$LOG" 2>&1
    $DISCORD_SEND "$ALERT_CHANNEL" "니노 프로세스가 죽어서 자동 재시작했어! (pane 프로세스 없음)" 2>/dev/null || true
    exit 0
fi

# Check 3: Claude 프로세스가 D state(uninterruptible sleep)인지
CLAUDE_PID=$(pgrep -P "$PANE_PID" -f "claude" 2>/dev/null | head -1 || true)
if [ -n "$CLAUDE_PID" ]; then
    STATE=$(awk '/^State:/{print $2}' /proc/$CLAUDE_PID/status 2>/dev/null || echo "?")
    if [ "$STATE" = "D" ]; then
        log "FROZEN: Claude PID $CLAUDE_PID in D state. Restarting..."
        "$SCRIPT_DIR/restart-nino.sh" >> "$LOG" 2>&1
        $DISCORD_SEND "$ALERT_CHANNEL" "니노가 얼어서 자동 재시작했어! (프로세스 D state)" 2>/dev/null || true
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
        $DISCORD_SEND "$ALERT_CHANNEL" "<@353914579929268226> 🔴 니노 **로그인이 풀린 것 같아.** 최근 $((AUTH_WINDOW / 60))분 동안 인증 에러가 **${AUTH_N}건** 났어.

이건 조용히 죽는 게 아니라 **에러를 뱉으면서 계속 도는 상태**라, 겉보기엔 멀쩡해 보여도 실제로는 아무 일도 못 하고 있어.

확인: WSL에서 \`tmux attach -t nino\` → \`/login\`. 브라우저 인증이라 내가 못 해.

재시작은 안 했어 — 토큰 문제라 재시작해도 그대로고 지금까지 맥락만 날아가거든." 2>/dev/null || true
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
                $DISCORD_SEND "$ALERT_CHANNEL" "<@353914579929268226> 🔴 니노가 **살아 있는데 $((SILENT / 60))분째 응답을 못 만들고 있어.** tmux랑 프로세스는 멀쩡해서 기존 감시엔 안 걸려 — **인증 만료(401)·사용량 소진·얼어붙음** 중 하나야.
$INCOMING_NOTE
$ACTIVITY_NOTE

확인: WSL에서 \`tmux attach -t nino\` 로 화면 봐줘. 화면에 뭐가 떠 있냐로 갈려:
· **401 / Please run /login** → 로그인 필요. 그건 내가 못 해(브라우저 인증이라).
· **session limit / 리셋 시각** → 한도 소진이야. **로그인 칠 필요 없어** — 그 시각 지나면 저절로 돌아와.
· 둘 다 아니면 얼어붙은 거라 재시작이 답이야.

이건 자동 재시작 안 했어 — 재시작해도 토큰 문제면 그대로고 지금까지 맥락만 날아가거든." 2>/dev/null || true
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

# 정상
exit 0
