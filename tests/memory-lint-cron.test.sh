#!/usr/bin/env bash
# memory-lint-cron.sh 계약 — **언제 소리를 내는가**
#
# 왜 이 시험이 생겼나 (2026-07-28):
#   기억 검사를 알림에 배선하는 걸 미뤄뒀던 이유가 결과가 **213건**이었기 때문이다.
#   그 상태로 켜면 시간마다 213건 경고가 오고 사람은 곧 무시한다 —
#   *초록에서 시작하지 않는 감시는 배경소음이 된다*.
#   CRLF 204건을 정리해 9건이 됐지만 **9건도 상시 상태**라 "매번 알림"은 여전히 소음이다.
#   그래서 계약을 **항목 집합의 차이**로 잡았고, 그 계약을 여기서 값으로 고정한다.
#
# 격리: 실제 lint·실제 discord-send 를 쓰지 않는다(둘 다 주입). 실제 logs/ 도 안 건드린다.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 🔴 코어 정본이 없으면 이 파일 «전체»가 판정 불가다 — 없으면 나머지 단언이 전부
#   *틀린 이유로* 빨개진다(원래 빨간 판 위의 빨강은 아무도 못 본다). 이유·경위는 헬퍼에.
REPO="${REPO:-$(cd "$SCRIPT_DIR/.." && pwd)}"
. "$REPO/tests/lib/require-core.sh"
BOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$BOT/scripts/memory-lint-cron.sh"

pass=0; fail=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; fail=$((fail + 1)); [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/     /'; }

[ -f "$SCRIPT" ] || { echo "❌ 없음: $SCRIPT"; exit 1; }
ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT
mkdir -p "$ROOT/logs"

# 가짜 lint — ITEMS 파일의 각 줄을 "  ⚠️  <메시지>" 로 내고, RC 파일의 코드로 죽는다.
# 🔴 **키 채널을 정본과 같은 모양으로 흉내낸다** (코어 #141): 줄이 `키<TAB>메시지` 면 그 키를,
#   탭이 없으면 **메시지 자신**을 키로 쓴다 — 정본 `issue()` 의 `${2:-$1}` 과 같은 규칙이다.
#   🔑 스텁이 키를 «유도»하면 안 된다. 유도하는 순간 시험은 크론이 아니라 스텁을 재게 된다.
#   ⇒ 픽스처가 키와 메시지를 **둘 다 명시**하고, 크론이 하는 일은 「그 키를 쓴다」뿐이다.
# 🔸 `FAKE_NO_KEYS=1` 이면 키를 아예 안 낸다 — **옛 검사기**(키 채널 없음) 재현용.
cat > "$ROOT/fake-lint.sh" <<'FAKE'
#!/usr/bin/env bash
echo "== 1. 어떤 섹션 =="
while IFS= read -r l; do
  [ -n "$l" ] || continue
  case "$l" in
    *"$(printf '\t')"*) k="${l%%$(printf '\t')*}"; m="${l#*$(printf '\t')}" ;;
    *) k="$l"; m="$l" ;;
  esac
  echo "  ⚠️  $m"
  if [ -n "${LINT_KEY_FILE:-}" ] && [ "${FAKE_NO_KEYS:-0}" != "1" ]; then
    printf '%s\n' "$k" >> "$LINT_KEY_FILE"
  fi
done < "$FAKE_ITEMS"
n=$(grep -c . "$FAKE_ITEMS" 2>/dev/null | head -1)
echo "== 결과: ${n:-0}건 =="
exit "$(cat "$FAKE_RC")"
FAKE
chmod +x "$ROOT/fake-lint.sh"

