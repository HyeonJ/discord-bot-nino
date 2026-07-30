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
# 🔴 `+` 도 벗겨야 한다 (2026-07-29, 룬드가 `#78` 리뷰에서 발견):
#   `-` 만 벗기면 `iso_off "+600"` → `date -v"++600"M` → **BSD 에서 빈 문자열**.
#   그러면 픽스처의 타임스탬프가 빈 값이 되고, 파싱 불가 = 판정 불가로 접혀
#   **미래 시각 시험이 가드가 있든 없든 초록**이 된다(룬드 실측: ② 변이 0실패).
#   ⇒ 헬퍼가 조용히 비면 그 위의 시험이 통째로 죽는다. 아래 자체 검사가 그걸 시끄럽게 만든다.
iso_off() {   # $1 = 분(음수=과거, 양수=미래)
  if date -u -d "1 minute ago" +%Y >/dev/null 2>&1; then
    date -u -d "$1 minutes" +%Y-%m-%dT%H:%M:%S.000Z
  else
    sign=+; n=$1
    case "$n" in -*) sign=-; n=${n#-} ;; +*) n=${n#+} ;; esac
    date -u -v"${sign}${n}"M +%Y-%m-%dT%H:%M:%S.000Z
  fi
}

# 🔴 픽스처 헬퍼 자체 검사 — **이게 조용히 비면 아래 시험이 전부 죽는다.**
#   룬드 기계에서 미래 시각 변이가 0실패로 나온 게 이 자리였다(구현이 아니라 헬퍼가 원인).
#   빈 값은 "시각이 아님"으로 접혀 **판정 불가 = 알림 발송**이 되고, 그 알림이 시험을 초록으로 만든다.
#   ⇒ 무음이 "없음"을 뜻하려면 실패가 시끄러워야 한다. 여기서 시끄럽게 만든다.
echo "🔴 픽스처 헬퍼 — 시각을 못 만들면 그 위 시험은 아무것도 안 잰다:"
for _a in -600 -1 60 "+600"; do
  _v="$(iso_off "$_a" 2>/dev/null)"
  case "$_v" in
    ????-??-??T??:??:??.000Z) ok "iso_off $_a → $_v" ;;
    *) bad "iso_off $_a" "ISO 시각(...Z)" "${_v:-<빈 문자열>}" ;;
  esac
done
echo ""

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
  # 🔴 세션 로그도 주입 seam 으로 — 안 그러면 시험이 **내 실제 대화 기록**을 읽어
  #   그날 401 이 났는지에 따라 결과가 갈린다(= 시험이 아니라 관측).
  WORK_MARK="$WORK" PATH="$WORK/bin:$PATH" NINO_SILENCE_LIMIT="${LIMIT:-3600}" \
    NINO_HISTORY_CLI="$WORK/bin/yaksu-history" \
    NINO_SESSION_LOG_DIR="$WORK/sessions" \
    bash "$WORK/scripts/nino-watchdog.sh" >/dev/null 2>"$WORK/stderr.txt"
  cat "$WORK/sent.txt" 2>/dev/null
}
set_hb()  { iso_off "-$1" > "$HB"; }        # $1 = 분 전
# 🔴 활동 축 — 도구 호출마다 갱신되는 파일. 하트비트(턴 종료)와 **의미가 다르다**.
set_activity() { iso_off "-$1" > "$ACT"; }  # $1 = 분 전
no_activity()  { rm -f "$ACT"; }            # 훅 미설치·초기 상태
bad_activity() { printf 'not-a-timestamp\n' > "$ACT"; }
# 🔴 인증 백오프도 지운다 — 안 지우면 백오프 시험이 건 30분 잠금이 **뒤 시험을 통째로 침묵시킨다**
#   (실제로 밟았다: 배치 시험 2개가 구현이 아니라 이 상태 누수로 빨갰다)
reset()   { rm -f "$STATE" "$WORK/logs/watchdog-auth-next" "$WORK/logs/watchdog.log"; no_activity; }

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
echo "🟡 침묵 알림은 원인 셋을 다 열어둔다 — 사람이 헛수고하지 않게:"
# 🔴 침묵 축은 **원인을 구분하지 못한다.** 산출이 멎었다는 사실만 안다.
#   실측(니노 API 에러 전수 36건): 인증 21 · **한도 소진 10** · 서버측 5.
#   한도 소진은 `Please run /login` 문구가 없어(인증 문제가 아니다) 인증 축이 안 센다 —
#   그런데 그동안 발화가 없으니 **침묵 축엔 걸린다.**
# ⚠️ 그때 본문이 로그인만 가리키면 Darren 이 **필요 없는 `/login` 을 친다.**
#   한도는 리셋되면 저절로 낫는다 — 할 일은 "기다린다"지 "로그인한다"가 아니다.
#   가능성 나열(인증·한도)은 이미 있었다. 없던 건 **한도일 때 뭘 할지**다.
# 🔸 룬드도 같은 줄을 갖고 있다(겪어서가 아니라 경로를 나열해서). 문구를 맞춰 양쪽을 같게 둔다.
reset; set_hb 120; make_history Tim; set_activity 7200
out="$(run_wd)"
[[ "$out" == *"사용량 소진"* ]] && ok "원인 후보에 한도 소진을 적는다" \
  || bad "한도 가능성 명시" "사용량 소진" "${out:-<없음>}"
[[ "$out" == *"리셋"* ]] && ok "한도일 때 할 일(리셋 시각 확인)을 적는다 — 헛된 /login 방지" \
  || bad "한도 행동 안내" "리셋" "${out:-<없음>}"
[[ "$out" == *"얼어붙"* ]] && ok "세 번째 경로(얼어붙음)도 열어둔다" \
  || bad "얼어붙음 명시" "얼어붙" "${out:-<없음>}"
# 🔴 이 줄은 원래 있던 안내다. 내가 구조를 고쳐 쓰면서 **같이 지워질 수 있어** 회귀로 묶는다.
#   (변이 ③ 이 안 물어서 알았다 — 새로 넣은 문구만 재고 있었다.)
[[ "$out" == *"브라우저 인증"* ]] && ok "401 일 때 '내가 못 한다'는 안내는 그대로 남아 있다" \
  || bad "401 안내 회귀" "브라우저 인증" "${out:-<없음>}"

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
echo "🔴 활동 축 두 번째 원천 — 세션 기록(jsonl) (2026-07-29 룬드 실오탐 #2 회귀):"
# 🔴 왜 원천이 둘인가:
#   훅은 **도구를 부를 때만** 찍는다. 그래서 *도구를 하나도 안 부르는 긴 턴*(순수 생성)은
#   활동 파일이 안 갱신되어 여전히 죽어 보인다 — 룬드가 오늘 21:21 에 이걸로 두 번째 오탐을 맞았다
#   (61분 턴 → "산출 정지" 발송 → 5분 뒤 재개). 훅을 하나 더 다는 길도 있었지만
#   **세션 기록(jsonl)에 턴 시작이 이미 남는다**(실측 21:53: 턴이 도는 중에 user 레코드가 먼저 flush).
#   ⇒ 새 훅 없이 덮는다. 덤으로 위 계약("훅이 죽으면 억제가 통째로 사라진다")의 약점도 준다 —
#     jsonl 은 내 훅이 아니라 Claude Code 가 쓰므로 훅이 죽어도 한 원천이 남는다.
SESSD="$WORK/sessions"
set_session() {   # $1 = 분 전
  rm -rf "$SESSD"; mkdir -p "$SESSD"
  printf '{"type":"user","timestamp":"%s","message":{"content":"안녕"}}\n' "$(iso_off "-$1")" > "$SESSD/s.jsonl"
}
no_session() { rm -rf "$SESSD"; }

