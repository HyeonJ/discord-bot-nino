#!/usr/bin/env bash
# check-auth.sh 계약 시험 — **감지기가 조용히 죽는 것**을 막는다
#
# 🔴 이 시험이 생긴 사고 (둘, 같은 뿌리):
#   ① 2026-07-25: `jq` 가 없어서 `set -e` 로 스크립트가 **즉사**했다 → 인증 만료 알림이
#      **한 번도 안 나갔다.** 증상(jq 의존)은 고쳤지만 *"죽은 걸 아무도 모른다"* 는 안 고쳤다.
#   ② 2026-07-30 실측: 로그가 한 줄도 없어서 **도는 것과 안 도는 것이 같은 모습**이었다.
#      경보 문구 과거 발송 0건 · 상태 파일 없음 · logs/ 에 auth 로그 없음
#      ⇒ 5분마다 돈다고 믿을 근거가 crontab 한 줄뿐이었다.
#
# 🔑 그래서 이 시험의 중심은 "판정이 맞나"가 아니라 **"판정했다는 사실이 남나"** 다.
#    특히 ⑤ — **죽어도 로그가 남는지**. 그게 없으면 다음 사고도 조용하다.
#
# ⚠️ 부작용 금지: 실제 Discord 전송·실제 `claude`·실제 `~/.claude` 를 건드리지 않는다.
#    전부 주입으로 대체하고, 상태·로그는 임시 디렉터리에 쓴다.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECK="$REPO/scripts/check-auth.sh"

# 🔴 코어 정본이 없으면 이 파일 «전체»가 판정 불가다 — 없으면 나머지 단언이 전부
#   *틀린 이유로* 빨개진다(원래 빨간 판 위의 빨강은 아무도 못 본다). 이유·경위는 헬퍼에.
. "$REPO/tests/lib/require-core.sh"

. "$SCRIPT_DIR/lib/capture-rc.sh"

pass=0; fail=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; [ -n "${2:-}" ] && echo "     want: $2"; [ -n "${3:-}" ] && echo "     got:  $3"; fail=$((fail + 1)); }

# ── 이식성 헬퍼 (bash 3.2 / BSD userland — 룬드 맥에서 6건 실패, 2026-07-31) ──────
# 🔴 세 개 다 **내가 이미 적어둔 함정**이다([[ref_bash_portability_32]] 33·213~219행).
#    적어둔 것이 손을 안 막았다 ⇒ 규칙 대신 **형태**로 내린다: 아래 헬퍼만 쓰고 원시 명령을 안 쓴다.
#    ⑮가 그 규약을 정적으로 잠근다(원시 명령이 다시 들어오면 빨개진다).

# 🔴 `wc -l` 은 BSD 에서 앞에 공백을 붙인다('       1') ⇒ **값이 같아도 문자열 비교가 깨진다.**
#    "1건" 을 기대했는데 "       1건" 이 와서 실패로 보인다 — 틀린 게 아니라 **못 잰 것**이다.
nlines() { wc -l < "$1" | tr -d '[:space:]'; }

# 🔴 `touch -d '@epoch'` 는 GNU 전용. BSD 는 `out of range or illegal time specification` 으로 죽는다.
#    ⇒ python 으로 옮긴다. `os.utime` 은 양쪽 동일하다(2026-07-29 에 같은 이유로 옮긴 적 있다).
set_mtime() { python3 -c 'import os,sys; t=float(sys.argv[2]); os.utime(sys.argv[1],(t,t))' "$1" "$2"; }

# 🔴 `stat -c %Y` 는 GNU, BSD 는 `stat -f %m`. 분기하지 않고 python 하나로 간다.
mtime() { python3 -c 'import os,sys; print(int(os.path.getmtime(sys.argv[1])))' "$1"; }

[ -f "$CHECK" ] || { echo "❌ 없음: $CHECK"; exit 1; }
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin" "$WORK/state"

# ── 가짜 claude: auth status 출력과 종료코드를 주입으로 제어 ──────────────────
cat > "$WORK/bin/claude" <<'STUB'
#!/bin/bash
[ -n "${FAKE_CLAUDE_OUT:-}" ] && printf '%s' "$FAKE_CLAUDE_OUT"
exit "${FAKE_CLAUDE_RC:-0}"
STUB
chmod +x "$WORK/bin/claude"

# ── 가짜 discord-send: 전송을 파일로 기록만 한다 ─────────────────────────────
# 🔑 `FAKE_SEND_RC` 로 **발송 실패**를 주입한다. 실패하면 SENT_LOG 에 안 적는다 —
#    "보냈다고 기록됐는데 실제론 안 갔다" 를 시험이 재현할 수 있어야 하기 때문이다.
cat > "$WORK/bin/discord-send" <<'STUB'
#!/bin/bash
if [ "${FAKE_SEND_RC:-0}" != 0 ]; then
  echo "discord-send: 전송 실패(주입)" >&2
  exit "$FAKE_SEND_RC"
fi
printf '%s\t%s\n' "$1" "$2" >> "$SENT_LOG"
STUB
chmod +x "$WORK/bin/discord-send"

# 자격증명 픽스처: $1=만료까지 남은 초, $2=mtime 을 만료-8h 로 맞출지(yes/no)
#   🔑 refresh 가 정상이면 **mtime + 8h ≈ expiresAt** 이다(2026-07-30 실측).
#      이 픽스처가 그 두 상태를 갈라준다 — 안 갈리면 "정상인데 경보" 를 못 잡는다.
creds() {
  local left="$1" anchor="${2:-yes}" f="$WORK/creds-$RANDOM.json"
  local exp_ms; exp_ms=$(( ( $(date +%s) + left ) * 1000 ))
  printf '{"claudeAiOauth":{"accessToken":"x","refreshToken":"y","expiresAt":%d,"subscriptionType":"max"}}' \
    "$exp_ms" > "$f"
  if [ "$anchor" = yes ]; then
    set_mtime "$f" "$(( exp_ms / 1000 - 28800 ))"    # 만료 - 8시간 = 발급 시각
  else
    set_mtime "$f" 1750000000                          # 아주 옛날 = 갱신이 멈춘 상태
  fi
  echo "$f"
}

