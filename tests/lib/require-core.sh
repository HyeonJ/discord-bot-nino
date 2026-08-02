#!/bin/bash
# require-core.sh — 코어 정본(cli-guard)이 없으면 **그 시험 파일 전체를 판정 불가로** 내려놓는다.
#
# 왜 필요한가 (2026-08-02 실측):
#   `scripts/lib/cli-guard-boot.sh` 는 코어를 못 찾으면 **일부러** `verdict=no_cli_guard` + `exit 2`
#   한다 — 가드가 안 붙은 채 도는 것을 막는 설계다. 그런데 그러면 코어를 못 받는 환경(=CI)에서
#   그 스크립트를 부르는 시험의 단언이 **전부 «틀린 이유로»** 빨개진다.
#   🔑 **원래 빨간 판 위에 빨간 걸 더하면 아무도 못 본다.** 실제로 내 CI 는 07-31 이후 이틀간
#      그 상태였고, 그 사이 PR 7건이 빨간 관문을 통과했다([[inbox-2026-07-31]] #159).
#   ⇒ 조용히 통과시키지도(그건 분모 0), 거짓 빨강을 내지도 않고 **판정 불가로 세어 보고**한다.
#
# 🔴 왜 파일마다 붙이지 않고 여기 한 곳인가:
#   같은 20줄을 파일마다 복사하면 **다음 시험 파일이 생길 때 또 샌다.** 이 레포가 이미 같은
#   교훈을 적어뒀다 — *"길목을 하나로 만드는 것이 처방이고, 호출부를 세어 붙이는 것은
#   다음 호출부가 생기면 다시 샌다"* (`check-usage-alert.test.sh` 의 `export CORE_REPO` 주석).
#
# 사용법:  REPO 를 정한 «뒤», 단언이 시작되기 «전»에
#     . "$REPO/tests/lib/require-core.sh"
#   찾으면 `CORE_FIXTURE` 를 채우고 `CORE_REPO` 를 export 한다(이후 `env …` 호출이 물려받는다).
#   못 찾으면 **호출한 시험 파일을 rc=0 으로 끝낸다** — 요약줄에 「판정 불가 1(파일 전체)」를 남기고.
#
# ⚠️ `exit` 는 source 한 «호출자»를 끝낸다 — 그게 의도다. 부재 갈래를 일부러 시험하는 곳은
#   이 파일을 source 하지 말고 직접 `CORE_REPO` 를 덮어쓸 것.

: "${REPO:?require-core.sh: REPO 가 정해지지 않았다 — source 하기 전에 정할 것}"

CORE_FIXTURE=""
for _rc_c in "${CORE_REPO:-}" "$REPO/../yaksu-bot-core-live" "$REPO/../yaksu-bot-core" \
             "$HOME/yaksu-bot-core-live" "$HOME/yaksu-bot-core"; do
    [ -n "$_rc_c" ] && [ -r "$_rc_c/scripts/cli-guard.sh" ] && { CORE_FIXTURE="$_rc_c"; break; }
done
unset _rc_c

if [ -z "$CORE_FIXTURE" ]; then
    echo "⛔ 판정 불가 — cli-guard 정본을 못 찾았다."
    echo "   찾아본 곳: \$CORE_REPO · <repo>/../yaksu-bot-core-live · <repo>/../yaksu-bot-core"
    echo "              · ~/yaksu-bot-core-live · ~/yaksu-bot-core"
    echo "   코어를 클론하거나 CORE_REPO=<경로> 로 지정하고 다시 돌릴 것."
    echo "  통과 0 · 실패 0 · 판정 불가 1(파일 전체)"
    # 🔴 **rc=2 로 나간다 — `exit 0` 이면 러너가 «✅ 통과」로 센다**(룬드 실측, 08-02).
    #   러너는 rc 기준이라 stdout 의 「판정 불가」 줄을 안 본다. 실제 출력이 스스로 증거였다:
    #       ✅ core-drift-cron   통과 0        ← 0개 돌았는데 초록
    #       ── 결과: 통과 1 · 실패 0 · 판정 불가 0
    #   ⇒ 그대로 뒀으면 **코어 경로가 깨진 날 커버리지가 0 으로 무너진 채 전부 초록**이다.
    #   러너의 기존 계약(rc=2 → ⛔ 집계 + 이름 목록 + 추세)이 수정 없이 맞물린다.
    exit 2
fi

# 🔑 **한 곳에서 export 한다** — 호출부마다 붙이면 다음 호출부가 생길 때 또 샌다.
export CORE_REPO="$CORE_FIXTURE"
