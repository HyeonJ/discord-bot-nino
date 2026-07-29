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
    log "DEAD: tmux session '$SESSION' not found. Restarting..."
    "$SCRIPT_DIR/start-nino.sh" >> "$LOG" 2>&1
    $DISCORD_SEND "$ALERT_CHANNEL" "니노가 죽어서 자동 재시작했어! (tmux 세션 없음)" 2>/dev/null || true
    exit 0
fi

# Check 2: tmux pane 안에 프로세스가 살아있는지
PANE_PID=$(tmux list-panes -t "$SESSION" -F '#{pane_pid}' 2>/dev/null | head -1)
if [ -z "$PANE_PID" ] || ! kill -0 "$PANE_PID" 2>/dev/null; then
    log "DEAD: pane process gone (PID: $PANE_PID). Respawning..."
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
SILENCE_STATE="$BOT_DIR/logs/watchdog-silence-next"
# 🔴 절대경로로 박으면 **시험이 실물 DB 를 읽는다.** 주입 seam 을 둔다(기본값은 실물과 동일).
HISTORY_CLI="${NINO_HISTORY_CLI:-$HOME/.local/bin/yaksu-history}"

# 하트비트 이후 **니노 외** 작성자의 메시지 건수. 셀 수 없으면 "unknown".
incoming_since() {
    [ -x "$HISTORY_CLI" ] || { printf 'unknown'; return 0; }
    local n
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
            if [ "$INCOMING" = "unknown" ]; then
                INCOMING_NOTE="
⚠️ 수신 건수를 확인 못 했어(yaksu-history 를 못 돌렸어) — 그냥 조용한 시간대일 수도 있어."
            else
                INCOMING_NOTE="
그 사이 **${INCOMING}건이 들어왔는데 하나도 못 받았어** — 조용한 시간대가 아니야."
            fi
            if [ "$SILENT" -ge "$NEXT" ]; then
                log "SILENT: 세션이 살아 있는데 ${SILENT}초($((SILENT / 60))분) 동안 턴을 못 끝냈다(수신 ${INCOMING}건). 사람 호출(복구 안 함)."
                $DISCORD_SEND "$ALERT_CHANNEL" "<@353914579929268226> 🔴 니노가 **살아 있는데 $((SILENT / 60))분째 응답을 못 만들고 있어.** tmux랑 프로세스는 멀쩡해서 기존 감시엔 안 걸려 — 인증 만료(401)나 사용량 소진일 수 있어.
$INCOMING_NOTE

확인: WSL에서 \`tmux attach -t nino\` 로 화면 봐줘. 401이면 로그인이 필요한데 그건 내가 못 해(브라우저 인증이라).

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
