#!/usr/bin/env bash
# vault-index.sh — Obsidian Vault의 wiki/ 전체를 스캔해서 루트 index.md(중앙 카탈로그)를 갱신
# Usage: vault-index.sh
#
# 동작:
#   1. wiki/<카테고리>/*.md 의 frontmatter title(없으면 파일명) 수집
#   2. 카테고리별로 [[링크]] 목록 생성
#   3. inbox/processed/ 소스 개수 집계
#   4. 루트 index.md로 출력

set -euo pipefail

VAULT_DIR="${VAULT_DIR:-$HOME/obsidian-vault}"
WIKI_DIR="$VAULT_DIR/wiki"
PROCESSED_DIR="$VAULT_DIR/inbox/processed"
INDEX_FILE="$VAULT_DIR/index.md"

# 파일에서 frontmatter title 추출 (없으면 basename)
get_title() {
    local file="$1"
    local title
    title=$(grep -m1 '^title:' "$file" 2>/dev/null | sed 's/^title:\s*//; s/^"//; s/"$//' || true)
    if [[ -z "$title" ]]; then
        title=$(basename "$file" .md)
    fi
    echo "$title"
}

build_index() {
    local now
    now=$(date '+%Y-%m-%d %H:%M')

    echo "# 📚 약수하우스 LLM Wiki — Index"
    echo ""
    echo "> 자동 생성 카탈로그. 직접 수정하지 말 것 (\`vault-index.sh\`가 덮어씀). 갱신: $now"
    echo ""

    local total_wiki=0
    local total_src=0

    if [[ -d "$WIKI_DIR" ]]; then
        # 카테고리(하위 디렉토리) 순회
        while IFS= read -r catdir; do
            local cat
            cat=$(basename "$catdir")
            local files
            files=$(find "$catdir" -maxdepth 1 -type f -name '*.md' ! -name 'README.md' 2>/dev/null | sort || true)
            [[ -z "$files" ]] && continue

            local count
            # 🔑 `|| echo 0` 은 값을 «두 줄»로 만든다 — `grep -c` 는 0 을 «출력하고» rc=1 을 내므로
            #   기본값이 덧대져 "0\n0" 이 된다. `|| true` 로 rc 만 삼키고 출력은 grep 것을 쓴다.
            count=$(printf '%s\n' "$files" | grep -c . || true)
            count=${count:-0}
            total_wiki=$((total_wiki + count))

            echo "## ${cat} (${count})"
            while IFS= read -r f; do
                [[ -z "$f" ]] && continue
                local title base
                title=$(get_title "$f")
                base=$(basename "$f" .md)
                echo "- [[${base}|${title}]]"
            done <<< "$files"
            echo ""
        done < <(find "$WIKI_DIR" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort)
    fi

    if [[ -d "$PROCESSED_DIR" ]]; then
        total_src=$(find "$PROCESSED_DIR" -maxdepth 1 -type f -name '*.md' 2>/dev/null | grep -c . || true)
        total_src=${total_src:-0}
    fi

    echo "---"
    echo ""
    echo "**합계**: wiki 노트 ${total_wiki}개 · 인제스트된 소스 ${total_src}개"
}

main() {
    if [[ ! -d "$VAULT_DIR" ]]; then
        echo "ERROR: VAULT_DIR not found: $VAULT_DIR" >&2
        exit 1
    fi
    build_index > "$INDEX_FILE"
    echo "index.md updated: $INDEX_FILE"
}

main
