#!/usr/bin/env bash
# nino-watchdog.sh 계약 테스트 — 특히 **산출 축**(2026-07-29 신설)
#
# 🔴 왜 산출 축인가 (Darren 승인 M:53qr):
#   2026-07-29 룬드가 **살아 있는 채로** 9시간 50분 침묵했다(인증 만료 401 × 21회).
#   tmux·프로세스·relay 전부 정상이라 **부재 감시엔 안 걸렸고**, 룬드 watchdog 은
#   그 9시간 50분 동안 로그를 0줄 남겼다. Tim 형 9시 기상 알람이 그래서 실패했다.
#   니노 워치독도 조건 3개가 **전부 자원**(세션 있나·pane 살았나·D state)이라 같은 구멍이 있었다.
#
# 🔑 자원 축은 원인마다 분기가 필요해 **새 원인마다 또 뚫린다.**
#   산출 축(마지막 턴 종료로부터 N분) 하나면 만료·한도소진·얼어붙음이 전부 걸린다.
#
# 🔴 니노는 룬드와 구조가 다르다 — **cron 2분 주기**라 상주 루프가 아니다.
#   재알림 백오프를 셸 변수에 둘 수 없고 **파일에 남겨야** 한다. 그 지점이 이 시험의 핵심이다.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
WD="$REPO/scripts/nino-watchdog.sh"

pass=0; fail=0; skip=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; echo "     want: $2"; echo "     got:  $3"; fail=$((fail + 1)); }
# ⛔ 판정 불가 — **못 쟀다**를 통과로도 실패로도 접지 않는다(자매 파일 catchup-hint 와 같은 관례).
#   통과로 접으면 안 잰 계약이 초록불이 되고, 실패로 접으면 남의 기계에서 못 재는 것이 결함이 된다.
skipt(){ echo "  ⛔ $1"; echo "     사유: $2"; skip=$((skip + 1)); }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/logs" "$WORK/scripts" "$WORK/src" "$WORK/bin"

# 🔴 GNU/BSD 양쪽 — 상대 봇(macOS)이 이 시험을 셀 수 있어야 한다. ref_bash_portability_32
iso_off() {   # $1 = 분(음수=과거, 양수=미래)
  if date -u -d "1 minute ago" +%Y >/dev/null 2>&1; then
    date -u -d "$1 minutes" +%Y-%m-%dT%H:%M:%S.000Z
  else
    sign=+; n=$1
    case "$n" in -*) sign=-; n=${n#-} ;; esac
    date -u -v"${sign}${n}"M +%Y-%m-%dT%H:%M:%S.000Z
  fi
}

cp "$WD" "$WORK/scripts/"
# 재시작 스크립트는 **불려선 안 되는** 것들이다. 불리면 흔적이 남게 한다.
for s in start-nino.sh restart-nino.sh; do
  printf '#!/bin/bash\necho "%s" >> "$WORK_MARK/restarted.txt"\nexit 0\n' "$s" > "$WORK/scripts/$s"
  chmod +x "$WORK/scripts/$s"
done
# discord-send 스텁 — 대상/본문을 기록
cat > "$WORK/src/discord-send" <<'EOF'
#!/bin/bash
printf '%s\n' "$1|$2" >> "$WORK_MARK/sent.txt"
# 🔴 **전체 argv 를 그대로 남긴다** — 아래 "실물 계약" 시험이 이걸 진짜 discord-send 에 재생한다.
#   본문에 개행이 있어서 줄 단위로는 못 담는다 → NUL 구분.
printf '%s\0' "$@" > "$WORK_MARK/argv.bin"
exit 0
EOF
chmod +x "$WORK/src/discord-send"

# tmux 스텁 — 기본은 "세션 정상". pane_pid 는 실제로 살아 있는 PID($$)를 준다(kill -0 통과)
make_tmux() {  # $1 = has-session 종료코드
  cat > "$WORK/bin/tmux" <<EOF
#!/bin/bash
case "\$1" in
  has-session) exit $1 ;;
  list-panes)  echo $$ ;;