# 🔑 이 시험이 이 PR 의 이유다 — 도구를 **하나도 안 부른** 긴 턴.
reset; set_hb 120; make_history Tim; no_activity; set_session 1
out="$(run_wd)"
[[ -z "$out" ]] && ok "🔑 도구를 안 불러도 세션 기록이 신선하면 안 부른다(룬드 21:21 오탐)" \
  || bad "도구 없는 긴 턴" "<없음>" "$out"

# 활동 파일이 **낡았어도** 세션 기록이 신선하면 억제된다 — 둘 중 최신을 쓴다.
reset; set_hb 120; make_history Tim; set_activity 120; set_session 1
out="$(run_wd)"
[[ -z "$out" ]] && ok "둘 중 더 최근 것을 쓴다(활동 2시간 전 · 기록 1분 전 → 억제)" \
  || bad "최신 우선" "<없음>" "$out"

# 반대 방향도 성립해야 한다 — 훅만 살아 있고 기록이 낡은 경우.
reset; set_hb 120; make_history Tim; set_activity 1; set_session 120
out="$(run_wd)"
[[ -z "$out" ]] && ok "반대도 성립한다(활동 1분 전 · 기록 2시간 전 → 억제)" \
  || bad "최신 우선(역방향)" "<없음>" "$out"

# 🔴 **진짜 정지**는 여전히 부른다 — 원천을 늘렸다고 감시가 꺼지면 안 된다.
reset; set_hb 120; make_history Tim; set_activity 120; set_session 120
out="$(run_wd)"
[[ -n "$out" ]] && ok "세 신호가 모두 멈췄으면 부른다(진짜 정지)" || bad "진짜 정지" "알림" "<없음>"

# 🟡 둘 다 없어야 비로소 판정 불가다. 하나만 없는 건 판정 불가가 아니다.
reset; set_hb 120; make_history Tim; no_activity; no_session
out="$(run_wd)"
[[ -n "$out" ]] && ok "두 원천이 다 없으면 판정 불가 → 이전 동작(부른다)" || bad "둘 다 부재" "알림" "<없음>"
grep -q "ACTIVITY-UNKNOWN:" "$WORK/logs/watchdog.log" 2>/dev/null \
  && ok "둘 다 부재가 로그에 남는다" || bad "부재 로그" "ACTIVITY-UNKNOWN:" "$(cat "$WORK/logs/watchdog.log" 2>/dev/null)"

# 🔴 억제기 전용 계약은 원천이 늘어도 그대로다 — 기록이 멈췄다는 사실만으로 부르지 않는다.
reset; set_hb 1; make_history Tim; no_activity; set_session 120
out="$(run_wd)"
[[ -z "$out" ]] && ok "🔑 하트비트가 신선하면 기록이 멈춰 있어도 안 부른다(억제기 전용 유지)" \
  || bad "기록 단독 트리거 금지" "<없음>" "$out"

# 🔴 미래 시각은 억제에 못 쓴다 — 깨진 값 하나가 감시를 **영구히** 꺼버리는 자리다.
#   (incoming_since 에서 '조회 실패가 0건이 되어 조용히 눈이 먼' 것과 같은 형태)
reset; set_hb 120; make_history Tim; no_activity
rm -rf "$SESSD"; mkdir -p "$SESSD"
printf '{"type":"user","timestamp":"%s","message":{"content":"미래"}}\n' "$(iso_off "+600")" > "$SESSD/s.jsonl"
out="$(run_wd)"
[[ -n "$out" ]] && ok "미래 타임스탬프는 무시한다(깨진 값이 감시를 끄지 못한다)" \
  || bad "미래 시각 무시" "알림" "<없음>"

# 깨진 줄이 섞여 있어도 성한 줄은 읽는다 — 기록은 append 중에 잘린 줄이 남을 수 있다.
reset; set_hb 120; make_history Tim; no_activity
rm -rf "$SESSD"; mkdir -p "$SESSD"
{ printf '{"type":"user","timestamp":"%s"}\n' "$(iso_off "-1")"; printf '{"type":"assist'; } > "$SESSD/s.jsonl"
out="$(run_wd)"
[[ -z "$out" ]] && ok "잘린 줄이 섞여도 성한 줄로 판정한다(append 중 꼬리 손상)" \
  || bad "손상 줄 내성" "<없음>" "$out"

no_session   # 🔴 상태 복구 — 안 지우면 뒤 인증 시험이 이 픽스처를 읽는다

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
echo "🔴 인증 축 — 401 은 침묵으로 안 잡힌다 (2026-07-29 실측, Darren 승인 M:wh7t):"
# 🔑 401 은 "멈춤"이 아니라 **에러를 뱉고 턴을 끝내는 것**이다.
#   ⇒ Stop 훅이 계속 돌아 하트비트가 **신선하게 유지**되므로 산출 축(Check 4)에 안 걸린다.
#   내 실측(7/17): 44분 35초 · 401 21건 · 간격 중앙 110초 · **60분 초과 간격 0건**
#   ⇒ 에피소드가 임계보다 짧아 침묵 감시로는 **원리적으로** 못 잡는다. 임계를 낮추면 오탐이 는다.
SESSLOG="$WORK/sessions"
# $1 = 인증 에러 건수, $2 = 서버측(529/502) 건수, $3 = 분 전(기본 5)
make_sessions() {
  rm -rf "$SESSLOG"; mkdir -p "$SESSLOG"
  local ts; ts="$(iso_off "-${3:-5}")"
  {
    printf '{"type":"user","timestamp":"%s","message":{"content":"평범한 대화"}}\n' "$ts"
    for _ in $(seq 1 "${1:-0}"); do
      printf '{"type":"user","isApiErrorMessage":true,"timestamp":"%s","message":{"content":"Please run /login · API Error: 401 OAuth access token has expired"}}\n' "$ts"
    done
    for _ in $(seq 1 "${2:-0}"); do
      printf '{"type":"user","isApiErrorMessage":true,"timestamp":"%s","message":{"content":"API Error: 529 Authentication service is temporarily unavailable"}}\n' "$ts"
    done
  } > "$SESSLOG/session-a.jsonl"
}
no_sessions() { rm -rf "$SESSLOG"; }
# 🔴 파일 단위로 만든다 — **재시작하면 새 파일이 생기고 직전 증거는 옛 파일에 남는다.**
#   $1=파일명 · $2=인증에러 건수 · $3=레코드/mtime 을 몇 분 전으로 둘지
make_session_file() {
  mkdir -p "$SESSLOG"
  local f="$SESSLOG/$1" ago="${3:-5}" ts; ts="$(iso_off "-$ago")"
  {
    printf '{"type":"user","timestamp":"%s","message":{"content":"평범한 대화"}}\n' "$ts"
    for _ in $(seq 1 "${2:-0}"); do
      printf '{"type":"user","isApiErrorMessage":true,"timestamp":"%s","message":{"content":"Please run /login · API Error: 401 OAuth access token has expired"}}\n' "$ts"
    done
  } > "$f"
  # mtime 을 레코드 시각에 맞춘다 — 실제로도 마지막 append 시각이 mtime 이다.
  # ⚠️ `touch -d` 는 GNU 전용이라 룬드 맥(BSD)에서 깨진다 → python os.utime 으로(이식성 가드가 잡아줬다).
  python3 -c 'import os,sys,time; t=time.time()-int(sys.argv[2])*60; os.utime(sys.argv[1],(t,t))' "$f" "$ago"
}

