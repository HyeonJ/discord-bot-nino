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
#
# 🔴 **실물 `gh` 는 «cwd 가 레포 안»이 아니면 죽는다** — 이 스텁이 그걸 안 흉내내서
#   10일간 「PR 생성을 시도했다」가 초록인 채로 **운영에선 0건**이었다(실측 2026-08-11:
#   `logs/sync-claude-config.log` — `OK: PR 생성` **0회** / `WARN: PR 생성 실패` **14회**,
#   08-01 21:30 부터 전부 `failed to run git: fatal: not a git repository`).
#   🔑 **스텁이 실물의 «실패 양식»을 못 흉내내면 그 축은 시험 밖이다.** 좌변이
#     「gh 를 «불렀나»」였고 실물이 죽는 자리는 「gh 가 «되나»」였다.
#   실물 확인(같은 날, 세 갈래): 비레포 cwd → rc=1 · 레포 cwd → rc=0 · `-R o/r` → rc=0.
cat > "$ROOT/gh" <<'GHEOF'
#!/bin/bash
echo "$*" >> "$GH_CALLS"
# 실물 gh 와 같은 전제: cwd 가 git 워크트리 안이거나 `-R` 이 명시돼야 한다.
if ! printf '%s\n' "$@" | grep -qx -- '-R'; then
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "failed to run git: fatal: not a git repository (or any of the parent directories): .git" >&2
    exit 1
  fi
fi
case "$1 $2" in
  "pr list") [ "${GH_STUB_PR_OPEN:-0}" = 1 ] && echo 42; exit 0 ;;
  "pr create") echo "https://example.invalid/pr/99"; exit 0 ;;
esac
exit 0
GHEOF
chmod +x "$ROOT/gh"
SYNC_BRANCH=chore/claude-config-sync

# 🔴 **cron 의 cwd 로 돈다 — 레포 «밖»이다.** 시험이 레포 안에서 부르면 스크립트가
#   cwd 에 기대는 것을 **공짜로 얻어** 그 의존이 안 보인다(실제로 그래서 10일 안 보였다).
#   크론은 `cd` 없이 돌아 cwd 가 `$HOME` 이고, `$HOME` 은 git 레포가 아니다.
NOREPO="$ROOT/norepo"; mkdir -p "$NOREPO"
run_git() {  # git 단계까지 도는 실행 (gh 스텁 + sync worktree 주입)
  ( cd "$NOREPO" || exit 1
    BOT_DIR="$ROOT/repo" CLAUDE_DIR="$ROOT/live" CONFIG_DIR="$ROOT/repo/claude-config" \
    LOG_FILE="$ROOT/repo/logs/sync.log" GH_BIN="$ROOT/gh" GH_CALLS="$ROOT/gh-calls.log" \
    SYNC_WORKTREE="$ROOT/sync-wt" GH_STUB_PR_OPEN="${GH_STUB_PR_OPEN:-0}" bash "$SCRIPT" 2>&1 )
}
main_commits() { git -C "$GITREPO" rev-list --count main; }
branch_commits() { git -C "$ROOT/origin.git" rev-list --count "$SYNC_BRANCH" 2>/dev/null || echo 0; }

before_main="$(main_commits)"
printf '# demo v3\n' > "$ROOT/live/skills/demo/SKILL.md"
# 🔑 **이 실행이 낸 줄만 본다.** 로그는 누적이라 앞 절(gh 를 «안» 주입한 실행)의 WARN 이
#   섞이고, 그러면 좌변이 「이 실행이 실패했나」가 아니라 「언젠가 실패한 적 있나」가 된다.
_log0="$(command grep -c '' "$ROOT/repo/logs/sync.log" 2>/dev/null || true)"; _log0="${_log0:-0}"
since_run() { tail -n +$((_log0 + 1)) "$ROOT/repo/logs/sync.log" 2>/dev/null; }
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
# 🔴 **「불렀다」와 「됐다」는 다른 축이다.** 위 단언만 두면 gh 가 매번 죽어도 초록이다 —
#   실물에서 정확히 그랬다(호출 14회 · 성공 0회 · 10일). ⇒ 결과를 따로 잰다.
since_run | grep -q 'OK: PR 생성' && ok "PR 생성이 «성공»했다" \
  || bad "PR 생성이 실패했다 — 시도만으론 아무도 안 본다" "성공 로그" "$(since_run | grep -E 'PR' | tail -2)"
since_run | grep -q 'WARN: gh pr list 실패' \
  && bad "PR 상태 조회가 실패했다 — 판정 불가라 브랜치가 옛 베이스에 계속 쌓인다" "조회 성공" \
         "$(since_run | grep 'pr list' | tail -1)" \
  || ok "PR 상태 조회가 «성공»했다 (판정 불가로 안 빠진다)"