esac
exit 0
EOF
  chmod +x "$WORK/bin/tmux"
}
printf '#!/bin/bash\nexit 1\n' > "$WORK/bin/pgrep"   # Claude PID 없음 → Check 3 건너뜀
chmod +x "$WORK/bin/pgrep"

HB="$WORK/logs/session-heartbeat-utc"
ACT="$WORK/logs/session-activity-utc"
STATE="$WORK/logs/watchdog-silence-next"

# 🔴 yaksu-history 스텁 — **실물 CLI/DB 를 절대 안 태운다.**
#   절대경로로 박힌 CLI 를 그대로 두면 시험이 진짜 DB 를 읽어, 결과가 그날 대화량에
#   따라 갈린다(= 시험이 아니라 관측). 주입 seam(NINO_HISTORY_CLI)을 쓰는 이유다.
#   make_history <작성자...>  — 인자 하나가 메시지 한 건. 인자 없으면 0건(조용한 밤).
make_history() {
  { printf '#!/bin/bash\n'
    printf 'echo "[yaksu-history] 결과 N건 · 사람이 읽는 요약 줄"\n'   # JSON 아닌 첫 줄
    for a in "$@"; do
      printf 'printf %s\\\\n %s\n' "'{\"author_name\": \"$a\", \"content\": \"x\"}'" ""
    done
    printf 'exit 0\n'
  } > "$WORK/bin/yaksu-history"
  chmod +x "$WORK/bin/yaksu-history"
}
no_history() { rm -f "$WORK/bin/yaksu-history"; }
fail_history() {
  printf '#!/bin/bash\necho "boom" >&2\nexit 1\n' > "$WORK/bin/yaksu-history"
  chmod +x "$WORK/bin/yaksu-history"
}

run_wd() {   # 환경 초기화 후 워치독 1회 실행 (cron 한 tick)
  : > "$WORK/sent.txt"; : > "$WORK/restarted.txt"
  # 🔴 stderr 를 삼키지 않는다. 삼켰더니 2026-07-29 에 룬드가 9건 빨간 이유를
  #    **화면에서 볼 수 없었다** — 스크립트가 13행 `source` 에서 죽고 있었는데
  #    stderr·카운터·로그 셋 다 신호가 없었다. 러너가 stderr 를 봐야 미지가 잡힌다.
  WORK_MARK="$WORK" PATH="$WORK/bin:$PATH" NINO_SILENCE_LIMIT="${LIMIT:-3600}" \
    NINO_HISTORY_CLI="$WORK/bin/yaksu-history" \
    bash "$WORK/scripts/nino-watchdog.sh" >/dev/null 2>"$WORK/stderr.txt"
  cat "$WORK/sent.txt" 2>/dev/null
}
set_hb()  { iso_off "-$1" > "$HB"; }        # $1 = 분 전
# 🔴 활동 축 — 도구 호출마다 갱신되는 파일. 하트비트(턴 종료)와 **의미가 다르다**.
set_activity() { iso_off "-$1" > "$ACT"; }  # $1 = 분 전
no_activity()  { rm -f "$ACT"; }            # 훅 미설치·초기 상태
bad_activity() { printf 'not-a-timestamp\n' > "$ACT"; }
reset()   { rm -f "$STATE" "$WORK/logs/watchdog.log"; no_activity; }

make_tmux 0
make_history Tim   # 기본은 "수신이 있었다" — 아래 침묵 케이스들은 전부 *먹통* 상황이다

echo "🔴 산출 축 — '살아 있나'가 아니라 '말을 하고 있나':"
reset; set_hb 120
out="$(run_wd)"
[[ "$out" == *"침묵"* || "$out" == *"응답"* ]] && ok "2시간 침묵 → 알림 전송" \
  || bad "2시간 침묵 → 알림 전송" "침묵 알림" "${out:-<없음>}"

reset; set_hb 1
out="$(run_wd)"
[[ -z "$out" ]] && ok "1분 전 턴 종료 → 조용(오탐 없음)" || bad "1분 → 조용" "<없음>" "$out"

