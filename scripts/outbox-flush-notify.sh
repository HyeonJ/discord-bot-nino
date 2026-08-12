#!/usr/bin/env bash
# 놀이터 발신 «시각»을 알린다 — 계기의 주어를 «나»에서 «크론»으로 옮긴다.
#
# 🔴 왜 있나: Darren Ⅲ 값(2026-08-12 `M:nx3l` 「3~4회로 해 너도」)으로 룬드 발신을 하루 4회에
#   묶었는데, **그 시각을 내가 기억해야 하면 결국 판정에 매달린다** — 옛 규칙이 샌 자리와 같다.
#   우리 계약 「계기는 «주어의 동작»을 촉발하는 것이라야 한다」의 적용이다.
# 🔑 규약: **확인된 빈 상태는 조용**하고 **못 읽은 것은 시끄럽다**(rc≠0). 돌았다는 흔적은 항상 남긴다
#   — 안 그러면 「안 울렸다」와 「안 돌았다」가 같은 화면이 된다.
set -uo pipefail
BOT_DIR="${BOT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
OUTBOX_FILE="${OUTBOX_FILE:-$BOT_DIR/memory/outbox-botplayground.md}"
TMUX_SESSION="${TMUX_SESSION:-nino}"
FLUSH_LOG="${FLUSH_LOG:-$BOT_DIR/logs/outbox-flush.log}"
# 주입 경로를 «주입 가능»하게 둔다 — 시험이 진짜 tmux 를 때리지 않게(코어 계약 ⑨와 같은 자리).
INJECT_CMD="${INJECT_CMD:-}"

mkdir -p "$(dirname "$FLUSH_LOG")" 2>/dev/null || true
stamp() { date '+%Y-%m-%dT%H:%M:%S%z'; }

if [[ ! -f "$OUTBOX_FILE" ]]; then
  # 🔴 부재를 «0건»으로 접지 않는다 — 대기함이 사라지면 규칙이 통째로 죽는데 조용하다.
  echo "$(stamp) pending=na ERROR outbox-missing=$OUTBOX_FILE" >> "$FLUSH_LOG"
  echo "⚠️ 대기함 없음: $OUTBOX_FILE" >&2
  exit 1
fi

# 「## 대기 중」 이후의 실질 항목만 센다 — 플레이스홀더·빈 줄·주석은 항목이 아니다.
PENDING="$(awk '
  /^## 대기 중/ { on = 1; next }
  /^## / { on = 0 }
  on {
    line = $0
    gsub(/^[ \t]+|[ \t]+$/, "", line)
    if (line == "" || line == "(비어 있음)" || line ~ /^>/) next
    n++
  }
  END { print n + 0 }
' "$OUTBOX_FILE")"

echo "$(stamp) pending=$PENDING" >> "$FLUSH_LOG"
(( PENDING > 0 )) || exit 0   # 확인된 빈 상태 → 조용

MSG="📮 놀이터 발신 시각이야 — memory/outbox-botplayground.md 에 ${PENDING}건 쌓여 있어. 하나로 묶어서 봇-놀이터에 보내고 대기함을 비워줘."
if [[ -n "$INJECT_CMD" ]]; then
  "$INJECT_CMD" "$MSG"
else
  escaped="${MSG//\'/\'\\\'\'}"
  tmux send-keys -t "$TMUX_SESSION" -- "$escaped" C-m 2>/dev/null
fi