# run <creds파일> [env...] — 격리 실행. 상태·로그는 매번 새 디렉터리.
run() {
  local cred="$1"; shift
  STATE="$WORK/state/$RANDOM"; mkdir -p "$STATE"
  SENT_LOG="$STATE/sent.tsv"; : > "$SENT_LOG"
  LOGF="$STATE/check-auth.log"
  env SENT_LOG="$SENT_LOG" \
      CHECK_AUTH_CREDENTIALS="$cred" \
      CHECK_AUTH_STATE_DIR="$STATE" \
      CHECK_AUTH_LOG="$LOGF" \
      CLAUDE_BIN="$WORK/bin/claude" \
      DISCORD_SEND="$WORK/bin/discord-send" \
      "$@" bash "$CHECK" >/dev/null 2>&1
  RC=$?
  return 0
}
LOGGED_IN='{"loggedIn": true, "authMethod": "claude.ai"}'
LOGGED_OUT='{"loggedIn": false}'

echo "── ① 정상: 로그가 남고 알림은 안 간다 ──"
C="$(creds 36000)"                                   # 10시간 남음 = 경고 창 밖
run "$C" FAKE_CLAUDE_OUT="$LOGGED_IN"
[ -s "$LOGF" ] && ok "정상 실행도 로그 1줄을 남긴다" || bad "정상 실행도 로그를 남긴다" "로그 있음" "빈 파일"
[ ! -s "$SENT_LOG" ] && ok "정상이면 알림 없음" || bad "정상이면 알림 없음" "0건" "$(nlines "$SENT_LOG")건"

echo "── ② 로그아웃: 알림 1건 + 로그에 흔적 ──"
C="$(creds 36000)"
run "$C" FAKE_CLAUDE_OUT="$LOGGED_OUT"
[ "$(nlines "$SENT_LOG")" = 1 ] && ok "로그아웃이면 알림 1건" || bad "로그아웃 알림" "1건" "$(nlines "$SENT_LOG")건"
grep -q 'alert=sent' "$LOGF" && ok "로그에 alert=sent 가 남는다" || bad "alert=sent" "있음" "$(cat "$LOGF")"

echo "── ③ 재알림 억제: 두 번째는 안 보내되 **로그는 남는다** ──"
C="$(creds 36000)"
STATE="$WORK/state/rep"; mkdir -p "$STATE"; SENT_LOG="$STATE/sent.tsv"; : > "$SENT_LOG"; LOGF="$STATE/log"
for _ in 1 2; do
  env SENT_LOG="$SENT_LOG" CHECK_AUTH_CREDENTIALS="$C" CHECK_AUTH_STATE_DIR="$STATE" \
      CHECK_AUTH_LOG="$LOGF" CLAUDE_BIN="$WORK/bin/claude" DISCORD_SEND="$WORK/bin/discord-send" \
      FAKE_CLAUDE_OUT="$LOGGED_OUT" bash "$CHECK" >/dev/null 2>&1
done
[ "$(nlines "$SENT_LOG")" = 1 ] && ok "1시간 안 두 번째는 안 보낸다" || bad "재알림 억제" "1건" "$(nlines "$SENT_LOG")건"
[ "$(nlines "$LOGF")" -ge 2 ] && ok "억제돼도 실행 로그는 2줄" || bad "억제 시에도 로그" "2줄 이상" "$(nlines "$LOGF")줄"
grep -q 'alert=skip' "$LOGF" && ok "억제는 alert=skip 으로 구분된다" || bad "alert=skip" "있음" "$(cat "$LOGF")"

echo "── ④ 하트비트: 매 실행 갱신된다 (워치독이 이걸 본다) ──"
C="$(creds 36000)"
run "$C" FAKE_CLAUDE_OUT="$LOGGED_IN"
HB="$STATE/check-auth-heartbeat"
[ -f "$HB" ] && ok "하트비트 파일이 생긴다" || bad "하트비트 파일" "존재" "없음"
if [ -f "$HB" ]; then
  set_mtime "$HB" 1750000000; OLD="$(mtime "$HB")"
  env SENT_LOG="$SENT_LOG" CHECK_AUTH_CREDENTIALS="$C" CHECK_AUTH_STATE_DIR="$STATE" \
      CHECK_AUTH_LOG="$LOGF" CLAUDE_BIN="$WORK/bin/claude" DISCORD_SEND="$WORK/bin/discord-send" \
      FAKE_CLAUDE_OUT="$LOGGED_IN" bash "$CHECK" >/dev/null 2>&1
  [ "$(mtime "$HB")" -gt "$OLD" ] && ok "재실행 시 하트비트가 앞으로 간다" || bad "하트비트 갱신" "갱신됨" "그대로"
fi

echo "── ⑤ 🔴 죽어도 로그가 남는다 (2026-07-25 사고 회귀) ──"
# claude 가 아예 없다 = 그때의 jq 부재와 같은 형태. set -e 로 즉사하면 로그가 안 남는다.
C="$(creds 36000)"
run "$C" CLAUDE_BIN="$WORK/bin/does-not-exist"
[ -s "$LOGF" ] && ok "의존성이 없어도 로그 1줄은 남는다" || bad "죽어도 로그" "로그 있음" "빈 파일(=조용한 죽음)"
grep -qE 'verdict=(unknown|error)' "$LOGF" && ok "판정 불가를 unknown/error 로 남긴다" \
  || bad "판정 불가 표기" "verdict=unknown|error" "$(cat "$LOGF")"
# 🔴 판정 불가를 "로그아웃"으로 접어 알림을 쏘면 안 된다 — 그건 오탐의 씨앗이다
[ ! -s "$SENT_LOG" ] && ok "판정 불가로는 알림을 쏘지 않는다" || bad "판정불가 알림 금지" "0건" "$(cat "$SENT_LOG")"
#
# 🔴 그리고 **status 가 깨져도 만료 판정은 독립적으로 계속돼야** 한다.
#   이게 없으면 `set -e` 로 즉사하는 구현도 초록이 된다 — 로그는 trap 이 남기니까
#   "죽어도 로그" 시험만으로는 **판정이 반쪽이 된 것**을 못 가른다(2026-07-30 변이 ③이 헛돌아 발견).
#   실제 값: `claude` 가 깨진 상태에서 토큰이 만료돼 있으면 그게 가장 위험한 조합이다.
C="$(creds -3600)"
run "$C" CLAUDE_BIN="$WORK/bin/does-not-exist"
[ "$(nlines "$SENT_LOG")" = 1 ] && ok "status 불가여도 만료 판정은 계속된다" \
  || bad "status 독립 만료판정" "1건" "$(nlines "$SENT_LOG")건"
grep -q 'expiry=stale' "$LOGF" && ok "그 판정이 로그에 expiry=stale 로 남는다" \
  || bad "expiry=stale 기록" "있음" "$(cat "$LOGF")"