# 🔑 **계측기를 먼저 먹인다** — 정답을 아는 최소 입력(빈 ITEMS = 0건)으로 *가짜 lint 자체*를 검사한다.
#    이 줄은 원래 `grep -c … || echo 0` 이었다. grep -c 는 무매치에도 "0" 을 찍으면서 rc=1 이라
#    `||` 가 또 실행돼 요약 줄이 **두 줄로 쪼개졌다**("== 결과: 0" / "0건 =="). 하네스가 틀린
#    형태라 어떤 케이스도 빨개지지 않았고, 그래서 몇 시간 동안 안 보였다.
#    ⇒ 대상만 검사하고 계측기는 안 검사하는 시험은 자기 오류를 못 본다. 하네스에도 시험을 붙인다.
: > "$ROOT/items.txt"; printf '0\n' > "$ROOT/rc.txt"
harness_out="$(FAKE_ITEMS="$ROOT/items.txt" FAKE_RC="$ROOT/rc.txt" bash "$ROOT/fake-lint.sh")"
if [ "$(printf '%s\n' "$harness_out" | grep -c '^== 결과: 0건 ==$' | head -1)" -eq 1 ]; then
  ok "하네스 자기검사 — 빈 입력에서 요약 줄이 한 줄로 나온다"
else
  bad "하네스 자기검사 — 요약 줄이 쪼개졌다(grep -c 함정)" "$harness_out"
fi

# 가짜 discord-send — 보낸 본문을 파일에 적는다. FAKE_SEND_RC 로 실패도 재현한다
cat > "$ROOT/fake-send" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$2" >> "$FAKE_SENT"
exit "${FAKE_SEND_RC:-0}"
FAKE
chmod +x "$ROOT/fake-send"

items() { printf '%s\n' "$@" > "$ROOT/items.txt"; }
# 키를 명시하는 판 — 인자는 `키|메시지`. (탭은 셸에서 다루기 번거로워 `|` 로 받아 탭으로 옮긴다)
kitems() {
  : > "$ROOT/items.txt"
  for a in "$@"; do printf '%s\t%s\n' "${a%%|*}" "${a#*|}" >> "$ROOT/items.txt"; done
}
rc_is() { printf '%s\n' "$1" > "$ROOT/rc.txt"; }
run() {
  : > "$ROOT/sent.txt"
  FAKE_ITEMS="$ROOT/items.txt" FAKE_RC="$ROOT/rc.txt" FAKE_SENT="$ROOT/sent.txt" \
  FAKE_SEND_RC="${1:-0}" \
  BOT_DIR="$ROOT" LINT="$ROOT/fake-lint.sh" DISCORD_SEND="$ROOT/fake-send" \
  STATE="$ROOT/logs/state" HEARTBEAT="$ROOT/logs/hb" LOG="$ROOT/logs/log" \
  bash "$SCRIPT" 2>&1
}
# ⚠️ `grep -c . f || echo 0` 은 **0 을 두 번** 낸다 — grep 은 0 을 찍고도 무매치면 rc=1 이라
#    `||` 가 또 실행된다. 그러면 `[ "$(sent_count)" -eq 0 ]` 이 "integer expression expected" 로
#    깨지고, 시험이 대상이 아니라 **자기 계측기 때문에** 빨개진다(2026-07-28 실제로 그랬다).
sent_count() { grep -c . "$ROOT/sent.txt" 2>/dev/null; }

echo "① 0건이면 조용하고 rc=0"
items ""; rc_is 0
out="$(run)"; rc=$?
[ "$rc" -eq 0 ] && ok "rc=0" || bad "rc=$rc" "$out"
[ "$(sent_count)" -eq 0 ] && ok "알림 없음" || bad "0건인데 알림을 보냈다" "$(cat "$ROOT/sent.txt")"
[ -s "$ROOT/logs/hb" ] && ok "하트비트 남김 (조용한 것과 죽은 것을 구분)" || bad "하트비트 없음"

echo "② 첫 실행에 항목이 있으면 알린다"
items "A 항목" "B 항목"; rc_is 1
out="$(run)"; rc=$?
[ "$(sent_count)" -ge 1 ] && ok "알림 1건" || bad "알림 없음" "$out"
grep -q "A 항목" "$ROOT/sent.txt" && grep -q "B 항목" "$ROOT/sent.txt" && ok "두 항목이 본문에 들어감" \
  || bad "항목이 본문에 없다" "$(cat "$ROOT/sent.txt")"

