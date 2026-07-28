#!/usr/bin/env bash
# lint-js.sh 계약 시험 + eslint 설정이 **실제로 무엇을 보는지** 재는 시험
#
# 🔴 이 시험이 생긴 이유 (2026-07-28):
#   eslint 를 처음 돌렸을 때 **296건**이 나왔다. 그중 291건은 위반이 아니라 `tests/**` 의
#   jest 전역을 선언하지 않은 **설정 구멍**이었다. 즉 그 숫자는 코드가 아니라 내 설정을
#   재고 있었다. 그래서 이 시험은 "0건이다" 를 보는 데서 멈추지 않고 **왜 0건인지**를 잰다:
#     · 계측기가 진짜 잡는가 (0건이 "아무것도 안 봤다" 일 수 있다 — 계측기를 먼저 먹인다)
#     · jest 전역이 살아 있는가 (빠지면 291건이 돌아온다)
#     · 전역을 너무 넓게 열지 않았는가 (`document` 오타를 노드 파일에서 놓치면 안 된다)
#
# ⚠️ 검사기를 **레포 밖 임시 트리**에 복사해서 먹인다. 레포 안에 위반 파일을 만들면
#    (ⓐ 다른 시험·CI 가 그걸 보고 빨간불이 되고 (ⓑ `git add -A` 에 딸려 들어간다.
#    코어 #84 에서 그 방식으로 node_modules 심링크를 커밋했다 — 같은 실수를 반복하지 않는다.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
LINT="$REPO/scripts/lint-js.sh"
CONFIG="$REPO/eslint.config.js"
ESLINT_BIN="$REPO/node_modules/.bin/eslint"

pass=0; fail=0; unk=0
ok()   { echo "  ✅ $1"; pass=$((pass + 1)); }
bad()  { echo "  ❌ $1"; [ -n "${2:-}" ] && echo "     want: $2"; [ -n "${3:-}" ] && echo "     got:  $3"; fail=$((fail + 1)); }
unmeasured() { echo "  ⛔ 판정 불가 — $1"; unk=$((unk + 1)); }

