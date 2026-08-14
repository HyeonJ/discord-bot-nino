#!/usr/bin/env bash
# pr-precheck.sh — 열린 PR 의 «리뷰 전 상태»를 잰다 (손으로 재던 축 셋을 도구로 옮긴 것)
#
# 🔴 왜 있나: 이 축들은 내 «메모리 파일»에 살고 있었는데 recall 때만 로드돼서,
#   정작 «재는 순간»에 안 떠올랐다. 2026-08-13 하루에 둘을 밟았다:
#     ① `pulls/<n>/files` 로 PR 범위를 재고 남의 PR 을 «틀리게» 막았다(base 시점 기준이라 부푼다)
#     ② 열린 12건 중 `#191 ⊂ #192` 공유 커밋이 며칠째 조용했다(양쪽 다 CI 초록·MERGEABLE 로 보인다)
#   🔑 「반복했나」가 아니라 «고정된 형태인가»가 Ⅳ 의 축이다 — 셋 다 매번 같은 검사라 도구로 간다.
#
# 🔑 이 도구가 «판정»하지 않는 것: 머지해도 되나. 그건 리뷰가 한다.
#   여기서 내는 것은 «리뷰 전에 고쳐질 수 있는 것»뿐이다.
#
# 사용법:
#   scripts/pr-precheck.sh [--repo owner/name]
#   scripts/pr-precheck.sh -h | --help
#
# 옵션:
#   --repo owner/name   대상 레포. 없으면 `gh repo view` 로 정한다
#   -h, --help          이 도움말
#
# 내는 것:
#   ① 순변화      머지하면 실제로 바뀌는 파일 수 — `compare/<base>...<head>`(세 점)
#   ② 공유 커밋   base=main PR 끼리 같은 sha 를 들고 있나 → 머지 «순서»가 생긴다
#   ③ 상태        CI 결론 · mergeable · base
#
# 종료코드:
#   0  잴 것을 다 쟀다 (문제 유무와 무관 — 판정은 사람·리뷰가 한다)
#   2  못 쟀다 (gh 부재·인증·레포 미지정 등)

set -uo pipefail

REPO="${PR_PRECHECK_REPO:-}"
GH="${GH_BIN:-gh}"


while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    # 도움말은 «머리 주석»에서 뽑는다 — 사본을 본문에 또 두면 둘이 갈린다(레포 관례)
    -h|--help) awk 'NR==1{next}
                    /^#/{if(b){printf "%s",b;b=""} sub(/^# ?/,""); print; next}
                    /^[[:space:]]*$/{b=b"\n"; next}
                    {exit}' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "알 수 없는 인자: $1" >&2; exit 2 ;;
  esac
done

command -v "$GH" >/dev/null 2>&1 || { echo "⛔ 판정 불가 — gh 없음" >&2; exit 2; }

if [[ -z "$REPO" ]]; then
  REPO="$("$GH" repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)"
fi
[[ -n "$REPO" ]] || { echo "⛔ 판정 불가 — 레포를 못 정했다 (--repo 로 지정)" >&2; exit 2; }

rows="$("$GH" pr list --repo "$REPO" --state open --limit 100 \
  --json number,baseRefName,headRefName,headRefOid,mergeable \
  --jq '.[] | [.number, .baseRefName, .headRefName, .headRefOid, .mergeable] | @tsv' 2>/dev/null)"
if [[ -z "$rows" ]]; then
  echo "열린 PR 없음 ($REPO)"
  exit 0
fi

echo "== $REPO — 열린 PR 리뷰 전 점검 =="
printf '%-6s %-9s %-11s %-8s %s\n' "PR" "CI" "mergeable" "순변화" "base ← head"

# ── ① 순변화 · ③ 상태
# 🔴 연관배열(`declare -A`)을 쓰지 않는다 — bash 4+ 라 3.2 에서 조용히 깨진다.
#   대신 "번호<TAB>커밋들" 한 줄씩인 파일로 둔다(같은 검색을 3.2 에서도 한다).
CO_FILE="$(mktemp)"; trap 'rm -f "$CO_FILE"' EXIT
commits_of() { awk -F'\t' -v k="$1" '$1==k{print $2; exit}' "$CO_FILE"; }
while IFS=$'\t' read -r n base head oid mergeable; do
  [[ -n "$n" ]] || continue
  ci="$("$GH" api "repos/$REPO/commits/$oid/check-runs" \
        --jq '[.check_runs[] | .conclusion // .status] | join(",")' 2>/dev/null)"
  # 🔴 「런이 없다」를 「빨강 아님」으로 접지 않는다 — 판정 불가는 판정 불가로 낸다
  [[ -z "$ci" ]] && ci="판정불가"
  # 🔴 순변화는 compare(세 점) 로 잰다 — `pulls/<n>/files` 는 base 시점 기준이라 부푼다
  nf="$("$GH" api "repos/$REPO/compare/${base}...${head}" --jq '.files | length' 2>/dev/null)"
  [[ -z "$nf" ]] && nf="?"
  printf '#%-5s %-9s %-11s %-8s %s ← %s\n' "$n" "$ci" "$mergeable" "$nf" "$base" "$head"

  if [[ "$base" == "main" ]]; then
    printf '%s\t%s\n' "$n" "$("$GH" pr view "$n" --repo "$REPO" --json commits \
                        --jq '[.commits[].oid] | join(" ")' 2>/dev/null)" >> "$CO_FILE"
  fi
done <<< "$rows"

# ── ② 공유 커밋 (base=main 끼리만 — squash 가 순서 사고를 만드는 자리)
echo
echo "-- 공유 커밋 (base=main 끼리) --"
shared=0
# 빈 배열은 3.2 + `set -u` 에서 unbound 라 배열 자체를 안 쓴다
keys="$(cut -f1 "$CO_FILE" 2>/dev/null | tr '\n' ' ')"
for a in $keys; do
  for b in $keys; do
    (( a < b )) || continue          # 한 쌍을 한 번만 본다
    ca="$(commits_of "$a")"; cb="$(commits_of "$b")"
    for oid in $ca; do
      if [[ " $cb " == *" $oid "* ]]; then
        # 포함 방향을 낸다 — 「어느 쪽을 먼저 머지하나」가 그것으로 정해진다
        na="$(wc -w <<< "$ca")"; nb="$(wc -w <<< "$cb")"
        if (( na < nb )); then first="$a"; second="$b"; else first="$b"; second="$a"; fi
        echo "🔴 #$a 와 #$b 가 ${oid:0:7} 을 공유 — 먼저 #$first, 그 뒤 #$second 를 rebase"
        shared=$((shared + 1))
        break
      fi
    done
  done
done
(( shared == 0 )) && echo "없음"

echo
echo "🔸 판정은 하지 않는다 — 여기 나온 것은 «리뷰 전에 고쳐질 수 있는 것»이다."
exit 0