echo "③ 🔑 같은 항목이면 **조용하다** — 이 스크립트의 존재 이유"
out="$(run)"; rc=$?
[ "$(sent_count)" -eq 0 ] && ok "두 번째 실행은 무음" || bad "같은 항목인데 또 알렸다 (배경소음)" "$(cat "$ROOT/sent.txt")"
[ "$rc" -eq 0 ] && ok "rc=0 (조치할 새 것이 없다)" || bad "rc=$rc"

echo "④ 새 항목이 생기면 **그것만** 알린다"
items "A 항목" "B 항목" "C 새로운 것"; rc_is 1
out="$(run)"
grep -q "C 새로운 것" "$ROOT/sent.txt" && ok "새 항목 포함" || bad "새 항목이 없다" "$(cat "$ROOT/sent.txt")"
grep -q "A 항목" "$ROOT/sent.txt" && bad "이미 알린 항목을 또 보냈다" "$(cat "$ROOT/sent.txt")" \
  || ok "기존 항목은 다시 안 보낸다"

echo "⑤ 🔑 개수가 같아도 **항목이 바뀌면** 알린다 (개수만 보면 놓치는 자리)"
items "A 항목" "B 항목" "D 교체된 것"; rc_is 1
out="$(run)"
grep -q "D 교체된 것" "$ROOT/sent.txt" && ok "교체를 잡는다" \
  || bad "개수가 같아 조용히 지나갔다 — 집합이 아니라 개수를 보고 있다" "$(cat "$ROOT/sent.txt")"

echo "⑤-a 🔴 **측정값만 바뀐 같은 항목은 조용하다** (2026-08-02 Darren 지적: 매시 울렸다)"
# 🔴 실사고: `🚨 1000줄 초과: inbox-…md (6627줄)` 의 **줄 수가 항목 이름 안에** 있었다.
#   내가 그 파일에 한 줄 쓸 때마다 6627→6667 로 문자열이 바뀌어 **같은 문제가 「새 항목」**이 됐다.
#   ⑤ 의 집합 비교는 «맞게» 돌고 있었다 — 틀린 건 한 층 아래, **원소의 식별자**다.
# 🔑 증거의 형태: 로그의 `항목=13` 이 8시간 내내 고정인데 알림은 왔다.
#   **개수가 안 변하는데 소리가 나면 그건 원소 «이름»이 바뀐 것이다.**
# 🔑 **수리 후의 축**: 크론은 문자열을 정규화하지 않는다 — 검사기가 준 키를 쓸 뿐이다.
#   그래서 픽스처가 «키는 같고 메시지만 다른» 두 판을 준다. 크론이 키를 안 보고 메시지를 보면 빨개진다.
kitems "docsize:🚨 1000줄 초과:inbox.md|🚨 1000줄 초과: inbox.md (6627줄) — 통째로 읽힌다"; rc_is 1
run >/dev/null                                     # 1회차: 첫 통보(정상)
: > "$ROOT/sent.txt"
kitems "docsize:🚨 1000줄 초과:inbox.md|🚨 1000줄 초과: inbox.md (6667줄) — 통째로 읽힌다"; rc_is 1
run >/dev/null                                     # 2회차: 줄 수만 +40 (키는 그대로)
if [ -s "$ROOT/sent.txt" ]; then
  bad "줄 수만 바뀌었는데 또 알렸다 — 낡는 측정값이 식별자에 박혀 있다" "$(cat "$ROOT/sent.txt")"
else
  ok "측정값만 바뀐 같은 항목은 조용하다"
fi