# 🔴 **핵심 회귀** — 하트비트가 신선해도 인증 축은 돌아야 한다. 401 의 정의가 그거니까.
reset; set_hb 1; set_activity 1; make_history Tim; make_sessions 5 0
out="$(run_wd)"
[[ -n "$out" ]] && ok "🔑 하트비트·활동 모두 신선해도 인증 에러 5건이면 부른다" \
  || bad "인증 축이 산출 축과 독립" "알림" "<없음>"
[[ "$out" == *"로그인"* || "$out" == *"인증"* ]] && ok "무슨 문제인지 말해준다(로그인/인증)" \
  || bad "원인 안내" "로그인|인증" "$out"
# 🔴 401 에 재시작·/clear 를 쏘면 **인증은 그대로고 맥락만 날아간다**(Tim M:s2um).
[[ ! -s "$WORK/restarted.txt" ]] && ok "🔑 인증 에러에는 재시작하지 않는다(토큰은 그대로고 맥락만 잃는다)" \
  || bad "재시작 금지" "<없음>" "$(cat "$WORK/restarted.txt")"

# 🟡 1~2건은 **재시도로 지나간다** — 산발을 사고로 읽지 않는다.
#   실측 근거: 내 현재 세션의 진짜 API 에러 전수 7건이 전부 산발(세션한도 3·Unable to 2·529 1·500 1)인데
#   진짜 401 에피소드는 44분에 21건이었다. 개수로 깨끗하게 갈린다.
reset; set_hb 1; set_activity 1; make_sessions 2 0
out="$(run_wd)"
[[ -z "$out" ]] && ok "인증 에러 2건은 안 부른다(재시도 산발)" || bad "min-count 미만" "<없음>" "$out"

# 🔴 서버측 일시 장애(529·502)는 **사람이 할 일이 없다** — 부르지 않는다.
reset; set_hb 1; set_activity 1; make_sessions 0 9
out="$(run_wd)"
[[ -z "$out" ]] && ok "529/502 서버측 장애는 안 부른다(사람이 할 게 없다)" || bad "서버측 제외" "<없음>" "$out"

# 🟡 오래된 에러는 **지난 사고**다. 창 밖이면 안 부른다(안 그러면 한 번 난 401이 영원히 부른다).
reset; set_hb 1; set_activity 1; make_sessions 9 0 600
out="$(run_wd)"
[[ -z "$out" ]] && ok "창 밖(10시간 전) 에러는 안 부른다 — 지난 사고로 영원히 부르지 않는다" \
  || bad "창 필터" "<없음>" "$out"

# 🟡 부재 = **판정 불가**지 정상이 아니다. 조용히 넘어가되 로그에 남긴다.
reset; set_hb 1; set_activity 1; no_sessions
out="$(run_wd)"
[[ -z "$out" ]] && ok "세션 로그 부재 → 안 부른다(부재는 고장이 아니다)" || bad "부재 처리" "<없음>" "$out"
grep -q "AUTH-UNKNOWN:" "$WORK/logs/watchdog.log" 2>/dev/null \
  && ok "부재가 로그에 남는다 — 조용한 무감시가 되지 않는다" \
  || bad "부재 로그" "AUTH-UNKNOWN:" "$(cat "$WORK/logs/watchdog.log" 2>/dev/null)"

# 🔴 백오프는 침묵 축과 **다른 파일**이어야 한다. 같이 쓰면 한쪽이 다른 쪽을 침묵시킨다.
reset; set_hb 1; set_activity 1; make_sessions 5 0
first="$(run_wd)"; second="$(run_wd)"
[[ -n "$first" && -z "$second" ]] && ok "같은 상태로 2분마다 부르지 않는다(백오프)" \
  || bad "인증 백오프" "1회차만" "1=${first:0:20} 2=${second:0:20}"
[[ -f "$WORK/logs/watchdog-auth-next" ]] && ok "백오프가 침묵 축과 분리된 파일에 남는다" \
  || bad "백오프 파일 분리" "watchdog-auth-next" "$(ls "$WORK/logs")"
# 🔴 **재시작 시나리오** — 사고 중 재시작되면 **새 파일이 생기고 직전 증거는 옛 파일에 남는다.**
#   최신 파일 하나만 보면 새 파일엔 0건이라 **방금 난 401 을 못 본다.**
#   ⇒ 파일 선택은 개수(`ls -t | head -N`)가 아니라 **mtime 이 창 안인가**로 한다:
#     파일이 창 안에 안 쓰였다면 창 안의 레코드를 **가질 수 없다**(append-only 라 mtime = 최신 레코드 시각).
#     N 을 고를 근거를 안 만들어도 되고, 재시작이 몇 번 연달아 나도 자동으로 맞는다.
reset; set_hb 1; set_activity 1; make_history Tim
rm -rf "$SESSLOG"
make_session_file "new.jsonl" 0 1      # 재시작 직후 새 파일 — 깨끗하다
make_session_file "prev.jsonl" 5 8     # 직전 파일 — 여기에 증거가 있다(창 안)
out="$(run_wd)"
[[ "$out" == *"로그인"* ]] && ok "🔑 재시작으로 증거가 옛 파일에 남아도 잡는다(최신 하나만 보면 놓친다)" \
  || bad "재시작 시나리오" "로그인 알림" "${out:-<없음>}"

# 🟡 창 **밖** 파일의 에러는 안 센다 — 지난 사고가 되살아나면 안 된다.
reset; set_hb 1; set_activity 1
rm -rf "$SESSLOG"
make_session_file "new.jsonl" 0 1
make_session_file "old.jsonl" 9 600    # 10시간 전 사고
out="$(run_wd)"
[[ -z "$out" ]] && ok "창 밖 파일(10시간 전)의 에러는 안 센다" || bad "창 밖 파일 제외" "<없음>" "$out"

