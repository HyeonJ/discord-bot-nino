#!/bin/bash
# lint-memory.sh — 기억 위키 건강검사 v2 (봇 공통 — 12종)
# 자동 수정 없음 — 보고만. idle 타임 또는 주 1회 실행.
# 검사: 인덱스 고아/깨진 링크, description 품질, 위키링크, 내용 분기, 스테일, CRLF
set -uo pipefail

# 봇 중립: 경로는 env로 (룬드/니노/하루 공용 — 계약 №1·3 구현체)
WIKI="${MEMORY_WIKI_DIR:-$HOME/Assistant/memory}"
AUTO="${MEMORY_AUTO_DIR:-$HOME/.claude/projects/-Users-klaude-Assistant/memory}"
YAKSU="${MEMORY_SHARED_DIR:-$HOME/yaksu-shared-data}"
ISSUES=0

section() { echo; echo "== $1 =="; }
issue() { echo "  ⚠️  $1"; ISSUES=$((ISSUES + 1)); }

section "1. auto-memory 인덱스 고아 (MEMORY.md 미등재)"
(cd "$AUTO" && for f in *.md; do
  [[ "$f" == "MEMORY.md" ]] && continue
  grep -q "$f" MEMORY.md || issue "고아: $f"
done)

section "2. 인덱스 깨진 링크 (등재됐는데 파일 없음)"
(cd "$AUTO" && grep -oE '\]\(([^)~][^)]*\.md)\)' MEMORY.md | tr -d '()]' | sort -u | while read -r f; do
  [[ -f "$f" ]] || issue "깨진 링크: $f"
done)

section "3. description 품질 (auto-memory, 15자 미만)"
(cd "$AUTO" && for f in *.md; do
  [[ "$f" == "MEMORY.md" ]] && continue
  d=$(grep -m1 "^description:" "$f" | sed 's/^description: *//')
  if [[ -z "$d" ]]; then
    issue "description 없음: $f"
  elif [[ ${#d} -lt 15 ]]; then
    issue "description 빈약(${#d}자): $f"
  fi
done)

section "4. 내용 분기 의심 (동명 파일이 스텁 아닌 채 2곳+)"
for name in $(cat <(ls "$WIKI" 2>/dev/null) <(ls "$AUTO" 2>/dev/null) <(ls "$YAKSU" 2>/dev/null) | grep '\.md$' | sort | uniq -d); do
  count=0; nonstub=""
  for d in "$WIKI" "$AUTO" "$YAKSU"; do
    p="$d/$name"
    [[ -f "$p" ]] || continue
    if ! head -12 "$p" | grep -q "canonical"; then
      count=$((count + 1)); nonstub="$nonstub $d"
    fi
  done
  [[ $count -ge 2 ]] && issue "분기 의심: $name (non-stub ×$count:$nonstub)"
done

section "5. 위키 깨진 [[위키링크]] (memory/ 전체, 코드블록·인라인코드 제외)"
ALL_BASENAMES=$(find "$WIKI" "$AUTO" "$YAKSU" -name "*.md" 2>/dev/null | xargs -n1 basename | sed 's/\.md$//' | sort -u)
ALLOWLIST="page|링크|위키링크|관련페이지|파일명|folder/file|name|their-name"  # 문서 예시 텍스트
find "$WIKI" -name "*.md" -not -path "*/discord-history/*" 2>/dev/null | while read -r f; do
  # 코드 펜스(```) 블록과 인라인 코드(`...`) 제거 후 위키링크 추출
  awk '/^```/{fence=!fence; next} !fence' "$f" | sed 's/`[^`]*`//g'
done | grep -hoE '\[\[[^]#|]+' | sed 's/\[\[//' | grep -vE '^[[:space:]]*($|\$)|:space:|^\.\.\.$' | grep -vxE "$ALLOWLIST" | sort -u | while read -r link; do
  echo "$ALL_BASENAMES" | grep -qxF "$link" || issue "깨진 위키링크: [[$link]]"
done

section "6. 스테일 research (90일+ 미수정, archive 제외 — git 커밋 날짜 기준)"
# mtime은 git pull이 오염시키므로 git log 날짜 사용 (git 밖 파일은 mtime 폴백)
NOW_EPOCH=$(date +%s)
find "$WIKI/research" -maxdepth 1 -name "*.md" 2>/dev/null | while read -r f; do
  last=$(git -C "$WIKI" log -1 --format=%ct -- "${f#$WIKI/}" 2>/dev/null)
  [[ -z "$last" ]] && last=$(stat -f %m "$f" 2>/dev/null || echo "$NOW_EPOCH")
  age_days=$(( (NOW_EPOCH - last) / 86400 ))
  [[ $age_days -gt 90 ]] && issue "${age_days}일 미수정: ${f#$WIKI/}"
done

section "7. CRLF 파일 (니노 스캔 버그 함정)"
for d in "$WIKI" "$AUTO"; do
  grep -rlI $'\r' "$d" --include="*.md" 2>/dev/null | grep -v discord-history | while read -r f; do
    issue "CRLF: ${f/#$HOME/~}"
  done
done

echo
echo "── lint 완료. 발견: 위 ⚠️ 항목들 (자동 수정 없음 — 판단 후 수동 처리)"

section "8. frozen 문서 ADR 블록 (status: frozen인데 ADR 요소 없음)"
grep -rl "^status: frozen" "$WIKI" --include="*.md" 2>/dev/null | while read -r f; do
  grep -q "Superseded-by\|Decision" "$f" || issue "frozen인데 ADR 블록 없음: ${f#$WIKI/}"
done

section "9. [[링크]] 밀도 (cascade 실효 지표 — 목표 30%+)"
TOTAL_MD=$(find "$WIKI" -name "*.md" -not -path "*discord-history*" | wc -l | tr -d ' ')
LINKED_MD=$(grep -rlE '\[\[[^]]+\]\]' "$WIKI" --include="*.md" 2>/dev/null | grep -v discord-history | wc -l | tr -d ' ')
echo "  📊 위키 링크 밀도: ${LINKED_MD}/${TOTAL_MD} ($(( LINKED_MD * 100 / (TOTAL_MD == 0 ? 1 : TOTAL_MD) ))%)"

section "10. 인덱스 예산 (한도 200줄/25KB, 80% 경고)"
IDX="$AUTO/MEMORY.md"
IDX_LINES=$(wc -l < "$IDX" | tr -d ' '); IDX_BYTES=$(wc -c < "$IDX" | tr -d ' ')
echo "  📊 MEMORY.md: ${IDX_LINES}줄 / $(( IDX_BYTES / 1024 ))KB"
[[ $IDX_LINES -gt 160 ]] && issue "인덱스 줄수 80% 초과 (${IDX_LINES}/200)"
[[ $IDX_BYTES -gt 20480 ]] && issue "인덱스 용량 80% 초과 ($(( IDX_BYTES / 1024 ))KB/25KB)"

section "11. cascade 큐 미처리"
CQ="${CASCADE_QUEUE:-$HOME/Assistant/state/cascade-queue.md}"
if [[ -f "$CQ" ]] && [[ -s "$CQ" ]]; then
  issue "cascade 큐에 미검토 $(wc -l < "$CQ" | tr -d ' ')건 — idle 때 백링크 문서 검토 후 큐 비우기"
fi

section "12. 승격 후보 자동 발굴 (read-when이 상시성)"
grep -rl "read_when.*\(항상\|모든\|매번\|언제나\)" "$AUTO" --include="feedback_*.md" 2>/dev/null | while read -r f; do
  issue "승격 후보 (상시성 read-when): $(basename "$f")"
done
