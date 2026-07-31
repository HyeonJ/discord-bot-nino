#!/usr/bin/env bash
# vault-audit.sh — wiki 건강검진 (LLM 없이 결정적 검사)
# Usage: vault-audit.sh [--stale-days N]
#
# ⚠️ Linux/bash 4+ 전용 (GNU date·grep -P·mapfile 사용). macOS(BSD)에서는 시작 시 에러로 중단.
#
# 검사 (정규식/파서 기반, false positive 적음):
#   1. broken wikilink — [[X]] 인데 X.md 페이지가 없음
#   2. duplicate       — 같은 slug(파일명)이 여러 카테고리에 중복
#   3. stale 후보      — frontmatter updated(없으면 created)가 N일 이상 지남
# 산출물: vault 루트 audit-report.md + stdout 요약
# 수정은 하지 않는다(진단만). 수정은 사람 승인 후 별도.
# audit-report.md는 git commit 하지 않는다 (cron 반복 시 노이즈 commit 방지 — 호출측이 필요하면 별도 처리).

set -euo pipefail

# GNU 도구 가드 — BSD(macOS)에서 silently fail(stale 0건 오인) 방지
if ! date --version 2>/dev/null | grep -q GNU; then
    echo "ERROR: GNU date가 필요합니다 (Linux/WSL 전용). macOS(BSD date)에서는 동작하지 않습니다." >&2
    exit 1
fi

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
    # 🔴 `grep -oP` 를 쓰지 않는다 (2026-07-31 실측). -P 가 없는 grep 이면 rc=2 로 죽고
    #   `|| true` 가 그걸 **빈 입력**으로 접어 *"깨진 링크 0"* 이 된다 — 실제로 1건인 픽스처에서
    #   0 이 나왔고 rc 도 0 이었다. 룬드 위키 사고와 **증상이 똑같다**(원인만 다르다).
    #   ⚠️ GNU date 가드(18행)가 이 축을 안 지켜준다 — date 는 GNU 인데 grep 만 갈리는 기계가
    #     실재한다(같은 날 실측된 `ugrep` 그림자). 가드가 있어도 축이 하나면 옆이 뚫린다.
    done < <(grep -o '\[\[[^]]*\]\]' "$f" 2>/dev/null | sed 's/^\[\[//; s/\]\]$//' || true)
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
# 🔑 **못 잰 것을 0 으로 접지 않는다.** 아래 세 자리가 전부 실패를 *"해당 없음"* 으로 접고 있었고,
#   진짜 답이 1건인 픽스처에서 `stale 후보 0 · rc=0` 이 나왔다. 사람이 읽는 리포트라
#   시험과 달리 나중에 터질 자리가 없다 — 읽고 안심하면 끝이다.
#   ⇒ 날짜가 있는데 못 읽은 것은 `undet_list` 로 세어 리포트에 **따로** 싣는다.
undet_list=()
# 기준선을 못 만들면 stale 은 **숫자를 내밀면 안 된다.** `0` 은 "없다"로 읽히는데 실제로는
#   아무것도 안 본 것이다. 아래 리포트에서 `?` 로 낸다.
stale_undetermined=0

# 프론트매터 날짜 추출 — `grep -oP` 대신 POSIX sed (위 63행과 같은 이유)
fm_date() { sed -n "s/^$2:[[:space:]]*\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\).*/\1/p" "$1" 2>/dev/null | head -1; }

threshold=$(date -d "-${STALE_DAYS} days" +%s 2>/dev/null || echo "")
if [[ -z "$threshold" ]]; then
    # 기준선 자체를 못 만들면 stale 판정은 **전부** 판정 불가다. 0 으로 접으면
    # "오래된 노트가 없다"로 읽히는데, 실제로는 아무것도 안 본 것이다.
    undet_list+=("stale 기준선(-${STALE_DAYS}일)을 계산 못 했다 — 이 절은 아무것도 안 쟀다")
    stale_undetermined=1
else
    for f in "${NOTES[@]}"; do
        rel=$(echo "$f" | sed "s|$VAULT_DIR/||")
        d=$(fm_date "$f" updated)
        [[ -z "$d" ]] && d=$(fm_date "$f" created)
        [[ -z "$d" ]] && continue          # 날짜 자체가 없는 노트는 대상이 아니다(못 잰 게 아니다)
        ts=$(date -d "$d" +%s 2>/dev/null || echo "")
        if [[ -z "$ts" ]]; then
            undet_list+=("$rel (날짜 '$d' 를 못 읽었다)")
            continue
        fi
        if [[ "$ts" -lt "$threshold" ]]; then
            stale_list+=("$rel (updated: $d)")
        fi
    done
fi

# 리포트 작성
now=$(date '+%Y-%m-%d %H:%M')
{
    echo "# 🩺 Wiki Audit Report"
    echo ""
    echo "> 결정적 검사(LLM 없음). 생성: $now · stale 기준: ${STALE_DAYS}일"
    echo ""
    # 🔑 판정 불가는 **0 일 때 안 붙인다** — 없는 걸 시끄럽게 만들지 않는다.
    #   대신 있을 때는 요약 첫 줄에 실어야 한다. 아래 절에만 있으면 요약만 읽는 사람이 못 본다.
    undet_note=""
    [[ ${#undet_list[@]} -gt 0 ]] && undet_note=" · ⚠️ 판정 불가 ${#undet_list[@]}"
    stale_disp="${#stale_list[@]}"
    [[ $stale_undetermined -eq 1 ]] && stale_disp="?"
    echo "**요약**: 깨진 링크 ${#broken_list[@]} · 중복 ${#dup_list[@]} · stale 후보 ${stale_disp}${undet_note}"
    echo ""
    echo "## 🔗 깨진 wikilink (${#broken_list[@]})"
    if [[ ${#broken_list[@]} -eq 0 ]]; then echo "- 없음"; else printf -- '- %s\n' "${broken_list[@]}"; fi
    echo ""
    echo "## 👯 중복 slug (${#dup_list[@]})"
    if [[ ${#dup_list[@]} -eq 0 ]]; then echo "- 없음"; else printf -- '- %s\n' "${dup_list[@]}"; fi
    echo ""
    echo "## 🕰️ stale 후보 (${stale_disp})"
    if [[ ${#stale_list[@]} -eq 0 ]]; then echo "- 없음"; else printf -- '- %s\n' "${stale_list[@]}"; fi
    if [[ ${#undet_list[@]} -gt 0 ]]; then
        echo ""
        echo "## ⚠️ 판정 불가 (${#undet_list[@]})"
        echo "> 통과도 실패도 아니다 — **못 쟀다.** 위 숫자는 이만큼 덜 본 결과다."
        printf -- '- %s\n' "${undet_list[@]}"
    fi
} > "$REPORT"

echo "AUDIT: broken(깨진링크)=${#broken_list[@]}, duplicate(중복)=${#dup_list[@]}, stale=${stale_disp}${undet_note} → $REPORT"
