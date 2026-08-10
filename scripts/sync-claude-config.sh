#!/bin/bash
# claude-config 동기화 스크립트
# ~/.claude/skills, hooks, settings → 레포의 claude-config/에 동기화
# cron: */30 * * * * bash ~/discord-bot-nino/sync-claude-config.sh

set -euo pipefail

# 환경변수로 주입 가능 — 시험이 실제 ~/.claude 와 레포를 건드리지 않게 (부작용 격리)
BOT_DIR="${BOT_DIR:-$HOME/discord-bot-nino}"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
CONFIG_DIR="${CONFIG_DIR:-$BOT_DIR/claude-config}"
LOG_FILE="${LOG_FILE:-$BOT_DIR/logs/sync-claude-config.log}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

CHANGED=0

# 설치본·캐시는 옮기지 않는다 (2026-07-28)
#   pptx 스킬에 의존성을 설치하자 node_modules 가 **147MB** 생겼고, 이 스크립트가
#   30분마다 그걸 통째로 복사하게 됐다. git 은 무시하지만(.gitignore) 복사 비용은 실재한다.
#   ⚠️ **비교(diff)에도 같은 제외를 걸어야 한다.** 복사만 제외하면 tracked 쪽엔 영원히
#      node_modules 가 없으므로 diff 가 매번 "다르다"고 판정해 **매 회차 재동기화**한다
#      (조용한 무한 재복사 — 로그만 늘고 원인이 안 보인다).
EXCLUDES=(node_modules .venv __pycache__ .pytest_cache)
DIFF_EXCLUDE=(); RSYNC_EXCLUDE=()
for e in "${EXCLUDES[@]+"${EXCLUDES[@]}"}"; do
    DIFF_EXCLUDE+=(--exclude="$e")
    RSYNC_EXCLUDE+=(--exclude="$e/")
done