echo "⑤-b 🧪 [대조군] 그렇다고 **한도 승격까지 접으면 안 된다** — 괄호 «밖» 숫자는 식별자다"
# 🔑 ⑤-a 를 「숫자를 전부 지운다」로 고치면 `500줄 초과` 와 `1000줄 초과` 가 같은 키가 되어
#   **파일이 한도를 넘어서는 순간이 조용해진다.** 접는 것은 «괄호 안 측정값»뿐이다.
#
# 🔴 **첫 판 대조군은 이 변이를 못 잡았다**(2026-08-02 실측: 변이 B 32·0 통과).
#   500 판과 1000 판을 «실제 lint 문구 그대로» 썼더니 이모지(⚠️/🚨)와 뒷문장까지 달라서,
#   숫자를 전부 지워도 **다른 것들이 키를 갈라줬다.** 즉 축이 격리되지 않았다.
#   ⇒ 대조군은 **바꾸려는 축 하나만** 다르게 한다. 아래 둘은 «괄호 밖 숫자»만 빼고 완전히 같다.
#   (같은 실수를 한 시간 전 lint 픽스처에서도 했다 — 축을 가르는 값 외의 것이 같이 움직이면
#    통과가 「축을 잠갔다」가 아니라 「다른 것 덕에 갈렸다」가 된다.)
# 🔑 수리 후엔 이 갈림이 **검사기 쪽**에 있다(키에 한도가 남는다 — 코어 시험 ⓑ). 여기서는
#   «키가 다르면 크론이 실제로 알리는가»를 잰다. 두 판은 **키의 한도 부분만** 다르다.
: > "$ROOT/sent.txt"
kitems "docsize:🚨 500줄 초과:grow.md|🚨 500줄 초과: grow.md (536줄) — 같은 뒷문장"; rc_is 1
run >/dev/null
: > "$ROOT/sent.txt"
kitems "docsize:🚨 1000줄 초과:grow.md|🚨 1000줄 초과: grow.md (536줄) — 같은 뒷문장"; rc_is 1
run >/dev/null
if grep -q '1000줄 초과' "$ROOT/sent.txt"; then
  ok "[대조군] 괄호 밖 한도 숫자만 달라도 알린다 (승격이 안 접힌다)"
else
  bad "[대조군] 승격이 조용해졌다 — 정규화가 «괄호 밖» 숫자까지 먹었다" "$(cat "$ROOT/sent.txt")"
fi

echo "⑤-c 🔴 **키가 안 오면 「조용」이 아니라 「판정 불가」다** (분모 가드 — 「전부인가」층)"
# 🔑 이 크론의 비교는 «사람 줄과 키가 행 단위로 짝»이라는 전제 위에 선다. 검사기가 옛 판이면
#   키가 0건인데, 그 상태는 **「새 항목 없음」과 똑같은 모양**이라 조용히 지나간다.
#   ⇒ 조용한 쪽으로 틀리지 않게, 짝이 안 맞으면 **시끄럽게** 낸다.
#   (룬드 정식화: 분모 가드는 두 층이다 — ①「0 인가」 ②「**전부**인가」. ②가 더 나쁘다,
#    ①은 0 이라 눈에 띄는데 ②는 말이 되는 값이라 아무도 안 묻는다.)
rm -f "$ROOT/logs/state"
items "무엇이든 한 건"; rc_is 1
: > "$ROOT/sent.txt"
out="$(FAKE_NO_KEYS=1 FAKE_ITEMS="$ROOT/items.txt" FAKE_RC="$ROOT/rc.txt" FAKE_SENT="$ROOT/sent.txt" \
      BOT_DIR="$ROOT" LINT="$ROOT/fake-lint.sh" DISCORD_SEND="$ROOT/fake-send" \
      STATE="$ROOT/logs/state" HEARTBEAT="$ROOT/logs/hb" LOG="$ROOT/logs/log" \
      bash "$SCRIPT" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && ok "키 채널 부재 → rc=2 (판정 불가)" || bad "rc=$rc — 조용히 지나갔다" "$out"
grep -q "판정 불가" "$ROOT/sent.txt" && ok "판정 불가라고 말한다" || bad "말 안 함" "$(cat "$ROOT/sent.txt")"
[ ! -f "$ROOT/logs/state" ] && ok "상태를 갱신하지 않는다 — 못 잰 것을 기준선으로 삼지 않는다" \
  || bad "판정 불가인데 상태를 갱신했다" "$(cat "$ROOT/logs/state")"

