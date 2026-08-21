#!/usr/bin/env bash
# Discord presence hook — 도구 실행 시 자리비움+작업내용 표시
# PreToolUse: idle|⏳ 작업 설명
# PostToolUse: 빈 파일 → 온라인 복귀

STATUS_FILE="/tmp/nino-presence/status"
mkdir -p /tmp/nino-presence
HOOK_EVENT="$CLAUDE_HOOK_EVENT"
TOOL_NAME="$CLAUDE_TOOL_NAME"

# stdin에서 JSON 읽기
INPUT=$(cat)

# discord-send 실행 시 무한루프 방지
if [ "$TOOL_NAME" = "Bash" ]; then
  CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
  case "$CMD" in
    *discord-send*) exit 0 ;;
  esac
fi

case "$HOOK_EVENT" in
  PreToolUse)
    # Bash 도구는 description 필드 사용 (더 구체적)
    DESC=$(echo "$INPUT" | jq -r '.tool_input.description // empty' 2>/dev/null)
    if [ -z "$DESC" ]; then
      DESC="${TOOL_NAME:-작업 중}"
    fi
    echo "idle|⏳ ${DESC}" > "$STATUS_FILE"
    ;;
  PostToolUse|Stop)
    echo -n "" > "$STATUS_FILE"
    ;;
esac