reset; set_hb 60
out="$(run_wd)"
[[ -n "$out" ]] && ok "정확히 임계(60분)에서도 잡는다(>= 경계)" || bad "60분 경계" "알림" "<없음>"

echo ""
echo "🔑 복구하지 않는다 — 사람을 부른다:"
# 401 은 재시작으로 안 풀린다(토큰이 만료면 새 세션도 401). 그리고 살아 있는 맥락만 날린다.
reset; set_hb 120; run_wd >/dev/null
if [[ -s "$WORK/restarted.txt" ]]; then
  bad "침묵에는 재시작하지 않는다" "재시작 없음" "$(cat "$WORK/restarted.txt")"
else
  ok "침묵에는 재시작하지 않는다(401 은 재시작으로 안 풀린다)"
fi
reset; set_hb 120
out="$(run_wd)"
[[ "$out" == *"tmux attach"* ]] && ok "사람이 뭘 하면 되는지 알려준다" \
  || bad "사람이 뭘 하면 되는지 알려준다" "tmux attach" "$out"
[[ "$out" == 현인-업무* ]] && ok "알림이 사람 채널로 간다(현인-업무)" \
  || bad "알림 채널" "현인-업무" "${out%%|*}"

echo ""
echo "🔴 신호가 없을 때 — 없는 걸 근거로 사람을 부르지 않는다:"
reset; rm -f "$HB"
out="$(run_wd)"
[[ -z "$out" ]] && ok "하트비트 없으면 검사를 건너뛴다(새 설치·훅 미배선)" || bad "하트비트 부재" "<없음>" "$out"
reset; printf 'garbage\n' > "$HB"
out="$(run_wd)"
[[ -z "$out" ]] && ok "깨진 하트비트도 건너뛴다" || bad "깨진 하트비트" "<없음>" "$out"
reset; : > "$HB"
out="$(run_wd)"
[[ -z "$out" ]] && ok "빈 하트비트도 건너뛴다" || bad "빈 하트비트" "<없음>" "$out"
reset; iso_off 60 > "$HB"
out="$(run_wd)"
[[ -z "$out" ]] && ok "미래 시각(시계 어긋남)은 침묵으로 읽지 않는다" || bad "미래 하트비트" "<없음>" "$out"

echo ""
echo "🔴 조용한 밤 ≠ 먹통 — 응답할 것이 있었나로 가른다 (2026-07-29 회귀):"
# 하트비트는 Stop 훅이라 *턴이 끝날 때만* 갱신된다. 아무도 말을 안 걸면 턴이 없다.
# ⇒ 조용한 밤이 401 침묵과 파일상 **완전히 같은 모습**이 된다.
#   실측: 정상 운영 중 60분 초과 공백이 최근 400발화에 7건(임계값 바로 위) — 매일 밤 걸릴 것이었다.
reset; set_hb 120; make_history        # 수신 0건
out="$(run_wd)"
[[ -z "$out" ]] && ok "2시간 침묵 + 수신 0건 → 안 부른다(조용한 밤)" \
  || bad "조용한 밤엔 안 부른다" "<없음>" "$out"
grep -q "QUIET:" "$WORK/logs/watchdog.log" 2>/dev/null \
  && ok "조용해서 넘어갔다는 사실은 로그에 남는다(조용히 삼키지 않는다)" \
  || bad "QUIET 로그" "QUIET:" "$(cat "$WORK/logs/watchdog.log" 2>/dev/null)"

reset; set_hb 120; make_history Tim Darren
out="$(run_wd)"
[[ -n "$out" ]] && ok "2시간 침묵 + 수신 2건 → 부른다(먹통)" || bad "먹통이면 부른다" "알림" "<없음>"
[[ "$out" == *"2건이 들어왔는데"* ]] && ok "몇 건을 못 받았는지 사람에게 말해준다" \
  || bad "수신 건수 안내" "2건" "$out"