echo "── ⑥ 상태 파일이 /tmp 밖이다 (재부팅 생존) ──"
grep -qE '^[^#]*=[^#]*"?/tmp/' "$CHECK" && bad "/tmp 경로 없음" "logs/ 사용" "$(grep -nE '^[^#]*/tmp/' "$CHECK" | head -3)" \
  || ok "스크립트에 /tmp 상태 경로가 없다"

echo "── ⑦ 만료 판정: **만료 전 60분**이 아니라 **만료 후 미갱신**을 본다 ──"
#
# 🔴 계약을 바꾼 이유 (2026-07-30, 시험을 쓰다가 발견):
#   옛 계약은 *"만료 60분 전이면 경고"* 였다. 그런데 refresh 는 **자동이고 만료 시점에 돈다**
#   ⇒ 60분 전 경고는 사람이 할 일이 없다 = **항상 거짓**이다(오늘 15:30 에 갈 예정이던 그것).
#   반대로 진짜 위험한 건 **만료가 지났는데도 갱신이 안 된 것** — 룬드가 8시간 27분 죽은 상태고,
#   옛 계약은 만료 "전" 60분만 봐서 그 갈래를 **아예 안 봤다**(사각).
# 🔑 이 판정은 `claude auth status` 와 **독립**이다 — 파일의 expiresAt 과 갱신 여부만 본다.
#   그래서 status 가 만료 토큰에 loggedIn:true 를 주는 거짓 음성을 **프로브 없이** 우회한다.
C="$(creds 1800)"                                    # 30분 남음 = 정상 수명 중
run "$C" FAKE_CLAUDE_OUT="$LOGGED_IN"
[ ! -s "$SENT_LOG" ] && ok "만료 임박(30분)에는 안 보낸다 — 옛 거짓 양성 제거" \
  || bad "옛 60분 경고 제거" "0건" "$(cat "$SENT_LOG")"
C="$(creds -3600)"                                   # 1시간 전에 만료됐고 갱신 안 됨
run "$C" FAKE_CLAUDE_OUT="$LOGGED_IN"
[ "$(nlines "$SENT_LOG")" = 1 ] && ok "만료됐는데 갱신 안 됨 → 알린다 (룬드 8h27m 갈래)" \
  || bad "만료 후 미갱신 알림" "1건" "$(nlines "$SENT_LOG")건"
C="$(creds -300)"                                    # 막 만료 = 갱신 중일 수 있다
run "$C" FAKE_CLAUDE_OUT="$LOGGED_IN"
[ ! -s "$SENT_LOG" ] && ok "막 만료(grace 안)는 안 보낸다 — 갱신 중 오탐 금지" \
  || bad "grace 내 오탐 금지" "0건" "$(cat "$SENT_LOG")"

# 🔴 회귀 — **20분짜리 만료가 통째로 무음이었다** (2026-08-12 05:46~06:07 실물).
#   옛 grace 가 1800(30분)이라 20분 만료는 «설계상» 한 번도 안 울었고 로그에도 expiry=ok 로 남았다.
#   그때 실제로 운 것은 사용량 체커가 «우연히» 401 을 맞은 부수 효과였다 — 그게 없었으면
#   이 20분은 아무 데도 안 남는다. 부재는 조용하다.
# 🔑 이 시험이 없으면 grace 를 다시 키워도 초록이다 — 위 -3600·-300 은 1800 에서도 600 에서도
#   같은 답을 내서 **경계를 하나도 안 잡는다**.
# ⚠️ 좌변은 「상수가 600 이냐」가 아니라 **「20분 만료가 우나」**다 — 상수는 수단이고 계약은 이것이다.
C="$(creds -1200)"                                   # 20분 전에 만료 · 갱신 안 됨
run "$C" FAKE_CLAUDE_OUT="$LOGGED_IN"
[ "$(nlines "$SENT_LOG")" = 1 ] && ok "20분 만료는 알린다 (08-12 무음 구간 회귀)" \
  || bad "20분 만료 알림" "1건" "$(nlines "$SENT_LOG")건"

echo "── ⑧ 저장소가 없으면(env 방식) 만료 판정을 **접지 않고 skip** 한다 ──"
# 🔴 파일 부재를 "만료"로 접으면 env 토큰으로 정상 동작하는 봇에 오보가 간다(룬드 14:38 사고의 형태).
run "$WORK/no-such-creds.json" FAKE_CLAUDE_OUT="$LOGGED_IN"
[ ! -s "$SENT_LOG" ] && ok "저장소 부재로는 알림을 쏘지 않는다" || bad "부재 오탐 금지" "0건" "$(cat "$SENT_LOG")"
grep -q 'expiry=skip' "$LOGF" && ok "로그에 expiry=skip 으로 남는다(판정 불가를 기록)" \
  || bad "expiry=skip 기록" "있음" "$(cat "$LOGF")"

echo "── ⑨ 전송은 반드시 주입 가능한 경로를 쓴다 (시험이 실제 Discord 를 때리지 않게) ──"
# 🔴 이 시험이 필요한 이유: 옛 스크립트는 `$BOT_DIR/src/discord-send` 를 직접 불렀다.
#   그래서 위 케이스들이 초록이어도 **가짜가 불린 게 아니라 실물이 불려 실패한 것**일 수 있었다
#   (= 항진명제). 실제로 2026-07-30 첫 실행에서 그 일이 났고, 부작용이 안 난 건 워크트리에
#   `.env` 가 없어서였다 — **우연이 안전을 만든 것이라 계약으로 박는다.**
grep -qE '\$\{?DISCORD_SEND' "$CHECK" && ok "DISCORD_SEND 변수를 쓴다" \
  || bad "DISCORD_SEND 주입" "변수 사용" "없음"
# 🔑 인용부호 패턴으로 "직접 호출"을 찾으면 쓰는 방식만 바뀌어도 빠져나간다(항진명제).
#    경로가 **기본값 한 줄에만** 나오는지를 센다 — 두 번 이상이면 어딘가에서 또 부르는 것이다.
SD_HITS=$(grep -c 'src/discord-send' "$CHECK")
[ "$SD_HITS" -le 1 ] && ok "경로가 기본값 1곳에만 있다 (직접 호출 없음)" \
  || bad "직접 호출 없음" "1곳 이하" "${SD_HITS}곳: $(grep -n 'src/discord-send' "$CHECK" | head -3)"

