#!/usr/bin/env bash
# mutate.sh 계약 테스트 — **가드가 실제로 막는가**가 본체다
#
# 왜 이 도구가 생겼나 (2026-07-28, 하루에 세 번):
#   변이시험은 "고친 줄을 되돌려 빨간불이 뜨는지" 보는 절차인데, 되돌리기를 `git checkout`
#   으로 한다. 그래서 **기준선이 커밋돼 있지 않으면 수정 자체가 같이 사라진다.**
#   니노가 오늘 세 번, 룬드가 한 번 밟았다. 메모를 적고 서로 알려준 뒤에도 다시 밟았다.
#   ⇒ 규칙을 아는 것과 손이 그렇게 움직이는 것은 다른 일이다. **판단이 필요 없는 형태**로
#      바꾼다 — 도구가 먼저 거부한다.
#
# ⚠️ 그런데 가드를 넣는 것만으로는 부족하다. 오늘 하루 종일 본 게 *안전장치가 안 도는 것*
#    이었다(24시간 떠 있던 데몬이 발동 0건 · 몇 달째 죽어 있던 훅 · 아무도 안 읽던 하트비트).
#    그래서 이 테스트의 본체는 **가드가 실제로 막는지**, 그리고 **막을 때 테스트 명령이
#    아예 실행되지 않는지**다. "거부했다고 말하면서 이미 돌아버린" 경우를 구분한다.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$BOT_DIR/scripts/mutate.sh"

pass=0; fail=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; fail=$((fail + 1)); [[ -n "${2:-}" ]] && printf '%s\n' "$2" | sed 's/^/     /'; }

[[ -f "$SCRIPT" ]] || { echo "❌ 없음: $SCRIPT"; exit 1; }
ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT

# ── 가짜 레포: 대상 파일 하나 + "테스트 명령"은 그 파일 내용을 보고 성패를 정한다 ──
REPO="$ROOT/repo"; mkdir -p "$REPO"
git init -q "$REPO"
printf 'VALUE=정답\n' > "$REPO/target.sh"
git -C "$REPO" -c user.email=t@e -c user.name=t add -A
git -C "$REPO" -c user.email=t@e -c user.name=t commit -qm init

# 테스트 명령: 파일에 '정답' 이 있으면 통과(0), 없으면 실패(1).
# 그리고 **자기가 실행됐다는 흔적**을 남긴다 — 가드가 막았는지 값으로 가르려고.
RAN="$ROOT/ran"
TESTCMD="touch '$RAN'; grep -q 정답 '$REPO/target.sh'"

run() { ( cd "$REPO" && bash "$SCRIPT" "$@" 2>&1 ); }

echo "① 잡히는 변이 — 되돌리면 테스트가 빨개진다"
rm -f "$RAN"
out="$(run --file target.sh --test "$TESTCMD" --name R1 --old '정답' --new '오답')"; rc=$?
[[ "$rc" -eq 0 ]] && ok "종료코드 0 (= 잡힘)" || bad "rc=$rc — 잡혔으면 0" "$out"
grep -q '잡힘' <<<"$out" && ok "'잡힘'을 명시" || bad "판정 문구 없음" "$out"
[[ -f "$RAN" ]] && ok "테스트 명령이 실제로 돌았다" || bad "안 돌았다"

echo "② 살아남는 변이 — 되돌려도 초록이면 시끄럽게 알린다"
rm -f "$RAN"
out="$(run --file target.sh --test "$TESTCMD" --name R2 --old 'VALUE' --new 'VALUE2')"; rc=$?
[[ "$rc" -eq 1 ]] && ok "종료코드 1 (= 살아남음)" || bad "rc=$rc — 살아남았으면 1" "$out"
grep -q '살아남' <<<"$out" && ok "'살아남음'을 명시" || bad "판정 문구 없음" "$out"

echo "③ 실행 후 파일이 원상복구된다"
grep -q '정답' "$REPO/target.sh" && ok "내용 복구됨" || bad "복구 안 됨" "$(cat "$REPO/target.sh")"
[[ -z "$(git -C "$REPO" status --porcelain)" ]] && ok "작업트리 깨끗" || bad "잔재 있음" "$(git -C "$REPO" status --porcelain)"

echo "④ 🔑 미커밋 변경이 있으면 **거부하고, 테스트를 실행하지 않는다** (이 도구의 존재 이유)"
printf 'VALUE=정답\n# 아직 커밋 안 한 소중한 수정\n' > "$REPO/target.sh"
rm -f "$RAN"
out="$(run --file target.sh --test "$TESTCMD" --name R3 --old '정답' --new '오답')"; rc=$?
[[ "$rc" -gt 1 ]] && ok "거부 종료코드($rc) — 잡힘(0)·살아남음(1)과 구분된다" || bad "rc=$rc — 판정과 구분돼야" "$out"
grep -q '미커밋' <<<"$out" && ok "이유를 말한다" || bad "이유 없음" "$out"
[[ ! -f "$RAN" ]] && ok "테스트 명령이 **안** 돌았다" || bad "이미 돌아버렸다 — 거부가 늦다"
grep -q '소중한 수정' "$REPO/target.sh" && ok "🔑 미커밋 수정이 그대로 남아 있다" \
  || bad "도구가 수정을 날렸다 — 막으려던 사고를 도구가 냈다" "$(cat "$REPO/target.sh")"