# 🟡 파일은 있는데 **전부 창 밖** = 최근 에러 0건이지 판정 불가가 아니다.
reset; set_hb 1; set_activity 1
rm -rf "$SESSLOG"; make_session_file "old.jsonl" 9 600
out="$(run_wd)"
[[ -z "$out" ]] && ok "전부 창 밖이면 안 부른다" || bad "전부 창 밖" "<없음>" "$out"
grep -q "AUTH-UNKNOWN:" "$WORK/logs/watchdog.log" 2>/dev/null \
  && bad "🔑 창 밖은 '0건'이지 '판정 불가'가 아니다" "AUTH-UNKNOWN 없음" "$(cat "$WORK/logs/watchdog.log")" \
  || ok "🔑 창 밖은 '0건'으로 읽는다 — 판정 불가와 구분한다"

# 🔴 **배치 계약** — Check 4 는 조용한 밤(QUIET)·긴 턴(WORKING)에서 `exit 0` 으로 빠진다.
#   401 은 바로 그때 나므로 인증 축이 **Check 4 뒤에 있으면 통째로 건너뛴다.**
#   이 두 케이스가 배치를 잠그는 유일한 판별점이다(하트비트가 신선하면 4 가 어차피 exit 하지 않아 구분이 안 된다).
reset; set_hb 120; set_activity 120; make_history; make_sessions 5 0   # 수신 0건 = QUIET 경로
out="$(run_wd)"
[[ "$out" == *"로그인"* ]] && ok "🔑 조용한 밤(QUIET)에도 인증 축은 돈다 — Check 4 앞에 있어야 한다" \
  || bad "QUIET 경로 배치" "로그인 알림" "${out:-<없음>}"
reset; set_hb 120; set_activity 1; make_history Tim; make_sessions 5 0  # 긴 턴 = WORKING 경로
out="$(run_wd)"
[[ "$out" == *"로그인"* ]] && ok "🔑 긴 턴(WORKING)에도 인증 축은 돈다" \
  || bad "WORKING 경로 배치" "로그인 알림" "${out:-<없음>}"
# 🔴 상태 복구 — 뒤 시험이 인증 알림에 오염되지 않게. **시각(3번째 인자)까지 챙겨야 한다:**
#   세션 기록은 이제 활동 축의 원천이라, 에러 0건이어도 레코드가 *신선하면* 침묵 알림이 억제된다.
#   `make_sessions 0 0`(기본 5분 전)으로 두면 아래 백오프 시험 3개가 조용히 억제된다(실제로 밟았다).
make_history Tim; make_sessions 0 0 600

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
echo "🔴 로그 표지는 원인마다 고유하다 — 사후 집계가 두 원인을 뭉치지 않게:"
# 🔴 실사고(2026-07-29): `DEAD:` 가 **tmux 세션 사망**과 **pane 프로세스 사망** 두 곳에 쓰였다.
#   Discord 알림 문구는 갈려 있었지만 **로그 표지가 같아서**, 나중에 로그로
#   *"뭐 때문에 죽었나"* 를 세면 두 원인이 한 칸으로 뭉친다.
#   ⇒ 룬드 known-issue *"축이 여럿이면 어느 축이 돌았는지도 구분이 안 된다"* 의 내 쪽 사례.
# 🔑 개별 표지를 하나씩 세지 않고 **겹침 자체를 구조로** 잠근다 — 새 표지를 추가해도 걸린다.
#
# 🔄 2026-07-29: 손으로 쓴 `uniq -d` 를 **코어 공용 도구**로 교체(Darren 승인 M:oxhg).
#    양봇이 같은 판정을 두 벌로 들고 있으면 한쪽만 고쳐져 조용히 갈린다 — 오늘 여러 번 본 형태.
#    코어가 대신 막아주는 것: ⓐ 아무것도 못 셈(--min-labels) ⓑ 내 정규식이 놓침(--candidate-pattern).
#    ⓒ 과대포착은 rc 로는 못 잡고 **접두사 경고**로 재료만 준다.
# ⚠️ 코어가 없거나 낡으면 **판정 불가로 남긴다.** 조용히 통과시키면 이 시험이 있으나 마나가 된다.
LV="${LABEL_VERDICT:-$HOME/yaksu-bot-core/scripts/label-verdict.sh}"   # dev 클론 — 프로덕션(-live) 무관
# 🔴 **있다 ≠ 그 기능이 있다** — `-x` 는 *없음*만 잡고 *낡음*은 안 잡는다.
#    구버전이 자리에 있으면 -x 통과·rc 정상인데 ⓒ 경고만 조용히 사라진다.
#    ⇒ 존재가 아니라 **능력**을 잰다: 접두사 관계가 확실한 픽스처를 태워 경고가 나오는지 본다.
LV_PROBE="$(mktemp)"
cat > "$LV_PROBE" <<'PROBEEOF'
log "DEAD: 본문"
log "DEAD-PANE: 본문"
log "WORKING: 본문"
log "STALE: 본문"
PROBEEOF
LV_PAT='log "([A-Z][A-Z-]*):'
LV_CAND='log "[A-Z]'
if [ ! -x "$LV" ]; then
  skipt "로그 표지 겹침 — 판정 불가" "코어 label-verdict.sh 없음($LV). \`git -C ~/yaksu-bot-core pull\` 후 재실행"
# 🔴 `--min-labels 1` 을 **명시한다** (2026-07-30, 룬드 `e29ace9` 지적 — 내 쪽에서도 재현).
#    안 주면 코어 기본값(현재 3)에 묶인다. 프로브가 4종이라 지금은 통과하지만
#    **코어가 기본값을 4 이상으로 올리는 순간** 프로브가 rc=2 로 떨어지고
#    이 시험은 *"구버전"* 이라고 오판한다 — 기능은 멀쩡한데 거짓 경보가 난다.
#    실측(기본값 5로 바꾼 사본): `판정 불가: 표지 4종 … (최소 5종)` → ⛔ "구버전으로 보인다".
#    🔑 **능력을 재는 프로브는 재는 대상의 기본값에 의존하면 안 된다** — 그 기본값도 움직인다.
elif ! "$LV" --file "$LV_PROBE" --min-labels 1 \
       --pattern "$LV_PAT" --candidate-pattern "$LV_CAND" 2>&1 \
     | grep -q '접두사 관계'; then
  skipt "로그 표지 겹침 — 판정 불가" "코어에 ⓒ(접두사 경고) 기능이 없다 — 구버전으로 보인다($LV)"
