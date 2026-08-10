#!/usr/bin/env bash
# derive-merge-mode.sh — 이 레포의 머지 모드를 판정기 원장에서 «파생»한다.
#
# 🔑 이건 «시험»이 아니라 «게이트»다 — `approve-fresh`·`ci-fresh-green` 과 같은 층이다.
#    CI 에 넣지 않는 이유: 파생 도구가 «코어 레포»에 살아서 러너엔 없다. 없으면 판정 불가가
#    되고, 그 판불이 원장에 실려 **다음 PR 을 막는다**. 못 재는 것을 CI 에 넣어 상시 판불을
#    만드는 대신, 머지 직전에 손으로 돌린다.
#
# 🔑 왜 래퍼인가 (Ⅳ — 사실을 도구에 넣는다): `--ledger`·`--repo-label` 두 값을 매번 손으로
#    치면 그때마다 «다른 값»을 칠 수 있다. 여기 한 번 박아두면 그 축이 안 흔들린다.
#    🔴 그 대신 칸 «이름»은 여기 안 적는다 — 그건 파생 도구가 정본이고, 사본을 만들면 따로 낡는다.
#
# 사용: scripts/derive-merge-mode.sh [ledger-mode.sh 로 그대로 넘길 인자…]
#   예: scripts/derive-merge-mode.sh                       (지금 모드만 조회)
#       scripts/derive-merge-mode.sh --base-fail "" --fail "" --unknown 11
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

LEDGER="${MERGE_LEDGER:-$ROOT/.github/merge-ledger.md}"
REPO_LABEL="${MERGE_REPO_LABEL:-니노}"
TOOL="${LEDGER_MODE_SH:-$HOME/yaksu-bot-core-live/scripts/ledger-mode.sh}"

# 🔴 부재를 «통과»로 접지 않는다. 도구가 없으면 모드는 «모른다»지 «정상»이 아니다.
#    조용히 0 을 내면 게이트를 통과했다고 읽히고, 그게 정확히 이 계약이 막으려는 것이다.
if [ ! -f "$TOOL" ]; then
    echo "⛔ 판정 불가 — 파생 도구가 없다: $TOOL" >&2
    echo "   코어 클론을 받거나 LEDGER_MODE_SH 로 경로를 준다:" >&2
    echo "     git -C ~/yaksu-bot-core-live pull --ff-only origin main" >&2
    exit 2
fi
if [ ! -f "$LEDGER" ]; then
    echo "⛔ 판정 불가 — 원장이 없다: $LEDGER" >&2
    exit 2
fi

exec bash "$TOOL" --ledger "$LEDGER" --repo-label "$REPO_LABEL" "$@"
