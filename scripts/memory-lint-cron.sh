#!/usr/bin/env bash
# 기억 검사 시간별 점검 — cron 래퍼 (승인 ③, Darren 2026-07-28 M:w41b)
#
# 🔑 이 래퍼의 계약은 **언제 소리를 내는가** 하나다:
#   0건            → 조용. 하트비트만 남긴다(안 돌고 있는 것과 구분하려고)
#   새 항목 있음   → 알린다. **그 항목만** 보낸다
#   같은 항목 반복 → 조용. ← 이게 이 스크립트의 존재 이유다
#   판정 불가      → 알린다. 검사가 못 돈 것을 "문제 없음"과 같게 두지 않는다
#
# ⚠️ 왜 "매번 알리기"가 아닌가 (2026-07-28 실측):
#    배선을 미뤄뒀던 이유가 검사 결과가 **213건**이었기 때문이다. 그 상태로 켜면 시간마다
#    213건짜리 경고가 날아오고 사람은 곧 무시한다 — *초록에서 시작하지 않는 감시는 배경소음*.
#    CRLF 204건을 정리해 9건이 됐지만 **9건도 상시 상태**다. 그래서 "개수"가 아니라
#    **항목 집합의 차이**를 본다. 새 항목에만 소리를 내면 감시가 조용한 상태에서 시작한다.
#
# ⚠️ 개수 대신 집합을 쓰는 이유: 하나가 해소되고 하나가 새로 생기면 **개수는 그대로다**.
#    개수만 보면 그 교체가 조용히 지나간다.
#
# TODO(후속): 하트비트가 2시간 이상 낡으면 아침 브리핑에서 경고. 지금은 파일만 남긴다.
#    드리프트 쪽(core-drift-cron.sh)에 같은 TODO 가 있었고 그건 #35 로 해소됐다 — 같은 자리다.
#    이게 없으면 "cron 이 죽은 상태"가 여전히 무음이다. 묻어두지 않으려고 여기 적는다.
set -uo pipefail

BOT_DIR="${BOT_DIR:-$HOME/discord-bot-nino}"
LINT="${LINT:-$BOT_DIR/scripts/lint-nino-memory.sh}"
STATE="${STATE:-$BOT_DIR/logs/memory-lint.state}"
HEARTBEAT="${HEARTBEAT:-$BOT_DIR/logs/memory-lint.heartbeat}"
LOG="${LOG:-$BOT_DIR/logs/memory-lint.log}"
NOTIFY_TARGET="${NOTIFY_TARGET:-봇-놀이터}"
DISCORD_SEND="${DISCORD_SEND:-$BOT_DIR/src/discord-send}"
DRY_RUN="${DRY_RUN:-0}"

[ -f "$BOT_DIR/.env" ] && { set -a; . "$BOT_DIR/.env"; set +a; }
mkdir -p "$(dirname "$HEARTBEAT")"

# ⚠️ 파이프를 끼우지 않는다 — `cmd | tail` 뒤의 $? 는 tail 의 코드다(오늘 네 번 걸린 자리).
OUT="$("$LINT" 2>&1)"; RC=$?
STAMP="$(TZ=Asia/Seoul date '+%Y-%m-%d %H:%M:%S')"

# 항목 추출: 검사가 내는 "  ⚠️  <내용>" 줄만. 요약줄·섹션 헤더는 상태로 쓰지 않는다.
CURRENT="$(printf '%s\n' "$OUT" | sed -n 's/^  ⚠️  //p' | sort -u)"
COUNT="$(printf '%s' "$CURRENT" | grep -c . || true)"

printf '%s rc=%s 항목=%s\n' "$STAMP" "$RC" "$COUNT" >> "$LOG"
printf '%s rc=%s 항목=%s\n' "$STAMP" "$RC" "$COUNT" > "$HEARTBEAT"

notify() {  # $1=본문
  if [ "$DRY_RUN" = "1" ]; then printf '%s\n' "$1"; return 0; fi
  "$DISCORD_SEND" "$NOTIFY_TARGET" "$1"
}

# 🔑 판정 불가를 먼저 가른다 — 0건(rc=0)도 아니고 항목 있음(rc=1)도 아닌 상태.
#    여기서 조용히 넘기면 "검사가 죽은 것"이 "문제 없음"과 같은 모양이 된다.
if [ "$RC" -ne 0 ] && [ "$RC" -ne 1 ]; then
  notify "⚠️ 기억 검사 **판정 불가** (rc=$RC) — 검사가 못 돌았다
\`\`\`
$(printf '%s' "$OUT" | tail -15)
\`\`\`"
  exit "$RC"
fi

# 이전 집합과 비교. 상태 파일이 없으면 첫 실행이므로 현재 전부가 '새 항목'이다(1회 통보).
PREV=""
[ -f "$STATE" ] && PREV="$(cat "$STATE")"
NEW="$(comm -13 <(printf '%s\n' "$PREV" | sort -u) <(printf '%s\n' "$CURRENT" | sort -u) | grep -c . || true)"
NEW_LINES="$(comm -13 <(printf '%s\n' "$PREV" | sort -u) <(printf '%s\n' "$CURRENT" | sort -u) | sed '/^$/d')"

# 상태는 **비교 후 항상** 갱신한다. 알림 실패와 무관하게 갱신하면 다음 회차에 조용해지므로,
# 알림을 보내는 경우에만 갱신한다 — "조치했다"가 "해소했다"를 대신하지 않게.
if [ "$NEW" -eq 0 ]; then
  # 새 항목 없음 = 조용. 상태만 최신화(해소된 항목 반영)
  printf '%s\n' "$CURRENT" > "$STATE"
  exit 0
fi

MSG="🔸 기억 검사 — **새 항목 ${NEW}건** (전체 ${COUNT}건)
\`\`\`
$NEW_LINES
\`\`\`"
if notify "$MSG"; then
  printf '%s\n' "$CURRENT" > "$STATE"
else
  echo "$STAMP 알림 전송 실패 — 상태를 갱신하지 않는다(다음 회차에 다시 알린다)" >> "$LOG"
  exit 3
fi
exit 0
