#!/usr/bin/env bash
# vault-audit.sh — wiki 건강검진 (LLM 없이 결정적 검사)
# Usage: vault-audit.sh [--stale-days N]
#
# 검사 (정규식/파서 기반, false positive 적음):
#   1. broken wikilink — [[X]] 인데 X.md 페이지가 없음
#   2. duplicate       — 같은 slug(파일명)이 여러 카테고리에 중복
#   3. stale 후보      — frontmatter updated(없으면 created)가 N일 이상 지남
# 산출물: vault 루트 audit-report.md + stdout 요약
# 수정은 하지 않는다(진단만). 수정은 사람 승인 후 별도.

set -euo pipefail

VAULT_DIR="${VAULT_DIR:-$HOME/obsidian-vault}"
WIKI_DIR="$VAULT_DIR/wiki"
REPORT="$VAULT_DIR/audit-report.md"
STALE_DAYS=180

while [[ $# -gt 0 ]]; do
    case "$1" in
        --stale-days) STALE_DAYS="$2"; shift 2 ;;
        *) echo "Unknown: $1"; exit 1 ;;
    esac
done

[[ -d "$WIKI_DIR" ]] || { echo "no wiki dir: $WIKI_DIR" >&2; exit 1; }

# 모든 wiki 노트 (README 제외)
mapfile -t NOTES < <(find "$WIKI_DIR" -type f -name '*.md' ! -name 'README.md' 2>/dev/null | sort)

# slug 집합 (파일명에서 .md 제거) — 링크 타겟 존재 확인용
declare -A SLUG_EXISTS
for f in "${NOTES[@]}"; do
    SLUG_EXISTS["$(basename "$f" .md)"]=1
done

broken_list=()
dup_list=()
stale_list=()

# 1. broken wikilink
for f in "${NOTES[@]}"; do
    rel=$(echo "$f" | sed "s|$VAULT_DIR/||")
    # [[X]] 또는 [[X|alias]] 에서 X 추출
    while IFS= read -r link; do
        [[ -z "$link" ]] && continue
        target="${link%%|*}"          # alias 앞부분
        target="${target%%#*}"         # 헤딩 앵커 제거
        target="$(echo "$target" | sed 's/^ *//; s/ *$//')"
        [[ -z "$target" ]] && continue
        if [[ -z "${SLUG_EXISTS[$target]:-}" ]]; then
            broken_list+=("$rel → [[$target]]")
        fi
    done < <(grep -oP '\[\[\K[^\]]+(?=\]\])' "$f" 2>/dev/null || true)
done

# 2. duplicate slug
while IFS= read -r dup; do
    [[ -z "$dup" ]] && continue
    locs=$(printf '%s\n' "${NOTES[@]}" | while read -r f; do
        [[ "$(basename "$f" .md)" == "$dup" ]] && echo "$(echo "$f" | sed "s|$VAULT_DIR/||")"
    done | tr '\n' ' ')
    dup_list+=("$dup → $locs")
done < <(for f in "${NOTES[@]}"; do basename "$f" .md; done | sort | uniq -d)

# 3. stale 후보
threshold=$(date -d "-${STALE_DAYS} days" +%s 2>/dev/null || echo 0)
for f in "${NOTES[@]}"; do
    rel=$(echo "$f" | sed "s|$VAULT_DIR/||")
    d=$(grep -m1 -oP '^updated:\s*\K[0-9]{4}-[0-9]{2}-[0-9]{2}' "$f" 2>/dev/null || true)
    [[ -z "$d" ]] && d=$(grep -m1 -oP '^created:\s*\K[0-9]{4}-[0-9]{2}-[0-9]{2}' "$f" 2>/dev/null || true)
    [[ -z "$d" ]] && continue
    ts=$(date -d "$d" +%s 2>/dev/null || echo "")
    [[ -z "$ts" ]] && continue
    if [[ "$ts" -lt "$threshold" ]]; then
        stale_list+=("$rel (updated: $d)")
    fi
done

# 리포트 작성
now=$(date '+%Y-%m-%d %H:%M')
{
    echo "# 🩺 Wiki Audit Report"
    echo ""
    echo "> 결정적 검사(LLM 없음). 생성: $now · stale 기준: ${STALE_DAYS}일"
    echo ""
    echo "**요약**: 깨진 링크 ${#broken_list[@]} · 중복 ${#dup_list[@]} · stale 후보 ${#stale_list[@]}"
    echo ""
    echo "## 🔗 깨진 wikilink (${#broken_list[@]})"
    if [[ ${#broken_list[@]} -eq 0 ]]; then echo "- 없음"; else printf -- '- %s\n' "${broken_list[@]}"; fi
    echo ""
    echo "## 👯 중복 slug (${#dup_list[@]})"
    if [[ ${#dup_list[@]} -eq 0 ]]; then echo "- 없음"; else printf -- '- %s\n' "${dup_list[@]}"; fi
    echo ""
    echo "## 🕰️ stale 후보 (${#stale_list[@]})"
    if [[ ${#stale_list[@]} -eq 0 ]]; then echo "- 없음"; else printf -- '- %s\n' "${stale_list[@]}"; fi
} > "$REPORT"

echo "AUDIT: broken(깨진링크)=${#broken_list[@]}, duplicate(중복)=${#dup_list[@]}, stale=${#stale_list[@]} → $REPORT"