echo "── ⑩ 🔴 cron 환경(PATH=/usr/bin:/bin)에서도 claude 를 스스로 찾는다 ──"
#
# 🔴 2026-07-30 실사고: crontab 이 `source $HOME/.nvm/nvm.sh && check-auth.sh` 였다.
#   **cron 의 sh(dash)엔 `source` 가 없다** → `&&` 가 끊겨 이 감지기가 **한 번도 안 불렸다.**
#   *"경보 발송 0건"* 의 진짜 원인이 "죽은 채 있었다"가 아니라 **"아예 안 불렸다"** 였고,
#   두 상태는 로그가 없으면 같은 모습이다(#83 이 붙인 로그가 tick 두 번 뒤에도 0줄이라 갈렸다).
#   ⇒ crontab 에서 그 줄을 없애려면 스크립트가 **스스로** claude 를 찾아야 한다.
#   🔸 같은 부류가 2026-07-28 에 이미 있었다(`check-core-drift.sh` 가 cron 에서 node 를 못 찾아
#     매 실행 판정 불가). 그래서 `scripts/lib/resolve-bin.sh` 가 생겼는데 이 감지기만 안 옮겨졌다.
FAKEHOME="$WORK/fakehome"
mkdir -p "$FAKEHOME/.nvm/versions/node/v24.14.0/bin"
cp "$WORK/bin/claude" "$FAKEHOME/.nvm/versions/node/v24.14.0/bin/claude"
C="$(creds 36000)"
STATE="$WORK/state/cronlike"; mkdir -p "$STATE"
SENT_LOG="$STATE/sent.tsv"; : > "$SENT_LOG"; LOGF="$STATE/log"
# 🔑 CLAUDE_BIN 을 **주지 않는다** — 주면 해석 경로를 안 태워서 이 시험이 헛돈다.
env -i PATH=/usr/bin:/bin HOME="$FAKEHOME" \
    SENT_LOG="$SENT_LOG" CHECK_AUTH_CREDENTIALS="$C" CHECK_AUTH_STATE_DIR="$STATE" \
    CHECK_AUTH_LOG="$LOGF" DISCORD_SEND="$WORK/bin/discord-send" \
    FAKE_CLAUDE_OUT="$LOGGED_IN" \
    bash "$CHECK" >/dev/null 2>&1
if grep -q 'verdict=ok' "$LOGF" 2>/dev/null; then
  ok "cron 유사 환경에서 nvm 의 claude 를 찾아 판정까지 간다"
else
  bad "cron 환경 claude 해석" "verdict=ok" "$(cat "$LOGF" 2>/dev/null || echo '<로그 없음>')"
fi

echo "── ⑪ setup.sh 의 cron 줄에 dash 가 모르는 \`source\` 가 없다 ──"
# 🔴 라이브 crontab 만 고치면 setup.sh 재실행 때 **되살아난다**(사본이 두 벌인 문제).
SETUP="$REPO/scripts/setup.sh"
if [ -f "$SETUP" ]; then
  line="$(grep 'check-auth' "$SETUP" | head -1)"
  case "$line" in
    *source*) bad "setup.sh cron 줄" "source 없음" "$line" ;;
    *check-auth*) ok "setup.sh 의 cron 줄이 스크립트를 직접 부른다" ;;
    *) bad "setup.sh cron 줄" "check-auth 등록 줄" "<없음>" ;;
  esac
else
  echo "  ⏭️  판정 불가 — setup.sh 가 없다"
fi

echo "── ⑫ 🔴 발송 실패를 삼키지 않는다 — **부르는 경로가 조용히 실패하는 자리** ──"
# 🔴 옛 코드:  notify(){ "$DISCORD_SEND" … >/dev/null 2>&1 || true; }
#             notify "…"; mark_alert …; ALERT=sent      ← **무조건** sent
#   ⇒ discord-send 가 죽어도 로그엔 `alert=sent` 가 남고, 게다가 백오프까지 찍혀
#     **1시간 침묵**한다. 인증이 진짜 끊긴 상황에서 이건 유일한 복구 수단이 사라지는 것이다.
# 🔑 이 시험의 본체는 "실패를 감지하나"가 아니라 **"실패했는데 성공으로 기록하나"** 다.
#    (룬드가 자기 check-auth 에서 먼저 밟고 고친 자리 — `send_failed` 로 가른다)
C="$(creds 36000)"
run "$C" FAKE_CLAUDE_OUT="$LOGGED_OUT" FAKE_SEND_RC=1
[ ! -s "$SENT_LOG" ] && ok "발송이 실제로 실패했다(대조군: 전송 기록 0건)" \
  || bad "실패 주입" "전송 0건" "$(nlines "$SENT_LOG")건"
grep -q 'alert=sent' "$LOGF" && bad "실패인데 alert=sent 로 기록" "sent 아님" "$(cat "$LOGF")" \
  || ok "실패를 sent 로 기록하지 않는다"
grep -q 'alert=send_failed' "$LOGF" && ok "alert=send_failed 로 갈린다" \
  || bad "alert=send_failed" "있음" "$(cat "$LOGF")"

echo "── ⑬ 🔑 발송 실패면 **백오프를 안 찍는다** — 다음 기회를 스스로 지우지 않는다 ──"
# 🔴 여기가 ⑫보다 아프다. 실패를 로그에 정직히 적어도 **백오프를 찍으면 1시간 동안 재시도가 없다.**
#    첫 시도가 일시 장애(네트워크·relay 재시작)였으면 그 1시간이 통째로 사라진다.
STATE="$WORK/state/failretry"; mkdir -p "$STATE"
SENT_LOG="$STATE/sent.tsv"; : > "$SENT_LOG"; LOGF="$STATE/log"
C="$(creds 36000)"
# 1회차: 실패 주입 · 2회차: 정상 — 백오프를 안 찍었다면 2회차가 **즉시** 나가야 한다
env SENT_LOG="$SENT_LOG" CHECK_AUTH_CREDENTIALS="$C" CHECK_AUTH_STATE_DIR="$STATE" \
    CHECK_AUTH_LOG="$LOGF" CLAUDE_BIN="$WORK/bin/claude" DISCORD_SEND="$WORK/bin/discord-send" \
    FAKE_CLAUDE_OUT="$LOGGED_OUT" FAKE_SEND_RC=1 bash "$CHECK" >/dev/null 2>&1
env SENT_LOG="$SENT_LOG" CHECK_AUTH_CREDENTIALS="$C" CHECK_AUTH_STATE_DIR="$STATE" \
    CHECK_AUTH_LOG="$LOGF" CLAUDE_BIN="$WORK/bin/claude" DISCORD_SEND="$WORK/bin/discord-send" \
    FAKE_CLAUDE_OUT="$LOGGED_OUT" bash "$CHECK" >/dev/null 2>&1