# 🔴 cron 발신자 7개가 **니노 이름으로** 말한다. 자기 발화를 수신으로 세면
#   #63 에서 앵커가 오염되던 그 함정이 판정 쪽에서 그대로 재현된다.
reset; set_hb 120; make_history 니노 니노 니노
out="$(run_wd)"
[[ -z "$out" ]] && ok "내 발화(cron)만 있으면 수신으로 안 센다" \
  || bad "자기 발화는 수신이 아니다" "<없음>" "$out"

reset; set_hb 120; make_history 니노 Tim
out="$(run_wd)"
[[ -n "$out" ]] && ok "내 발화에 섞여 있어도 남의 발화 1건은 잡는다" || bad "혼재 시 수신 인식" "알림" "<없음>"

# 🟡 셀 수 없을 때는 **부르는 쪽**으로 넘어간다 — 못 부른 사고가 헛부름보다 비싸다.
reset; set_hb 120; no_history
out="$(run_wd)"
[[ -n "$out" ]] && ok "CLI 부재 → 그래도 부른다(fail-open)" || bad "CLI 부재 fail-open" "알림" "<없음>"
[[ "$out" == *"확인 못 했"* ]] && ok "확인 못 했다는 걸 본문에 적는다" \
  || bad "unknown 안내 문구" "확인 못 했" "$out"
reset; set_hb 120; fail_history
out="$(run_wd)"
[[ "$out" == *"확인 못 했"* ]] && ok "CLI 실패도 같은 취급" || bad "CLI 실패" "확인 못 했" "${out:-<없음>}"
make_history Tim   # 기본 복구

echo ""
echo "🔴 긴 턴 ≠ 먹통 — 활동 축 (2026-07-29 룬드 실오탐 회귀):"
# 하트비트는 **턴이 끝날 때만** 찍힌다 ⇒ 한 턴이 임계를 넘으면 *가장 활발히 일할 때*가
# *가장 죽어 보인다*. 룬드 실발동: 63분짜리 턴 도중 "산출 정지 · 수신 38건" 이 Tim 께 나갔다.
# 🔴 수신 축(#67)은 이걸 **막지 못한다** — GitHub 웹훅 등이 계속 들어와 게이트를 통과하고,
#   본문에 "38건 들어왔는데 하나도 못 받았어" 라고 **확신까지 실어준다**. 실측: 니노 외 38건/시간.
reset; set_hb 120; make_history Tim; set_activity 1
out="$(run_wd)"
[[ -z "$out" ]] && ok "🔑 긴 턴(하트비트 2시간 전 + 수신 있음 + 활동 1분 전) → 안 부른다" \
  || bad "긴 턴 오탐 방지" "<없음>" "$out"
grep -q "WORKING:" "$WORK/logs/watchdog.log" 2>/dev/null \
  && ok "일하는 중이라 넘어갔다는 사실이 로그에 남는다(조용히 삼키지 않는다)" \
  || bad "WORKING 로그" "WORKING:" "$(cat "$WORK/logs/watchdog.log" 2>/dev/null)"

reset; set_hb 120; make_history Tim; set_activity 120
out="$(run_wd)"
[[ -n "$out" ]] && ok "둘 다 멈췄으면(활동도 2시간 전) 부른다 — 진짜 정지" \
  || bad "진짜 정지" "알림" "<없음>"

# 🔴 **억제기 전용 계약** — 활동 축은 알림을 *줄이기만* 한다. 혼자서 트리거하면
#   훅이 죽었을 때 사람을 부르게 되어, 감시를 고치려다 감시가 새 오탐원이 된다.
reset; set_hb 1; make_history Tim; set_activity 120
out="$(run_wd)"
[[ -z "$out" ]] && ok "🔑 하트비트가 신선하면 활동이 멈춰 있어도 안 부른다(억제기 전용)" \
  || bad "활동 축 단독 트리거 금지" "<없음>" "$out"

# 🟡 부재는 **정지가 아니라 판정 불가**다. 부재를 정지로 읽으면 훅 하나 빠뜨렸을 때
#   2분마다 사람을 부른다(#64 에서 밟은 자리). 억제만 못 할 뿐 이전 동작으로 되돌아간다.
reset; set_hb 120; make_history Tim; no_activity
out="$(run_wd)"
[[ -n "$out" ]] && ok "활동 파일 부재 → 억제 못 하고 이전 동작(부른다)" || bad "부재 fail-open" "알림" "<없음>"
[[ "$out" == *"활동 축"* ]] && ok "활동 축을 못 봤다는 걸 본문에 적는다(사람이 판단하게)" \
  || bad "부재 안내 문구" "활동 축" "$out"
