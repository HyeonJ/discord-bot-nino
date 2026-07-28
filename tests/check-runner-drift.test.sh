#!/usr/bin/env bash
# check-runner-drift.sh 계약 시험 — "두 소스" 를 조용히 두지 않는지 잰다
#
# 🔑 이 검사에서 틀리기 쉬운 두 자리:
#   ① 정본이 안 보일 때 **통과로 접으면** 사본이 영원히 안 잡힌다 → rc=2 여야 한다
#   ② 헤더 주석 차이로 **상시 빨간불**이 되면 그 빨간불을 아무도 안 본다 → 코드 줄만 본다
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECK="$REPO/scripts/check-runner-drift.sh"

pass=0; fail=0; unk=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; [ -n "${2:-}" ] && echo "     want: $2"; [ -n "${3:-}" ] && echo "     got:  $3"; fail=$((fail + 1)); }
unmeasured() { echo "  ⛔ 판정 불가 — $1"; unk=$((unk + 1)); }

[ -f "$CHECK" ] || { echo "❌ 없음: $CHECK"; exit 1; }
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

mkcore() {  # $1=이름 $2=본문 → 가짜 코어 체크아웃 경로
  local d="$WORK/$1"; mkdir -p "$d/scripts"; printf '%s' "$2" > "$d/scripts/run-tests.sh"; echo "$d"
}
mklocal() { # $1=이름 $2=본문 → 사본 경로
  local f="$WORK/$1.sh"; printf '%s' "$2" > "$f"; echo "$f"
}
run() {  # $1=코어경로 $2=사본경로
  CORE_REPO="$1" LOCAL_RUNNER="$2" bash "$CHECK" 2>&1
}

BODY='#!/usr/bin/env bash
# 정본 헤더
set -uo pipefail
echo "run"
exit 0
'
COPY_SAME_CODE='#!/usr/bin/env bash
# 사본 헤더 — 정본은 코어다(주석만 다르다)
# 한 줄 더 적어도 코드가 같으면 같다고 봐야 한다

set -uo pipefail
echo "run"
exit 0
'
COPY_DIFF='#!/usr/bin/env bash
# 사본 헤더
set -uo pipefail
echo "run"
exit 1
'

echo "① 코드 줄이 같으면 rc=0 — 헤더 주석 차이로 빨간불을 만들지 않는다"
C="$(mkcore core-a "$BODY")"; L="$(mklocal same "$COPY_SAME_CODE")"
out="$(run "$C" "$L")"; rc=$?
[ "$rc" -eq 0 ] && ok "rc=0" || bad "rc" "0" "$rc"
printf '%s\n' "$out" | grep -q "정본과 같다" && ok "  → 같다고 말하고 정본 경로를 찍는다" || bad "문구" "정본과 같다" "$out"

echo "② 코드 줄이 다르면 rc=1 + 어디가 다른지"
L2="$(mklocal diff "$COPY_DIFF")"
out="$(run "$C" "$L2")"; rc=$?
[ "$rc" -eq 1 ] && ok "rc=1" || bad "rc" "1" "$rc"
printf '%s\n' "$out" | grep -q "갈라졌다" && ok "  → 갈라졌다고 말한다" || bad "문구" "갈라졌다" "$out"
printf '%s\n' "$out" | grep -q "exit 1" && ok "  → diff 를 보여준다(무엇이 다른지 없이 빨간불만 주지 않는다)" || bad "diff" "exit 1" "$out"
printf '%s\n' "$out" | grep -q "해소: cp" && ok "  → 해소 방법을 말한다" || bad "해소" "cp" "$out"

echo "③ 🔑 정본이 안 보이면 rc=2 — 통과로 접으면 사본이 영원히 안 잡힌다"
out="$(run "$WORK/no-core" "$L")"; rc=$?
[ "$rc" -eq 2 ] && ok "rc=2" || bad "rc" "2" "$rc"
printf '%s\n' "$out" | grep -q "정본을 못 봤다" && ok "  → 무엇을 못 봤는지 경로로 말한다" || bad "문구" "정본을 못 봤다" "$out"
printf '%s\n' "$out" | grep -q "CI 에서는 구조적으로 못 잰다" && ok "  → 왜 여기서 재야 하는지 알려준다" || bad "안내" "구조적으로" "$out"

echo "④ 사본 자체가 없으면 rc=2"
out="$(run "$C" "$WORK/nope-$$.sh")"; rc=$?
[ "$rc" -eq 2 ] && ok "rc=2" || bad "rc" "2" "$rc"

echo "⑤ 실물 — 이 레포의 사본이 코어 정본과 같은가"
out="$(bash "$CHECK" 2>&1)"; rc=$?
case "$rc" in
  0) ok "rc=0 — 사본이 정본과 같다" ;;
  1) bad "사본이 갈라졌다(코어에서 다시 복사할 것)" "0" "$out" ;;
  2) unmeasured "코어 체크아웃이 없어 못 쟀다 — CI 라면 정상: $(printf '%s' "$out" | head -1)" ;;
  *) bad "모르는 rc" "0/1/2" "$rc" ;;
esac

echo
echo "  통과 $pass · 실패 $fail · 판정 불가 $unk"
[ "$fail" -eq 0 ] || exit 1
[ "$unk" -eq 0 ] || exit 2