[ "$(nlines "$SENT_LOG")" = 1 ] && ok "실패 뒤 다음 실행이 **즉시** 재시도해서 도달한다" \
  || bad "실패 후 재시도" "1건 도달" "$(nlines "$SENT_LOG")건 — 백오프를 찍어 침묵했다"

# ⚠️ 백오프 파일 유무는 **실패 실행만 격리해서** 본다. 위 2회차는 성공이라 파일을 만드니,
#    거기서 재면 어느 쪽이든 설명이 붙어 **항진명제**가 된다(처음에 그렇게 썼다가 고침).
STATE2="$WORK/state/failonly"; mkdir -p "$STATE2"
env SENT_LOG="$STATE2/sent.tsv" CHECK_AUTH_CREDENTIALS="$C" CHECK_AUTH_STATE_DIR="$STATE2" \
    CHECK_AUTH_LOG="$STATE2/log" CLAUDE_BIN="$WORK/bin/claude" DISCORD_SEND="$WORK/bin/discord-send" \
    FAKE_CLAUDE_OUT="$LOGGED_OUT" FAKE_SEND_RC=1 bash "$CHECK" >/dev/null 2>&1
[ ! -f "$STATE2/check-auth-last-alert" ] && ok "실패했을 땐 백오프 파일을 안 만든다" \
  || bad "실패 시 백오프" "파일 없음" "파일 생성됨 — 다음 기회를 스스로 지운다"

echo "── ⑭ 만료 갈래도 같은 계약이다 — 한 자리만 고치면 다른 자리가 남는다 ──"
# 🔴 `notify` 호출부는 **둘**이다(로그아웃·만료 후 미갱신). 오늘 밤 계속 본 형태 —
#    같은 계약이 여러 자리에서 실현되면 한 자리만 덮고도 초록이 된다.
C="$(creds -7200)"                                   # 2시간 전 만료 + 갱신 안 됨
run "$C" FAKE_CLAUDE_OUT="$LOGGED_IN" FAKE_SEND_RC=1
grep -q 'expiry_failed' "$LOGF" && ok "만료 알림 실패도 expiry_failed 로 갈린다" \
  || bad "expiry_failed" "있음" "$(cat "$LOGF")"
grep -qE 'alert=[a-z_]*\+expiry(\b|[^_])' "$LOGF" \
  && bad "만료 발송 실패인데 +expiry(성공)로 기록" "+expiry 아님" "$(cat "$LOGF")" \
  || ok "실패를 +expiry(성공)로 기록하지 않는다"

echo "── ⑮ 🔴 이식성 규약을 **형태로** 잠근다 — 원시 명령이 다시 들어오면 빨개진다 ──"
# 🔴 왜 시험으로 잠그나: `touch -d`·`wc -l`·`stat -c` 셋 다 **내가 이미 메모리에 적어둔 함정**인데
#    이 파일에 그대로 썼다(룬드 맥에서 6건 실패, 2026-07-31). **적어둔 것이 손을 안 막았다.**
#    ⇒ 오늘 밤 내내 확인한 것: 규칙보다 형태가 강하다. 다음에 누가 `wc -l` 을 다시 쓰면 여기서 걸린다.
# ⚠️ 헬퍼 정의 줄과 주석은 제외한다 — 안 그러면 설명조차 못 적는다(자기 자신을 잡는 시험이 된다).
_hf_viol="$(mktemp)"   # 🔴 3.2: $( … << ) 형태를 피한다 (heredoc-form-guard)
python3 - "$0" <<'PYEOF' > "${_hf_viol}"
import re, sys
# 🔑 리터럴을 조립한다 — 면제 구역을 두면 그 구역이 뚫린다(자기 printer 를 정의하는 형태).
#    이러면 이 가드도 **자기 자신을 포함해** 파일 전체를 검사한다.
RAW = {'touch' + ' -d': 'set_mtime', 'stat' + ' -c': 'mtime', 'wc' + ' -l': 'nlines'}
ALLOW = ('nlines()', 'set_mtime()', 'mtime()')          # 헬퍼 정의 줄만 원시 명령을 쓴다
bad = []
for i, ln in enumerate(open(sys.argv[1]), 1):
    t = ln.strip()
    if t.startswith('#') or any(a in ln for a in ALLOW):
        continue
    for raw, fix in RAW.items():
        if raw in ln:
            bad.append("%d행: `%s` 대신 `%s` 를 쓸 것" % (i, raw, fix))
print('\n'.join(bad))
PYEOF
_hf_rc_viol=$?   # 🔴 PYEOF 바로 다음 줄 — 한 줄만 밀려도 딴 명령의 rc 다
viol="$(cat "${_hf_viol}")"; rm -f "${_hf_viol}"
if _hf_msg="$(hf_verdict "$_hf_rc_viol" "이식성")"; then
    [ -z "$viol" ] && ok "원시 GNU 명령을 직접 안 쓴다 (헬퍼 경유)" || bad "이식성 규약 위반" "0건" "$viol"
else
    bad "$_hf_msg" "rc=0" "«${viol}»"
fi
# 음성 검사 — 이 시험이 실제로 물 수 있나(항상 초록인 시험이 아닌지)
probe="$(mktemp)"; printf 'x="$(wc %s < "$f")"\n' '-l' > "$probe"
_hf_pv="$(mktemp)"   # 🔴 3.2: $( … << ) 형태를 피한다 (heredoc-form-guard)
python3 - "$probe" <<'PYEOF' > "${_hf_pv}"
import sys
print('HIT' if 'wc' + ' -l' in open(sys.argv[1]).read() else '')
PYEOF
_hf_rc_pv=$?   # 🔴 PYEOF 바로 다음 줄 — 한 줄만 밀려도 딴 명령의 rc 다
pv="$(cat "${_hf_pv}")"; rm -f "${_hf_pv}"
if _hf_msg="$(hf_verdict "$_hf_rc_pv" "음성 대조군")"; then
    [ -n "$pv" ] && ok "  → 원시 명령이 들어오면 잡는다(음성 대조군)" || bad "  이 시험은 어떤 변이로도 안 갈린다"
else
    bad "$_hf_msg" "rc=0" "«${pv}»"
fi
rm -f "$probe"

