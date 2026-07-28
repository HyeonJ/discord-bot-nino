#!/usr/bin/env bash
# ci-verdict.sh 계약 시험 — 러너의 세 상태를 CI 의 두 상태로 옮기는 **정책**을 잠근다
#
# 🔑 이 정책의 위험한 자리는 rc=2 하나다. rc=2 에는 성질이 **다른 두 가지**가 들어온다:
#     ⓐ CI 에서 구조적으로 못 재는 검사가 있다(systemd 유닛 부재 등)  → 경고로 넘겨야 한다
#     ⓑ 시험이 하나도 안 돌았다                                      → 반드시 빨강이어야 한다
#   둘을 같은 칸에 두면 **시험이 전부 사라진 상태가 경고 하나로 지나간다.** 그래서
#   "초록 개수" 로 가르고, 그 경계를 여기서 못박는다.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
V="$REPO/scripts/ci-verdict.sh"

pass=0; fail=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; [ -n "${2:-}" ] && echo "     want: $2"; [ -n "${3:-}" ] && echo "     got:  $3"; fail=$((fail + 1)); }

[ -f "$V" ] || { echo "❌ 없음: $V"; exit 1; }
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

mkout() {  # $1=파일명 $2=통과수 → 러너 출력 모양의 파일
  printf '== 셸 시험 ==\n  ✅ alpha  통과 3\n\n── 결과: 통과 %s · 실패 0 · 판정 불가 1\n   판정 불가: start-md-web\n' "$2" > "$WORK/$1"
  echo "$WORK/$1"
}

echo "① rc=0 → 초록"
out="$(bash "$V" --rc 0 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "exit 0" || bad "rc" "0" "$rc"

echo "② rc=1 → 빨강 (실패는 CI 가 막는다)"
out="$(bash "$V" --rc 1 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && ok "exit 1" || bad "rc" "1" "$rc"
printf '%s\n' "$out" | grep -q "시험 실패" && ok "  → 이유를 말한다" || bad "문구" "시험 실패" "$out"

echo "③ 🔑 rc=2 + 초록 충분 → 초록 + 경고 (헛빨간불 금지)"
f="$(mkout many 17)"
out="$(bash "$V" --rc 2 --out "$f" --min-green 5 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "exit 0" || bad "rc" "0" "$rc"
printf '%s\n' "$out" | grep -q "::warning::" && ok "  → GitHub 경고 주석을 남긴다(보이지 않는 경고는 없는 경고)" || bad "주석" "::warning::" "$out"
printf '%s\n' "$out" | grep -q "판정 불가: start-md-web" && ok "  → 무엇을 못 쟀는지 이름까지 옮긴다" || bad "이름" "start-md-web" "$out"

echo "④ 🔴 rc=2 + 초록 부족 → 빨강 ('아무것도 안 돌았다' 와 구별 불가)"
f="$(mkout few 2)"
out="$(bash "$V" --rc 2 --out "$f" --min-green 5 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && ok "exit 1" || bad "rc" "1" "$rc"
printf '%s\n' "$out" | grep -q "::error::" && ok "  → 에러 주석을 남긴다" || bad "주석" "::error::" "$out"

echo "⑤ 경계값 — 기준과 같으면 초록(≥), 하나 아래면 빨강"
f="$(mkout edge 5)"
bash "$V" --rc 2 --out "$f" --min-green 5 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "초록 5 · 기준 5 → 초록" || bad "rc" "0" "$rc"
f="$(mkout edge2 4)"
bash "$V" --rc 2 --out "$f" --min-green 5 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && ok "초록 4 · 기준 5 → 빨강" || bad "rc" "1" "$rc"

echo "⑥ 🔑 초록 개수를 **못 읽으면 빨강** — 못 읽었다를 초록으로 만들지 않는다"
printf '아무 요약 줄도 없는 출력\n' > "$WORK/noline"
out="$(bash "$V" --rc 2 --out "$WORK/noline" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && ok "요약 줄 없음 → exit 1" || bad "rc" "1" "$rc"
printf '%s\n' "$out" | grep -q "못 읽었다" && ok "  → 못 읽었다고 말한다" || bad "문구" "못 읽었다" "$out"
out="$(bash "$V" --rc 2 --out "$WORK/no-such-file-$$" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && ok "출력 파일 부재 → exit 1" || bad "rc" "1" "$rc"
out="$(bash "$V" --rc 2 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && ok "--out 자체가 없으면 exit 1 (셀 수 없으면 가를 수 없다)" || bad "rc" "1" "$rc"

echo "⑦ 러너가 정의하지 않은 종료코드 → 빨강 (판정이 아니라 사고다)"
for r in 3 4 127; do
  out="$(bash "$V" --rc "$r" 2>&1)"; rc=$?
  [ "$rc" -eq 1 ] && ok "rc=$r → exit 1" || bad "rc=$r" "1" "$rc"
  # 🔑 종료코드만 보면 **아래 rc=2 갈래로 흘러도 우연히 1** 이 된다(--out 이 없어 die 하므로).
  #    변이(모르는 rc 검사 제거)가 살아남아서 알려준 자리다 — 이유까지 봐야 그 줄이 잠긴다.
  printf '%s\n' "$out" | grep -q "정의하지 않은 종료코드" \
    && ok "  → rc=$r 을 '판정이 아니라 사고' 로 말한다" || bad "rc=$r 이유" "정의하지 않은 종료코드" "$out"
done
# 그리고 초록이 충분한 출력이 함께 있으면 그 차이가 드러난다: rc=2 갈래로 흘렀다면 초록이 됐을 것
f="$(mkout unknown-rc 17)"
out="$(bash "$V" --rc 3 --out "$f" --min-green 10 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && ok "rc=3 + 초록 17개여도 빨강 (rc=2 갈래로 흐르지 않는다)" || bad "rc" "1" "$rc"

echo "⑧ 인자 사고도 빨강 — 조용히 통과시키지 않는다"
bash "$V" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && ok "--rc 없음 → exit 1" || bad "rc" "1" "$rc"
bash "$V" --rc abc >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && ok "--rc 가 숫자가 아니면 exit 1" || bad "rc" "1" "$rc"
bash "$V" --rc 0 --nope >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && ok "모르는 인자 → exit 1 (rc=0 이어도 인자 사고가 먼저)" || bad "rc" "1" "$rc"

echo "⑨ 마지막 요약 줄을 읽는다 — 러너가 여러 블록을 찍어도"
printf '── 결과: 통과 1 · 실패 0 · 판정 불가 0\n중간 잡음\n── 결과: 통과 12 · 실패 0 · 판정 불가 1\n' > "$WORK/multi"
bash "$V" --rc 2 --out "$WORK/multi" --min-green 10 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "마지막 줄(통과 12)을 기준으로 판정한다" || bad "rc" "0" "$rc"

echo
echo "  통과 $pass · 실패 $fail"
[ "$fail" -eq 0 ] || exit 1
