#!/usr/bin/env bash
# session-heartbeat.sh — Stop 훅. 세션이 한 턴을 끝낼 때마다 그 시각을 남긴다.
#
# 🔴 왜 필요한가 (Tim 지시 2026-07-29 M:uv86):
#   catchup-hint.sh의 앵커는 "세션이 반응을 멈춘 시각"이어야 하는데, 그 대리값으로
#   **"내가 마지막으로 발화한 시각"**(yaksu-history last-seen --author 니노)을 썼다.
#   그런데 니노 이름으로 말하는 건 세션만이 아니다 — cron이 7개다:
#     nino-watchdog(2분) · check-auth(5분) · check-usage-alert(30분) · core-drift(매시:15)
#     memory-lint(매시:35) · alarm-tool fire(1분) · health-checker(relay addon)
#   세션이 죽은 동안에도 이것들이 발화하므로 **앵커가 "지금"으로 끌려온다 → 창이 0에 수렴**한다.
#   실측(룬드, 2026-07-29): 마지막 실발화 2026-07-28T17:36:27Z 인데 재시작 알림이
#   03:25:47Z에 나가서 그게 앵커가 됐다 — **9시간 50분이 통째로 창 밖으로 밀렸다.**
#   워치독 복구 경로는 "재시작 알림을 보내고 재시작"하므로 이 오염이 **확정적**으로 난다.
#
# 🔑 해법: 앵커를 **세션만이 만들 수 있는 신호**에서 뽑는다. Stop 훅은 세션이 한 턴을
#   끝낼 때만 돈다 — cron이 위조할 수 없다. 그게 이 파일이다.
#
# 🔴 이전 실패(logs/last-stop-utc)를 반복하지 않기 위한 불변식:
#   **restart-nino.sh / start-nino.sh는 이 파일을 절대 쓰지 않는다.**
#   그때는 재시작 스크립트가 맨 위에서 now를 쓰고 7초 뒤 읽어서 경과가 항상 0이었다
#   → 창이 최소값 5분에 고정. 쓰는 주체가 "재시작하는 쪽"이면 같은 함정이 다시 난다.
#   시험(tests/catchup-hint.test.sh)이 이 불변식을 회귀로 잠근다.
#
# 계약:
#   · 절대 실패하지 않는다(exit 0 고정). Stop 훅이 죽으면 세션 턴이 방해받는다.
#   · 형식은 catchup-hint가 파싱하는 것과 같은 `...Z`. 접미사 없는 시각은 쓰지 않는다.
set -uo pipefail

BOT_DIR="${HEARTBEAT_BOT_DIR:-/home/bpx27/discord-bot-nino}"
OUT="$BOT_DIR/logs/session-heartbeat-utc"

mkdir -p "$BOT_DIR/logs" 2>/dev/null || exit 0

# 원자적 교체 — catchup-hint가 half-written 파일을 읽는 창을 없앤다.
TMP="$OUT.$$"
if date -u +%Y-%m-%dT%H:%M:%S.000Z > "$TMP" 2>/dev/null; then
    mv -f "$TMP" "$OUT" 2>/dev/null || rm -f "$TMP" 2>/dev/null
else
    rm -f "$TMP" 2>/dev/null
fi

exit 0