[ -f "$LINT" ]   || { echo "❌ 없음: $LINT"; exit 1; }
[ -f "$CONFIG" ] || { echo "❌ 없음: $CONFIG"; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

# ── 임시 트리 하나 만들기: 설정만 복사하고 node_modules 는 레포 것을 빌린다 ──
# 심링크는 git 밖 임시 디렉터리에만 만든다(레포 안에는 만들지 않는다)
make_probe() {  # $1=이름 → 트리 경로를 표준출력으로
  local d="$WORK/$1"
  mkdir -p "$d"
  cp "$CONFIG" "$d/eslint.config.js"
  ln -s "$REPO/node_modules" "$d/node_modules"
  git -C "$d" init -q 2>/dev/null
  echo "$d"
}
run_lint() {  # $1=트리 → lint-js.sh 를 그 트리에 대해 돌린다
  LINT_ROOT="$1" ESLINT_BIN="$ESLINT_BIN" bash "$LINT" 2>&1
}

if [ ! -x "$ESLINT_BIN" ]; then
  unmeasured "eslint 가 설치돼 있지 않다($ESLINT_BIN) — 계약을 하나도 못 쟀다. 'npm ci' 후 다시"
  echo; echo "  통과 $pass · 실패 $fail · 판정 불가 $unk"
  exit 2
fi

echo "① 🔑 계측기를 먼저 먹인다 — 위반을 넣으면 정말 잡는가 (0건이 '안 봤다' 일 수 있다)"
A="$(make_probe probe-a)"
mkdir -p "$A/media"
printf 'const neverUsed = 1;\nmodule.exports = {};\n' > "$A/media/tracked-bad.js"
printf 'const alsoUnused = 2;\nmodule.exports = {};\n' > "$A/media/untracked-bad.js"
git -C "$A" add media/tracked-bad.js eslint.config.js 2>/dev/null
out="$(run_lint "$A")"; rc=$?
[ "$rc" -eq 1 ] && ok "추적 파일에 위반이 있으면 rc=1" || bad "rc" "1" "$rc"
printf '%s\n' "$out" | grep -q "❌ 추적 파일 위반 1건" \
  && ok "  → 추적 위반을 1건으로 센다(no-unused-vars 를 실제로 잡는다)" \
  || bad "추적 위반 개수" "1건" "$out"

echo "② 🔑 미추적 위반은 **말은 하고 실패로는 만들지 않는다** (헛빨간불 금지)"
# 실측 근거: 라이브 트리 위반 8건 = 추적 4 + 미추적 4(of/*.js·media/ytm-play.js).
# 미추적으로 빨간불을 만들면 '빨간불이 정상' 이 되고 진짜 회귀가 그 안에 묻힌다.
printf '%s\n' "$out" | grep -q "ℹ️  미추적 파일 위반 1건" \
  && ok "미추적 1건을 ℹ️ 로 보고한다" || bad "미추적 보고" "ℹ️  미추적 파일 위반 1건" "$out"
printf '%s\n' "$out" | grep -q "media/untracked-bad.js" \
  && ok "  → 어느 파일인지 경로로 말한다(조용히 삼키지 않는다)" || bad "미추적 경로" "media/untracked-bad.js" "$out"
B="$(make_probe probe-b1)"   # 미추적 위반만 있으면 rc=0 이어야 한다
mkdir -p "$B/media"; printf 'const u = 1;\n' > "$B/media/only-untracked.js"
git -C "$B" add eslint.config.js 2>/dev/null
out2="$(run_lint "$B")"; rc2=$?
[ "$rc2" -eq 0 ] && ok "  → 미추적 위반만 있으면 rc=0 (레포가 고칠 대상이 아니다)" || bad "rc" "0" "$rc2"

echo "③ 🔴 jest 전역 회귀 — 이게 빠지면 291건이 돌아온다"
C="$(make_probe probe-c)"
mkdir -p "$C/tests"
cat > "$C/tests/jest-globals.test.js" <<'JS'
describe('probe', () => {
  beforeEach(() => {});
  test('전역', () => { expect(jest.fn()).toBeDefined(); });
});
JS
git -C "$C" add -A 2>/dev/null
out3="$(run_lint "$C")"; rc3=$?
[ "$rc3" -eq 0 ] && ok "describe·test·expect·jest·beforeEach 가 전부 선언돼 있다 → rc=0" || bad "rc" "0" "$rc3"
printf '%s\n' "$out3" | grep -q "no-undef" \
  && bad "jest 전역이 no-undef 로 잡힌다(설정 구멍 재발)" "no-undef 없음" "$out3" \
  || ok "  → no-undef 가 한 건도 없다"

echo '④ 🔑 그렇다고 전역을 넓게 열지는 않았다 — 노드 파일의 document 는 여전히 잡힌다'
D="$(make_probe probe-d)"
mkdir -p "$D/media"
printf 'document.querySelector("a");\n' > "$D/media/dom-typo.js"
git -C "$D" add -A 2>/dev/null
out4="$(run_lint "$D")"; rc4=$?
[ "$rc4" -eq 1 ] && ok "media/*.js 에서 document 를 쓰면 rc=1" || bad "rc" "1" "$rc4"
printf '%s\n' "$out4" | grep -q "no-undef" \
  && ok "  → no-undef 로 잡는다(브라우저 전역을 전 파일에 열지 않았다)" || bad "규칙" "no-undef" "$out4"
# 같은 파일이 tests/ 에 있어도 jest 전역만 열려 있으므로 document 는 여전히 잡혀야 한다
mkdir -p "$D/tests"; mv "$D/media/dom-typo.js" "$D/tests/dom-typo.test.js"
git -C "$D" add -A 2>/dev/null
out4b="$(run_lint "$D")"; rc4b=$?
[ "$rc4b" -eq 1 ] && ok "  → tests/ 안에서도 document 는 잡힌다(jest 전역만 열었다)" || bad "rc" "1" "$rc4b"

echo "⑤ 검사 대상이 0개면 **판정 불가** — 대상 없는 초록을 통과로 읽지 않는다"
E="$(make_probe probe-e)"
rm -f "$E/eslint.config.js"                      # 설정까지 없으면 치명적 오류 → 역시 2
out5="$(run_lint "$E")"; rc5=$?
[ "$rc5" -eq 2 ] && ok "설정이 없으면 rc=2" || bad "rc" "2" "$rc5"
printf '%s\n' "$out5" | grep -q "판정 불가" && ok "  → 판정 불가라고 말한다" || bad "문구" "판정 불가" "$out5"
F="$(make_probe probe-f)"                        # 설정은 있고 js 파일이 하나도 없다
mkdir -p "$F/media"
node -e '
const fs = require("fs"); const p = process.argv[1] + "/eslint.config.js";
fs.writeFileSync(p, "module.exports = [{ ignores: [\"**/*.js\"] }];\n");   // 전부 무시
' "$F"
out6="$(run_lint "$F")"; rc6=$?
[ "$rc6" -eq 2 ] && ok "ignores 가 전부를 덮어 0개를 검사하면 rc=2" || bad "rc" "2" "$rc6"
# 실측(eslint 10.8.0): 전부 무시되면 eslint 자신이 rc=2 로 죽는다 — "0개를 검사하고 초록" 이
# 아니라 "보고를 못 냈다" 로 들어온다. 그래도 화면에 **이유**가 남아야 한다. 위반 0건과
# 구별이 안 되면 사람은 이 rc=2 를 초록으로 읽는다.
printf '%s\n' "$out6" | grep -q "are ignored" \
  && ok "  → 무시돼서 못 쟀다는 eslint 원문 이유를 같이 보여준다" || bad "이유 노출" "are ignored" "$out6"
# 🔑 래퍼 자신의 '검사한 파일 0개' 갈래는 **가짜 eslint** 로 잰다. 실제 eslint 10 은 그
#    상태에서 rc=2 로 죽어 이 갈래에 도달하지 않는다(위 실측) — 방어용 갈래이므로 도달
#    가능한 경로를 만들어 계약만 확인한다. 없는 갈래를 있다고 말하지 않기 위해 분리했다.
STUB="$WORK/stub-eslint"
printf '#!/bin/sh\nprintf "[]"\nexit 0\n' > "$STUB"; chmod +x "$STUB"
out6b="$(LINT_ROOT="$REPO" ESLINT_BIN="$STUB" bash "$LINT" 2>&1)"; rc6b=$?
[ "$rc6b" -eq 2 ] && ok "보고가 빈 배열이면(파일 0개) rc=2 — 통과로 접지 않는다" || bad "rc" "2" "$rc6b"
printf '%s\n' "$out6b" | grep -q "검사한 파일이 0개" \
  && ok "  → '대상이 없는 것은 통과가 아니다' 라고 말한다" || bad "문구" "검사한 파일이 0개" "$out6b"

echo "⑥ eslint 부재는 rc=2 — npm ci 안 한 기계에서 조용한 초록 금지"
out7="$(LINT_ROOT="$REPO" ESLINT_BIN="/nonexistent/eslint-$$" bash "$LINT" 2>&1)"; rc7=$?
[ "$rc7" -eq 2 ] && ok "rc=2" || bad "rc" "2" "$rc7"
printf '%s\n' "$out7" | grep -q "npm ci" && ok "  → 무엇을 하라고 말한다(npm ci)" || bad "안내" "npm ci" "$out7"

echo "⑦ 이 레포 자신 — 추적 파일 위반 0건 ('0건이 된 다음에 켠다')"
out8="$(bash "$LINT" 2>&1)"; rc8=$?
if [ "$rc8" -eq 0 ]; then
  ok "rc=0"
  printf '%s\n' "$out8" | grep -q "검사한 파일 0개" \
    && bad "0개를 검사하고 초록이 됐다" "1개 이상" "$out8" \
    || ok "  → 실제로 파일을 봤다: $(printf '%s\n' "$out8" | sed -n 's/.*검사한 파일 \([0-9]*\)개.*/\1/p')개"
elif [ "$rc8" -eq 2 ]; then
  unmeasured "이 레포를 못 쟀다(rc=2): $out8"
else
  bad "이 레포에 추적 위반이 있다" "0건" "$out8"
fi

echo "⑧ 배선 — package.json 에 lint 스크립트와 의존성이 선언돼 있다"
PKG="$REPO/package.json"
node -e '
const p = require(process.argv[1]);
const out = [];
out.push(p.scripts && p.scripts.lint ? "script:" + p.scripts.lint : "script:MISSING");
for (const d of ["eslint", "globals"]) {
  out.push(d + ":" + ((p.devDependencies && p.devDependencies[d]) || "MISSING"));
}
console.log(out.join("\n"));
' "$PKG" > "$WORK/pkg.txt" 2>/dev/null || echo "script:PARSE-FAIL" > "$WORK/pkg.txt"
if grep -q '^script:.*lint-js.sh' "$WORK/pkg.txt"; then
  ok "npm run lint → scripts/lint-js.sh (eslint 를 직접 부르지 않는다 = 종료코드 계약이 산다)"
else
  bad "lint 스크립트가 래퍼를 부르지 않는다" "bash scripts/lint-js.sh" "$(sed -n 's/^script://p' "$WORK/pkg.txt")"
fi
for d in eslint globals; do
  if grep -q "^$d:MISSING" "$WORK/pkg.txt"; then
    bad "$d 가 devDependencies 에 없다" "선언" "MISSING"
  else
    ok "  → $d 가 devDependencies 에 선언돼 있다"
  fi
done

echo
echo "  통과 $pass · 실패 $fail · 판정 불가 $unk"
[ "$fail" -eq 0 ] || exit 1
[ "$unk" -eq 0 ] || exit 2