echo "── ⑯ 🔴 인자 계약 (코어 cli-guard) — 09:50 사고의 형태를 막는다 ──"
# 🔴 이 감지기는 **5분마다** 돈다. 그래서 여기서 조용히 틀리면 하루 288번 조용히 틀린다.
# 🔑 계약 ③: *"플래그가 있나"* 가 아니라 **"스텁이 몇 번 불렸나"** 로 잠근다.
# 🔸 이 절 전용 발송 스텁 — **호출 1회 = 1줄.** 공용 스텁은 본문을 그대로 적는데 경보 본문이
#   여러 줄이라, 줄로 세면 1건이 N건으로 보인다(배치 2에서 실제로 4건으로 보였다).
cat > "$WORK/bin/send-1" <<'STUB'
#!/bin/bash
printf 'SEND\t%s\n' "$1" >> "$G_SENT"
STUB
chmod +x "$WORK/bin/send-1"
g_sends() { grep -c '^SEND' "$G_SENT" 2>/dev/null | head -1; }
gr() {   # gr <스크립트 인자…>   (GUARD_ENV 를 세우면 CLI_DRY_RUN 을 환경으로 물려준다)
  G_STATE="$WORK/guard$RANDOM"; mkdir -p "$G_STATE"
  G_SENT="$G_STATE/sent.tsv"; : > "$G_SENT"
  G_LOG="$G_STATE/check-auth.log"
  # 🔴 stderr 를 **따로 받는다.** 합치면 코어의 `DRY-RUN: 보내지 않았다 → …` 안내에 본문이
  #   통째로 들어가서, 내 stdout 단언이 *코어가 낸 문구로* 통과하거나(배치2 M5) 집계가
  #   오염된다(배치3 morning-briefing 은 그래서 결정적으로 1 fail 이었다).
  g_out="$(env G_SENT="$G_SENT" SENT_LOG="$G_SENT" \
      CHECK_AUTH_CREDENTIALS="$(creds 36000)" \
      CHECK_AUTH_STATE_DIR="$G_STATE" CHECK_AUTH_LOG="$G_LOG" \
      CLAUDE_BIN="$WORK/bin/claude" DISCORD_SEND="$WORK/bin/send-1" \
      FAKE_CLAUDE_OUT="$LOGGED_OUT" \
      ${GUARD_ENV:+CLI_DRY_RUN="$GUARD_ENV"} \
      bash "$CHECK" "$@" 2>"$G_STATE/err")"
  G_RC=$?
  return 0
}

# 🧪 [대조군] **먼저 이것부터.** 아래 "발송 0건"들이 가드 덕인지, 이 픽스처가 애초에
#   아무것도 안 보내는 건지 못 가른다 — 대조군이 초록이 아니면 나머지 빨간불은 증거가 아니다.
# 🔸 만료 임박 자격증명을 줘서 경보가 실제로 나가게 한다.
GUARD_ENV="" gr
CTRL_SENDS="$(g_sends)"
[ "$CTRL_SENDS" -ge 1 ] && ok "🧪 [대조군] 인자 없이 부르면 실제로 발송이 일어난다 (${CTRL_SENDS}건)" \
  || bad "대조군" "1건 이상" "0건 — 이 픽스처는 원래 안 보낸다. 아래 0건은 증거가 아니다"

GUARD_ENV="" gr --report
[ "$G_RC" -eq 2 ] && ok "모르는 인자 --report 를 rc=2 로 거절한다 (1 아님 — 못 쟀다)" \
  || bad "모르는 인자 rc" "2" "$G_RC"
[ "$(g_sends)" -eq 0 ] && ok "  🔑 거절되면 발송 0건 (09:50 사고 재현 차단)" \
  || bad "거절인데 발송" "0건" "$(g_sends)건"
# 🔑 **거절도 흔적을 남긴다.** cron 은 stderr 를 버린다 — 안 남기면 crontab 오타 하나로
#   5분마다 돌던 이 감지기가 *아무 표시 없이* 멈춘다. 그게 이 스크립트가 막으려는 바로 그것이다.
grep -q 'verdict=bad_args' "$G_LOG" 2>/dev/null && ok "  🔑 거절이 로그에 남는다 (verdict=bad_args)" \
  || bad "거절 로그" "verdict=bad_args" "$(cat "$G_LOG" 2>/dev/null || echo '<로그 없음>')"

GUARD_ENV="" gr --dry-run
[ "$(g_sends)" -eq 0 ] && ok "--dry-run 이면 발송 0건" || bad "dry-run 발송" "0건" "$(g_sends)건"
# 🔴 **발송 0건만으로는 부족하다.** 백오프 도장을 찍으면 진단 한 번이 다음 **실경보를
#   최대 1시간 늦춘다** — 아무 표시 없이. 여기가 이 감지기가 막으려는 바로 그 고장이다.
#   (룬드 assistant#50 리뷰 중 내 쪽에서 같은 구멍을 발견 — 그쪽은 이미 닫았고 내 쪽은 열려 있었다.)
[ ! -f "$G_STATE/check-auth-last-alert" ] && ok "  🔑 --dry-run 은 백오프 도장을 안 찍는다" \
  || bad "dry-run 백오프" "도장 없음" "찍힘 — 진단이 다음 실경보를 지연시킨다"
# 🔑 **기록이 사실이어야 한다.** 안 보낸 것을 sent 로 적으면 로그가 거짓이 되고,
#   나중에 "그때 알렸는데 왜 못 봤나"로 사람이 엉뚱한 데를 판다.
grep -q 'alert=sent_dry_run' "$G_LOG" 2>/dev/null && ok "  🔑 로그가 사실대로 alert=sent_dry_run — 어느 경보였는지까지 남는다" \
  || bad "dry-run 로그" "alert=sent_dry_run" "$(grep -o 'alert=[a-z_+]*' "$G_LOG" 2>/dev/null | tail -1)"

# 🔴 환경 상속은 **거절**한다(코어 계약 ④). 무시하면 dry-run 을 기대한 쪽이 발송당하고,
#   따르면 발송을 기대한 쪽이 조용해진다 — 어느 쪽으로 접어도 조용히 틀린다.
GUARD_ENV=1 gr
[ "$G_RC" -eq 2 ] && ok "🔴 CLI_DRY_RUN 을 환경에서 물려받으면 rc=2 로 거절한다" \
  || bad "환경 상속" "rc=2" "rc=$G_RC — 플래그 없이 dry-run 이 켜졌거나 조용히 무시됐다"
[ "$(g_sends)" -eq 0 ] && ok "  → 거절이므로 발송 0건" || bad "상속 거절 발송" "0건" "$(g_sends)건"
grep -q 'verdict=bad_env' "$G_LOG" 2>/dev/null && ok "  🔑 bad_args 와 갈라 센다 (고칠 곳이 환경이라서)" \
  || bad "bad_env 표지" "verdict=bad_env" "$(cat "$G_LOG" 2>/dev/null || echo '<로그 없음>')"

