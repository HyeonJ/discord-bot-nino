#!/usr/bin/env bash
# core-clone-guard.sh — 셔틀이 **어느 코어 클론을 보는지** 를 실행 직전에 말한다
#
# 사용: bash scripts/core-clone-guard.sh <클론경로> <기대브랜치|->
#   경고만 한다. **절대 차단하지 않는다**(rc 는 항상 0) — 가드가 셔틀 본작업을 막으면
#   가드를 끄게 되고, 그러면 가드가 없는 것보다 나쁘다(있다고 믿는데 꺼져 있다).
#
# 왜 이게 필요했나 (2026-08-01 실측): lint 셔틀이 기본값 ~/yaksu-bot-core(=dev)를 실행해서
#   코어 #64~#74 개선이 **하나도 안 돌고 있었다. 그런데 에러가 0이었다** — 문구는 맞았고
#   가리키는 **자리**가 갈렸다. 내용 대조로는 구조적으로 못 잡는 형태다.
#
# 🔑 왜 코어가 아니라 셔틀에 사나: **검사가 검사 대상 안에 살면 안 된다.**
#   잘못된 클론을 실행 중이면 그 안의 가드도 잘못된 클론의 것이다.
#
# 🔑 왜 심링크·behind 체크가 아닌가: 이 레이아웃은 클론이 둘이고 **역할이 다르다.**
#     ~/yaksu-bot-core       dev   main 에서 벗어나 있는 게 정상
#     ~/yaksu-bot-core-live  prod  main
#   심링크는 prod 를 feat 브랜치로 끌고 가고, dev behind 체크는 **영구 오탐**이다.
#   ⇒ 묻는 것은 "최신인가"가 아니라 **"제 역할인가"**. 그래서 경로마다 기대값이 다르다.
set -uo pipefail

CORE="${1:-}"
EXPECT="${2:-}"

if [ -z "$CORE" ] || [ -z "$EXPECT" ]; then
    printf '➖ 코어 가드: 인자 부족 (사용: %s <경로> <기대브랜치|->) — 판정 불가\n' "$0" >&2
    exit 0
fi

# 안 재는 것과 통과가 같아 보이면 안 된다 — «-» 도 반드시 말한다
if [ "$EXPECT" = "-" ]; then
    printf '➖ 코어 가드: 기대값 없음 — 브랜치 검사 안 함 (%s)\n' "$CORE" >&2
    exit 0
fi

if [ ! -d "$CORE" ]; then
    printf '➖ 코어 가드: 경로 없음 — 판정 불가 (%s)\n' "$CORE" >&2
    exit 0
fi

if ! git -C "$CORE" rev-parse --git-dir >/dev/null 2>&1; then
    printf '➖ 코어 가드: git 저장소 아님 — 판정 불가 (%s)\n' "$CORE" >&2
    exit 0
fi

# symbolic-ref 는 detached 에서 빈 문자열이 아니라 **실패**한다.
# 빈 문자열로 두면 기대값과 우연히 같아 보이는 경로가 생기므로 명시적 라벨을 붙인다.
BRANCH="$(git -C "$CORE" symbolic-ref --short -q HEAD 2>/dev/null)" || BRANCH='(detached)'
[ -n "$BRANCH" ] || BRANCH='(detached)'

if [ "$BRANCH" != "$EXPECT" ]; then
    printf '⚠️ 코어 가드: 기대=%s 실제=%s — 경로 %s\n' "$EXPECT" "$BRANCH" "$CORE" >&2
fi

exit 0