# skills 동기화 (symlink 제외)
for d in "$CLAUDE_DIR/skills"/*/; do
    # 🔴 `[ -L "$d" ]` 는 **한 번도 동작하지 않았다** (2026-07-28 시험으로 발견).
    #    글롭 `*/` 은 `linked/` 처럼 **슬래시로 끝나는** 경로를 내고, 그러면 bash 가 링크를
    #    따라가 버려 `-L` 이 항상 거짓이 된다(실측: `[ -L link ]`=참 · `[ -L link/ ]`=거짓).
    #    주석엔 "symlink은 건너뜀"이라 적혀 있었지만 실제로는 링크 대상을 통째로 복사했다.
    [ -L "${d%/}" ] && continue  # symlink은 건너뜀 (슬래시를 떼고 판정해야 한다)
    name=$(basename "$d")
    if ! diff -rq "${DIFF_EXCLUDE[@]+"${DIFF_EXCLUDE[@]}"}" "$d" "$CONFIG_DIR/skills/$name" &>/dev/null 2>&1; then
        rm -rf "$CONFIG_DIR/skills/$name"
        mkdir -p "$CONFIG_DIR/skills/$name"
        rsync -a "${RSYNC_EXCLUDE[@]+"${RSYNC_EXCLUDE[@]}"}" "$d" "$CONFIG_DIR/skills/$name/"
        log "SYNC: skill/$name"
        CHANGED=$((CHANGED + 1))
    fi
done

# hooks 동기화
for f in "$CLAUDE_DIR/hooks"/*; do
    [ ! -f "$f" ] && continue
    name=$(basename "$f")
    if ! diff -q "$f" "$CONFIG_DIR/hooks/$name" &>/dev/null 2>&1; then
        cp "$f" "$CONFIG_DIR/hooks/"
        log "SYNC: hooks/$name"
        CHANGED=$((CHANGED + 1))
    fi
done

# user-settings.json 동기화
if ! diff -q "$CLAUDE_DIR/settings.json" "$CONFIG_DIR/user-settings.json" &>/dev/null 2>&1; then
    cp "$CLAUDE_DIR/settings.json" "$CONFIG_DIR/user-settings.json"
    log "SYNC: user-settings.json"
    CHANGED=$((CHANGED + 1))
fi

# project settings.json 동기화
if ! diff -q "$BOT_DIR/.claude/settings.json" "$CLAUDE_DIR/settings.json" &>/dev/null 2>&1; then
    # 프로젝트 설정이 다르면 업데이트 (이건 별도 파일)
    :
fi

# ── 변경 있으면 **sync 전용 브랜치**에 커밋 + PR (main 직접 커밋 금지)
#
# 왜 (Darren 승인 2026-07-30 M:w6mk "응 바꿔"):
#   전에는 이 스크립트가 **현재 브랜치에 커밋하고 push** 했다. cron 이 30분마다 도니까
#   `claude-config/` 아래 파일은 "기능/변경은 브랜치 → PR → 리뷰" 규칙을 **구조적으로 우회**했다.
#   실제로 md-web 훅(PR #81)이 리뷰 전에 그렇게 main 에 들어갔다(`67a461c`).
#
# 설계 결정:
#   - main 워크트리의 **HEAD·인덱스를 건드리지 않는다**(내가 그 트리에서 작업 중일 수 있다)
#     → 별 워크트리($SYNC_WORKTREE)에서 커밋한다. checkout·stash·add 를 공유 인덱스에 하지 않는다.
#   - 열린 PR 이 있으면 그 위에 커밋을 **쌓고**, 없으면 브랜치를 main 기준으로 **새로 만든다**
#     (PR 이 머지된 뒤에도 옛 베이스에 계속 쌓이는 걸 막는다).
#   - gh 가 없거나 실패해도 **커밋·push 는 진행**하고 로그에 남긴다 — 부재는 조용하니까.
SYNC_BRANCH="${SYNC_BRANCH:-chore/claude-config-sync}"
SYNC_WORKTREE="${SYNC_WORKTREE:-$BOT_DIR/../nino-config-sync}"
GH_BIN="${GH_BIN:-gh}"
export GH_CALLS="${GH_CALLS:-/dev/null}"   # 시험 스텁이 호출을 기록하는 자리

if [[ $CHANGED -eq 0 ]]; then
    log "OK: no changes"
    exit 0
fi

git -C "$BOT_DIR" fetch -q origin 2>/dev/null || log "WARN: git fetch 실패 (오프라인일 수 있다)"

# 열린 PR 이 있나 — **세 상태**다: open / none / unknown
# 🔴 unknown(gh 없음·조회 실패)을 none 으로 접으면 안 된다. none 갈래는 브랜치를 main 기준으로
#    **reset --hard** 하므로, 판정 불가를 none 으로 읽으면 이미 push 한 커밋을 버리려 하고
#    push 는 non-FF 로 거부돼 **원격이 조용히 안 갱신된다**(시험이 이걸 잡았다).
#    모르면 버리지 않는다 = 쌓는다.
PR_STATE=unknown
if command -v "$GH_BIN" >/dev/null 2>&1; then
    if pr_nums="$("$GH_BIN" pr list --head "$SYNC_BRANCH" --state open --json number -q '.[].number' 2>/dev/null)"; then
        if printf '%s' "$pr_nums" | grep -q '[0-9]'; then PR_STATE=open; else PR_STATE=none; fi
    else
        log "WARN: gh pr list 실패 — PR 상태 판정 불가(브랜치를 초기화하지 않는다)"
    fi
else
    log "WARN: gh 없음($GH_BIN) — PR 은 못 만든다. 커밋·push 는 진행한다"
fi

BASE="$(git -C "$BOT_DIR" rev-parse --verify -q origin/main || git -C "$BOT_DIR" rev-parse --verify -q main || git -C "$BOT_DIR" rev-parse HEAD)"

# sync 워크트리 준비 (main 체크아웃은 그대로 둔다)
if [[ ! -d "$SYNC_WORKTREE/.git" && ! -f "$SYNC_WORKTREE/.git" ]]; then
    rm -rf "$SYNC_WORKTREE"
    if [[ "$PR_STATE" != none ]] && git -C "$BOT_DIR" rev-parse --verify -q "origin/$SYNC_BRANCH" >/dev/null; then
        git -C "$BOT_DIR" worktree add -q "$SYNC_WORKTREE" -B "$SYNC_BRANCH" "origin/$SYNC_BRANCH"
    else
        git -C "$BOT_DIR" worktree add -q "$SYNC_WORKTREE" -B "$SYNC_BRANCH" "$BASE"
    fi
    log "SYNC-WT: 워크트리 생성 ($SYNC_WORKTREE, PR=$PR_STATE)"
elif [[ "$PR_STATE" == none ]]; then
    # 열린 PR 이 **없다고 확인됐다** = 앞 PR 이 머지되거나 없었다 → main 기준으로 다시 시작
    git -C "$SYNC_WORKTREE" reset -q --hard "$BASE"
    log "SYNC-WT: 브랜치를 main 기준으로 초기화 (열린 PR 없음)"
else
    log "SYNC-WT: 기존 브랜치에 쌓는다 (PR=$PR_STATE)"
fi

# 동기화 결과를 워크트리로 옮긴다 (제외는 복사·비교와 같은 목록을 쓴다)
mkdir -p "$SYNC_WORKTREE/claude-config" "$SYNC_WORKTREE/.claude"
# 🔴 --checksum 필수: rsync 의 기본 quick check 는 **크기+mtime** 이라, 같은 크기의 내용 수정이
#    같은 초에 일어나면 **갱신을 건너뛴다**. 실제로 시험에서 `# demo v2`→`# demo v5`(둘 다 10바이트)가
#    복사되지 않아 "tracked 내용은 동일"로 흘렀다 — 조용히 옛 내용을 커밋할 경로였다.
rsync -a --checksum --delete "${RSYNC_EXCLUDE[@]+"${RSYNC_EXCLUDE[@]}"}" "$CONFIG_DIR/" "$SYNC_WORKTREE/claude-config/"
[ -f "$BOT_DIR/.claude/settings.json" ] && cp "$BOT_DIR/.claude/settings.json" "$SYNC_WORKTREE/.claude/settings.json"