# 🔴 감시 구멍이 **조용히** 생기지 않게: 부재는 로그에도 남는다.
grep -q "ACTIVITY-UNKNOWN:" "$WORK/logs/watchdog.log" 2>/dev/null \
  && ok "부재가 로그에 남는다 — 훅 미설치가 조용한 무감시가 되지 않는다" \
  || bad "부재 로그" "ACTIVITY-UNKNOWN:" "$(cat "$WORK/logs/watchdog.log" 2>/dev/null)"

reset; set_hb 120; make_history Tim; bad_activity
out="$(run_wd)"
[[ -n "$out" ]] && ok "활동 파일이 깨져 있어도 부재와 같은 취급(부른다)" || bad "손상 fail-open" "알림" "<없음>"
[[ "$out" == *"활동 축"* ]] && ok "손상도 판정 불가로 안내한다" || bad "손상 안내" "활동 축" "$out"

# 🟢 조용한 밤(#67)과 **독립**이다 — 수신 0건이면 활동 여부와 무관하게 안 부른다.
reset; set_hb 120; make_history; set_activity 120
out="$(run_wd)"
[[ -z "$out" ]] && ok "수신 0건이면 활동이 멈춰 있어도 안 부른다(#67 그대로)" \
  || bad "QUIET 우선" "<없음>" "$out"
make_history Tim   # 🔴 상태 복구 — 위에서 0건 스텁으로 바꿨다. 안 되돌리면 뒤 시험이 전부 QUIET 로 샌다

echo ""
echo "🔴 활동 훅 계약 — 이 훅이 죽으면 억제가 통째로 사라진다:"
HOOK="$REPO/hooks/session-activity.sh"
HOOKWORK="$WORK/hookhome"; mkdir -p "$HOOKWORK"
if [[ -f "$HOOK" ]]; then
  ACTIVITY_BOT_DIR="$HOOKWORK" bash "$HOOK"; rc=$?
  [[ $rc -eq 0 ]] && ok "훅이 rc=0 으로 끝난다(도구 호출을 방해하지 않는다)" || bad "훅 rc" "0" "$rc"
  v="$(cat "$HOOKWORK/logs/session-activity-utc" 2>/dev/null)"
  [[ "$v" == *Z ]] && ok "워치독이 읽는 형식(...Z)으로 쓴다" || bad "형식" "...Z" "${v:-<없음>}"
  # 🔴 하트비트와 **다른 파일**이어야 한다. 같은 파일이면 재시작 따라잡기 앵커가 오염된다(#63).
  [[ ! -e "$HOOKWORK/logs/session-heartbeat-utc" ]] \
    && ok "🔑 하트비트 파일은 건드리지 않는다(앵커 오염 금지)" \
    || bad "앵커 오염" "하트비트 미생성" "생성됨"
  # 원자적 교체 — 임시파일을 남기면 워치독이 반쯤 쓰인 값을 읽을 수 있다
  [[ -z "$(find "$HOOKWORK/logs" -name 'session-activity-utc.*' 2>/dev/null)" ]] \
    && ok "임시파일을 남기지 않는다(원자적 교체)" || bad "임시파일 잔존" "<없음>" "$(ls "$HOOKWORK/logs")"
  # 쓸 수 없는 곳이어도 죽지 않는다 — 훅이 죽으면 세션의 도구 호출이 막힌다
  ACTIVITY_BOT_DIR="/proc/nonexistent-$$" bash "$HOOK" >/dev/null 2>&1; rc=$?
  [[ $rc -eq 0 ]] && ok "쓸 수 없는 경로에서도 rc=0(세션을 막지 않는다)" || bad "실패 시 rc" "0" "$rc"
else
  skipt "활동 훅 계약" "hooks/session-activity.sh 가 없다"
