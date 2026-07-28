#!/usr/bin/env bash
# lint-js.sh — eslint 를 **판정 가능한 종료코드**로 감싼다
#
# 왜 감싸나 (2026-07-28, Darren 승인 M:1t4b):
#   ① eslint 는 **설치 안 된 기계에서 그냥 실패**한다. 그 실패를 "위반 있음(rc=1)" 과 같은
#      칸에 두면 `npm ci` 를 안 한 기계에서 "빨간불 = 코드 문제" 로 잘못 읽는다.
#      더 나쁜 쪽은 그 반대 — CI 가 `|| true` 로 감싸면 **한 번도 안 재고 초록**이 된다.
#   ② 이 레포에는 **추적하지 않는 개인 스크립트**가 섞여 있다(of/*.js, media/ytm-play.js …).
#      실측 2026-07-28: 라이브 트리 위반 8건 = 추적 4 + 미추적 4. 미추적 4건으로 빨간불을
#      만들면 첫날부터 "빨간불이 정상" 이 되고, 그 뒤 **진짜 회귀가 그 빨간불 안에 묻힌다.**
#      ⇒ 미추적 위반은 **말은 하고 실패로는 만들지 않는다.**
#   ③ 검사 대상이 0개인 것은 통과가 아니다 — 못 쟀다. (경로 오타·ignores 과잉으로 조용히
#      아무것도 안 보는 상태를 초록으로 읽지 않는다)
#
# 종료코드 — 세 상태를 접지 않는다:
#   0  정상        추적 파일 위반 0건 (미추적 위반은 ℹ️ 로만 알린다)
#   1  위반        추적 파일에 위반이 있다
#   2  판정 불가   eslint 부재 · 설정 오류 · 검사한 파일 0개
#
# 주입 가능한 값(시험용): LINT_ROOT · ESLINT_BIN
set -uo pipefail

ROOT="${LINT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
ESLINT_BIN="${ESLINT_BIN:-$ROOT/node_modules/.bin/eslint}"

if [ ! -x "$ESLINT_BIN" ]; then
    echo "⛔ 판정 불가 — eslint 가 없다: $ESLINT_BIN"
    echo "   → 먼저 'npm ci'. 없는 것을 초록으로 읽지 않는다"
    exit 2
fi

cd "$ROOT" || { echo "⛔ 판정 불가 — 루트로 못 갔다: $ROOT"; exit 2; }

REPORT="$("$ESLINT_BIN" . -f json 2>/dev/null)"
ESLINT_RC=$?
# eslint: 0 위반없음 · 1 위반있음 · 2 이상 치명적(설정 오류 등)
if [ "$ESLINT_RC" -gt 1 ] || [ -z "$REPORT" ]; then
    echo "⛔ 판정 불가 — eslint 가 보고를 못 냈다 (rc=$ESLINT_RC)"
    # 🔑 왜 못 냈는지를 같이 보여준다. 가장 흔한 원인이 **전부 무시됨**인데(ignores 과잉·
    #    설정 위치), 그건 "위반 0건" 과 화면상 구별이 안 되므로 이유를 명시해야 한다.
    "$ESLINT_BIN" . 2>&1 | grep -v '^$' | grep -v '^ *\*' | grep -v '^https\?://' | head -6
    exit 2
fi

# 추적/미추적 분류는 node 로 한다 — JSON 을 셸로 긁으면 메시지 안의 따옴표에서 깨진다
SUMMARY="$(printf '%s' "$REPORT" | node -e '
const { execSync } = require("child_process");
const rs = JSON.parse(require("fs").readFileSync(0, "utf8"));
let tracked = new Set();
try {
  tracked = new Set(execSync("git ls-files \"*.js\"", { encoding: "utf8" }).trim().split("\n").filter(Boolean));
} catch (e) { /* git 밖이면 전부 추적으로 본다 — 조용히 봐주는 쪽이 아니라 엄한 쪽으로 접는다 */ }
const gitless = tracked.size === 0;
const cwd = process.cwd() + "/";
let nT = 0, nU = 0;
const lines = [];
for (const r of rs) {
  const f = r.filePath.startsWith(cwd) ? r.filePath.slice(cwd.length) : r.filePath;
  if (!r.messages.length) continue;
  const isT = gitless || tracked.has(f);
  if (isT) { nT += r.messages.length; } else { nU += r.messages.length; }
  for (const m of r.messages) {
    lines.push(`${isT ? "T" : "U"}\t${f}:${m.line}\t${m.ruleId || "(fatal)"}\t${m.message}`);
  }
}
console.log(`#COUNT\t${rs.length}\t${nT}\t${nU}\t${gitless ? 1 : 0}`);
for (const l of lines) console.log(l);
')"
NODE_RC=$?
if [ "$NODE_RC" -ne 0 ]; then
    echo "⛔ 판정 불가 — 보고를 분류하지 못했다 (node rc=$NODE_RC)"
    exit 2
fi

COUNT_LINE="$(printf '%s\n' "$SUMMARY" | sed -n 's/^#COUNT\t//p')"
CHECKED="$(printf '%s' "$COUNT_LINE" | cut -f1)"
N_TRACKED="$(printf '%s' "$COUNT_LINE" | cut -f2)"
N_UNTRACKED="$(printf '%s' "$COUNT_LINE" | cut -f3)"
GITLESS="$(printf '%s' "$COUNT_LINE" | cut -f4)"

if [ -z "$CHECKED" ]; then
    echo "⛔ 판정 불가 — 파일 수를 못 읽었다"
    exit 2
fi
if [ "$CHECKED" -eq 0 ]; then
    echo "⛔ 판정 불가 — 검사한 파일이 0개다. 대상이 없는 것은 통과가 아니다"
    echo "   → eslint.config.js 의 ignores 나 실행 경로를 본다"
    exit 2
fi

[ "$GITLESS" -eq 1 ] && echo "ℹ️  git 목록을 못 읽었다 — 미추적 봐주기 없이 전부 세었다"

if [ "$N_UNTRACKED" -gt 0 ]; then
    echo "ℹ️  미추적 파일 위반 ${N_UNTRACKED}건 — 실패로 세지 않는다(레포가 고칠 대상이 아니다)"
    printf '%s\n' "$SUMMARY" | sed -n 's/^U\t/     · /p'
fi

if [ "$N_TRACKED" -gt 0 ]; then
    echo "❌ 추적 파일 위반 ${N_TRACKED}건 (검사한 파일 ${CHECKED}개)"
    printf '%s\n' "$SUMMARY" | sed -n 's/^T\t/  · /p'
    exit 1
fi

echo "✅ 추적 파일 위반 0건 (검사한 파일 ${CHECKED}개)"
exit 0