echo "⑤-d 🧪 [대조군] 같은 입력이 키 채널이 «살아 있으면» 정상 판정된다"
# 🔑 ⑤-c 만 두면 「어떤 이유로든 rc=2」로도 통과한다. 분모를 갈라주는 건 이 대조군이다.
: > "$ROOT/sent.txt"; rm -f "$ROOT/logs/state"
out="$(run)"; rc=$?
[ "$rc" -eq 0 ] && ok "[대조군] 키가 오면 rc=0" || bad "rc=$rc" "$out"
grep -q "판정 불가" "$ROOT/sent.txt" && bad "[대조군] 키가 있는데 판정 불가라 했다" "$(cat "$ROOT/sent.txt")" \
  || ok "[대조군] 판정 불가 아님 — ⑤-c 의 rc=2 는 «키 부재»에서 왔다"

echo "⑤-e 🔴 **옛 상태 파일(사람 줄)은 조용히 기준선으로 삼는다** — 수리가 마지막으로 크게 울지 않게"
# 🔑 상태에는 이제 «키»가 산다. 옛 상태(사람 줄)를 키로 읽으면 **전 항목이 「새 항목」**이 되어,
#   Darren 이 잡은 그 소음을 고치면서 **같은 소음을 한 번 더** 낸다. 첫 줄 표지로 형식을 가른다.
: > "$ROOT/sent.txt"
printf '%s\n' "🚨 1000줄 초과: inbox.md (6627줄) — 통째로 읽힌다" > "$ROOT/logs/state"   # 옛 형식
kitems "docsize:🚨 1000줄 초과:inbox.md|🚨 1000줄 초과: inbox.md (6772줄) — 통째로 읽힌다"; rc_is 1
out="$(run)"; rc=$?
[ "$(sent_count)" -eq 1 ] && ok "전환을 «한 줄»로 알린다" \
  || bad "전환 통보가 1건이 아니다 (0=조용히 삼킴 · 2+=통째 나열)" "$(cat "$ROOT/sent.txt")"
grep -q '기준선' "$ROOT/sent.txt" && ok "무엇을 기준선으로 삼았는지 말한다" \
  || bad "전환이라고만 하고 기준선을 안 말한다" "$(cat "$ROOT/sent.txt")"
grep -q '통째로 읽힌다' "$ROOT/sent.txt" && bad "전환 통보에 항목을 통째로 나열했다 (피하려던 그 소음)" "$(cat "$ROOT/sent.txt")" \
  || ok "항목을 나열하지 않는다"
[ "$(head -1 "$ROOT/logs/state")" = "#keys-v1" ] && ok "상태가 키 형식으로 바뀐다" \
  || bad "상태 형식이 안 바뀌었다" "$(cat "$ROOT/logs/state")"
: > "$ROOT/sent.txt"
kitems "docsize:🚨 1000줄 초과:inbox.md|🚨 1000줄 초과: inbox.md (6999줄) — 통째로 읽힌다"; rc_is 1
run >/dev/null
[ "$(sent_count)" -eq 0 ] && ok "전환 다음 회차는 조용하다 (기준선이 실제로 잡혔다)" \
  || bad "전환 후 첫 비교에서 울었다" "$(cat "$ROOT/sent.txt")"

echo "⑤-f 🔴 [룬드 실증] **전환 통보가 실패하면 기준선을 잡지 않는다** — 아무도 모르는 채로 삼키지 않게"
# 🔑 ⑤-e 가 「한 줄 온다」를 잠근다면 여기는 「그 한 줄이 «실제로 닿았을 때만» 기준선이 된다」를 잠근다.
#   전환은 **되돌릴 수 없는 자리**다(옛 상태를 덮어쓴다). 통보가 유실되면 그 시점의 미발견 항목이
#   **아무 흔적 없이** 영구 매장된다 — ⑧ 과 같은 규율을 여기에도 건다.
rm -f "$ROOT/logs/state"
printf '%s\n' "옛 형식 한 줄" > "$ROOT/logs/state"
kitems "keyX|X 항목"; rc_is 1
out="$(run 1)"; rc=$?                                  # 전송 실패 주입
[ "$rc" -ne 0 ] && ok "전환 통보 실패를 rc 로 드러낸다 (rc=$rc)" || bad "통보가 실패했는데 rc=0" "$out"
[ "$(head -1 "$ROOT/logs/state")" != "#keys-v1" ] && ok "상태를 갱신하지 않는다 — 다음 회차에 다시 시도" \
  || bad "통보 실패인데 기준선을 잡았다 (그 시점 항목이 영구 매장된다)" "$(cat "$ROOT/logs/state")"
