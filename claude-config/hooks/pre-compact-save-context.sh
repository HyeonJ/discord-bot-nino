#!/bin/bash
# PreCompact Hook — 압축 직전에 중요한 세션 컨텍스트를 메모리에 저장
# Fires on: /compact (manual) or auto-compaction

MEMORY_DIR="$HOME/.claude/projects/-home-bpx27-discord-bot-nino/memory"
PROJ_DIR="$HOME/discord-bot-nino"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

mkdir -p "$MEMORY_DIR"

# Read hook input from stdin
INPUT=$(cat)
TRIGGER=$(echo "$INPUT" | jq -r '.trigger // "auto"' 2>/dev/null || echo "auto")

# 1. Log compression event
LOG="$MEMORY_DIR/compression-log.md"
if [ ! -f "$LOG" ]; then
  echo "# Context Compression Log" > "$LOG"
  echo "" >> "$LOG"
fi
echo "- \`$TIMESTAMP\` — $TRIGGER compression" >> "$LOG"

# 2. Save session context snapshot
{
  echo "---"
  echo "name: session-context-snapshot"
  echo "description: 마지막 압축 직전 자동 저장된 세션 컨텍스트 — read when: 세션 압축 후 복구"
  echo "type: project"
  echo "---"
  echo ""
  echo "# Session Context Snapshot"
  echo "**마지막 저장**: $TIMESTAMP ($TRIGGER compression)"
  echo ""
  echo "## 백그라운드 프로세스"
  # List relevant background processes
  ps aux 2>/dev/null | grep -E "(of-download|agent-browser|cdp-proxy|record-drm)" | grep -v grep | while read line; do
    echo "- \`$(echo "$line" | awk '{for(i=11;i<=NF;i++) printf "%s ", $i; print ""}')\`"
  done
  echo ""
  echo "## Git 상태"
  cd "$PROJ_DIR" 2>/dev/null && echo "- Branch: $(git branch --show-current 2>/dev/null)"
  echo ""
  echo "## 활성 tmux 세션"
  tmux list-sessions 2>/dev/null | while read line; do
    echo "- \`$line\`"
  done
  echo ""
  echo "## 최근 로그 (OF 다운로드)"
  for logfile in /tmp/of-*.log; do
    [ -f "$logfile" ] || continue
    account=$(basename "$logfile" .log | sed 's/of-//')
    last=$(tail -1 "$logfile" 2>/dev/null)
    echo "- **$account**: $last"
  done
} > "$MEMORY_DIR/session-context-snapshot.md"

exit 0
