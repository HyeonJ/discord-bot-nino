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
# 🔴 시각 조작은 정본 하나를 지난다 — `touch -d '@N'`·`stat -c %Y` 는 GNU 전용이라
#   룬드 맥(BSD)에서 `out of range or illegal time specification` 으로 죽는다.
. "$SCRIPT_DIR/lib/timeshift.sh"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECK="$REPO/scripts/check-auth.sh"

pass=0; fail=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; [ -n "${2:-}" ] && echo "     want: $2"; [ -n "${3:-}" ] && echo "     got:  $3"; fail=$((fail + 1)); }

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
cat > "$WORK/bin/discord-send" <<'STUB'
#!/bin/bash
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
    touch_at "$(( exp_ms / 1000 - 28800 ))" "$f"      # 만료 - 8시간 = 발급 시각
  else
    touch_at 1750000000 "$f"                          # 아주 옛날 = 갱신이 멈춘 상태
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
[ ! -s "$SENT_LOG" ] && ok "정상이면 알림 없음" || bad "정상이면 알림 없음" "0건" "$(wc -l < "$SENT_LOG")건"

echo "── ② 로그아웃: 알림 1건 + 로그에 흔적 ──"
C="$(creds 36000)"
run "$C" FAKE_CLAUDE_OUT="$LOGGED_OUT"
[ "$(wc -l < "$SENT_LOG")" = 1 ] && ok "로그아웃이면 알림 1건" || bad "로그아웃 알림" "1건" "$(wc -l < "$SENT_LOG")건"
grep -q 'alert=sent' "$LOGF" && ok "로그에 alert=sent 가 남는다" || bad "alert=sent" "있음" "$(cat "$LOGF")"

echo "── ③ 재알림 억제: 두 번째는 안 보내되 **로그는 남는다** ──"
C="$(creds 36000)"
STATE="$WORK/state/rep"; mkdir -p "$STATE"; SENT_LOG="$STATE/sent.tsv"; : > "$SENT_LOG"; LOGF="$STATE/log"
for _ in 1 2; do
  env SENT_LOG="$SENT_LOG" CHECK_AUTH_CREDENTIALS="$C" CHECK_AUTH_STATE_DIR="$STATE" \
      CHECK_AUTH_LOG="$LOGF" CLAUDE_BIN="$WORK/bin/claude" DISCORD_SEND="$WORK/bin/discord-send" \
      FAKE_CLAUDE_OUT="$LOGGED_OUT" bash "$CHECK" >/dev/null 2>&1
done
[ "$(wc -l < "$SENT_LOG")" = 1 ] && ok "1시간 안 두 번째는 안 보낸다" || bad "재알림 억제" "1건" "$(wc -l < "$SENT_LOG")건"
[ "$(wc -l < "$LOGF")" -ge 2 ] && ok "억제돼도 실행 로그는 2줄" || bad "억제 시에도 로그" "2줄 이상" "$(wc -l < "$LOGF")줄"
grep -q 'alert=skip' "$LOGF" && ok "억제는 alert=skip 으로 구분된다" || bad "alert=skip" "있음" "$(cat "$LOGF")"

echo "── ④ 하트비트: 매 실행 갱신된다 (워치독이 이걸 본다) ──"
C="$(creds 36000)"
run "$C" FAKE_CLAUDE_OUT="$LOGGED_IN"
HB="$STATE/check-auth-heartbeat"
[ -f "$HB" ] && ok "하트비트 파일이 생긴다" || bad "하트비트 파일" "존재" "없음"
if [ -f "$HB" ]; then
  touch_at 1750000000 "$HB"; OLD="$(mtime_of "$HB")"
  env SENT_LOG="$SENT_LOG" CHECK_AUTH_CREDENTIALS="$C" CHECK_AUTH_STATE_DIR="$STATE" \
      CHECK_AUTH_LOG="$LOGF" CLAUDE_BIN="$WORK/bin/claude" DISCORD_SEND="$WORK/bin/discord-send" \
      FAKE_CLAUDE_OUT="$LOGGED_IN" bash "$CHECK" >/dev/null 2>&1
  [ "$(mtime_of "$HB")" -gt "$OLD" ] && ok "재실행 시 하트비트가 앞으로 간다" || bad "하트비트 갱신" "갱신됨" "그대로"
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
[ "$(wc -l < "$SENT_LOG")" = 1 ] && ok "status 불가여도 만료 판정은 계속된다" \
  || bad "status 독립 만료판정" "1건" "$(wc -l < "$SENT_LOG")건"
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
[ "$(wc -l < "$SENT_LOG")" = 1 ] && ok "만료됐는데 갱신 안 됨 → 알린다 (룬드 8h27m 갈래)" \
  || bad "만료 후 미갱신 알림" "1건" "$(wc -l < "$SENT_LOG")건"
C="$(creds -300)"                                    # 막 만료 = 갱신 중일 수 있다
run "$C" FAKE_CLAUDE_OUT="$LOGGED_IN"
[ ! -s "$SENT_LOG" ] && ok "막 만료(grace 안)는 안 보낸다 — 갱신 중 오탐 금지" \
  || bad "grace 내 오탐 금지" "0건" "$(cat "$SENT_LOG")"

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

echo
# 🔑 형식을 러너 정규식(`통과 ?[0-9]+`)에 맞춘다 — 안 맞으면 `⚠️건수 미상` 이 되고,
#    그러면 **0개를 쟀어도 초록**이라 시험이 사라진 것을 아무도 모른다(2026-07-30 실측).
echo "  통과 $pass · 실패 $fail"
[ "$fail" -eq 0 ]
