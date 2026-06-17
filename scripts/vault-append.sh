#!/usr/bin/env bash
# vault-append.sh — 대화 중 위키에 정보 축적 (주제별 한 파일에 누적)
# Usage: vault-append.sh --topic "도쿄 여행" --category travel --content "새로운 정보..."
# Usage: vault-append.sh --topic "도쿄 여행" --category travel --file /tmp/content.md
#
# 동작:
#   1. wiki/카테고리/ 에서 기존 노트 검색 (제목 매칭)
#   2. 있으면 → 기존 노트에 내용 추가 (AI가 자연스럽게 병합)
#   3. 없으면 → 새 노트 생성
#   4. git commit + push

set -euo pipefail

VAULT_DIR="${VAULT_DIR:-$HOME/obsidian-vault}"
WIKI_DIR="$VAULT_DIR/wiki"
BOT_DIR="${BOT_DIR:-$HOME/discord-bot-nino}"
LOG_FILE="$BOT_DIR/logs/vault-append.log"
VAULT_LOG="$VAULT_DIR/log.md"
CLAUDE_BIN="${CLAUDE_BIN:-claude}"

TOPIC=""
CATEGORY=""
CONTENT=""
CONTENT_FILE=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --topic) TOPIC="$2"; shift 2 ;;
        --category) CATEGORY="$2"; shift 2 ;;
        --content) CONTENT="$2"; shift 2 ;;
        --file) CONTENT_FILE="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        *) echo "Unknown: $1"; exit 1 ;;
    esac
done

if [[ -z "$TOPIC" ]] || [[ -z "$CATEGORY" ]]; then
    echo "Usage: vault-append.sh --topic '주제' --category 카테고리 --content '내용' [--file 파일]"
    exit 1
fi

if [[ -n "$CONTENT_FILE" ]] && [[ -f "$CONTENT_FILE" ]]; then
    CONTENT=$(cat "$CONTENT_FILE")
fi

if [[ -z "$CONTENT" ]]; then
    echo "ERROR: --content or --file required"
    exit 1
fi

touch "$LOG_FILE" 2>/dev/null || true

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# vault/log.md audit trail — 사람이 읽는 vault 행동 기록 (ingest와 통일)
vault_log() {
    $DRY_RUN && return 0
    [[ -f "$VAULT_LOG" ]] || printf '# 🪵 Vault Action Log\n\n> 에이전트 행동 감사 추적. 자동 append.\n\n' > "$VAULT_LOG"
    echo "- [$(date '+%Y-%m-%d %H:%M')] $1" >> "$VAULT_LOG"
}

# 토픽명 → 파일명 변환 (공백→하이픈, 소문자)
topic_to_filename() {
    echo "$1" | sed 's/ /-/g' | tr -cd '가-힣a-zA-Z0-9\-' 2>/dev/null || echo "$1" | sed 's/ /-/g'
}

