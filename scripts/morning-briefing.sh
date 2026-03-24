#!/bin/bash
# 매일 아침 Darren 채널에 오늘의 할 일 브리핑 전송
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VAULT_SCHEDULE="/mnt/c/Users/bpx27/OneDrive/문서/Vault/schedule"
CHANNEL_ID="1480593132511826092"

TODAY=$(TZ=Asia/Seoul date +%Y-%m-%d)
DAY_OF_WEEK=$(TZ=Asia/Seoul date +%u)  # 1=Mon ... 7=Sun
MONTH=$(TZ=Asia/Seoul date +%-m)
DAY=$(TZ=Asia/Seoul date +%-d)

# 해당 날짜의 주차 스케줄 파일 찾기 (월 기준)
YEAR=$(TZ=Asia/Seoul date +%Y)
MONTH_DIR="$VAULT_SCHEDULE/${YEAR}년_${MONTH}월"

# 날짜가 포함된 일간 파일 찾기
SCHEDULE_FILE=""
for f in "$MONTH_DIR"/2026_일간_*.md; do
  [[ -f "$f" ]] || continue
  # 파일명에서 날짜 범위 추출 (예: W11_(3.9-3.13))
  BASENAME=$(basename "$f")
  RANGE=$(echo "$BASENAME" | grep -oP '\(\K[^)]+')  # e.g. 3.9-3.13
  START_M=$(echo "$RANGE" | cut -d. -f1)
  START_D=$(echo "$RANGE" | cut -d. -f2 | cut -d- -f1)
  END_D=$(echo "$RANGE" | cut -d- -f2 | cut -d. -f2)
  if [[ "$MONTH" -eq "$START_M" && "$DAY" -ge "$START_D" && "$DAY" -le "$END_D" ]]; then
    SCHEDULE_FILE="$f"
    break
  fi
done

if [[ -z "$SCHEDULE_FILE" ]]; then
  source ~/.nvm/nvm.sh
  "$BOT_DIR/src/discord-send" -c "$CHANNEL_ID" "오늘($TODAY) 스케줄 파일을 찾지 못했어ㅠ Vault에 파일 있는지 확인해줘"
  exit 0
fi

# 오늘 요일 이름 (파일 내 섹션명 매칭용)
DAY_NAMES=("" "월요일" "화요일" "수요일" "목요일" "금요일" "토요일" "일요일")
DAY_NAME="${DAY_NAMES[$DAY_OF_WEEK]}"
DAY_LABEL="$DAY_NAME (${MONTH}/${DAY})"

# 서브 Claude로 오늘 섹션 읽고 브리핑 전송
source ~/.nvm/nvm.sh
env -u CLAUDECODE claude -p "
다음 파일을 읽고, '$DAY_LABEL' 섹션의 할 일들을 파악해.
파일: $SCHEDULE_FILE

그 다음 discord-send 도구로 채널 $CHANNEL_ID 에 아래 형식으로 메시지를 보내줘:
- 가볍고 친근한 아침 인사 (1줄)
- 오늘의 할 일 리스트 (체크 안 된 것들 위주로, 업무/퇴근후 구분)
- 오늘 제일 먼저 할 일 리마인드 강조

말투는 니노처럼 반말 카톡체로. 너무 길지 않게.
" --model claude-haiku-4-5-20251001 --dangerously-skip-permissions 2>/dev/null || true
