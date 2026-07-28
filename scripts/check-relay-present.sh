#!/usr/bin/env bash
# check-relay-present.sh — **실제로 도는 relay 가 존재하는가**를 잰다
#
# 왜 생겼나 (2026-07-28, Darren 승인 M:i9s0):
#   `setup.sh` Phase 9 의 필수 파일 목록에 `src/discord-relay.js` 가 있었다. bot-core 전환
#   (2026-07) 이후 relay 는 **코어 사본**에서 돌는데(systemd ExecStart), 그 낡은 파일이
#   레포에 남아 있어서 점검은 계속 **초록**이었다. 즉 *존재 확인은 통과하는데 실제 relay
#   유무는 한 번도 안 재고 있었다* — 두 방향 다 틀린 거짓 초록이다:
#     · 코어 relay 가 사라져도 setup 은 조용하다
#     · 낡은 파일을 지우면 아무 문제 없는데 경고가 뜬다
#   실측(2026-07-28): src/discord-relay.js 존재(14.7KB) · ExecStart=~/yaksu-bot-core-live/relay/index.js
#
# 🔑 무엇을 재는가
#   ① 코어 사본에 relay 실체가 있는가            ($CORE_REPO/relay/index.js)
#   ② 유닛이 있으면 **그 유닛이 가리키는 절대경로들이 실제로 존재하는가**
#      — 인터프리터 경로까지 본다. nvm 버전이 올라가면 `.../node/v24.14.0/bin/bun` 이
#        조용히 사라지는데, 그건 "relay 파일은 있지만 못 뜬다" 라서 파일 존재만으론 안 잡힌다.
#   유닛이 없는 것은 실패가 아니다(부트스트랩 전이면 정상) — 다만 **말은 한다.** 부재를
#   조용히 넘기면 "안 쟀다"가 "정상"으로 읽힌다.
#
# 종료코드 — 세 상태를 접지 않는다:
#   0  정상        relay 실체가 있고, 유닛이 있으면 그 대상들도 존재한다
#   1  문제        relay 가 없거나 유닛이 없는 파일을 가리킨다 → 지금 못 뜬다
#   2  판정 불가   유닛 상태를 못 쟀다(systemctl 부재 등). 0/1 로 접지 않는다
#
# 주입 가능한 값(시험용): CORE_REPO · RELAY_UNIT · SYSTEMCTL
set -uo pipefail

CORE_REPO="${CORE_REPO:-$HOME/yaksu-bot-core-live}"   # check-core-drift.sh 와 같은 이름
RELAY_UNIT="${RELAY_UNIT:-nino-relay.service}"
SYSTEMCTL="${SYSTEMCTL:-systemctl}"

PROBLEM=0

RELAY_JS="$CORE_REPO/relay/index.js"
if [[ -f "$RELAY_JS" ]]; then
    echo "✓ relay 실체: $RELAY_JS"
else
    echo "✗ relay 실체 없음: $RELAY_JS"
    echo "  → 코어 사본을 받아야 한다(bot-core 전환 이후 relay 는 이 레포에 없다)"
    PROBLEM=1
fi

if ! command -v "$SYSTEMCTL" >/dev/null 2>&1; then
    echo "⛔ 판정 불가 — $SYSTEMCTL 이 없다. 유닛이 무엇을 가리키는지 못 쟀다"
    exit 2
fi

UNIT_TEXT="$("$SYSTEMCTL" --user cat "$RELAY_UNIT" 2>/dev/null)"
UNIT_RC=$?
if [[ "$UNIT_RC" -ne 0 || -z "$UNIT_TEXT" ]]; then
    # 부트스트랩 전이면 정상 — 그래도 "안 쟀다"를 말한다
    echo "ℹ️  유닛 미설치: $RELAY_UNIT (부트스트랩 전이면 정상 — 유닛 대상은 못 쟀다)"
    [[ "$PROBLEM" -eq 0 ]] && exit 0
    exit 1
fi

EXEC_LINE="$(printf '%s\n' "$UNIT_TEXT" | grep -m1 '^ExecStart=')"
if [[ -z "$EXEC_LINE" ]]; then
    echo "⛔ 판정 불가 — $RELAY_UNIT 에 ExecStart 가 없다"
    exit 2
fi

# ExecStart 의 **절대경로 토큰 전부**가 존재해야 한다(인터프리터 + 스크립트)
CHECKED=0
for tok in ${EXEC_LINE#ExecStart=}; do
    [[ "$tok" == /* ]] || continue
    CHECKED=$((CHECKED + 1))
    if [[ -e "$tok" ]]; then
        echo "✓ 유닛 대상 존재: $tok"
    else
        echo "✗ 유닛이 없는 경로를 가리킨다: $tok"
        echo "  → relay 는 지금 못 뜬다(nvm 버전 올라가면 인터프리터 경로가 조용히 사라진다)"
        PROBLEM=1
    fi
done

if [[ "$CHECKED" -eq 0 ]]; then
    echo "⛔ 판정 불가 — ExecStart 에 절대경로가 없다: $EXEC_LINE"
    exit 2
fi

exit "$PROBLEM"