fi

echo ""
echo "🔴 cron 주기 실행이라 백오프가 **파일**에 남아야 한다 (룬드와 구조가 다른 지점):"
# 상주 루프면 변수로 되지만 니노는 2분마다 새 프로세스다 — 변수는 매번 초기화된다.
reset; set_hb 120
first="$(run_wd)"
second="$(run_wd)"
[[ -n "$first" ]] && ok "1회차: 알림" || bad "1회차 알림" "알림" "<없음>"
[[ -z "$second" ]] && ok "2회차(같은 상태): 조용 — 2분마다 부르지 않는다" \
  || bad "2회차 조용" "<없음>" "$second"
[[ -f "$STATE" ]] && ok "백오프 상태가 파일에 남는다" || bad "백오프 상태 파일" "$STATE 존재" "없음"

# 침묵이 두 배로 길어지면 다시 부른다
set_hb 260
third="$(run_wd)"
[[ -n "$third" ]] && ok "침묵이 2배로 길어지면 다시 부른다" || bad "재알림" "알림" "<없음>"

echo ""
echo "🟢 회복:"
reset; set_hb 120; run_wd >/dev/null
set_hb 1
out="$(run_wd)"
[[ -z "$out" ]] && ok "회복하면 조용" || bad "회복 후 조용" "<없음>" "$out"
[[ ! -f "$STATE" ]] && ok "회복하면 백오프 상태를 지운다(다음 사고에 즉시 부른다)" \
  || bad "회복 시 상태 초기화" "파일 없음" "남아 있음"

echo ""
echo "🟡 기존 자원 축이 그대로 동작한다(회귀):"
reset; set_hb 1; make_tmux 1     # 세션 없음
out="$(run_wd)"
[[ "$out" == *"자동 재시작"* ]] && ok "세션 부재 → 기존대로 재시작 + 알림" \
  || bad "세션 부재 경로" "자동 재시작 알림" "${out:-<없음>}"
[[ -s "$WORK/restarted.txt" ]] && ok "세션 부재에는 실제로 재시작한다" \
  || bad "세션 부재 재시작" "start-nino 호출" "없음"
# 🔴 세션이 없으면 침묵 검사까지 가지 않는다 — 이미 재시작했는데 또 사람을 부르면 중복이다
reset; set_hb 120; make_tmux 1
out="$(run_wd)"
[[ "$out" != *"tmux attach"* ]] && ok "세션 부재 시 침묵 알림은 안 낸다(중복 방지)" \
  || bad "부재 경로에서 침묵 알림 억제" "침묵 알림 없음" "$out"
make_tmux 0

echo ""
echo "🔴 이식성 — 상대 봇(macOS·bash 3.2·BSD)이 이 시험을 셀 수 있어야 한다:"
# 🔴 상수로 세지 않는다 (룬드 #68 리뷰).
#   원래 `grep -c 'date -u -d' "$0"` 로 세고 `-le 3` 으로 판정했는데, 그 3 중 하나가
#   **검사 코드 자신**이었다(패턴 문자열이 파일 안에 있다). 검사 코드를 리팩터하면
#   실사용이 그대로여도 카운트가 흔들린다 — 오늘 코어에서 잡은 *계측 상수* 형태이자,
#   *검사기가 자기를 센다* 의 네 번째 사례다.
#   ⇒ 개수가 아니라 **구조**를 본다: iso_off 밖에 있으면 몇 개든 빨간불.
gnu=$(python3 - "$0" <<'PYEOF'
import re, sys
src = open(sys.argv[1]).read()
src = re.sub(r"<<'PYEOF'.*?^PYEOF", "", src, flags=re.S | re.M)   # 검사기를 대상에서 뺀다
m = re.search(r'^iso_off\(\)\s*\{.*?^\}', src, re.S | re.M)
if not m:
    print("iso_off 헬퍼가 없다"); raise SystemExit
outside = src.replace(m.group(0), "")
outside = "\n".join(l for l in outside.splitlines() if not l.lstrip().startswith("#"))
n = len(re.findall(r'date\s+-u\s+-d', outside))
print(f"iso_off 밖에서 {n}곳" if n else "")
PYEOF
)
[[ -z "$gnu" ]] && ok "GNU 전용 date -d 는 iso_off 안에만 있다" \
  || bad "GNU date -d" "iso_off 안에만" "$gnu"