else
  LV_OUT="$("$LV" --file "$WD" --pattern "$LV_PAT" --candidate-pattern "$LV_CAND" 2>&1)"; LV_RC=$?
  case "$LV_RC" in
    0) ok "로그 표지가 전부 고유하다 (코어 label-verdict 판정)" ;;
    1) bad "같은 표지가 서로 다른 원인에 쓰인다 — 로그로 원인을 못 가른다" \
           "겹치는 표지 없음" "$(printf '%s' "$LV_OUT" | tr '\n' ' ')" ;;
    *) skipt "로그 표지 겹침 — 판정 불가" "코어 rc=$LV_RC: $(printf '%s' "$LV_OUT" | tr '\n' ' ')" ;;
  esac
  # ⓒ 과대포착은 rc 를 안 바꾼다 — 사람이 볼 재료로만 띄운다.
  printf '%s' "$LV_OUT" | grep -q '접두사 관계' && \
    echo "       ⚠️ $(printf '%s' "$LV_OUT" | grep -A1 '접두사 관계' | tail -1 | sed 's/^ *//')"
fi
rm -f "$LV_PROBE"

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
# 🔴 주입점이 생기면서 그 줄이 `ALERT_CHANNEL="${ALERT_CHANNEL:-현인-업무}"` 가 됐다.
#   **추출기는 자기가 낡은 걸 스스로 알리지 않는다** — 안 고치면 리터럴 `${ALERT_CHANNEL:-…}` 를
#   뽑아 channel-map 조회가 빈 값이 되고, 그건 "채널이 안 잡힌다"는 **엉뚱한 실패**로 보인다.
#   ⇒ 감싼 형태에서 기본값만 벗겨낸다. 두 형태 다 받는다.
ALERT_CH="$(sed -n 's/^ALERT_CHANNEL="\([^"]*\)".*/\1/p' "$WD" | head -1)"
ALERT_CH="${ALERT_CH#\$\{ALERT_CHANNEL:-}"; ALERT_CH="${ALERT_CH%\}}"

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


# ═══════════════════════════════════════════════════════════════════════════
# 🔴 주입 축 — **시험이 실물을 건드릴 수 있는가**
#
#   2026-07-31 06:28~06:32, 룬드의 `check-usage-alert` 시험이 형 채널로 **84건을 실제로 쐈다.**
#   원인은 하나였다: 전송 경로가 하드코딩이라 **시험이 다른 데로 돌릴 방법이 없었다.**
#   여기는 지금 안 샌다 — 시험이 가짜 `$BOT_DIR` 트리를 깔기 때문이다. 하지만 그건
#   *경로 조작에 기댄 간접 안전*이고, 다음 시험이 그 전제를 안 지키면 그대로 샌다.
#
# 🔑 두 축이 재는 게 다르다 (룬드 정리):
#     동적 — 스텁을 **탔을 때** 무엇이 갔나
#     정적 — 스텁을 **안 탈 수 있는가**
#   샌 전송은 정의상 스텁을 안 지나갔으니 **스텁 로그에는 영원히 안 나온다.**
#   그래서 동적 축만으로는 "안 샌다"를 절대 못 잰다 — 정적 축이 그걸 잰다.
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "🔴 주입 축 — 시험이 실채널로 샐 수 있는가:"

INJ_SEND="$WORK/bin/injected-send"
printf '#!/bin/bash\nprintf "%%s|%%s\\n" "$1" "$2" >> "$WORK_MARK/injected.txt"\nexit 0\n' > "$INJ_SEND"
chmod +x "$INJ_SEND"

run_wd_inject() {   # $1=DISCORD_SEND $2=ALERT_CHANNEL ; 나머지는 run_wd 와 같은 환경
  : > "$WORK/sent.txt"; : > "$WORK/injected.txt"; : > "$WORK/restarted.txt"
  WORK_MARK="$WORK" PATH="$WORK/bin:$PATH" NINO_SILENCE_LIMIT="${LIMIT:-3600}" \
    NINO_HISTORY_CLI="$WORK/bin/yaksu-history" \
    NINO_SESSION_LOG_DIR="$WORK/sessions" \
    DISCORD_SEND="$1" ALERT_CHANNEL="$2" \
    bash "$WORK/scripts/nino-watchdog.sh" >/dev/null 2>"$WORK/stderr.txt"
}

# 🧪 [양성 대조군] 먼저 — **주입 안 했을 때 기본 경로가 실제로 받는가.**
#   이걸 안 재면 아래 "기본 경로가 안 받았다"가 *주입이 먹혀서*인지 *애초에 알림이 안 떴는지*
#   구별이 안 된다. 두 상태가 같은 모습이면 그 시험은 아무것도 안 잰 것이다.
reset; set_hb 120; make_history Tim
CTRL="$(run_wd)"
[ -n "$CTRL" ] \
  && ok "🧪 [양성 대조군] 주입이 없으면 기본 경로가 받는다" \
  || bad "🧪 [양성 대조군] 기본 경로 수신" "sent.txt 에 한 건 이상" "<없음> — 알림 자체가 안 떴다면 아래 축은 무의미하다"

# ① 동적 — 주입하면 **모든** 호출이 그리로 간다
reset; set_hb 120; make_history Tim
run_wd_inject "$INJ_SEND" "주입-채널"
INJ_OUT="$(cat "$WORK/injected.txt" 2>/dev/null)"
DEF_OUT="$(cat "$WORK/sent.txt" 2>/dev/null)"
[ -n "$INJ_OUT" ] \
  && ok "주입한 전송 경로로 간다" \
  || bad "주입한 경로 수신" "injected.txt 에 한 건 이상" "<없음> — DISCORD_SEND 주입이 안 먹는다"
[ -z "$DEF_OUT" ] \
  && ok "기본 경로(=운영 경로)는 한 건도 안 받는다" \
  || bad "기본 경로 무수신" "<없음>" "$DEF_OUT — 주입해도 일부가 실물로 샌다"
case "$INJ_OUT" in
  주입-채널*) ok "채널도 주입한 값으로 간다" ;;
  *) bad "주입 채널" "주입-채널|…" "${INJ_OUT:-<없음>} — 채널이 하드코딩이면 실채널로 쏜다" ;;
esac

# ② 이름의 소유 — **`.env` 는 이 두 이름을 정의하면 안 된다**
#   🔴 이 시험을 처음엔 "주입이 `.env` 를 이긴다"로 썼다가 빨갛게 나왔고, **빨간 게 맞았다.**
#     `.env` 의 평범한 `DISCORD_SEND=…` 는 해석을 앞에 두든 뒤에 두든 **항상 이긴다**(나중 대입이 이긴다).
#     이기게 하려면 주입값을 미리 대피시키는 폴백 사슬이 필요한데 — 06:46 사고가 정확히
#     **사슬을 한 칸 늘렸다가** 난 것이다(`${DISCORD_SEND_BIN:-…}` 가 실물 경로를 되돌려놨다).
#   🔑 ⇒ 사슬로 이기려 하지 말고 **충돌 자체를 금지**한다. 이 두 이름은 주입점이 소유한다.
#     못 이기는 싸움을 없애는 쪽이, 이기는 장치를 덧대는 쪽보다 잴 것이 적다.
# 🔴 worktree 에는 `.env` 가 없다(untracked 라 본체에만 있다). 여기서 멈추면 이 계약은
#   **내가 일하는 모든 자리에서 판정 불가**가 된다 — 즉 사실상 안 재는 계약이다.
#   ⇒ 운영이 실제로 읽는 파일을 본다. 워치독은 `$BOT_DIR/.env` 를 읽고, 운영 BOT_DIR 은 본체다.
REAL_ENV="${WD_ENV:-}"
if [ -z "$REAL_ENV" ]; then
  for _c in "$REPO/.env" "$HOME/discord-bot-nino/.env"; do
    [ -r "$_c" ] && { REAL_ENV="$_c"; break; }
  done
