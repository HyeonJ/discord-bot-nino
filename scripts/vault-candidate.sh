#!/usr/bin/env bash
# vault-candidate.sh — 대화에서 발견한 지식을 wiki에 '바로 저장'하지 않고 후보로만 적재
# (Karpathy LLM Wiki compounding의 안전한 MVP — 자동 저장 대신 자동 후보화)
#
# Usage:
#   vault-candidate.sh --topic "주제" --category tech --content "내용" \
#       --source local|discord|dm [--privacy public|private|sensitive] \
#       [--confidence high|medium|low] [--reason "이유"] [--target-note "wiki/tech/노트.md"]
#
# 동작:
#   1. 필수 인자(topic/category/content) + category 유효성 검증
#   2. 프라이버시 가드: source=dm 또는 privacy=sensitive 는 거부 (자동 적재 금지)
#   3. inbox/wiki-candidates/YYYY-MM-DD-<slug>.md 후보 파일 생성 (provenance frontmatter 포함)
#   ※ 후보는 사람/명시 명령으로 검토 후 vault-append.sh로 실제 병합. 이 스크립트는 병합하지 않는다.

set -euo pipefail

VAULT_DIR="${VAULT_DIR:-$HOME/obsidian-vault}"
CAND_DIR="$VAULT_DIR/inbox/wiki-candidates"

VALID_CATEGORIES="travel tech work music gaming general"

TOPIC="" CATEGORY="" CONTENT="" SOURCE=""
PRIVACY="public" CONFIDENCE="" REASON="" TARGET_NOTE=""

err() { echo "ERROR: $1" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --topic) TOPIC="$2"; shift 2 ;;
        --category) CATEGORY="$2"; shift 2 ;;
        --content) CONTENT="$2"; shift 2 ;;
        --source) SOURCE="$2"; shift 2 ;;
        --privacy) PRIVACY="$2"; shift 2 ;;
        --confidence) CONFIDENCE="$2"; shift 2 ;;
        --reason) REASON="$2"; shift 2 ;;
        --target-note) TARGET_NOTE="$2"; shift 2 ;;
        *) err "Unknown option: $1" ;;
    esac
done

# 1. 필수 인자
[[ -n "$TOPIC" ]]    || err "--topic 필수"
[[ -n "$CATEGORY" ]] || err "--category 필수"
[[ -n "$CONTENT" ]]  || err "--content 필수"

# 2. category 유효성
if ! echo " $VALID_CATEGORIES " | grep -q " $CATEGORY "; then
    err "잘못된 category: $CATEGORY (허용: $VALID_CATEGORIES)"
fi

# 3. 프라이버시 가드 — 자동 적재 금지 대상
if [[ "$SOURCE" == "dm" ]]; then
    err "DM 소스는 자동 후보화 금지 (프라이버시). 명시적 '두뇌에 넣어줘'면 vault-append.sh로 직접 저장할 것."
fi
if [[ "$PRIVACY" == "sensitive" ]]; then
    err "privacy=sensitive 는 저장 금지 (민감정보)."
fi

# slug: 공백→-, 경로/제어문자 제거 (한글 보존)
slug=$(echo "$TOPIC" | tr ' ' '-' | tr -d '/\\:*?"<>|')
date_str=$(date '+%Y-%m-%d')
mkdir -p "$CAND_DIR"
out_file="$CAND_DIR/${date_str}-${slug}.md"

{
    echo "---"
    echo "topic: \"$TOPIC\""
    echo "category: $CATEGORY"
    echo "source: ${SOURCE:-local}"
    echo "privacy: $PRIVACY"
    [[ -n "$CONFIDENCE" ]] && echo "confidence: $CONFIDENCE"
    [[ -n "$REASON" ]] && echo "reason: \"$REASON\""
    [[ -n "$TARGET_NOTE" ]] && echo "target_note: \"$TARGET_NOTE\""
    echo "created: $date_str"
    echo "status: candidate"
    echo "---"
    echo ""
    echo "$CONTENT"
} > "$out_file"

echo "CANDIDATE: $out_file"