: > "$ROOT/gh-calls.log"
printf '# demo v4\n' > "$ROOT/live/skills/demo/SKILL.md"
GH_STUB_PR_OPEN=1 run_git >/dev/null
grep -q 'pr create' "$ROOT/gh-calls.log" 2>/dev/null \
  && bad "PR 이 열려 있는데 또 만들었다" "$(cat "$ROOT/gh-calls.log")" \
  || ok "열린 PR 이 있으면 생성 안 함"
git -C "$ROOT/origin.git" show "$SYNC_BRANCH:claude-config/skills/demo/SKILL.md" 2>/dev/null | grep -q v4 \
  && ok "두 번째 변경이 원격 브랜치에 올라갔다 (v4)" || bad "두 번째 변경이 브랜치에 안 올라갔다"

echo "⑧-b 🔴 열린 PR 이어도 «main 위에서 재생성»한다 — 브랜치는 항상 main+1 이다"
# 🔴 **옛 계약은 「열린 PR 위에 커밋을 쌓는다」였고, 그게 결함이었다.**
#   단방향 미러 브랜치라 아무도 사람 손으로 커밋하지 않는데, 쌓기만 하면 **base 가 영원히
#   안 따라온다** — PR 이 며칠 열려 있으면 그 사이 main 에 들어간 것이 전부 diff 에 남고,
#   CI 도 낡은 base 에서 돈다(2026-08-15 실물: `#230` 을 손으로 «재생성»해야 했다).
# 🔑 새 보장: **원격 브랜치 = 「origin/main + 라이브 델타 커밋 하나」.** `main..branch` 는
#   0 또는 1이고, base 는 매 회차 저절로 따라온다. 고를 자리가 없다.
branch_ahead() { git -C "$ROOT/origin.git" rev-list --count "main..$SYNC_BRANCH" 2>/dev/null || echo 99; }
[ "$(branch_ahead)" -eq 1 ] && ok "main..branch = 1 (쌓이지 않는다)" \
  || bad "브랜치가 main 위에 «쌓였다»" "1" "$(branch_ahead)"
# 대조군 — 세 번째 변경을 넣어도 여전히 1이다(「한 번만 1」이 아니라 «불변»이라야 한다)
printf '# demo v4b\n' > "$ROOT/live/skills/demo/SKILL.md"
GH_STUB_PR_OPEN=1 run_git >/dev/null
[ "$(branch_ahead)" -eq 1 ] && ok "세 번째 회차에도 main..branch = 1 (불변)" \
  || bad "회차마다 쌓인다" "1" "$(branch_ahead)"
git -C "$ROOT/origin.git" show "$SYNC_BRANCH:claude-config/skills/demo/SKILL.md" 2>/dev/null | grep -q v4b \
  && ok "재생성된 커밋이 «최신» 라이브를 담는다" || bad "재생성이 옛 내용을 담았다"

echo "⑧-c 🔴 base 가 밀려도 «따라온다» — 그게 이 형태의 존재 이유다"
# 🔑 좌변은 「내가 아무것도 안 해도 판정이 바뀌나」의 반대편이다: 남이 main 을 밀면
#   다음 회차가 **저절로** 그 위로 옮겨가야 한다. 안 옮겨가면 diff 가 남의 것을 물고 자란다.
( cd "$GITREPO" && printf 'x\n' > unrelated.txt && git add unrelated.txt \
  && git commit -qm "남의 커밋" && git push -q origin main ) >/dev/null 2>&1
printf '# demo v4c\n' > "$ROOT/live/skills/demo/SKILL.md"
GH_STUB_PR_OPEN=1 run_git >/dev/null
[ "$(branch_ahead)" -eq 1 ] && ok "남이 main 을 민 뒤에도 main..branch = 1" \
  || bad "base 가 안 따라왔다 (남의 커밋이 내 diff 에 들어간다)" "1" "$(branch_ahead)"
git -C "$ROOT/origin.git" cat-file -e "$SYNC_BRANCH:unrelated.txt" 2>/dev/null \
  && ok "브랜치가 남의 커밋을 «포함»한다 (그 위에 서 있다)" \
  || bad "브랜치가 새 main 위에 안 서 있다"

echo "⑨ gh 가 없어도 커밋·push 는 남는다 (판정 불가를 실패로 접지 않는다)"
: > "$ROOT/gh-calls.log"
printf '# demo v5\n' > "$ROOT/live/skills/demo/SKILL.md"
# 🔑 좌변이 «커밋 수»면 안 된다 — 재생성 계약에서 수는 **불변(main+1)**이라 «항상 거짓»이
#   되어, 이 시험이 「gh 부재가 커밋을 막았다」를 영원히 외친다. 물어야 할 것은 수가 아니라
#   **「원격 tip 이 새 내용으로 바뀌었나」**다.
branch_tip() { git -C "$ROOT/origin.git" rev-parse "$SYNC_BRANCH" 2>/dev/null || echo none; }
before_tip="$(branch_tip)"
out9="$(BOT_DIR="$ROOT/repo" CLAUDE_DIR="$ROOT/live" CONFIG_DIR="$ROOT/repo/claude-config" \
  LOG_FILE="$ROOT/repo/logs/sync.log" GH_BIN="$ROOT/없는gh" GH_CALLS="$ROOT/gh-calls.log" \
  SYNC_WORKTREE="$ROOT/sync-wt" bash "$SCRIPT" 2>&1)"; rc9=$?