git -C "$SYNC_WORKTREE" add -A claude-config .claude/settings.json 2>/dev/null || \
    git -C "$SYNC_WORKTREE" add -A claude-config

if git -C "$SYNC_WORKTREE" diff --cached --quiet; then
    log "OK: 라이브는 바뀌었지만 tracked 내용은 동일 — 커밋할 게 없다"
    exit 0
fi

git -C "$SYNC_WORKTREE" commit -q -m "chore: claude-config 자동 동기화 ($CHANGED 파일)

sync-claude-config.sh cron 이 라이브(~/.claude) → tracked 를 옮긴 결과.
main 직접 커밋 대신 이 브랜치로 모아 PR 로 검토한다(Darren 지시 2026-07-30).

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>" && log "OK: $CHANGED files committed ($SYNC_BRANCH)" \
    || { log "ERROR: 커밋 실패 — 여기서 멈춘다"; exit 1; }

if git -C "$SYNC_WORKTREE" push -q -u origin "$SYNC_BRANCH" 2>/dev/null; then
    log "OK: pushed → origin/$SYNC_BRANCH"
else
    log "WARN: push 실패 (커밋은 로컬에 남아 있다 — 다음 회차에 다시 시도한다)"
fi

if [[ "$PR_STATE" == open ]]; then
    log "OK: 열린 PR 에 커밋 추가 (새 PR 안 만듦)"
elif command -v "$GH_BIN" >/dev/null 2>&1; then
    if url="$("$GH_BIN" pr create --base main --head "$SYNC_BRANCH" \
            --title "chore: claude-config 동기화 (라이브 → tracked)" \
            --body "$(printf '%s\n' \
                'sync-claude-config.sh cron 이 모은 라이브 설정(스킬·훅·settings) 변경이다.' \
                '' \
                '이 PR 이 존재하는 이유: 전에는 cron 이 main 에 직접 커밋+push 해서' \
                '`claude-config/` 아래 파일이 리뷰 게이트를 구조적으로 우회했다(Darren 지시 2026-07-30 로 변경).' \
                '' \
                '## Test plan' \
                '- `bash tests/sync-claude-config.test.sh`' \
                '- 라이브가 정본이므로 이 PR 을 머지해도 실행 중인 설정은 바뀌지 않는다(기록/검토용).')" 2>&1)"; then
        log "OK: PR 생성 — $url"
    else
        log "WARN: PR 생성 실패 — $url"
    fi
fi