GUARD_ENV="" gr --help
[ "$(g_sends)" -eq 0 ] && ok "--help 는 발송 0건" || bad "help 발송" "0건" "$(g_sends)건"
printf '%s' "$g_out" | grep -q 'usage:' && ok "  → 사용법을 stdout 으로 낸다" || bad "usage 출력" "usage: 줄" "$g_out"

echo "── ⑰ 🔴 stale 을 «탐침»으로 가른다 — idle 만료와 갱신 고장은 다른 것이다 ──"
#
# 🔴 왜 생겼나 (2026-08-14, Darren 이 세서 알려줬다):
#   *「너 만료 안됐는데 이 알림 하루에 한번씩 꼭 오는거같아」* — 11일에 6번, **전부 verdict=ok**.
#   오늘 건은 **25초** 차이였다: 경보 16:15:07 · 자격증명 파일 갱신 16:15:32.
#   기전 — `accessToken` 갱신은 **«호출할 때»** 돈다. 세션이 조용하면 `expiresAt` 은 과거인 채
#   남고, 옛 판정은 그걸 「갱신이 안 되고 있다」로 읽었다. ⇒ **idle 이 사고로 오독됐다.**
#
# 🔴 순진한 수리(「refreshTokenExpiresAt 가 미래면 무해」)는 **쓰면 안 된다** — 룬드 8시간 27분
#   먹통 때 그의 파일엔 refreshToken 이 **있는데 안 쓰이고 있었다**(2026-07-30 실측).
#   그 조건이면 그 사고를 「무해」라 불렀을 것이다. **있음 ≠ 쓰임.**
#
# ✅ 그래서 좌변이 «필드»가 아니라 «호출»이다: stale 이면 한 번 찔러보고 **파일을 다시 읽는다.**
#   판정은 탐침의 rc 가 아니라 **「expiresAt 이 미래로 갔나」** — 우리가 실제로 신경 쓰는 그 상태다.
#   🔑 부수 효과가 처방이다: 찌르는 행위가 갱신을 시켜서 **진단이 곧 수리**다.

# 탐침용 가짜: 호출 횟수를 세고, PROBE_REFRESH=1 이면 자격증명을 «실제로» 갱신한다
cat > "$WORK/bin/claude-probe" <<'STUB'
#!/bin/bash
PROBE=0
for a in "$@"; do [ "$a" = "-p" ] && PROBE=1; done
if [ "$PROBE" = 1 ]; then
  echo probe >> "$PROBE_LOG"
  [ "${PROBE_RC:-0}" != 0 ] && exit "$PROBE_RC"
  if [ "${PROBE_REFRESH:-0}" = 1 ]; then
    python3 -c 'import sys,json,time;p=sys.argv[1];d=json.load(open(p));d["claudeAiOauth"]["expiresAt"]=int((time.time()+28800)*1000);json.dump(d,open(p,"w"))' "$PROBE_CREDS"
  fi
  exit 0
fi
printf '%s' "${FAKE_CLAUDE_OUT:-}"; exit "${FAKE_CLAUDE_RC:-0}"
STUB
chmod +x "$WORK/bin/claude-probe"

probe_run() {   # $1=creds · $2=PROBE_REFRESH · $3=PROBE_RC
  PROBE_LOG="$WORK/probe-$RANDOM.log"; : > "$PROBE_LOG"
  run "$1" CLAUDE_BIN="$WORK/bin/claude-probe" FAKE_CLAUDE_OUT="$LOGGED_IN" \
      PROBE_LOG="$PROBE_LOG" PROBE_CREDS="$1" PROBE_REFRESH="$2" PROBE_RC="${3:-0}"
}
probes() { nlines "$PROBE_LOG"; }

# ⓐ 오늘의 실물 — stale 인데 탐침이 갱신시킨다 ⇒ **안 울린다**
C="$(creds -3600 no)"
probe_run "$C" 1
[ "$(nlines "$SENT_LOG")" = 0 ] && ok "🔴 갱신되면 «안» 울린다 (Darren 이 센 6건이 이 자리다)" \
  || bad "idle 만료 오보" "0건" "$(nlines "$SENT_LOG")건 — 거짓 경보가 그대로다"
[ "$(probes)" = 1 ] && ok "  → 탐침을 «한 번» 돌았다" || bad "탐침 횟수" "1" "$(probes)"
grep -q 'expiry=refreshed' "$LOGF" && ok "  🔑 로그가 stale 과 갈라 적는다 (expiry=refreshed)" \
  || bad "판정 표지" "expiry=refreshed" "$(grep -o 'expiry=[a-z_]*' "$LOGF" | tail -1)"

# ⓑ 🔴 회귀 방지 — 탐침 후에도 미갱신이면 **진짜다.** 룬드 8시간 27분이 이 가지다
C="$(creds -3600 no)"
probe_run "$C" 0
[ "$(nlines "$SENT_LOG")" = 1 ] && ok "🔴 탐침해도 안 갱신되면 «울린다» (룬드 8h27m 회귀 방지)" \
  || bad "진짜 사고 무음" "1건" "$(nlines "$SENT_LOG")건 — 수리가 사고를 삼켰다"
grep -q 'expiry=stale' "$LOGF" && ok "  → expiry=stale 로 남는다" \
  || bad "stale 표지" "expiry=stale" "$(grep -o 'expiry=[a-z_]*' "$LOGF" | tail -1)"

# ⓒ 🔴 탐침이 «죽어도» 무해로 새면 안 된다 — Darren Ⅲ(「조용히 안 오는 쪽이 더 나쁘다」) 보존
C="$(creds -3600 no)"
probe_run "$C" 0 9
[ "$(nlines "$SENT_LOG")" = 1 ] && ok "🔴 탐침이 실패해도 «무해»로 접지 않는다 (시끄러운 쪽으로 실패)" \
  || bad "탐침 실패 삼킴" "1건" "$(nlines "$SENT_LOG")건 — 탐침 고장이 감지기를 껐다"
# 🔑 이게 «판정을 탐침 rc 가 아니라 파일 상태»로 두는 이유다 — rc 를 믿으면 이 가지가 뒤집힌다

# ⓓ 🔑 비용 — stale 이 «아니면» 탐침을 아예 안 돈다 (이 스크립트는 5분마다 돈다)
C="$(creds 3600)"
probe_run "$C" 1
[ "$(probes)" = 0 ] && ok "🔑 정상일 땐 탐침 0회 — 5분마다 도는 자리에 비용을 안 넣는다" \
  || bad "불필요한 탐침" "0" "$(probes)회"
[ "$(nlines "$SENT_LOG")" = 0 ] && ok "  → 발송도 0건" || bad "정상인데 발송" "0건" "$(nlines "$SENT_LOG")건"

