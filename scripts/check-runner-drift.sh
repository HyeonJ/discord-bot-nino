#!/usr/bin/env bash
# check-runner-drift.sh — 사본이 정본과 갈라졌는지 잰다
#
# 왜 사본이 있나 (2026-07-28):
#   `scripts/run-tests.sh` 의 **정본은 코어**(dazebug/yaksu-bot-core)다. 룬드와 "코어에 본체 +
#   레포에 목록" 으로 합의했다. 그런데 **GitHub Actions 는 코어를 볼 수 없다** — 러너는 이
#   레포만 체크아웃하고 코어는 private 이라 cross-repo checkout 에 PAT 시크릿이 필요하다
#   (남의 레포 시크릿을 내 CI 에 넣는 결정이라 우리끼리 정할 일이 아니다).
#   ⇒ 사본을 둔다. 대신 **두 소스를 조용히 두지 않고 잰다.**
#
# 🔑 어디서 재는가가 이 검사의 요점이다 — **코어가 실제로 보이는 곳(내 기계·cron)** 에서만
#   잴 수 있다. CI 에 넣으면 언제나 "판정 불가" 가 되어 그 rc=2 가 상시가 되고, 상시가 된
#   경고는 안 보는 경고다. 그래서 이 검사는 CI 가 아니라 로컬/cron 자리에 둔다.
#
# 종료코드:
#   0  같다
#   1  갈라졌다 — 코어를 정본으로 사본을 갱신할 것
#   2  판정 불가 — 코어 체크아웃이나 파일이 없어 **못 쟀다**(통과가 아니다)
#
# 주입 가능한 값(시험용): CORE_REPO · LOCAL_RUNNER · RUNNER_REL
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_REPO="${CORE_REPO:-$HOME/yaksu-bot-core-live}"
RUNNER_REL="${RUNNER_REL:-scripts/run-tests.sh}"
LOCAL_RUNNER="${LOCAL_RUNNER:-$ROOT/$RUNNER_REL}"
CORE_RUNNER="$CORE_REPO/$RUNNER_REL"

if [ ! -f "$LOCAL_RUNNER" ]; then
    echo "⛔ 판정 불가 — 사본이 없다: $LOCAL_RUNNER"
    exit 2
fi
if [ ! -f "$CORE_RUNNER" ]; then
    echo "⛔ 판정 불가 — 정본을 못 봤다: $CORE_RUNNER"
    echo "   → 코어 체크아웃이 있는 곳에서 재야 한다(CI 에서는 구조적으로 못 잰다)"
    exit 2
fi

# 🔑 헤더 주석은 갈릴 수 있다(사본에는 '정본은 코어' 라고 적는다). 그래서 **주석을 뺀
#    코드 줄만** 비교한다. 전체 파일을 비교하면 의미 없는 차이로 상시 rc=1 이 되고,
#    그 빨간불이 상시가 되면 진짜 드리프트가 그 안에 묻힌다.
strip() { grep -v '^[[:space:]]*#' "$1" | grep -v '^[[:space:]]*$'; }

if diff -q <(strip "$LOCAL_RUNNER") <(strip "$CORE_RUNNER") >/dev/null 2>&1; then
    echo "✓ 러너 사본이 정본과 같다 (주석 제외 코드 줄 기준)"
    echo "  정본: $CORE_RUNNER"
    exit 0
fi

echo "✗ 러너 사본이 정본과 갈라졌다 — 코어가 정본이다"
echo "  사본: $LOCAL_RUNNER"
echo "  정본: $CORE_RUNNER"
diff <(strip "$LOCAL_RUNNER") <(strip "$CORE_RUNNER") | head -20 | sed 's/^/  /'
echo "  → 해소: cp \"$CORE_RUNNER\" \"$LOCAL_RUNNER\" (사본 헤더 주석은 유지)"
exit 1