fi
if [ -z "$REAL_ENV" ] || [ ! -r "$REAL_ENV" ]; then
  skipt "이름 소유: .env 가 DISCORD_SEND/ALERT_CHANNEL 을 안 쓴다" \
    "$REAL_ENV 를 못 읽는다 — 니노 기계에서만 잴 수 있다"
else
  ENV_CLASH="$(sed 's/#.*//' "$REAL_ENV" | grep -E '^[[:space:]]*(export[[:space:]]+)?(DISCORD_SEND|ALERT_CHANNEL)=')"
  if [ -z "$ENV_CLASH" ]; then
    ok "이름 소유: .env 가 DISCORD_SEND/ALERT_CHANNEL 을 정의하지 않는다"
  else
    bad "이름 소유" "<없음>" "$ENV_CLASH — .env 대입이 주입을 조용히 덮는다(순서로는 못 이긴다)"
  fi
  # 🧪 [양성 대조군] 이 검사기가 실제로 잡는가 — `_BIN` 접미사에 낚이지 않는지까지.
  #   `.env` 에 있는 `DISCORD_SEND_BIN` 을 위반으로 세면 이 시험은 영원히 빨갛고, 그것도 못 재는 것이다.
  CLASH_PROBE="$WORK/env-probe"
  printf 'DISCORD_SEND_BIN=/x/y\nexport ALERT_CHANNEL=현인-업무\n#DISCORD_SEND=/주석\n' > "$CLASH_PROBE"
  PROBE_OUT="$(sed 's/#.*//' "$CLASH_PROBE" | grep -E '^[[:space:]]*(export[[:space:]]+)?(DISCORD_SEND|ALERT_CHANNEL)=')"
  case "$PROBE_OUT" in
    *ALERT_CHANNEL*) case "$PROBE_OUT" in
        *DISCORD_SEND_BIN*) bad "🧪 [양성 대조군] 이름 충돌 검사기" "_BIN 은 위반이 아니다" "$PROBE_OUT" ;;
        *) ok "🧪 [양성 대조군] 이름 충돌 검사기가 export/주석/_BIN 을 정확히 가른다" ;;
      esac ;;
    *) bad "🧪 [양성 대조군] 이름 충돌 검사기" "심어둔 ALERT_CHANNEL 검출" "${PROBE_OUT:-<없음>} — 검사가 공허하다" ;;
  esac
  rm -f "$CLASH_PROBE"
fi

# ③ 정적 — **스텁을 안 탈 수 있는 자리가 남아 있는가**
#   위 동적 축은 "스텁을 탄 것"만 본다. 샌 전송은 스텁을 안 지나가므로 거기엔 절대 안 남는다.
#   ⇒ 소스에서 직접 센다: 주입점 한 줄 말고 `src/discord-send` 를 직접 부르는 자리가 있으면 위반.
hardcoded_send_lines() {   # $1 = 파일 ; stdout = 위반 줄 ; rc 0=쟀다 2=못 쟀다
  local f="$1" stripped
  # 주석을 먼저 지운다 — 주석 속 경로는 호출이 아니다
  stripped="$(sed 's/#.*//' "$f")" || return 2
  printf '%s\n' "$stripped" | grep 'src/discord-send' | grep -v 'DISCORD_SEND:-'
  return 0
}
VIOL="$(hardcoded_send_lines "$WD")"; VRC=$?
if [ "$VRC" -ne 0 ]; then
  # 🔴 검사 도구가 죽은 것을 **통과로 접지 않는다.** 오늘 룬드 `#106` 이 바로 그 형태였다
  #   (가드가 실패하면 열려서 항상 초록).
  skipt "정적: 하드코딩된 전송 자리 없음" "검사기가 파일을 못 읽었다(rc=$VRC) — 못 쟀다"
elif [ -z "$VIOL" ]; then
  ok "정적: 주입점 밖에서 src/discord-send 를 직접 부르는 자리가 없다"
else
  bad "정적: 하드코딩된 전송 자리" "<없음>" "$VIOL"
fi

# 🧪 [양성 대조군] 정적 검사기 자체가 일을 하는가 — 하드코딩을 심은 사본을 잡아야 한다.
#   안 재면 정규식이 아무것도 안 맞아도 초록이다(= 빈 검사가 통과로 보인다).
MUT="$WORK/mutant-wd.sh"
cp "$WD" "$MUT" && printf '\n"$BOT_DIR/src/discord-send" "현인-업무" "샌다"\n' >> "$MUT"
MVIOL="$(hardcoded_send_lines "$MUT")"; MRC=$?
if [ "$MRC" -ne 0 ]; then
  skipt "🧪 [양성 대조군] 정적 검사기" "변이 사본을 못 만들었다 — 검사기가 일하는지 못 쟀다"
elif [ -n "$MVIOL" ]; then
  ok "🧪 [양성 대조군] 정적 검사기가 심어둔 하드코딩을 잡는다"
else
  bad "🧪 [양성 대조군] 정적 검사기" "위반 검출" "<없음> — 검사기가 아무것도 안 잰다(위 초록은 공허하다)"
fi
rm -f "$MUT"


# ═══════════════════════════════════════════════════════════════════════════
# 🔴 Check 6: 감지기 축 — **감지기가 죽었는지는 누가 보나**
#
#   2026-07-30 실측: `check-auth.sh` 가 cron 5분으로 등록돼 있는데 로그가 한 줄도 없어
#   **도는 것과 안 도는 것이 같은 모습**이었다. 2026-07-25 에 실제로 `jq` 부재로 즉사해
#   "인증 만료 알림이 한 번도 안 나간" 사고가 있었고 아무도 몰랐다.
#   ⇒ 감지기가 하트비트를 찍게 했고(PR #83), **그걸 보는 눈**이 이 축이다.
#     안 보면 로그만 쌓이고, 그건 내가 룬드에게 지적한 "감지 포기"와 같아진다.
#
# 🔑 부재를 다루는 방식이 이 축의 핵심이다 — 세 상태다:
#     신선            → ok
#     오래됨          → 감지기가 멈췄다
#     아예 없음       → **첫 관측은 조용하다**(배포 직후엔 정상적으로 없다).
#                        부재를 처음 본 시각을 적고, 그때부터 임계를 재서 알린다.
#     ⚠️ 부재를 "정상"으로 접으면 cron 이 아예 안 걸린 경우를 영구히 놓치고,
#        "죽었다"로 접으면 배포 직후마다 오탐이 난다. 접지 않고 **시각을 기록**한다.
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "🔴 Check 6 — 감지기(check-auth) 하트비트:"