: > "$ROOT/sent.txt"
out="$(run 0)"                                         # 다음 회차: 전송 정상
[ "$(sent_count)" -eq 1 ] && ok "다음 회차에 전환 통보를 실제로 다시 보낸다" \
  || bad "재통보 안 됨" "$(cat "$ROOT/sent.txt")"

echo "⑥ 판정 불가(rc≠0,1)는 **알린다** — 검사가 죽은 것을 '문제 없음'과 같게 두지 않는다"
items "무엇이든"; rc_is 4
out="$(run)"; rc=$?
[ "$rc" -eq 4 ] && ok "rc 를 그대로 전달(4)" || bad "rc=$rc — 원래 코드가 사라졌다" "$out"
grep -q "판정 불가" "$ROOT/sent.txt" && ok "판정 불가라고 말한다" || bad "판정 불가 문구 없음" "$(cat "$ROOT/sent.txt")"

echo "⑦ 하트비트는 rc 와 무관하게 갱신된다"
: > "$ROOT/logs/hb"; items "x"; rc_is 1; run >/dev/null
[ -s "$ROOT/logs/hb" ] && ok "항목 있을 때도 갱신" || bad "갱신 안 됨"

echo "⑧ 🔑 전송이 실패하면 상태를 갱신하지 않는다 — 조치 기록이 해소 기록을 대신하지 않게"
rm -f "$ROOT/logs/state"; items "E 실패테스트"; rc_is 1
out="$(run 1)"; rc=$?
[ "$rc" -ne 0 ] && ok "전송 실패를 rc 로 드러낸다 (rc=$rc)" || bad "전송이 실패했는데 rc=0" "$out"
[ ! -f "$ROOT/logs/state" ] && ok "상태 미갱신 → 다음 회차에 다시 알린다" \
  || bad "전송 실패인데 상태를 갱신했다 (그 항목은 영구히 조용해진다)" "$(cat "$ROOT/logs/state")"
out="$(run 0)"
grep -q "E 실패테스트" "$ROOT/sent.txt" && ok "다음 회차에 실제로 다시 알렸다" || bad "재알림 안 됨" "$(cat "$ROOT/sent.txt")"

echo "⑨ 🔴 인자 계약 (코어 cli-guard) — 09:50 사고의 형태를 막는다"
# 🔴 이 절 전용 스텁: **호출 1회 = 1줄.** 공용 `fake-send` 는 본문을 그대로 적는데 알림 본문이
#   여러 줄이라, `sent_count`(줄 세기)로 재면 **1건 보낸 것이 4건으로 보인다**(실제로 그랬다).
#   🔑 계약 ③이 요구하는 건 *줄 수*가 아니라 **호출 횟수**다 — 세는 대상이 어긋나면
#     대조군이 먼저 거짓말하고, 그 위의 "0건"들은 전부 증거 자격을 잃는다.
cat > "$ROOT/fake-send-1" <<'FAKE'
#!/usr/bin/env bash
printf 'SEND\t%s\n' "$1" >> "$FAKE_SENT"
FAKE
chmod +x "$ROOT/fake-send-1"
g_sends() { grep -c '^SEND' "$ROOT/sent.txt" 2>/dev/null | head -1; }
# 🔴 옛 형태는 `DRY_RUN="${DRY_RUN:-0}"` 였다 — **환경에서만** 켤 수 있는 dry-run 이고,
#   바로 위에서 `set -a; . .env` 를 하므로 `.env` 한 줄에 이 감시기가 **발송 0건 · rc=0** 으로
#   조용히 멈춘다. 그리고 인자 파싱이 없어 모르는 플래그를 조용히 먹었다.
# 🔑 계약 ③: *"플래그가 있나"* 가 아니라 **"스텁이 몇 번 불렸나"** 로 잠근다.
gr() {  # gr <스크립트 인자…>   (GUARD_ENV 를 세우면 CLI_DRY_RUN 을 환경으로 물려준다)
  : > "$ROOT/sent.txt"; : > "$ROOT/glog"
  g_out="$(FAKE_ITEMS="$ROOT/items.txt" FAKE_RC="$ROOT/rc.txt" FAKE_SENT="$ROOT/sent.txt" \
    env BOT_DIR="$ROOT" LINT="$ROOT/fake-lint.sh" DISCORD_SEND="$ROOT/fake-send-1" \
    STATE="$ROOT/gstate$RANDOM" HEARTBEAT="$ROOT/logs/hb" LOG="$ROOT/glog" \
    ${GUARD_ENV:+CLI_DRY_RUN="$GUARD_ENV"} bash "$SCRIPT" "$@" 2>"$ROOT/gerr")"
  g_rc=$?
}
items "GUARD 계약시험 항목"; rc_is 1

