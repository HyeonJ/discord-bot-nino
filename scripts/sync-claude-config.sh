#!/bin/bash
# claude-config 동기화 스크립트
# ~/.claude/skills, hooks, settings → 레포의 claude-config/에 동기화
# cron: */30 * * * * bash ~/discord-bot-nino/sync-claude-config.sh

set -euo pipefail

BOT_DIR="$HOME/discord-bot-nino"
CLAUDE_DIR="$HOME/.claude"
CONFIG_DIR="$BOT_DIR/claude-config"
LOG_FILE="$BOT_DIR/logs/sync-claude-config.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

CHANGED=0

# skills 동기화 (symlink 제외)
for d in "$CLAUDE_DIR/skills"/*/; do
    [ -L "$d" ] && continue  # symlink은 건너뜀
    name=$(basename "$d")
    if ! diff -rq "$d" "$CONFIG_DIR/skills/$name" &>/dev/null 2>&1; then
        rm -rf "$CONFIG_DIR/skills/$name"
        cp -r "$d" "$CONFIG_DIR/skills/"
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
