#!/usr/bin/env bash
# vault-audit-llm.sh — wiki 모순 검사 (제한적 LLM audit)
# Usage: vault-audit-llm.sh [--days N]
#
# ⚠️ Linux/bash 4+ 전용 (GNU date·grep -P·mapfile).
#
# 전체 스캔이 아니라 비용·오탐을 줄이기 위해:
#   - 최근 N일(기본 7) 변경된 노트만 대상
#   - 그중 같은 태그를 공유하는 묶음(2개 이상)에 대해서만 LLM 모순 판정
# 산출물: vault 루트 llm-audit-report.md + stdout 요약. 진단만(수정 X).
# llm-audit-report.md는 git commit 하지 않는다 (cron 노이즈 방지).

set -euo pipefail

VAULT_DIR="${VAULT_DIR:-$HOME/obsidian-vault}"
WIKI_DIR="$VAULT_DIR/wiki"
CLAUDE_BIN="${CLAUDE_BIN:-claude}"
REPORT="$VAULT_DIR/llm-audit-report.md"
DAYS=7

while [[ $# -gt 0 ]]; do
    case "$1" in
        --days) DAYS="$2"; shift 2 ;;
        *) echo "Unknown: $1"; exit 1 ;;
    esac
done

if ! date --version 2>/dev/null | grep -q GNU; then
    echo "ERROR: GNU 환경 필요 (Linux/WSL 전용)." >&2
    exit 1
fi
[[ -d "$WIKI_DIR" ]] || { echo "no wiki dir: $WIKI_DIR" >&2; exit 1; }

# 1. 최근 N일 변경된 노트
mapfile -t RECENT < <(find "$WIKI_DIR" -type f -name '*.md' ! -name 'README.md' -mtime "-${DAYS}" 2>/dev/null | sort)

# 노트에서 frontmatter tags 추출 (#travel/japan 형식)
# 로케일 의존 문자클래스([가-힣])는 collation 에러를 내므로 쓰지 않는다 — 빈 줄만 거른다.
extract_tags() {
    grep -m1 -oP '^tags:\s*\[\K[^\]]+' "$1" 2>/dev/null \
        | tr ',' '\n' | sed 's/^ *//; s/ *$//' | grep -v '^$' || true
}

# 2. 태그 → 변경노트 목록
declare -A TAG_NOTES
for f in "${RECENT[@]}"; do
    [[ -z "$f" ]] && continue
    while IFS= read -r tag; do
        [[ -z "$tag" ]] && continue
        TAG_NOTES["$tag"]+="${f}"$'\n'
    done < <(extract_tags "$f")
done

findings=()
checked_groups=0

# 3. 같은 태그 묶음(2개 이상)에 LLM 모순 판정
for tag in "${!TAG_NOTES[@]}"; do
    mapfile -t group < <(printf '%s' "${TAG_NOTES[$tag]}" | sort -u | grep -v '^$')
    [[ ${#group[@]} -lt 2 ]] && continue
    ((checked_groups++)) || true

    # 묶음 노트 내용 합치기
    bundle=""
    for f in "${group[@]}"; do
        rel=$(echo "$f" | sed "s|$VAULT_DIR/||")
        bundle+="### ${rel}"$'\n'"$(cat "$f")"$'\n\n'
    done

    prompt="다음은 태그 '${tag}'를 공유하는 wiki 노트들이다. 노트 사이에 '사실이 서로 모순되는 부분'이 있는지만 판정하라.
- 시간 조건이 다른 것(예: 2025년 vs 2026년 기준)은 모순이 아니다.
- 모순이 있으면 어떤 노트의 어떤 내용이 충돌하는지 구체적으로.
- 모순이 없으면 정확히 '모순 없음'이라고만 답하라.
한국어로 간결히.

${bundle}"

    verdict=$(source ~/.nvm/nvm.sh 2>/dev/null; cd /tmp && "$CLAUDE_BIN" -p "$prompt" --model claude-sonnet-4-6 --dangerously-skip-permissions 2>/dev/null || echo "(판정 실패)")
    verdict=$(echo "$verdict" | sed '/^```/d')

    # "모순 없음" 뒤 마침표/공백 허용 (LLM이 '모순 없음.' 등으로 답해도 오탐 안 나게)
    if ! echo "$verdict" | grep -qE '^모순 없음[.[:space:]]*$'; then
        findings+=("[$tag] ${verdict}")
    fi
done

# 4. 리포트
now=$(date '+%Y-%m-%d %H:%M')
{
    echo "# 🧠 Wiki LLM Audit Report (모순 검사)"
    echo ""
    echo "> 최근 ${DAYS}일 변경 + 같은 태그 묶음만 검사. 생성: $now"
    echo ""
    echo "**요약**: 검사한 태그 묶음 ${checked_groups}개 · 모순 의심 ${#findings[@]}건"
    echo ""
    echo "## ⚠️ 모순 의심 (${#findings[@]})"
    if [[ ${#findings[@]} -eq 0 ]]; then
        echo "- 없음"
    else
        printf -- '- %s\n\n' "${findings[@]}"
    fi
} > "$REPORT"

echo "LLM AUDIT: 묶음 ${checked_groups}개 검사, 모순 의심 ${#findings[@]}건 → $REPORT"