git -C "$REPO" checkout -q -- target.sh

echo "⑤ --old 가 없으면 거부 (주입 MISS 를 조용히 넘기지 않는다)"
rm -f "$RAN"
out="$(run --file target.sh --test "$TESTCMD" --name R4 --old '존재하지않는문자열' --new 'x')"; rc=$?
[[ "$rc" -gt 1 ]] && ok "거부 종료코드($rc)" || bad "rc=$rc" "$out"
grep -qE 'MISS|못 찾' <<<"$out" && ok "주입 실패를 명시" || bad "이유 없음" "$out"
[[ ! -f "$RAN" ]] && ok "테스트 명령이 안 돌았다" || bad "돌았다 — 원본 결과를 변이 결과로 읽게 된다"

echo "⑥ --old 가 여러 번 나오면 거부 (어디를 바꿨는지 모르는 변이는 근거가 안 된다)"
printf 'A=정답\nB=정답\n' > "$REPO/target.sh"
git -C "$REPO" -c user.email=t@e -c user.name=t commit -qam dup
rm -f "$RAN"
out="$(run --file target.sh --test "$TESTCMD" --name R5 --old '정답' --new '오답')"; rc=$?
[[ "$rc" -gt 1 ]] && ok "거부 종료코드($rc)" || bad "rc=$rc" "$out"
grep -qE '2건|여러' <<<"$out" && ok "몇 건인지 말한다" || bad "건수 없음" "$out"
[[ ! -f "$RAN" ]] && ok "테스트 명령이 안 돌았다" || bad "돌았다"

echo "⑦ 추적되지 않는 파일이면 거부 (git checkout 으로 되돌릴 수 없다)"
printf 'x=1\n' > "$REPO/untracked.sh"
rm -f "$RAN"
out="$(run --file untracked.sh --test "$TESTCMD" --name R6 --old 'x=1' --new 'x=2')"; rc=$?
[[ "$rc" -gt 1 ]] && ok "거부 종료코드($rc)" || bad "rc=$rc" "$out"
grep -qE '추적|tracked' <<<"$out" && ok "이유를 말한다" || bad "이유 없음" "$out"
grep -q 'x=1' "$REPO/untracked.sh" && ok "파일을 안 건드렸다" || bad "건드렸다"
rm -f "$REPO/untracked.sh"

echo "⑧ --old 와 --new 가 같으면 거부 (아무것도 안 바뀐 실행을 '변이시험'으로 세지 않는다)"
# 변이 M8(`git diff --quiet` 검사 제거)이 살아남아서 찾은 구멍이다.
# 등가변이가 아니라 **안 밟히는 갈래**였다 — 코드는 닿을 수 있는데 시험에 그 입력이 없었다.
# 이 갈래가 뚫리면 "치환이 조용히 실패했는데 원본 결과를 변이 결과로 읽는" 최악이 통과한다.
printf 'VALUE=정답\n' > "$REPO/target.sh"
git -C "$REPO" -c user.email=t@e -c user.name=t commit -qam reset8
rm -f "$RAN"
out="$(run --file target.sh --test "$TESTCMD" --name R7 --old '정답' --new '정답')"; rc=$?
[[ "$rc" -gt 1 ]] && ok "거부 종료코드($rc)" || bad "rc=$rc" "$out"
grep -qE '안 바뀌|같은가' <<<"$out" && ok "이유를 말한다" || bad "이유 없음" "$out"
[[ ! -f "$RAN" ]] && ok "테스트 명령이 안 돌았다 — 원본을 변이로 착각할 여지를 없앤다" || bad "돌았다"
[[ -z "$(git -C "$REPO" status --porcelain)" ]] && ok "작업트리 깨끗" || bad "잔재 있음"

echo "⑨ 복구가 실패하면 판정과 **다른 층**의 종료코드(4)를 낸다 (룬드 지적, PR #37 리뷰)"
# 0/1 은 "시험이 잡았나"의 답, 3 은 "못 쟀다". 복구 실패는 **레포가 변이된 채 남았다** —
# 다음 사람이 당장 손대야 하는 유일한 경우라 3 에 묶으면 안 된다.
# 재현: 시험 명령이 대상 파일을 읽기전용으로 만들어 복구(cp)를 실패시킨다.
printf 'VALUE=정답\n' > "$REPO/target.sh"
git -C "$REPO" -c user.email=t@e -c user.name=t commit -qam reset9 >/dev/null 2>&1 || true
out="$(run --file target.sh --test "chmod 444 '$REPO/target.sh'; true" --name R8 --old '정답' --new '오답')"; rc=$?
chmod 644 "$REPO/target.sh"
[[ "$rc" -eq 4 ]] && ok "종료코드 4 (복구 실패) — 0·1·3 과 갈린다" || bad "rc=$rc — 4여야" "$out"
grep -q '복구 실패' <<<"$out" && ok "복구 실패를 명시" || bad "문구 없음" "$out"
grep -q '판정보다 이게 먼저' <<<"$out" && ok "무엇이 우선인지 말한다" || bad "우선순위 안내 없음" "$out"
grep -q 'git checkout' <<<"$out" && ok "복구 방법을 준다" || bad "복구 방법 없음" "$out"
git -C "$REPO" checkout -q -- target.sh

echo
echo "  통과 $pass · 실패 $fail"
[[ "$fail" -eq 0 ]]
