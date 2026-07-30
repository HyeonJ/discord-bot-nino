#!/bin/bash
# CLAUDE.md 수정 시 private gist 자동 업데이트
# Hook: PostToolUse (Edit, Write) 에서 ~/.claude/CLAUDE.md 변경 감지

GIST_ID="fea0ac8a4f5ce780a494cdf9d089e9c4"
CLAUDE_MD="$HOME/.claude/CLAUDE.md"

# stdin에서 hook 데이터 읽기
INPUT=$(cat)

# 파일 경로 추출
FILE_PATH=$(echo "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null)

# ~/.claude/CLAUDE.md 수정인 경우에만 동기화
if [ "$FILE_PATH" = "$CLAUDE_MD" ]; then
    gh gist edit "$GIST_ID" "$CLAUDE_MD" >/dev/null 2>&1 &
fi
