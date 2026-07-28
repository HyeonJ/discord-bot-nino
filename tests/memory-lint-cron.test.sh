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
BOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$BOT/scripts/memory-lint-cron.sh"

pass=0; fail=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; fail=$((fail + 1)); [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/     /'; }

[ -f "$SCRIPT" ] || { echo "❌ 없음: $SCRIPT"; exit 1; }
ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT
mkdir -p "$ROOT/logs"

# 가짜 lint — ITEMS 파일의 각 줄을 "  ⚠️  <줄>" 로 내고, RC 파일의 코드로 죽는다
cat > "$ROOT/fake-lint.sh" <<'FAKE'
#!/usr/bin/env bash
echo "== 1. 어떤 섹션 =="
while IFS= read -r l; do [ -n "$l" ] && echo "  ⚠️  $l"; done < "$FAKE_ITEMS"
echo "== 결과: $(grep -c . "$FAKE_ITEMS" 2>/dev/null || echo 0)건 =="
exit "$(cat "$FAKE_RC")"
FAKE
chmod +x "$ROOT/fake-lint.sh"

# 가짜 discord-send — 보낸 본문을 파일에 적는다. FAKE_SEND_RC 로 실패도 재현한다
cat > "$ROOT/fake-send" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$2" >> "$FAKE_SENT"
exit "${FAKE_SEND_RC:-0}"
FAKE
chmod +x "$ROOT/fake-send"

items() { printf '%s\n' "$@" > "$ROOT/items.txt"; }
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

echo
echo "  통과 $pass · 실패 $fail"
[ "$fail" -eq 0 ]