# 🧪 [대조군] **먼저 이것부터.** 아래 "발송 0건" 들이 가드 덕인지, 이 입력이 애초에
#   아무것도 안 보내는 건지 못 가른다 — 대조군이 초록이 아니면 나머지 빨간불은 증거가 아니다.
GUARD_ENV="" gr
[ "$(g_sends)" -eq 1 ] && ok "🧪 [대조군] 인자 없이 부르면 실제로 1건 나간다" \
  || bad "대조군 — 이 입력은 원래 안 보낸다. 아래 0건은 증거가 아니다" "$(g_sends)건"

GUARD_ENV="" gr --report
[ "$g_rc" -eq 2 ] && ok "모르는 인자 --report 를 rc=2 로 거절한다 (1 아님 — 못 쟀다)" || bad "모르는 인자 rc" "want 2 / got $g_rc"
[ "$(g_sends)" -eq 0 ] && ok "  🔑 거절되면 발송 0건 (사고 재현 차단)" || bad "거절인데 발송" "$(g_sends)건"
# 🔑 **거절도 흔적을 남겨야 한다.** cron 은 stderr 를 버린다 — 안 남기면 crontab 오타 하나로
#   이 감시기가 *아무 표시 없이* 멈추고, 그건 감시기가 조용히 죽는 그 형태 그대로다.
grep -q 'verdict=bad_args' "$ROOT/glog" && ok "  🔑 거절이 로그에 남는다 (verdict=bad_args)" \
  || bad "거절 로그" "$(cat "$ROOT/glog" 2>/dev/null || echo '<빈 로그>')"

GUARD_ENV="" gr --dry-run
[ "$(g_sends)" -eq 0 ] && ok "--dry-run 이면 발송 0건" || bad "dry-run 발송" "$(g_sends)건"
printf '%s' "$g_out" | grep -q 'GUARD 계약시험 항목' && ok "  → 보낼 뻔한 본문을 stdout 으로 보여준다" \
  || bad "dry-run 가시성 — 조용하면 고장과 구별이 안 된다" "$g_out"

# 🔴 환경 상속은 **거절**한다. 무시하면 dry-run 을 기대한 쪽이 발송당하고, 따르면 발송을
#   기대한 쪽이 조용해진다 — 어느 쪽으로 접어도 조용히 틀린다(코어 계약 ④).
GUARD_ENV=1 gr
[ "$g_rc" -eq 2 ] && ok "🔴 CLI_DRY_RUN 을 환경에서 물려받으면 rc=2 로 거절한다" || bad "환경 상속" "want rc=2 / got $g_rc"
[ "$(g_sends)" -eq 0 ] && ok "  → 거절이므로 발송 0건" || bad "상속 거절 발송" "$(g_sends)건"
grep -q 'verdict=bad_env' "$ROOT/glog" && ok "  🔑 bad_args 와 갈라 센다 (고칠 곳이 환경이라서)" \
  || bad "bad_env 표지" "$(cat "$ROOT/glog" 2>/dev/null || echo '<빈 로그>')"

