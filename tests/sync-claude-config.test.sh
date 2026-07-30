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
# 진짜 origin(bare)을 둔다 — push 가 도달했는지 **원격에서** 확인해야 판정이 된다
git -c init.defaultBranch=main init -q --bare "$ROOT/origin.git"
( cd "$GITREPO" && git -c init.defaultBranch=main init -q && git config user.email t@t && git config user.name t \
  && mkdir -p .claude && printf '{}\n' > .claude/settings.json \
  && git add -A >/dev/null 2>&1 && git commit -qm init >/dev/null 2>&1 \
  && git remote add origin "$ROOT/origin.git" && git push -q -u origin main ) || true

# gh 스텁: 호출을 기록하고, 열린 PR 여부를 GH_STUB_PR_OPEN 으로 조종한다
cat > "$ROOT/gh" <<'GHEOF'
#!/bin/bash
echo "$*" >> "$GH_CALLS"
case "$1 $2" in
  "pr list") [ "${GH_STUB_PR_OPEN:-0}" = 1 ] && echo 42; exit 0 ;;
  "pr create") echo "https://example.invalid/pr/99"; exit 0 ;;
esac
exit 0
GHEOF
chmod +x "$ROOT/gh"
SYNC_BRANCH=chore/claude-config-sync

run_git() {  # git 단계까지 도는 실행 (gh 스텁 + sync worktree 주입)
  BOT_DIR="$ROOT/repo" CLAUDE_DIR="$ROOT/live" CONFIG_DIR="$ROOT/repo/claude-config" \
  LOG_FILE="$ROOT/repo/logs/sync.log" GH_BIN="$ROOT/gh" GH_CALLS="$ROOT/gh-calls.log" \
  SYNC_WORKTREE="$ROOT/sync-wt" GH_STUB_PR_OPEN="${GH_STUB_PR_OPEN:-0}" bash "$SCRIPT" 2>&1
}
main_commits() { git -C "$GITREPO" rev-list --count main; }
branch_commits() { git -C "$ROOT/origin.git" rev-list --count "$SYNC_BRANCH" 2>/dev/null || echo 0; }

before_main="$(main_commits)"
printf '# demo v3\n' > "$ROOT/live/skills/demo/SKILL.md"
out="$(run_git)"; rc=$?
[ "$rc" -eq 0 ] && ok "종료코드 0" || bad "종료코드 $rc — 중간에 죽었다" "$out"
grep -q 'committed' "$ROOT/repo/logs/sync.log" \
  && ok "커밋 단계 로그에 도달한다" \
  || bad "복사만 하고 죽었다 — 마지막 줄에 도달 못 함" "$(tail -3 "$ROOT/repo/logs/sync.log")"

echo "⑦ 🔴 **main 에는 커밋하지 않는다** (Darren 승인 2026-07-30 — PR 게이트 우회 차단)"
# 이 시험이 없던 동안 sync cron 이 main 에 직접 커밋+push 해서, claude-config 아래 파일은
# "기능/변경은 브랜치 → PR → 리뷰" 규칙을 **구조적으로 우회**했다(#81 훅이 실제로 그렇게 들어갔다).
[ "$(main_commits)" -eq "$before_main" ] && ok "main 커밋 수가 그대로 ($before_main)" \
  || bad "main 에 커밋했다 ($before_main → $(main_commits))" "$(git -C "$GITREPO" log --oneline -2 main)"
[ -z "$(git -C "$GITREPO" status --porcelain --untracked-files=no -- .claude claude-config 2>/dev/null | grep -v '^$' || true)" ] \
  && ok "main 워킹트리 인덱스를 스테이징하지 않는다" \
  || ok "main 워킹트리는 dirty (복사 결과 — 커밋만 안 하면 된다)"
[ "$(branch_commits)" -ge 1 ] && ok "origin 의 $SYNC_BRANCH 에 커밋이 도달했다 ($(branch_commits)개)" \
  || bad "push 가 원격에 안 닿았다" "$(tail -4 "$ROOT/repo/logs/sync.log")"
git -C "$ROOT/origin.git" show "$SYNC_BRANCH:claude-config/skills/demo/SKILL.md" 2>/dev/null | grep -q v3 \
  && ok "원격 브랜치 내용이 라이브와 같다" || bad "원격 브랜치에 새 내용이 없다"

echo "⑧ PR 이 없으면 만들고, 있으면 또 만들지 않는다"
grep -q 'pr create' "$ROOT/gh-calls.log" 2>/dev/null && ok "PR 생성을 시도했다" \
  || bad "PR 을 만들지 않았다 — 커밋만 브랜치에 쌓이면 아무도 안 본다" "$(cat "$ROOT/gh-calls.log" 2>/dev/null)"
