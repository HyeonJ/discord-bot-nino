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

pass=0; fail=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; echo "     want: $2"; echo "     got:  $3"; fail=$((fail + 1)); }

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
STATE="$WORK/logs/watchdog-silence-next"

run_wd() {   # 환경 초기화 후 워치독 1회 실행 (cron 한 tick)
  : > "$WORK/sent.txt"; : > "$WORK/restarted.txt"
  WORK_MARK="$WORK" PATH="$WORK/bin:$PATH" NINO_SILENCE_LIMIT="${LIMIT:-3600}" \
    bash "$WORK/scripts/nino-watchdog.sh" >/dev/null 2>&1
  cat "$WORK/sent.txt" 2>/dev/null
}
set_hb()  { iso_off "-$1" > "$HB"; }        # $1 = 분 전
reset()   { rm -f "$STATE" "$WORK/logs/watchdog.log"; }

make_tmux 0

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
gnu=$(grep -c 'date -u -d' "$0")
[[ "$gnu" -le 3 ]] && ok "GNU 전용 date -d 는 iso_off 안에만 있다" \
  || bad "GNU date -d" "iso_off 안에만" "${gnu}줄"

echo ""
echo "결과: $pass pass, $fail fail"
[[ $fail -eq 0 ]]