DHB="$WORK/logs/check-auth-heartbeat"
DABS="$WORK/logs/watchdog-detector-absent-since"
DNEXT="$WORK/logs/watchdog-detector-next"

# 감지기 축만 남기고 다른 축은 조용한 상태로 만든다(알림이 섞이면 무엇이 울렸는지 안 갈린다)
det_reset() { reset; rm -f "$DABS" "$DNEXT"; set_hb 1; set_activity 1; make_history Tim; }
det_hb()    { touch -d "@$(( $(date +%s) - ${1:-0} * 60 ))" "$DHB"; }   # $1 = 분 전
det_no_hb() { rm -f "$DHB"; }
det_absent_since() { echo "$(( $(date +%s) - ${1:-0} * 60 ))" > "$DABS"; }  # $1 = 분 전

det_reset; det_hb 5
out="$(run_wd)"
case "$out" in
  *감지기*|*check-auth*) bad "신선한 하트비트엔 조용하다" "알림 0건" "$out" ;;
  *) ok "신선한 하트비트(5분 전)엔 조용하다" ;;
esac

det_reset; det_hb 45
out="$(run_wd)"
# 🔴 고정 헤더에도 "check-auth" 가 있어서 그걸 grep 하면 **두 갈래가 같은 알림을 내도 통과**한다
#   (2026-07-30 변이 ⑧이 그래서 헛돌았다). 사유에 **경과 분**이 들어가는지로 가른다.
case "$out" in
  *"분째 안 움직"*) ok "오래된 하트비트(45분)면 경과 분과 함께 알린다" ;;
  *) bad "감지기 멈춤 알림" "경과 분이 담긴 사유" "${out:-<없음>}" ;;
esac

det_reset; det_no_hb
out="$(run_wd)"
if [ -n "$out" ]; then
  bad "부재 첫 관측은 조용하다" "알림 0건" "$out"
else
  ok "하트비트 부재 첫 관측은 조용하다 (배포 직후 오탐 금지)"
fi
[ -f "$DABS" ] && ok "부재를 처음 본 시각을 기록한다" || bad "부재 시각 기록" "파일 생성" "없음"

det_reset; det_no_hb; det_absent_since 45
out="$(run_wd)"
# 🔑 부재는 "오래됨"과 **다른 문구**여야 한다 — 같으면 사람이 원인을 못 가른다
#   (파일이 없는 것과 감지기가 멈춘 것은 손볼 데가 다르다: cron 등록 vs 스크립트 자체).
case "$out" in
  *"아예 없"*) ok "부재가 임계를 넘기면 '아예 없다'로 알린다 (cron 미등록도 잡는다)" ;;
  *) bad "영구 부재 알림" "부재 전용 문구" "${out:-<없음>}" ;;
esac

# 백오프 — 같은 사고로 매 tick 부르지 않는다
det_reset; det_hb 45
run_wd >/dev/null
out="$(run_wd)"
case "$out" in
  *check-auth*) bad "감지기 알림 백오프" "두 번째 tick 은 조용" "$out" ;;
  *) ok "백오프: 두 번째 tick 은 안 부른다" ;;
esac

# 회복 — 신선해지면 상태를 지워 다음 사고에 **즉시** 부른다
det_reset; det_hb 45
run_wd >/dev/null
det_hb 1
run_wd >/dev/null
if [ -f "$DNEXT" ]; then
  bad "회복 시 백오프 초기화" "상태 파일 삭제" "남아 있다(다음 사고를 늦게 알린다)"
else
  ok "회복되면 백오프 상태를 지운다"
fi

# 🔴 판정 불가(하트비트가 있는데 mtime 을 못 읽는다) — 접지 않는다
#   재현: 하네스가 PATH 를 주입하므로 `stat` 을 실패하는 스텁으로 덮는다.
#   ⚠️ 이 갈래를 안 재면 "판정 불가를 고장으로 접는" 구현도 초록이 된다(변이 ⑦).
det_reset; det_hb 45
printf '#!/bin/bash\nexit 1\n' > "$WORK/bin/stat"; chmod +x "$WORK/bin/stat"
out="$(run_wd)"
rm -f "$WORK/bin/stat"
if [ -n "$out" ]; then
  bad "판정 불가로는 안 부른다" "알림 0건" "$out"
else
  ok "mtime 을 못 읽으면 알리지 않는다 (판정 불가를 고장으로 접지 않는다)"
fi
grep -q 'DETECTOR-UNKNOWN' "$WORK/logs/watchdog.log" 2>/dev/null \
  && ok "판정 불가 사유가 로그에 남는다" \
  || bad "판정 불가 로그" "DETECTOR-UNKNOWN" "$(tail -2 "$WORK/logs/watchdog.log" 2>/dev/null)"

# 🔴 상태 파일이 다른 축과 겹치면 **서로를 침묵시킨다** (기존 시험 주석이 실제로 밟은 자리)
WD_SRC="$WORK/scripts/nino-watchdog.sh"
if grep -q 'watchdog-detector-next' "$WD_SRC" \
   && ! grep -qE 'DETECTOR_STATE=.*watchdog-(silence|auth)-next' "$WD_SRC"; then
  ok "감지기 축은 침묵·인증 축과 다른 상태 파일을 쓴다"
else
  bad "상태 파일 분리" "watchdog-detector-next 전용" "$(grep -n 'next"' "$WD_SRC" | head -3)"
fi

# ══════════════════════════════════════════════════════════════════════════════
# Check 6-b · 감시자 자신의 관측 가능성 (2026-07-30, Darren 승인 M:4ays)
#
# 🔴 배경: check-auth 는 cron 이 4.6일 · 약 1,340회 "실행"으로 기록하는 동안
#    **한 번도 안 돌았다**(syslog CMD 50건 vs check-auth.log 0줄, 15:00~15:50 실측).
#    `cron → sh -c "source … && script"` 는 `&&` 앞이 끊겨도 cron 이 정상 실행으로 센다.
#    ⇒ 워치독 자신도 같은 사각에 있었다: 정상이면 완전히 침묵하는 설계라
#      "조용함"이 **문제없음인지 안 돎인지** 구별되지 않았다(실제로 35분 공백을 오독했다).
# 🔑 판별법은 **기계 독립**이어야 한다(룬드 M:yrne): launchd `runs` 카운터는 직접 exec
#    이라 기동을 보증하지만 cron 에는 그런 값이 없다. 파일 하나는 양쪽에서 똑같이 쓴다.
# ══════════════════════════════════════════════════════════════════════════════
WDHB="$WORK/logs/watchdog.heartbeat"

