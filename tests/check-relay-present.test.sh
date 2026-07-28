#!/usr/bin/env bash
# check-relay-present.sh 계약 시험 + setup.sh 의 거짓 초록 회귀 방지
#
# 🔴 이 시험이 생긴 사고 (2026-07-28):
#   setup.sh Phase 9 의 필수 파일 목록에 `src/discord-relay.js` 가 있었다. bot-core 전환 뒤
#   relay 는 코어 사본에서 도는데, 낡은 파일이 남아 있어서 점검은 **초록**이었다.
#   실측: 파일 존재(14.7KB) · 실제 ExecStart=~/yaksu-bot-core-live/relay/index.js
#   ⇒ *점검이 통과하는 것과 대상이 살아 있는 것이 갈려 있었다.* 그래서 검사를 스크립트로
#     떼어내 **주입 가능한 값으로** 재고(여기), setup.sh 는 그걸 호출만 한다(소스 하나).
#
# ⚠️ setup.sh 자체는 실행하지 않는다 — Phase 8 이 **crontab 을 수정**한다. 시험이 부작용을
#    내면 안 되므로, setup.sh 에 대해서는 *정적 계약*(목록·호출 여부)만 본다.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECK="$REPO/scripts/check-relay-present.sh"
SETUP="$REPO/scripts/setup.sh"

pass=0; fail=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; [ -n "${2:-}" ] && echo "     want: $2"; [ -n "${3:-}" ] && echo "     got:  $3"; fail=$((fail + 1)); }

[ -f "$CHECK" ] || { echo "❌ 없음: $CHECK"; exit 1; }
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

# ── 가짜 systemctl: 유닛 텍스트와 종료코드를 주입으로 제어한다(실제 systemd 는 안 건드린다) ──
mkdir -p "$WORK/bin"
cat > "$WORK/bin/systemctl" <<'STUB'
#!/bin/bash
printf '%s' "${FAKE_UNIT_TEXT:-}"
exit "${FAKE_UNIT_RC:-0}"
STUB
chmod +x "$WORK/bin/systemctl"

core_with_relay() {   # $1=디렉터리명 → relay 실체가 있는 가짜 코어 사본
  mkdir -p "$WORK/$1/relay"; : > "$WORK/$1/relay/index.js"; echo "$WORK/$1"
}
run() {  # 주입값은 호출부에서 env 로 준다
  CORE_REPO="$1" SYSTEMCTL="${2:-$WORK/bin/systemctl}" \
  FAKE_UNIT_TEXT="${3:-}" FAKE_UNIT_RC="${4:-0}" \
  bash "$CHECK" 2>&1
}

CORE_OK="$(core_with_relay core-ok)"
BUN="$WORK/bin/fake-bun"; : > "$BUN"; chmod +x "$BUN"
UNIT_OK="[Service]
ExecStart=$BUN $CORE_OK/relay/index.js
Restart=always"

echo "① 정상 — relay 실체 + 유닛 대상 전부 존재 → rc=0"
out="$(run "$CORE_OK" "" "$UNIT_OK" 0)"; rc=$?
[ "$rc" -eq 0 ] && ok "rc=0" || bad "rc" "0" "$rc"
printf '%s\n' "$out" | grep -q "✓ relay 실체" && ok "  → relay 실체를 확인했다고 말한다" \
  || bad "relay 실체 문구" "✓ relay 실체" "$out"
# 🔑 인터프리터 경로까지 봤는지 — 스크립트만 보면 nvm 회귀를 놓친다
[ "$(printf '%s\n' "$out" | grep -c '✓ 유닛 대상 존재')" -eq 2 ] \
  && ok "  → 유닛의 절대경로 2개(인터프리터+스크립트)를 다 확인한다" \
  || bad "유닛 대상 개수" "2" "$(printf '%s\n' "$out" | grep -c '✓ 유닛 대상 존재')"

echo "② relay 실체가 없으면 rc=1 (거짓 초록 금지)"
out="$(run "$WORK/no-core" "" "$UNIT_OK" 0)"; rc=$?
[ "$rc" -eq 1 ] && ok "rc=1" || bad "rc" "1" "$rc"
printf '%s\n' "$out" | grep -q "✗ relay 실체 없음" && ok "  → 무엇이 없는지 경로로 말한다" \
  || bad "부재 문구" "✗ relay 실체 없음" "$out"

echo "③ 🔑 유닛이 **없는 인터프리터**를 가리키면 rc=1 (nvm 버전 올라간 상황)"
# relay 파일은 멀쩡하다 — 파일 존재만 보는 점검으로는 절대 안 잡히는 갈래다
UNIT_STALE="[Service]
ExecStart=$WORK/bin/nvm-v99-bun $CORE_OK/relay/index.js"
out="$(run "$CORE_OK" "" "$UNIT_STALE" 0)"; rc=$?
[ "$rc" -eq 1 ] && ok "rc=1" || bad "rc" "1" "$rc"
printf '%s\n' "$out" | grep -q "✗ 유닛이 없는 경로를 가리킨다" && ok "  → relay 파일이 있어도 못 뜬다고 말한다" \
  || bad "경로 부재 문구" "✗ 유닛이 없는 경로" "$out"