echo ""
echo "🔴 러너 계약 — 예상 못 한 stderr 는 실패다 (룬드 제안 2026-07-29):"
# 가드(항목 목록)는 **내가 아는 함정**만 잡는다. stderr 감시는 아직 모르는 축까지 잡는다.
# 실제로 이 사고(source + || true)는 가드로 못 잡혔다 — `source`·`|| true` 는 정상 문법이라서.
reset; set_hb 120; run_wd >/dev/null
if [ -s "$WORK/stderr.txt" ]; then
  bad "워치독이 stderr 를 내지 않는다" "빈 stderr" "$(head -c 200 "$WORK/stderr.txt")"
else
  ok "워치독이 stderr 를 내지 않는다(command not found·unbound 를 조용히 지나치지 않는다)"
fi

echo ""
echo "🔴 회귀 잠금 — set -e 아래 \`source … || true\` 는 bash 3.2 에서 죽는다:"
# 🔴 이 고침은 **내 기계에서 검증이 안 된다.** 버그가 3.2 에서만 나타나서
#    고치기 전후가 5.x 에선 똑같이 통과한다(실측: 5.2 는 after 가 나오고 rc=0).
#    ⇒ 동작 시험으로는 못 잠그니 **패턴을 정적으로** 잠근다. 실증은 룬드 재측정에 의존한다.
# 🔸 룬드는 "가드로 못 잡는다"고 했는데(source·|| true 가 정상 문법이라) 맞다 —
#    다만 **set -e + source + || true 라는 조합**은 잡힌다. 넓은 그물은 위 stderr 감시가 맡고,
#    이건 *이미 두 번 사고 난 이 줄*만 좁게 잠그는 용도다.
if grep -qE '^[[:space:]]*set -[a-z]*e' "$REPO/scripts/nino-watchdog.sh" \
   && grep -qE '^[[:space:]]*(source|\.)[[:space:]].*\|\|[[:space:]]*true' "$REPO/scripts/nino-watchdog.sh"; then
  bad "set -e + source … || true 조합이 없다" "없음" "있음 — bash 3.2 에서 || true 가 source 실패를 못 잡는다"
else
  ok "set -e + source … || true 조합이 없다([ -f x ] && source x 로 쓸 것)"
fi

