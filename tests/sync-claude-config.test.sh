#!/usr/bin/env bash
# sync-claude-config.sh 계약 — **설치본을 옮기지 않고, 매 회차 재동기화하지 않는다**
#
# 왜 이 시험이 생겼나 (2026-07-28):
#   pptx 스킬에 의존성을 설치하자 `node_modules` 가 147MB 생겼고, 이 스크립트가
#   30분마다 그걸 통째로 복사하게 됐다. git 은 무시하지만 복사 비용은 실재한다.
#
#   🔑 그리고 복사만 제외하면 더 나쁜 상태가 된다 — tracked 쪽엔 영원히 node_modules 가
#   없으므로 `diff -rq` 가 매 회차 "다르다"고 판정해 **끝없이 재동기화**한다.
#   로그만 늘고 원인은 안 보인다(*조용한 낭비*). 그래서 ③이 이 시험의 핵심이다.
#
# 격리: 실제 ~/.claude·레포를 건드리지 않는다(CLAUDE_DIR·CONFIG_DIR·LOG_FILE 주입).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$BOT/scripts/sync-claude-config.sh"

pass=0; fail=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; fail=$((fail + 1)); [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/     /'; }

[ -f "$SCRIPT" ] || { echo "❌ 없음: $SCRIPT"; exit 1; }
ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT

# 라이브 쪽: 스킬 1개 + 무거운 설치본
mkdir -p "$ROOT/live/skills/demo/scripts" "$ROOT/live/skills/demo/node_modules/pkg" \
         "$ROOT/live/skills/demo/__pycache__" "$ROOT/live/hooks"
printf '# demo\n'      > "$ROOT/live/skills/demo/SKILL.md"
printf 'console.log(1)\n' > "$ROOT/live/skills/demo/scripts/run.js"
head -c 200000 /dev/zero > "$ROOT/live/skills/demo/node_modules/pkg/big.bin"
printf 'x\n'           > "$ROOT/live/skills/demo/__pycache__/x.pyc"
printf '{}\n'          > "$ROOT/live/settings.json"
printf '{}\n'          > "$ROOT/live/user-settings.json"
mkdir -p "$ROOT/repo/claude-config/skills" "$ROOT/repo/claude-config/hooks" "$ROOT/repo/logs"

run() {
  BOT_DIR="$ROOT/repo" CLAUDE_DIR="$ROOT/live" CONFIG_DIR="$ROOT/repo/claude-config" \
  LOG_FILE="$ROOT/repo/logs/sync.log" bash "$SCRIPT" 2>&1
}

echo "① 스킬 본문은 옮긴다"
run >/dev/null
[ -f "$ROOT/repo/claude-config/skills/demo/SKILL.md" ] && ok "SKILL.md 복사됨" || bad "SKILL.md 가 없다"
[ -f "$ROOT/repo/claude-config/skills/demo/scripts/run.js" ] && ok "하위 디렉터리도 복사됨" || bad "scripts/run.js 가 없다"

echo "② 🔑 설치본·캐시는 옮기지 않는다"
[ ! -d "$ROOT/repo/claude-config/skills/demo/node_modules" ] && ok "node_modules 제외됨" \
  || bad "node_modules 가 복사됐다 ($(du -sh "$ROOT/repo/claude-config/skills/demo/node_modules" 2>/dev/null | cut -f1))"
[ ! -d "$ROOT/repo/claude-config/skills/demo/__pycache__" ] && ok "__pycache__ 제외됨" || bad "__pycache__ 가 복사됐다"

echo "③ 🔑 두 번째 실행은 **재동기화하지 않는다** (diff 에도 제외가 걸려 있어야 한다)"
# 복사만 제외하고 비교를 안 고치면 여기서 SYNC 가 계속 늘어난다 — 무한 재복사
run >/dev/null
n="$(grep -c 'SYNC: skill/demo' "$ROOT/repo/logs/sync.log" 2>/dev/null)"
[ "$n" -eq 1 ] && ok "SYNC 로그가 1회 (재동기화 없음)" \
  || bad "SYNC 가 ${n}회 — 매 회차 다시 복사하고 있다(비교에 제외가 안 걸렸다)"

echo "④ 실제 변경이 있으면 다시 동기화한다 (제외가 감지를 죽이지 않았나)"
printf '# demo v2\n' > "$ROOT/live/skills/demo/SKILL.md"
run >/dev/null
n2="$(grep -c 'SYNC: skill/demo' "$ROOT/repo/logs/sync.log" 2>/dev/null)"
[ "$n2" -eq 2 ] && ok "본문 변경은 감지된다" || bad "본문을 바꿨는데 동기화 안 됨 (SYNC ${n2}회)"
grep -q 'v2' "$ROOT/repo/claude-config/skills/demo/SKILL.md" && ok "새 내용이 반영됨" || bad "옛 내용이 남았다"

echo "⑤ symlink 스킬은 건너뛴다 (기존 동작 보존)"
ln -s "$ROOT/live/skills/demo" "$ROOT/live/skills/linked"
run >/dev/null
[ ! -e "$ROOT/repo/claude-config/skills/linked" ] && ok "symlink 은 복사 안 함" || bad "symlink 을 따라갔다"

echo "⑥ 🔴 **변경이 있으면 커밋 단계까지 도달한다** (2026-07-29 — 67회 복사·0회 커밋)"
# 🔑 이 시험이 없던 동안 스크립트는 **첫 변경 하나를 복사한 직후 매번 죽었다.**
#    로그에 SYNC 67줄 · "synced and pushed" 0줄 · 자동동기화 커밋 0개.
#    원인: `set -e` + `((CHANGED++))` — **후위 증가는 옛 값을 반환**하므로 0→1 에서
#    `((...))` 가 0(거짓)을 내고 set -e 가 죽인다. `C=1` 이면 살아남아 *가끔 되는 것처럼* 보인다.
#    ⚠️ 복사는 눈에 보이고(파일이 생긴다) 커밋은 안 보인다 — **절반이 성공하면 성공처럼 보인다.**
#       그래서 ①~⑤(복사 결과)만으로는 이 결함을 영원히 못 잡는다. 마지막 단계를 봐야 한다.
GITREPO="$ROOT/repo"
( cd "$GITREPO" && git init -q 2>/dev/null && git config user.email t@t && git config user.name t \
  && mkdir -p .claude && printf '{}\n' > .claude/settings.json \
  && git add -A >/dev/null 2>&1 && git commit -qm init 2>/dev/null ) || true
printf '# demo v3\n' > "$ROOT/live/skills/demo/SKILL.md"
out="$(run)"; rc=$?
grep -q 'synced and pushed' "$ROOT/repo/logs/sync.log" \
  && ok "커밋 단계 로그에 도달한다" \
  || bad "복사만 하고 죽었다 — 마지막 줄에 도달 못 함" "$(tail -3 "$ROOT/repo/logs/sync.log")"
[ "$rc" -eq 0 ] && ok "종료코드 0" || bad "종료코드 $rc — 중간에 죽었다" "$out"

echo "⑦ 변경이 없을 때도 정상 종료한다 (대조군 — ⑥이 그냥 항상 참이 아님을 보인다)"
run >/dev/null; rc2=$?
[ "$rc2" -eq 0 ] && ok "무변경 종료코드 0" || bad "무변경인데 종료코드 $rc2"
tail -1 "$ROOT/repo/logs/sync.log" | grep -q 'no changes' && ok "무변경 경로는 다른 줄을 남긴다" \
  || bad "무변경 로그가 다르지 않다" "$(tail -1 "$ROOT/repo/logs/sync.log")"

echo
echo "  통과 $pass · 실패 $fail"
[ "$fail" -eq 0 ]