GUARD_ENV="" gr --help
[ "$(g_sends)" -eq 0 ] && ok "--help 는 발송 0건" || bad "help 발송" "$(g_sends)건"
printf '%s' "$g_out" | grep -q 'usage:' && ok "  → 사용법을 출력한다" || bad "usage 출력" "$g_out"

# ─────────────────────────────────────────────────────────────────────────────
# 🔴 발송 «대상» — 단일 소유자 보고가 공용 채널로 가면 남에게는 소음이다 (2026-08-02)
#   이 검사는 «내 메모리만» 훑는데(lint-nino-memory.sh: MEMORY_AUTO_DIR) 기본 대상이
#   봇-놀이터(룬드와 공용)였다. 룬드는 같은 경보를 세 번 받고 매번 `wc -l` 로 자기 것을
#   되재서 「내 것 아니네」로 닫았다 — **행동이 안 바뀌는 정보**다(그의 판정 근거).
#
# 🔑 **소스 문자열이 아니라 「발송 대상」을 잰다** (룬드 `#143` 리뷰).
#   처음엔 `grep '^NOTIFY_TARGET=' "$SCRIPT"` 로 «선언문»을 봤는데, 그건 두 가지가 틀렸다:
#     ① 세는 대상이 «대상»이 아니라 «선언문»이다 — 선언을 바꾸지 않고 라우팅만 바꿔도 통과한다
#     ② 대조군이 **손으로 한 번 더 쓴 리터럴**에 걸려서 검사기와 공유 코드가 0줄이었다
#        ⇒ grep 이 통째로 깨져도 대조군은 초록이다. **검사기를 안 태우는 대조군**이다
#   🔸 이 파일 129~132행에 내가 이미 적어둔 문장에 내가 걸렸다 —
#     *「세는 대상이 어긋나면 대조군이 먼저 거짓말하고, 그 위의 0건들은 전부 증거 자격을 잃는다」*
#   ⇒ `fake-send-1` 이 `printf 'SEND\t%s' "$1"` 로 **첫 인자(대상)를 기록**한다. 그걸 읽는다.
echo "🔴 발송 대상 — 단일 소유자 보고는 내 채널로:"

g_target() { grep -m1 '^SEND' "$ROOT/sent.txt" 2>/dev/null | cut -f2; }

items "대상 확인용 항목"; rc_is 1
gr
_t="$(g_target)"
if [ -z "$_t" ]; then
    bad "판정 불가 — 발송이 0건이라 대상을 못 쟀다" "SEND 1건" "<없음>"
else
    case "$_t" in
        현인-업무) ok "발송 대상이 현인-업무 (실제 호출 인자: «${_t}»)" ;;
        봇-놀이터) bad "공용 채널로 보냈다 — 남에게 소음이 간다" "현인-업무" "«${_t}»" ;;
        *)         bad "대상이 예상 밖이다" "현인-업무" "«${_t}»" ;;
    esac
fi

# 🧪 [양성 대조군] **검사기를 실제로 태운다** — 옛 기본값을 «환경으로 주입»해 같은 경로를 돌린다.
#   위 판정과 **같은 코드**(gr → fake-send-1 → g_target)를 지나므로, 그 경로가 깨지면
#   대조군도 같이 죽는다. 리터럴에 case 를 거는 형태로는 이게 안 된다.
items "대조군 항목"; rc_is 1
NOTIFY_TARGET=봇-놀이터 gr
_c="$(g_target)"
case "$_c" in
    봇-놀이터) ok "[대조군] 주입한 옛 기본값이 실제로 대상에 나타난다 — 검사기가 대상을 본다" ;;
    "")        bad "[대조군] 발송 0건 — 경로가 죽어서 위 판정도 못 믿는다" "봇-놀이터" "<없음>" ;;
    *)         bad "[대조군] 주입이 안 먹었다 — 이 시험은 대상을 재는 게 아니다" "봇-놀이터" "«${_c}»" ;;
esac

echo
echo "  통과 $pass · 실패 $fail"
[ "$fail" -eq 0 ]