# 기존 wiki에서 매칭되는 노트 찾기
find_existing_note() {
    local slug
    slug=$(topic_to_filename "$TOPIC")
    local cat_dir="$WIKI_DIR/$CATEGORY"

    # 정확한 파일명 매칭
    if [[ -f "$cat_dir/${slug}.md" ]]; then
        echo "$cat_dir/${slug}.md"
        return
    fi

    # 부분 매칭 (파일명에 토픽 키워드 포함)
    local keywords
    keywords=$(echo "$TOPIC" | sed 's/ /\n/g')
    for f in "$cat_dir"/*.md; do
        [[ -f "$f" ]] || continue
        [[ "$(basename "$f")" == "README.md" ]] && continue
        local fname
        fname=$(basename "$f" .md)
        local match_count=0
        local total=0
        while IFS= read -r kw; do
            [[ ${#kw} -lt 2 ]] && continue
            ((total++))
            if echo "$fname" | grep -qi "$kw"; then
                ((match_count++))
            fi
        done <<< "$keywords"
        # 키워드 절반 이상 매칭이면 같은 노트로 판단
        if [[ $total -gt 0 ]] && [[ $match_count -ge $((total / 2 + 1)) ]]; then
            echo "$f"
            return
        fi
    done

    echo ""
}

# 기존 위키 노트 목록 (링크용)
get_existing_wiki_titles() {
    find "$WIKI_DIR" -name '*.md' ! -name 'README.md' -exec basename {} .md \; 2>/dev/null | sort | tr '\n' ', '
}

mkdir -p "$WIKI_DIR/$CATEGORY"

existing_note=$(find_existing_note)
existing_titles=$(get_existing_wiki_titles)
slug=$(topic_to_filename "$TOPIC")
target_file="$WIKI_DIR/$CATEGORY/${slug}.md"

# --dry-run: 실제 LLM 호출/쓰기/commit 없이 계획만 출력하고 종료
if $DRY_RUN; then
    if [[ -n "$existing_note" ]]; then
        echo "[dry-run] APPEND 계획: '$TOPIC' → 기존 노트 $(echo "$existing_note" | sed "s|$VAULT_DIR/||") (병합 전 .bak 백업)"
    else
        echo "[dry-run] CREATE 계획: '$TOPIC' → 새 노트 wiki/$CATEGORY/${slug}.md"
    fi
    echo "[dry-run] 파일/커밋 변경 없음."
    exit 0
fi

prompt_file=$(mktemp /tmp/vault-append-XXXXXX.txt)

if [[ -n "$existing_note" ]]; then
    # 기존 노트에 병합
    existing_content=$(cat "$existing_note")
    target_file="$existing_note"
    log "APPEND: '$TOPIC' → $(basename "$existing_note")"

    cat > "$prompt_file" <<PROMPT
You are an LLM Wiki editor. Merge the NEW INFORMATION into the EXISTING wiki note below.

RULES:
- Keep the existing YAML frontmatter, update 'updated' date to $(date '+%Y-%m-%d')
- Integrate new info into the appropriate section (don't just append at the bottom)
- If the new info relates to an existing section, merge it there
- If it's a new subtopic, add a new section
- Maintain [[links]] and add new ones if relevant
- Keep the note well-organized and concise — no duplication
- Output ONLY the complete updated markdown note. No explanations, no code block wrapping.
- Write in Korean

EXISTING WIKI NOTES (for linking): ${existing_titles}

EXISTING NOTE:
${existing_content}

NEW INFORMATION TO MERGE:
${CONTENT}
PROMPT

else
    # 새 노트 생성
    log "CREATE: '$TOPIC' → wiki/$CATEGORY/${slug}.md"

    cat > "$prompt_file" <<PROMPT
You are an LLM Wiki engine. Create a new structured Obsidian wiki note from the information below.

OUTPUT FORMAT:
---
title: "${TOPIC}"
tags: [relevant tags]
category: ${CATEGORY}
created: $(date '+%Y-%m-%d')
updated: $(date '+%Y-%m-%d')
---

# ${TOPIC}

(organized content)

## See also
- [[related notes]]

RULES:
- Output ONLY the raw markdown note. No explanations, no code block wrapping.
- Tags use #category/detail format
- Link to existing wiki notes if relevant: ${existing_titles}
- Write in Korean

INFORMATION:
${CONTENT}
PROMPT

fi

ingest_prompt=$(cat "$prompt_file")

output=$(source ~/.nvm/nvm.sh && cd /tmp && "$CLAUDE_BIN" -p "$ingest_prompt" --model claude-sonnet-4-6 --dangerously-skip-permissions 2>/dev/null) || {
    log "ERROR: Claude failed for '$TOPIC'"
    rm -f "$prompt_file"
    exit 1
}
rm -f "$prompt_file"

# 코드블록 래핑 제거
output=$(echo "$output" | sed '/^```markdown$/d; /^```$/d')

if [[ -z "$output" ]] || [[ ${#output} -lt 50 ]]; then
    log "ERROR: Output too short for '$TOPIC'"
    exit 1
fi

# 기존 노트 덮어쓰기 전 백업 (.bak) — 잘못된 병합 복구용
if [[ -f "$target_file" ]]; then
    cp "$target_file" "${target_file}.bak"
    log "BACKUP: ${target_file}.bak"
fi

echo "$output" > "$target_file"
log "SAVED: $target_file"
rel_path=$(echo "$target_file" | sed "s|$VAULT_DIR/||")
if [[ -n "$existing_note" ]]; then
    vault_log "병합(append): '$TOPIC' → [[${slug}]] ($rel_path)"
else
    vault_log "생성(create): '$TOPIC' → [[${slug}]] ($rel_path)"
fi

# 로컬 memory에 참조 등록
tags=$(echo "$output" | grep -oP 'tags:\s*\[([^\]]*)\]' | sed 's/tags:\s*\[//;s/\]//' | tr -d '#' || echo "")
wiki_rel_path=$(echo "$target_file" | sed "s|$VAULT_DIR/||")
"$BOT_DIR/scripts/wiki-register-memory.sh" \
    --title "$TOPIC" \
    --wiki-path "$wiki_rel_path" \
    --tags "$tags" 2>/dev/null && log "MEMORY: registered wiki ref for '$TOPIC'" || true

# Git sync (.bak 백업은 로컬 복구용 — 커밋 제외)
cd "$VAULT_DIR"
if ! git diff --quiet || ! git diff --cached --quiet || [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
    git add -A
    git reset -q -- '*.bak' 2>/dev/null || true
    git -c user.name="Nino" -c user.email="nino@yaksu.house" commit -m "wiki: ${TOPIC} 업데이트 ($(date '+%Y-%m-%d %H:%M'))" 2>/dev/null || true
    git push origin main 2>/dev/null && log "Git push done" || log "Git push failed"
fi

log "DONE: '$TOPIC'"
