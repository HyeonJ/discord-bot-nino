#!/usr/bin/env bash
# 코어 드리프트 시간별 점검 — cron 래퍼 (승인 ③, Darren 2026-07-28 M:c3rg)
#
# 🔑 이 래퍼의 계약은 **언제 소리를 내는가** 하나다:
#   rc=0 충족    → 조용. 대신 **하트비트를 남긴다**(안 돌고 있는 것과 구분하려고)
#   rc=2 미달    → 알린다 (조치가 있다: pull 또는 재시작)
#   그 외        → **알린다**. "판정 불가"를 조용히 넘기면 *괜찮음*과 같아지고,
#                  없는 경고는 pull 을 미루게 해서 옛 코드로 계속 돌게 만든다.
#
# ⚠️ 하트비트가 필요한 이유: 이 cron 자체가 죽으면 출력이 없다 = rc=0 과 같은 모양이다.
#    무음이 "드리프트 없음"을 뜻하려면 **이 스크립트가 살아 있다는 증거**가 따로 있어야 한다.
#    지금은 파일 mtime 으로 남기고, 그 신선도를 보는 쪽은 아직 없다 → TODO(아래).
#
# TODO(승인 ③ 후속): 하트비트가 2시간 이상 낡으면 아침 브리핑에서 경고. 지금은 파일만 남긴다.
#    묻어두지 않으려고 여기 적는다 — 이게 없으면 "cron 이 죽은 상태"가 여전히 무음이다.
set -uo pipefail

BOT_DIR="${BOT_DIR:-$HOME/discord-bot-nino}"
CHECK="${CHECK:-$BOT_DIR/scripts/check-core-drift.sh}"
HEARTBEAT="${HEARTBEAT:-$BOT_DIR/logs/core-drift.heartbeat}"
LOG="${LOG:-$BOT_DIR/logs/core-drift.log}"
NOTIFY_TARGET="${NOTIFY_TARGET:-봇-놀이터}"
DISCORD_SEND="${DISCORD_SEND:-$BOT_DIR/src/discord-send}"
DRY_RUN="${DRY_RUN:-0}"

[ -f "$BOT_DIR/.env" ] && { set -a; . "$BOT_DIR/.env"; set +a; }
mkdir -p "$(dirname "$HEARTBEAT")"

OUT="$("$CHECK" 2>&1)"; RC=$?
STAMP="$(TZ=Asia/Seoul date '+%Y-%m-%d %H:%M:%S')"

printf '%s rc=%s %s\n' "$STAMP" "$RC" "$(printf '%s' "$OUT" | head -1)" >> "$LOG"
printf '%s rc=%s\n' "$STAMP" "$RC" > "$HEARTBEAT"

# 충족이면 여기서 끝 — 조용한 게 정상이고, 살아 있다는 증거는 하트비트가 댄다
[ "$RC" -eq 0 ] && exit 0

if [ "$RC" -eq 2 ]; then
    HEAD="🔴 코어 드리프트 — 조치 필요"
else
    # rc=1 등: 판정이 안 된 것이지 괜찮은 게 아니다
    HEAD="⚠️ 코어 드리프트 **판정 불가** (rc=$RC) — 검사가 못 돌았다"
fi

MSG="$HEAD
\`\`\`
$OUT
\`\`\`"

if [ "$DRY_RUN" = "1" ]; then
    printf '%s\n' "$MSG"
    exit "$RC"
fi

"$DISCORD_SEND" "$NOTIFY_TARGET" "$MSG"
exit "$RC"
