#!/bin/bash
# nino-watchdog.sh — 2분마다 crontab으로 실행, tmux/Claude 죽으면 자동 재시작 + 디코 알림
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SESSION="nino"
LOG="$BOT_DIR/logs/watchdog.log"
DISCORD_SEND="$BOT_DIR/src/discord-send"
CHANNEL_MAP="$BOT_DIR/config/channel-map.json"
ALERT_CHANNEL=$(python3 -c "import json; print(json.load(open('$CHANNEL_MAP'))['현인-업무'])" 2>/dev/null || echo "1479813609499394171")

source "$BOT_DIR/.env" 2>/dev/null || true

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"; }

# Check 1: tmux 세션 살아있는지
if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    log "DEAD: tmux session '$SESSION' not found. Restarting..."
    "$SCRIPT_DIR/start-nino.sh" >> "$LOG" 2>&1
    $DISCORD_SEND -c "$ALERT_CHANNEL" "니노가 죽어서 자동 재시작했어! (tmux 세션 없음)" 2>/dev/null || true
    exit 0
fi

# Check 2: tmux pane 안에 프로세스가 살아있는지
PANE_PID=$(tmux list-panes -t "$SESSION" -F '#{pane_pid}' 2>/dev/null | head -1)
if [ -z "$PANE_PID" ] || ! kill -0 "$PANE_PID" 2>/dev/null; then
    log "DEAD: pane process gone (PID: $PANE_PID). Respawning..."
    "$SCRIPT_DIR/restart-nino.sh" >> "$LOG" 2>&1
    $DISCORD_SEND -c "$ALERT_CHANNEL" "니노 프로세스가 죽어서 자동 재시작했어! (pane 프로세스 없음)" 2>/dev/null || true
    exit 0
fi

# Check 3: Claude 프로세스가 D state(uninterruptible sleep)인지
CLAUDE_PID=$(pgrep -P "$PANE_PID" -f "claude" 2>/dev/null | head -1 || true)
if [ -n "$CLAUDE_PID" ]; then
    STATE=$(awk '/^State:/{print $2}' /proc/$CLAUDE_PID/status 2>/dev/null || echo "?")
    if [ "$STATE" = "D" ]; then
        log "FROZEN: Claude PID $CLAUDE_PID in D state. Restarting..."
        "$SCRIPT_DIR/restart-nino.sh" >> "$LOG" 2>&1
        $DISCORD_SEND -c "$ALERT_CHANNEL" "니노가 얼어서 자동 재시작했어! (프로세스 D state)" 2>/dev/null || true
        exit 0
    fi
fi

# 정상
exit 0
