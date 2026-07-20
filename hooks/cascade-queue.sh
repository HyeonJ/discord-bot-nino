#!/bin/bash
# cascade-queue.sh — 기억 문서 수정 시 백링크 문서를 검토 큐에 적재 (v2 씨앗)
# PostToolUse(Write|Edit) hook. 니노 [[링크]] 밀도(현 7%)가 차오르면 자동 실효 — 지금은 빈 그래프라 부작용0.
# stdin: hook JSON (tool_input.file_path)
# 룬드 assistant hooks/cascade-queue.sh의 니노 적응판 (경로만 니노용, 재발명 X)
set -uo pipefail
WIKI="$HOME/.claude/projects/-home-bpx27-discord-bot-nino/memory"   # 니노 [[링크]] 그래프가 사는 곳(auto-memory)
QUEUE="$HOME/discord-bot-nino/memory/state/cascade-queue.md"

FILE=$(python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))" 2>/dev/null)
case "$FILE" in
  "$WIKI"/MEMORY.md) exit 0 ;;   # 인덱스는 고빈도 파일 — 백링크 검토 유발 대상 아님 (룬드 큐 노이즈 교훈)
  "$WIKI"/*.md) ;;
  *) exit 0 ;;
esac
BASE=$(basename "$FILE" .md)
mkdir -p "$(dirname "$QUEUE")"
# 이 문서를 [[백링크]]하는 다른 문서 검색 (자기 자신·큐 파일 제외)
grep -rlF "[[${BASE}]]" "$WIKI" --include="*.md" 2>/dev/null | grep -v "$(basename "$QUEUE")\|$FILE" | while read -r ref; do
  LINE="$(date '+%F %H:%M')\t${BASE} 변경 → 검토: ${ref#$WIKI/}"
  grep -qF "검토: ${ref#$WIKI/}" "$QUEUE" 2>/dev/null || printf '%b\n' "$LINE" >> "$QUEUE"
done
exit 0
