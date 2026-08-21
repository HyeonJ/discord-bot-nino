#!/usr/bin/env bash
# vault-sync.sh — 로컬 memory 수정 시 vault nino/에 동기화
# Claude Code PostToolUse hook (Edit|Write 매처)
#
# 동작:
#   1. 수정된 파일이 memory/ 경로인지 확인
#   2. vault nino/의 적절한 하위 폴더에 복사
#   3. git push는 별도 cron으로 (1시간마다)

MEMORY_DIR="$HOME/.claude/projects/-home-bpx27-discord-bot-nino/memory"
VAULT_NINO="$HOME/obsidian-vault/nino"
LOG_FILE="$HOME/discord-bot-nino/logs/vault-sync.log"

# stdin에서 hook JSON 읽기
input=$(cat)

# 수정된 파일 경로 추출
file_path=$(echo "$input" | grep -oP '"file_path"\s*:\s*"([^"]*)"' | head -1 | sed 's/.*"file_path"\s*:\s*"//;s/"$//')

# memory 경로가 아니면 스킵
if [[ -z "$file_path" ]] || [[ "$file_path" != *"/memory/"* && "$file_path" != *"/memory/MEMORY.md"* ]]; then
    exit 0
fi

# vault nino/ 존재 확인
if [[ ! -d "$VAULT_NINO" ]]; then
    exit 0
fi

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE" 2>/dev/null
}

filename=$(basename "$file_path")

# 파일 분류 → vault 하위 폴더 결정
get_vault_dest() {
    local fname="$1"
    case "$fname" in
        feedback_*) echo "$VAULT_NINO/feedback/$fname" ;;
        project_*) echo "$VAULT_NINO/project/$fname" ;;
        ref_*) echo "$VAULT_NINO/reference/$fname" ;;
        research_*|research/*) echo "$VAULT_NINO/research/$fname" ;;
        skill_*) echo "$VAULT_NINO/skill/$fname" ;;
        user_*) echo "$VAULT_NINO/user/$fname" ;;
        MEMORY.md) echo "$VAULT_NINO/INDEX.md" ;;
        session-context-snapshot.md) echo "$VAULT_NINO/$fname" ;;
        current-tasks.md) echo "$VAULT_NINO/$fname" ;;
        compression-log.md) echo "$VAULT_NINO/$fname" ;;
        *) echo "$VAULT_NINO/$fname" ;;
    esac
}

dest=$(get_vault_dest "$filename")

# research/ 하위 폴더 처리
if [[ "$file_path" == */memory/research/* ]]; then
    subfname=$(echo "$file_path" | sed "s|.*/memory/research/||")
    dest="$VAULT_NINO/research/$subfname"
fi

# 대상 디렉토리 생성
dest_dir=$(dirname "$dest")
mkdir -p "$dest_dir" 2>/dev/null

# 파일 복사
if [[ -f "$file_path" ]]; then
    cp "$file_path" "$dest" 2>/dev/null && log "SYNC: $filename → $dest"
fi

exit 0