det_reset; det_hb 5; rm -f "$WDHB"
run_wd >/dev/null
[ -f "$WDHB" ] && ok "워치독이 돌면 자기 하트비트를 남긴다" \
  || bad "감시자 자기 하트비트" "watchdog.heartbeat 생성" "없음 — 감시자 생사를 못 잰다"

det_reset; det_hb 5; rm -f "$WDHB"
run_wd >/dev/null
case "$(cat "$WDHB" 2>/dev/null)" in
  *rc=0*) ok "하트비트에 완주 표시(rc=0)가 들어간다 — 진입만과 완주를 가른다" ;;
  *) bad "완주 표시" "rc=0 포함" "${_x:=$(head -c 60 "$WDHB" 2>/dev/null)}${_x:-<빈 파일>}" ;;
esac

# 🔑 하트비트는 **한 줄**이어야 한다 — 덧붙이기(`>>`)로 바뀌면 옛 `running` 이 남아
#   "지금 상태"가 모호해지고, rc 를 grep 하는 판정이 옛 줄에 맞아 통과해버린다(변이 E 로 발견).
det_reset; det_hb 5; rm -f "$WDHB"
run_wd >/dev/null; run_wd >/dev/null
wd_lines=$(grep -c . "$WDHB" 2>/dev/null || echo 0)
[ "$wd_lines" -eq 1 ] && ok "하트비트는 항상 한 줄 (현재 상태만 남긴다)" \
  || bad "하트비트 한 줄 계약" "1줄" "${wd_lines}줄 — 옛 상태가 섞여 판정이 모호해진다"

det_reset; det_hb 5; rm -f "$WDHB"
run_wd >/dev/null; touch -d '@100' "$WDHB"; wd_old=$(stat -c %Y "$WDHB")
run_wd >/dev/null; wd_new=$(stat -c %Y "$WDHB")
[ "$wd_new" -gt "$wd_old" ] && ok "두 번째 tick 이 하트비트를 갱신한다" \
  || bad "하트비트 갱신" "mtime 증가" "$wd_old → $wd_new (안 갱신되면 stale 판정이 영원히 참)"

# 🔑 진입했지만 완주 못 한 경우 — trap 이 **실제 rc** 를 담는가.
#   ⚠️ 처음엔 tmux 스텁을 `exit 9` 로 깨서 죽이려 했는데 **전제가 틀렸다**: 그건 워치독이
#     죽는 조건이 아니라 *세션 없음 → 재시작* 이라는 **정상 처리 대상**이라 rc=0 으로 완주했다.
#     (시험이 못 죽인 것을 구현 결함으로 읽을 뻔했다 — 실패의 방향을 확인해야 하는 자리.)
#   ⇒ 그래서 **변이 사본**으로 잰다: 진입 직후 강제 종료시켜 trap 만 남긴다.
#     구현을 복제하지 않으므로 항진명제가 아니다 — trap 을 지우면 rc=running 이 남아 빨개진다.
det_reset; det_hb 5; rm -f "$WDHB"
python3 - "$WORK/scripts/nino-watchdog.sh" "$WORK/scripts/wd-dies.sh" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
# 🔴 앵커는 **줄 전체**로 잡는다 — 부분 문자열로 잡았더니 구현 *주석* 안의 같은 문구가
#   먼저 맞아서 `exit 3` 가 trap 설치 **앞**에 꽂혔고, 시험이 엉뚱한 구간을 쟀다.
lines = open(src).read().split("\n")
hit = [i for i, l in enumerate(lines) if l.strip() == "wd_beat running"]
assert len(hit) == 1, f"진입 하트비트 호출 줄이 {len(hit)}개 — 앵커가 모호하다"
lines.insert(hit[0] + 1, "exit 3")
open(dst, "w").write("\n".join(lines))
PY
if [ -f "$WORK/scripts/wd-dies.sh" ]; then
  WORK_MARK="$WORK" PATH="$WORK/bin:$PATH" NINO_HISTORY_CLI="$WORK/bin/yaksu-history" \
    NINO_SESSION_LOG_DIR="$WORK/sessions" bash "$WORK/scripts/wd-dies.sh" >/dev/null 2>&1 || true
  case "$(cat "$WDHB" 2>/dev/null)" in
    *rc=3*)       ok "진입 후 죽으면 trap 이 실제 rc 를 남긴다(rc=3)" ;;
    *rc=running*) bad "죽었을 때 rc 기록" "rc=3" "rc=running — trap 이 안 돌아 죽음이 '진행 중'으로 보인다" ;;
    *rc=0*)       bad "죽었을 때 rc 기록" "rc=3" "rc=0 — 죽었는데 완주로 오독된다" ;;
    *)            bad "죽었을 때 rc 기록" "rc=3" "${_g:=$(head -c 60 "$WDHB" 2>/dev/null)}${_g:-<빈 파일>}" ;;
  esac
else
  skipt "죽었을 때 rc 기록" "변이 사본을 못 만들었다 — 이 갈래는 못 쟀다"
fi

# 🔴 ㉡ 조용히 시작한 상태는 조용히 끝나서 로그가 **안 닫힌다**.
#   회복 로그 조건이 백오프 파일(=경보를 보냈을 때만 생긴다)이라, *첫 관측이라 조용히*
#   기록한 부재는 해소도 조용했다. 그러면 로그 마지막 줄이 영원히 ABSENT 로 남아
#   나중에 읽는 사람은 **아직 부재 중**으로 읽는다(2026-07-30 15:42→16:05 실제 사례).
det_reset; det_hb 1; rm -f "$DNEXT"; det_absent_since 3
run_wd >/dev/null
grep -q 'DETECTOR-RECOVERED' "$WORK/logs/watchdog.log" 2>/dev/null \
  && ok "경보 없이 시작한 부재도 해소를 남긴다" \
  || bad "부재 해소 기록" "DETECTOR-RECOVERED" "없음 — 로그 마지막 줄이 영원히 ABSENT 로 남는다"

det_reset; det_hb 1; rm -f "$DNEXT" "$DABS"
run_wd >/dev/null
grep -q 'DETECTOR-RECOVERED' "$WORK/logs/watchdog.log" 2>/dev/null \
  && bad "부재 이력 없을 때" "조용함" "RECOVERED — 로그가 2분마다 시끄러워진다" \
  || ok "회귀: 부재 이력이 없으면 조용하다 (매 tick 찍지 않는다)"

echo ""
echo "결과: $pass pass, $fail fail, $skip 판정 불가"
# 판정 불가는 rc 를 바꾸지 않는다(자매 파일 catchup-hint 와 같은 관례) — 못 잰 것이지 깨진 게 아니다.
# 대신 위에 사유가 찍히므로 "왜 안 쟀나"가 화면에 남는다.
[[ $fail -eq 0 ]]