echo ""
echo "🔴 실물 계약 — 스텁이 받은 argv 를 **진짜 discord-send** 에 재생한다:"
# 🔑 위 시험들은 전부 **페이크**가 받았다. 페이크는 무슨 인자를 줘도 exit 0 이라
#   "인자 순서가 맞나 · 채널이 해석되나"를 **하나도 못 잰다.**
#   2026-07-29 실발동(Darren 승인 M:7jj6)으로 실물 도달은 확인했지만, 그건 손으로 만든
#   일회성 셋업이라 **회귀가 안 된다** — 다음에 인자 계약이 바뀌면 아무도 모른다.
#   ⇒ 스텁이 받은 **진짜 argv 를 그대로** 실물에 넘기고, `DISCORD_SEND_DRY_RUN=1` 로
#     네트워크 없이 해석까지만 태운다. 인자를 시험이 다시 적지 않으므로 드리프트가 없다.
REAL_SEND="$REPO/src/discord-send"
# 채널명을 시험에 다시 적지 않는다 — 스크립트에서 뽑는다(적으면 드리프트가 난다)
ALERT_CH="$(sed -n 's/^ALERT_CHANNEL="\([^"]*\)".*/\1/p' "$WD" | head -1)"

# 🔴 **이 계약은 니노 기계에서만 잴 수 있다 — 그건 결함이 아니라 설계다.**
#   src/discord-send 는 BOT_DIR·CORE_CLI·BUN 을 **절대경로로 고정**한다:
#     "env 절대경로 고정 → 어디서 실행해도 니노 정체 고정(401 근본교정)"
#     "⚠️ $HOME 폴백 금지(룬드 M:xm2p 리뷰) — $HOME 은 실행 주체에 따라 바뀌고,
#       어긋나면 전송이 아니라 **해시 역조회**가 조용히 깨진다"
#   즉 상대 기계에서 못 도는 건 **의도된 고정**이지 이식성 결함이 아니다.
#   ⇒ 그 기계에선 통과도 실패도 아닌 **판정 불가**다. 실패로 접으면 룬드가 내 PR 을
#     빨간불로 보게 되고(2026-07-29 실측 32 pass·2 fail), 통과로 접으면 안 잰 게 초록불이 된다.
SEND_BOT_DIR="$(sed -n 's/^BOT_DIR="\([^"]*\)".*/\1/p' "$REAL_SEND" | head -1)"
reset; set_hb 120; make_history Tim; run_wd >/dev/null    # 알림 1회 발동 → argv 확보

if [ ! -x "$REAL_SEND" ]; then
  skipt "실물 discord-send 계약" "$REAL_SEND 가 없거나 실행 불가"
elif [ -z "$SEND_BOT_DIR" ] || [ ! -r "$SEND_BOT_DIR/.env" ]; then
  skipt "실물 discord-send 계약" \
    "discord-send 가 고정한 정체에 못 닿는다(${SEND_BOT_DIR:-BOT_DIR 미검출}/.env). 니노 기계에서만 잴 수 있는 계약이다 — 고정은 의도다(401 근본교정 · \$HOME 폴백 금지)"
elif [ ! -s "$WORK/argv.bin" ]; then
  # 🔴 이건 판정 불가가 아니라 **실패**다 — 알림 분기가 argv 를 안 남겼다는 뜻이라
  #   기계와 무관하게 내 코드의 문제다.
  bad "알림 호출의 argv 를 잡았다" "argv.bin 비어있지 않음" "<없음>"
else
  ok "알림 호출의 argv 를 잡았다"
  # NUL 구분 argv 를 위치인자로 복원 — 배열을 안 쓴다(bash 3.2)
  replay() {
    set --
    while IFS= read -r -d '' a; do set -- "$@" "$a"; done < "$WORK/argv.bin"
    DISCORD_SEND_DRY_RUN=1 "$REAL_SEND" "$@" 2>&1
  }
  rp="$(replay)"; rp_rc=$?
  [ "$rp_rc" -eq 0 ] && ok "실물 discord-send 가 이 argv 를 받아들인다(rc=0)" \
    || bad "실물이 argv 를 받아들인다" "rc=0" "rc=$rp_rc · $rp"
  # 🔴 "받아들였다"로 끝내지 않는다 — **의도한 채널로 갔나**까지 본다.
  #   dry-run 은 해석된 채널 ID 를 찍는다: DRY_RUN POST /channels/<id>/messages
  want_id="$(python3 -c '
import json, sys
m = json.load(open(sys.argv[1]))
key = sys.argv[2]
v = m.get(key)
print(v if isinstance(v, str) else (v or {}).get("id", ""))
' "$REPO/config/channel-map.json" "$ALERT_CH" 2>/dev/null || true)"
  if [ -n "$want_id" ]; then
    case "$rp" in
      *"/channels/$want_id/"*) ok "의도한 채널($ALERT_CH=$want_id)로 해석된다" ;;
      *) bad "의도한 채널로 해석된다" "/channels/$want_id/" "$rp" ;;
    esac
  else
    bad "channel-map 에서 $ALERT_CH 를 찾았다" "채널 ID" "<없음>"
  fi
fi

echo ""
echo "결과: $pass pass, $fail fail, $skip 판정 불가"
# 판정 불가는 rc 를 바꾸지 않는다(자매 파일 catchup-hint 와 같은 관례) — 못 잰 것이지 깨진 게 아니다.
# 대신 위에 사유가 찍히므로 "왜 안 쟀나"가 화면에 남는다.
[[ $fail -eq 0 ]]
