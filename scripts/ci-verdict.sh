#!/usr/bin/env bash
# ci-verdict.sh — 러너의 **세 상태**를 CI 의 **두 상태**로 옮긴다 (정책은 여기 한 곳에만)
#
# 왜 필요한가 (2026-07-28):
#   `scripts/run-tests.sh` 는 0(통과)·1(실패)·2(판정 불가)를 낸다. 그런데 GitHub Actions 의
#   스텝은 **초록/빨강 둘**뿐이다. 이 변환을 워크플로 YAML 안에 인라인으로 쓰면
#     ① 시험할 수 없고 ② 두 레포에서 각자 달라지고 ③ 조용히 틀려도 아무도 모른다.
#   그래서 정책을 **파일 하나**로 떼고 시험으로 잠근다.
#
# 🔑 정책 — 그리고 왜 그렇게 정했나:
#   rc=0 → 초록.
#   rc=1 → 빨강. (실패는 CI 가 막아야 하는 것)
#   rc=2 → **초록 개수를 보고 가른다.**
#     · 초록이 충분하면 → 초록 + `::warning::`
#       CI 에서 구조적으로 못 재는 검사가 있다(systemd 유닛·코어 체크아웃·로컬 도구).
#       그걸 빨강으로 만들면 **첫날부터 빨간불이 정상**이 되고 진짜 회귀가 그 안에 묻힌다.
#     · 초록이 모자라면 → 빨강.
#       rc=2 의 다른 원인이 **"아무것도 안 돌았다"** 이기 때문이다. 그 둘을 같은 칸에 두면
#       시험이 전부 사라진 상태가 경고 하나로 지나간다 — 이 배선이 없애려던 바로 그 상태다.
#   rc=그 외 → 빨강. 러너가 정의하지 않은 코드는 판정이 아니라 사고다.
#
# ⚠️ 초록 개수를 **못 읽으면 빨강**이다. "못 읽었다" 를 초록으로 만들면 이 스크립트가
#    자기 자신에게 조용한 초록을 허용하는 셈이 된다.
#
# 사용법:
#   scripts/ci-verdict.sh --rc <러너 종료코드> --out <러너 출력 파일> [--min-green N]
#     --min-green  rc=2 를 경고로 넘길 최소 초록 개수 (기본 5)
set -uo pipefail

RC=""
OUT=""
MIN_GREEN=5

die() { echo "❌ ci-verdict: $1"; exit 1; }   # 인자 사고도 빨강 — 조용히 통과시키지 않는다

while [ $# -gt 0 ]; do
    case "$1" in
        --rc)        [ $# -ge 2 ] || die "--rc 값 없음"; RC="$2"; shift 2 ;;
        --out)       [ $# -ge 2 ] || die "--out 값 없음"; OUT="$2"; shift 2 ;;
        --min-green) [ $# -ge 2 ] || die "--min-green 값 없음"; MIN_GREEN="$2"; shift 2 ;;
        -h|--help)   sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)           die "모르는 인자: $1" ;;
    esac
done

case "$RC" in
    ''|*[!0-9]*) die "--rc 가 숫자가 아니다: '$RC'" ;;
esac

if [ "$RC" -eq 0 ]; then
    echo "✅ 전부 통과 (rc=0)"
    exit 0
fi

if [ "$RC" -eq 1 ]; then
    echo "🔴 시험 실패 (rc=1) — CI 를 빨강으로 둔다"
    exit 1
fi

if [ "$RC" -ne 2 ]; then
    echo "🔴 러너가 정의하지 않은 종료코드 rc=$RC — 판정이 아니라 사고다"
    exit 1
fi

# rc=2 — 초록 개수로 가른다
[ -n "$OUT" ] || die "rc=2 인데 --out 이 없다. 초록 개수를 못 세면 가를 수 없다"
[ -f "$OUT" ] || die "rc=2 인데 출력 파일이 없다: $OUT"

GREEN="$(sed -n 's/.*── 결과: 통과 \([0-9][0-9]*\).*/\1/p' "$OUT" | tail -1)"
if [ -z "$GREEN" ]; then
    echo "🔴 rc=2 인데 초록 개수를 못 읽었다 — '못 읽었다' 를 초록으로 만들지 않는다"
    echo "   (러너 출력에 '── 결과: 통과 N' 줄이 있어야 한다)"
    exit 1
fi

if [ "$GREEN" -ge "$MIN_GREEN" ]; then
    echo "::warning::판정 불가가 있다 — CI 에서 구조적으로 못 재는 검사(초록 ${GREEN}개는 확인됨)"
    echo "⚠️ rc=2 · 초록 ${GREEN}개 ≥ 기준 ${MIN_GREEN} → 초록으로 두고 경고만 남긴다"
    sed -n 's/^   판정 불가:/   판정 불가:/p' "$OUT"
    exit 0
fi

echo "::error::판정 불가인데 초록이 ${GREEN}개뿐이다 — 시험이 안 돌았을 가능성"
echo "🔴 rc=2 · 초록 ${GREEN}개 < 기준 ${MIN_GREEN} → 빨강. '아무것도 안 돌았다' 와 구별할 수 없다"
exit 1