[ "$rc9" -eq 0 ] && ok "gh 없음에도 종료코드 0" || bad "gh 없으면 죽는다 (rc=$rc9)" "$out9"
[ "$(branch_tip)" != "$before_tip" ] && ok "커밋·push 는 그대로 진행됐다 (원격 tip 이 바뀌었다)" \
  || bad "gh 부재가 커밋까지 막았다" "새 tip" "$before_tip 그대로"
git -C "$ROOT/origin.git" show "$SYNC_BRANCH:claude-config/skills/demo/SKILL.md" 2>/dev/null | grep -q v5 \
  && ok "그 push 가 «새 내용»을 담았다 (tip 만 흔들린 게 아니다)" || bad "원격에 v5 가 없다"
grep -q 'WARN.*gh' "$ROOT/repo/logs/sync.log" && ok "gh 부재를 로그에 남긴다 (조용히 넘기지 않는다)" \
  || bad "gh 부재가 로그에 없다 — 부재는 조용하다" "$(tail -3 "$ROOT/repo/logs/sync.log")"

echo "⑩ 라이브는 바뀌었지만 tracked 내용이 같으면 **빈 커밋을 만들지 않는다**"
# 실제로 나는 경우: 누가 tracked 사본을 되돌려 놓으면 다음 회차가 그걸 다시 복사한다(CHANGED>0)
# → 그런데 워크트리 내용은 HEAD 와 같다. 여기서 커밋을 시도하면 `git commit` 이 실패해
#   스크립트가 rc=1 로 죽는다(cron 이라 아무도 안 읽는 조용한 실패).
: > "$ROOT/gh-calls.log"
# 🔑 «재생성» 계약에서 이 갈래의 좌변은 「브랜치 HEAD 와 같나」가 아니라 **「main 과 같나」**다.
#   그래서 픽스처도 그쪽으로 옮긴다 — 앞 PR 이 머지된 상태(main 이 그 내용을 이미 담음)를 만든다.
# 🔴 main 을 브랜치로 «ff» 시키면 안 된다 — 그러면 `main..branch` 가 **자동으로 0** 이라
#   아래 되돌림 단언이 옛 판에서도 초록이다(대조군이 죽는다). 앞 PR 이 «squash 머지»된
#   실제 모양대로, **같은 내용의 «다른 커밋»**을 main 에 넣는다 ⇒ 브랜치는 여전히 1 앞선다.
( cd "$GITREPO" && git add -A claude-config .claude \
  && git commit -qm "동등 내용을 main 에 (앞 PR squash 머지 흉내)" && git push -q origin main ) >/dev/null 2>&1
git -C "$GITREPO" fetch -q origin
[ "$(branch_ahead)" -eq 1 ] && ok "픽스처 확인: 되돌리기 «전»엔 브랜치가 main 보다 1 앞선다" \
  || bad "픽스처가 무효 — 대조군이 죽었다" "1" "$(branch_ahead)"
rm -rf "$ROOT/repo/claude-config/skills/demo"           # tracked 사본만 되돌린 상태 (CHANGED>0 을 만든다)
out10="$(GH_STUB_PR_OPEN=1 run_git)"; rc10=$?
[ "$rc10" -eq 0 ] && ok "tracked 되돌림 후에도 종료코드 0" || bad "커밋할 게 없는데 죽었다 (rc=$rc10)" "$out10"
grep -q 'main 과 같다' "$ROOT/repo/logs/sync.log" && ok "그 갈래를 로그로 구분한다" \
  || bad "무엇 때문에 커밋을 안 했는지 로그에 없다" "$(tail -2 "$ROOT/repo/logs/sync.log")"
# 🔴 그리고 «원격을 그대로 두면» 안 된다 — 브랜치가 main 보다 앞선 채 남으면 그 PR 은
#   「이미 머지된 내용」을 리뷰하라고 계속 열려 있고, 그 낡음이 조용하다.
[ "$(branch_ahead)" -eq 0 ] && ok "라이브가 main 과 같으면 브랜치를 main 으로 되돌린다 (main..branch=0)" \
  || bad "브랜치가 main 보다 앞선 채 남았다" "0" "$(branch_ahead)"

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
