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
for e in "${EXCLUDES[@]}"; do
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
    if ! diff -rq "${DIFF_EXCLUDE[@]}" "$d" "$CONFIG_DIR/skills/$name" &>/dev/null 2>&1; then
        rm -rf "$CONFIG_DIR/skills/$name"
        mkdir -p "$CONFIG_DIR/skills/$name"
        rsync -a "${RSYNC_EXCLUDE[@]}" "$d" "$CONFIG_DIR/skills/$name/"
        log "SYNC: skill/$name"
        ((CHANGED++))
    fi
done

# hooks 동기화
for f in "$CLAUDE_DIR/hooks"/*; do
    [ ! -f "$f" ] && continue
    name=$(basename "$f")
    if ! diff -q "$f" "$CONFIG_DIR/hooks/$name" &>/dev/null 2>&1; then
        cp "$f" "$CONFIG_DIR/hooks/"
        log "SYNC: hooks/$name"
        ((CHANGED++))
    fi
done

# user-settings.json 동기화
if ! diff -q "$CLAUDE_DIR/settings.json" "$CONFIG_DIR/user-settings.json" &>/dev/null 2>&1; then
    cp "$CLAUDE_DIR/settings.json" "$CONFIG_DIR/user-settings.json"
    log "SYNC: user-settings.json"
    ((CHANGED++))
fi

# project settings.json 동기화
if ! diff -q "$BOT_DIR/.claude/settings.json" "$CLAUDE_DIR/settings.json" &>/dev/null 2>&1; then
    # 프로젝트 설정이 다르면 업데이트 (이건 별도 파일)
    :
fi

# 변경 있으면 커밋+푸시
if [[ $CHANGED -gt 0 ]]; then
    cd "$BOT_DIR"
    git add claude-config/ .claude/settings.json
    git commit -m "chore: claude-config 자동 동기화 ($CHANGED 파일)

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>" 2>/dev/null || true
    git push 2>/dev/null || true
    log "OK: $CHANGED files synced and pushed"
else
    log "OK: no changes"
fi
