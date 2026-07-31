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

[ -f "$BOT_DIR/.env" ] && { set -a; . "$BOT_DIR/.env"; set +a; }
mkdir -p "$(dirname "$HEARTBEAT")"

# ── 인자 계약 ────────────────────────────────────────────────────────────────
# 🔴 옛 형태는 `DRY_RUN="${DRY_RUN:-0}"` 였다 — **환경에서 물려받는** dry-run 이고, 하필
#   **바로 위 줄에서 `set -a; . .env`** 를 한다. `.env` 에 한 줄 들어가면 이 감시기는
#   **발송 0건 · rc=0** 으로 조용히 멈추고 성공처럼 보인다. 게다가 인자 파싱이 없어서
#   `DRY_RUN` 은 **환경으로만** 켤 수 있었다 — 끄는 길이 플래그로 존재하지도 않았다.
#   🔑 어느 쪽으로 접어도 조용히 틀린다 — 거절만이 두 오독을 다 막는다(코어 계약 ④).
cli_guard_usage() {
    echo "usage: $(basename "$0") [--dry-run] [-h|--help]"
    echo "  --dry-run   판정까지 하되 Discord 발송은 하지 않는다 (진단용)"
}
# 🔑 거절도 로그 1줄로 남긴다 — cron 은 stderr 를 버리므로 안 남기면 crontab 오타 하나에
#   이 감시기가 아무 표시 없이 멈춘다.
cli_guard_reject_log() {
    printf '%s verdict=%s rc=2\n' "$(TZ=Asia/Seoul date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG" 2>/dev/null || true
}
CLI_GUARD_ON_REJECT=cli_guard_reject_log
# 🔴 배선은 **스크립트 자기 위치**에서 찾는다 — `$BOT_DIR` 는 *데이터*(logs·state)를 옮기는
#   손잡이라 시험이 임시 디렉터리로 바꾼다. 거기서 코드를 찾게 했더니 시험 8건이 깨졌다.
#   🔑 주입점 하나로 두 축(코드·데이터)을 같이 움직이면, 한 축을 흔들 때 다른 축이 따라온다.
CLI_GUARD_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$CLI_GUARD_LIB_DIR/lib/cli-guard-boot.sh"
cli_guard_boot "$@"

# ⚠️ 파이프를 끼우지 않는다 — `cmd | tail` 뒤의 $? 는 tail 의 코드다(오늘 네 번 걸린 자리).
OUT="$("$LINT" 2>&1)"; RC=$?
STAMP="$(TZ=Asia/Seoul date '+%Y-%m-%d %H:%M:%S')"

# 항목 추출: 검사가 내는 "  ⚠️  <내용>" 줄만. 요약줄·섹션 헤더는 상태로 쓰지 않는다.
CURRENT="$(printf '%s\n' "$OUT" | sed -n 's/^  ⚠️  //p' | sort -u)"
COUNT="$(printf '%s' "$CURRENT" | grep -c . || true)"

printf '%s rc=%s 항목=%s\n' "$STAMP" "$RC" "$COUNT" >> "$LOG"
printf '%s rc=%s 항목=%s\n' "$STAMP" "$RC" "$COUNT" > "$HEARTBEAT"

notify() {  # $1=본문
  # 🔸 dry-run 이면 **보낼 뻔한 본문을 stdout 으로** 보여준다. 코어 안내는 stderr 라 파이프로
  #   못 받는데, dry-run 은 *보려고* 부르는 것이라 본문이 필요하다.
  if [ "$CLI_DRY_RUN" = "1" ]; then printf '%s\n' "$1"; return 0; fi
  # 🔑 위 갈래가 먼저 잡아 dry-run 일 때 여기 도달하지 않는다. 그래도 감싸는 이유는 저 갈래가
  #   지워지거나 발송 자리가 하나 더 생겨도 **계약이 남게** 하려는 것 — 억제의 정본은 여기다.
  cli_guard_send "$DISCORD_SEND" "$NOTIFY_TARGET" "$1"
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