: > "$ROOT/gh-calls.log"
printf '# demo v4\n' > "$ROOT/live/skills/demo/SKILL.md"
GH_STUB_PR_OPEN=1 run_git >/dev/null
grep -q 'pr create' "$ROOT/gh-calls.log" 2>/dev/null \
  && bad "PR 이 열려 있는데 또 만들었다" "$(cat "$ROOT/gh-calls.log")" \
  || ok "열린 PR 이 있으면 생성 안 함"
[ "$(branch_commits)" -ge 2 ] && ok "열린 PR 위에 커밋을 더 쌓는다 ($(branch_commits)개)" \
  || bad "두 번째 변경이 브랜치에 안 올라갔다"

echo "⑨ gh 가 없어도 커밋·push 는 남는다 (판정 불가를 실패로 접지 않는다)"
: > "$ROOT/gh-calls.log"
printf '# demo v5\n' > "$ROOT/live/skills/demo/SKILL.md"
before_b="$(branch_commits)"
out9="$(BOT_DIR="$ROOT/repo" CLAUDE_DIR="$ROOT/live" CONFIG_DIR="$ROOT/repo/claude-config" \
  LOG_FILE="$ROOT/repo/logs/sync.log" GH_BIN="$ROOT/없는gh" GH_CALLS="$ROOT/gh-calls.log" \
  SYNC_WORKTREE="$ROOT/sync-wt" bash "$SCRIPT" 2>&1)"; rc9=$?
[ "$rc9" -eq 0 ] && ok "gh 없음에도 종료코드 0" || bad "gh 없으면 죽는다 (rc=$rc9)" "$out9"
[ "$(branch_commits)" -gt "$before_b" ] && ok "커밋·push 는 그대로 진행됐다" \
  || bad "gh 부재가 커밋까지 막았다"
grep -q 'WARN.*gh' "$ROOT/repo/logs/sync.log" && ok "gh 부재를 로그에 남긴다 (조용히 넘기지 않는다)" \
  || bad "gh 부재가 로그에 없다 — 부재는 조용하다" "$(tail -3 "$ROOT/repo/logs/sync.log")"

echo "⑩ 라이브는 바뀌었지만 tracked 내용이 같으면 **빈 커밋을 만들지 않는다**"
# 실제로 나는 경우: 누가 tracked 사본을 되돌려 놓으면 다음 회차가 그걸 다시 복사한다(CHANGED>0)
# → 그런데 워크트리 내용은 HEAD 와 같다. 여기서 커밋을 시도하면 `git commit` 이 실패해
#   스크립트가 rc=1 로 죽는다(cron 이라 아무도 안 읽는 조용한 실패).
: > "$ROOT/gh-calls.log"
# PR 이 열려 있어야 브랜치가 초기화되지 않아 "브랜치 HEAD == 새 내용" 상태를 만들 수 있다
rm -rf "$ROOT/repo/claude-config/skills/demo"           # tracked 만 되돌린 상태
b_same="$(branch_commits)"
out10="$(GH_STUB_PR_OPEN=1 run_git)"; rc10=$?
[ "$rc10" -eq 0 ] && ok "tracked 되돌림 후에도 종료코드 0" || bad "커밋할 게 없는데 죽었다 (rc=$rc10)" "$out10"
[ "$(branch_commits)" -eq "$b_same" ] && ok "빈 커밋을 만들지 않는다 ($b_same 유지)" \
  || bad "빈/중복 커밋이 쌓였다 ($b_same → $(branch_commits))"
grep -q 'tracked 내용은 동일' "$ROOT/repo/logs/sync.log" && ok "그 갈래를 로그로 구분한다" \
  || bad "무엇 때문에 커밋을 안 했는지 로그에 없다" "$(tail -2 "$ROOT/repo/logs/sync.log")"

echo "⑪ 변경이 없을 때도 정상 종료한다 (대조군 — 위 검사가 항상 참이 아님을 보인다)"
b_before="$(branch_commits)"
run_git >/dev/null; rc2=$?
[ "$rc2" -eq 0 ] && ok "무변경 종료코드 0" || bad "무변경인데 종료코드 $rc2"
tail -1 "$ROOT/repo/logs/sync.log" | grep -q 'no changes' && ok "무변경 경로는 다른 줄을 남긴다" \
  || bad "무변경 로그가 다르지 않다" "$(tail -1 "$ROOT/repo/logs/sync.log")"
[ "$(branch_commits)" -eq "$b_before" ] && ok "무변경이면 빈 커밋을 만들지 않는다" \
  || bad "빈 커밋이 쌓였다 ($b_before → $(branch_commits))"

echo
echo "  통과 $pass · 실패 $fail"
[ "$fail" -eq 0 ]