echo "④ 유닛 미설치는 실패가 아니지만 **조용히 넘기지 않는다** → rc=0 + 안내"
out="$(run "$CORE_OK" "" "" 1)"; rc=$?
[ "$rc" -eq 0 ] && ok "rc=0 (부트스트랩 전이면 정상)" || bad "rc" "0" "$rc"
printf '%s\n' "$out" | grep -q "ℹ️  유닛 미설치" && ok "  → 유닛 대상을 못 쟀다고 말한다(부재는 조용하다)" \
  || bad "미설치 안내" "ℹ️  유닛 미설치" "$out"
out="$(run "$WORK/no-core" "" "" 1)"; rc=$?
[ "$rc" -eq 1 ] && ok "  → 유닛 미설치 + relay 부재면 rc=1 (부재가 부재를 덮지 않는다)" || bad "rc" "1" "$rc"

echo "⑤ systemctl 이 없으면 rc=2 — **판정 불가를 0/1 로 접지 않는다**"
out="$(run "$CORE_OK" "no-such-systemctl-$$" "" 0)"; rc=$?
[ "$rc" -eq 2 ] && ok "rc=2" || bad "rc" "2" "$rc"
printf '%s\n' "$out" | grep -q "판정 불가" && ok "  → 판정 불가라고 말한다" || bad "문구" "판정 불가" "$out"

echo "⑥ ExecStart 가 없거나 절대경로가 없으면 rc=2"
out="$(run "$CORE_OK" "" "[Service]
Restart=always" 0)"; rc=$?
[ "$rc" -eq 2 ] && ok "ExecStart 부재 → rc=2" || bad "rc" "2" "$rc"
out="$(run "$CORE_OK" "" "[Service]
ExecStart=bun relay/index.js" 0)"; rc=$?
[ "$rc" -eq 2 ] && ok "상대경로만 있으면 → rc=2 (있다고도 없다고도 말할 수 없다)" || bad "rc" "2" "$rc"

echo "⑦ 🔴 setup.sh 회귀 — 죽은 relay 경로를 필수 파일로 점검하지 않는다"
if [ -f "$SETUP" ]; then
  # ⚠️ 파일 전체를 grep 하면 **왜 지웠는지 적은 주석**이 걸린다(오늘 다섯 번째: 대상을 패턴으로
  #    지목하는 도구는 자기가 만든 텍스트도 대상으로 본다). 면제하지 않고 **대상을 좁힌다** —
  #    거짓 초록의 위험은 *목록*과 *코드*에 있고, 주석에는 없다.
  if sed -n 's/^REQUIRED_FILES=(\(.*\))$/\1/p' "$SETUP" | grep -q 'src/discord-relay.js'; then
    bad "REQUIRED_FILES 가 아직 src/discord-relay.js 를 점검한다(거짓 초록)" "없어야 한다" \
        "$(sed -n '/^REQUIRED_FILES=(/p' "$SETUP")"
  else
    ok "REQUIRED_FILES 에 src/discord-relay.js 가 없다"
  fi
  if grep -v '^[[:space:]]*#' "$SETUP" | grep -q 'src/discord-relay.js'; then
    bad "주석이 아닌 코드가 아직 그 경로를 참조한다" "없어야 한다" \
        "$(grep -n 'src/discord-relay.js' "$SETUP" | grep -v ':[[:space:]]*#')"
  else
    ok "  → 코드 줄에도 그 경로 참조가 없다(주석의 설명은 남겨둔다)"
  fi
  grep -q 'check-relay-present.sh' "$SETUP" \
    && ok "  → 대신 이 검사기를 호출한다(소스 하나)" \
    || bad "setup.sh 가 검사기를 호출하지 않는다" "check-relay-present.sh 호출" "없음"
  # 목록에 남은 경로들은 **실물과 일치**해야 한다 — 존재하지 않는 것을 점검하면 또 거짓 신호가 된다
  list="$(sed -n 's/^REQUIRED_FILES=(\(.*\))$/\1/p' "$SETUP" | tr -d '"')"
  missing=""
  for f in $list; do
    [ "$f" = ".env" ] && continue   # .env 는 레포에 없는 것이 정상(gitignore)
    [ -e "$REPO/$f" ] || missing="$missing $f"
  done
  [ -z "$missing" ] && ok "  → REQUIRED_FILES 의 경로가 전부 레포에 실재한다" \
    || bad "REQUIRED_FILES 에 없는 경로가 있다" "전부 존재" "$missing"
else
  bad "setup.sh 를 못 찾았다" "$SETUP" "없음"
fi

echo
echo "  통과 $pass · 실패 $fail"
[ "$fail" -eq 0 ] || exit 1