# ⓔ 🧪 ⓐ의 «양성» — 같은 픽스처에서 갱신만 끄면 판정이 뒤집힌다(ⓐ가 항진명제가 아니다)
C="$(creds -3600 no)"; probe_run "$C" 1; A="$(nlines "$SENT_LOG")"
C="$(creds -3600 no)"; probe_run "$C" 0; B="$(nlines "$SENT_LOG")"
[ "$A" != "$B" ] && ok "🧪 갱신 여부 하나로 판정이 갈린다 ($A ↔ $B) — ⓐ가 항진명제가 아니다" \
  || bad "판정이 안 갈린다" "다른 값" "둘 다 ${A}건 — 탐침이 아무것도 안 재고 있다"

echo "── ⑱ 🔴 알림 문안이 «관측»과 «처방»을 가른다 — 호출부 «둘 다» ──"
# 🔑 실물 2026-08-13: 내 알림이 「사람이 /login 해야 함」을 «사실»처럼 실어서 룬드가 그걸
#    «관측»으로 읽고 자기 갈래 «정의»를 바꿨다(그의 3ec50e6 자기 정정).
#    접두 «[감시]» 는 「누가 말했나」만 가르지 「관측인가 판정인가」는 «안» 가른다.
# 🔴 호출부가 «둘»이다(로그아웃 · 만료 후 미갱신). 한 자리만 고치면 다른 자리가 남고,
#    같은 계약이 여러 자리에 있으면 «한 자리만 덮고도 초록»이 된다(⑭ 와 같은 축).
for _case in logged_out stale; do
  if [ "$_case" = logged_out ]; then
    C="$(creds 36000)"; run "$C" FAKE_CLAUDE_OUT="$LOGGED_OUT"
  else
    C="$(creds -7200 no)"; run "$C" FAKE_CLAUDE_OUT="$LOGGED_IN"
  fi
  body="$(cut -f2 "$SENT_LOG" 2>/dev/null)"
  # 🔴 대조군 — 좌변이 비면 아래 case 가 «상수 참»이 된다. 추출 자체를 먼저 단언한다.
  if [ -z "$body" ]; then
    bad "⑱ ${_case} — 알림 본문 추출 실패" "1건 이상" "SENT_LOG 가 비었다(발송 자체가 안 났다)"
    continue
  fi
  case "$body" in
    *"관측:"*) ok "⑱ ${_case} — «관측:» 라벨이 있다" ;;
    *) bad "⑱ ${_case} — 관측 라벨 없음" "관측:" "$body" ;;
  esac
  case "$body" in
    *"처방(추정):"*) ok "⑱ ${_case} — «처방(추정):» 라벨이 있다" ;;
    *) bad "⑱ ${_case} — 처방 라벨 없음" "처방(추정):" "$body" ;;
  esac
done

echo "── ⑲ 🔴 정적 전수 — «새 호출부»가 생겨도 잡힌다 (⑱ 만으로는 다음 자리가 또 샌다) ──"
# 🔑 ⑱ 은 «지금 있는 두 자리»를 재고, 이건 «앞으로 생길 자리»를 잰다. 근본이 「한 자리만
#    덮고도 초록」이라 좌변이 «전수»여야 한다 — 동적 시험 옆에 정적 전수를 둔다.
# 🔴 판별식: 이건 checklist(목록 «밖»이 무검사 = 조용하다)라 좌변이 «닫혀» 있어야 한다.
#    ⇒ 리터럴 호출은 라벨을 «재고», 변수 호출은 «판정 불가»로 시끄럽게 낸다(안 재고 넘기지 않는다).
# 🔴 **좌변(분모)과 판정을 «따로» 조인다 — 첫 판은 판정만 조였다** (룬드 #224 리뷰).
#    분모가 `grep -c 'notify "'` 라 **겹따옴표로 시작하는 호출만** 셌다. 그래서
#      notify '라벨 없는 홑따옴표'   ← 분모 밖 ⇒ 초록(미탐)
#      notify $MSG                   ← 분모 밖 ⇒ 초록(미탐)
#    가 «개수도 안 변한 채» 조용히 통과했다(실측: 심은 뒤에도 「2곳 전부」).
#    🔑 *「검사가 틀리면 오탐이 시끄럽고, 분모가 좁으면 «아무 일도 안 일어난다»」* —
#      allowlist 는 «판정»의 성질이지 «분모»를 넓혀주지 않는다.
#    ⇒ 좌변은 «함수 이름»으로 잡는다(따옴표·조립 방식과 무관).
# 🔴 **allowlist 로 읽는다 — 목록 «밖»이 더 엄격하다.** 첫 판에서 `notify "$...` 를
#    「변수로 조립 → 판정 불가」로 접었는데, 지금 두 호출부가 «전부» `$MENTION` 으로 시작해서
#    **라벨이 없어도 조용히 넘어갔다**(checklist 가 되어 미탐이 무음). 좌변을 뒤집는다:
#    «라벨 형태와 정확히 일치하지 않으면 전부 실패». 변수로 조립한 새 호출부가 생기면
#    그것도 여기서 «시끄럽게» 걸리고, 정당하면 그때 이 좌변을 함께 고친다.
_sites="$(command grep -cE '(^|[^_[:alnum:]])notify ' "$CHECK" || true)"
if [ "${_sites:-0}" -eq 0 ]; then
  bad "⑲ 대조군 — notify 호출부가 0건이다" "1건 이상" "좌변이 비어 «항진명제»가 된다"
else
  _nolabel=0
  while IFS= read -r line; do
    case "$line" in
      *'notify "$MENTION 관측:'*) : ;;
      *) _nolabel=$((_nolabel + 1)); echo "     라벨 없음: $line" ;;
    esac
  done < <(command grep -nE '(^|[^_[:alnum:]])notify ' "$CHECK")
  if [ "$_nolabel" -eq 0 ]; then
    ok "⑲ notify 호출부 ${_sites}곳 «전부» 관측 라벨로 시작한다"
  else
    bad "⑲ 라벨 없는 호출부 ${_nolabel}곳" "0곳" "위 목록 참조"
  fi
fi

echo
# 🔑 형식을 러너 정규식(`통과 ?[0-9]+`)에 맞춘다 — 안 맞으면 `⚠️건수 미상` 이 되고,
#    그러면 **0개를 쟀어도 초록**이라 시험이 사라진 것을 아무도 모른다(2026-07-30 실측).
echo "  통과 $pass · 실패 $fail"
[ "$fail" -eq 0 ]
