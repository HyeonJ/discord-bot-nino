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
# 🔴 `--dry-run` — 세고 로그만 남기고 «주입하지 않는다».
#   실물 2026-08-12 09:53·09:54: 이 스크립트를 «진짜 대기함으로 확인»하려고 돌렸더니 그대로 내
#   세션에 주입됐고, 그중 하나는 버그판이라 **틀린 수(12건)가 «지시»로 도착**했다.
#   🔑 확인이 계기를 만들면, 계기의 주어를 크론으로 옮겨놓은 것이 확인할 때마다 «나»로 되돌아온다.
#   🔑 dry 회차는 로그에서 `DRY` 로 갈린다 — 안 그러면 이 로그의 본업(「안 울렸다 ↔ 안 돌았다」)이
#     「내가 시험한 것 ↔ 크론이 돈 것」에서 다시 무너진다.
DRY=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    *) echo "알 수 없는 인자: $a (쓸 수 있는 것: --dry-run)" >&2; exit 2 ;;
  esac
done

mkdir -p "$(dirname "$FLUSH_LOG")" 2>/dev/null || true
stamp() { date '+%Y-%m-%dT%H:%M:%S%z'; }

if [[ ! -f "$OUTBOX_FILE" ]]; then
  # 🔴 부재를 «0건»으로 접지 않는다 — 대기함이 사라지면 규칙이 통째로 죽는데 조용하다.
  echo "$(stamp) pending=na ERROR outbox-missing=$OUTBOX_FILE" >> "$FLUSH_LOG"
  echo "⚠️ 대기함 없음: $OUTBOX_FILE" >&2
  exit 1
fi

# 「## 대기 중」 이후의 실질 «항목»을 센다.
# 🔴 «줄»을 세면 안 된다 — 첫 실사용에서 항목 2건이 `pending=12` 로 나왔다(줄을 세고 「N건」이라
#   불렀다). 시험 픽스처가 전부 «한 줄짜리 항목»이라 줄 수와 항목 수가 같아 **이 축을 안 쟀다**.
# 🔑 항목의 단위는 «최상위 항목»이다 — `### ` 제목 **또는** 들여쓰지 않은 `- ` 불렛.
#   들여쓴 `  - ` 는 그 항목의 «본문»이라 안 센다. 제목도 불렛도 없이 본문만 있으면 **한 건**
#   (형식을 안 지킨 것을 0건으로 접으면 그 건이 조용히 사라진다 — 부재는 조용하다).
# 🔴 좌변이 `### ` «하나»였던 판이 2026-08-14 에 «항상 1» 을 냈다 — 실사용 파일은 항목을
#   `- **제목**` 으로 쌓는데(머리말이 `###` 를 금지한다: 08-13 에 하위 제목이 별도 항목으로
#   세어졌다) 시험 픽스처만 `### ` 를 써서 **두 규칙이 서로를 무효화하는 걸 아무도 못 봤다**.
#   ⇒ 좌변은 «형식 하나»가 아니라 «최상위냐»여야 한다. 시험 ①-c·①-d 가 그 자리다.
# 🔴 두 형식은 «섞이면 원리적으로 구별 불가»다 — 제목형에서 «제목 아래 본문»도 들여쓰지 않은
#   `- ` 로 쓴다. 그래서 한 문서 안에서 「항목 불렛」과 「본문 불렛」이 같은 모양이 된다.
#   ⇒ 문서 «단위»로 가른다: 제목이 하나라도 있으면 제목형(제목만 센다), 없으면 불렛형.
#   ⇒ 섞인 문서는 접어 세되 **로그에 `MIXED-FORMAT` 표지를 남긴다**(조용히 접으면 그게 이 버그다).
_scan="$(awk '
  /^## 대기 중/ { on = 1; next }
  /^## / { on = 0 }
  on {
    raw = $0
    line = raw
    gsub(/^[ \t]+|[ \t]+$/, "", line)
    if (line == "" || line == "(비어 있음)" || line ~ /^>/) next
    if (line ~ /^### /) { titles++; next }
    if (raw ~ /^- /) { bullets++; next }
    body++
  }
  END {
    n = (titles > 0) ? titles : ((bullets > 0) ? bullets : ((body > 0) ? 1 : 0))
    printf "%d\t%d\n", n, (titles > 0 && bullets > 0) ? 1 : 0
  }
' "$OUTBOX_FILE")"
PENDING="${_scan%%	*}"
MIXED="${_scan##*	}"

echo "$(stamp) pending=$PENDING$( ((MIXED)) && echo " MIXED-FORMAT" )$( ((DRY)) && echo " DRY" )" >> "$FLUSH_LOG"
(( PENDING > 0 )) || exit 0   # 확인된 빈 상태 → 조용
if (( DRY )); then
  echo "[dry-run] 주입 안 함 — pending=$PENDING"
  exit 0
fi

MSG="📮 놀이터 발신 시각이야 — memory/outbox-botplayground.md 에 ${PENDING}건 쌓여 있어. 하나로 묶어서 봇-놀이터에 보내고 대기함을 비워줘."
# 🔴 주입 실패를 «삼키지» 않는다 — 이 도구의 존재 이유가 「안 울렸다 ↔ 안 돌았다」를 가르는
#   것인데, 마지막 단계가 조용히 실패하면 그 구별이 정확히 거기서 사라진다.
#   (룬드 `4425734` 좌변: `2>/dev/null` 은 실패를 «뒤 명령의 에러»로 미뤄 원인을 못 가르게 한다.)
# 🔴 `tmux send-keys` 를 «직접» 부르지 않는다 — 코어 `tmux-send.sh` 가 닫아둔 구멍을 다시 연다.
#   실물 2026-08-12 18:00: 직접 호출이 rc=0 을 냈는데 텍스트가 **입력창에 92분 앉아 있다가**
#   19:32 릴레이의 Enter 에 «붙어서» 제출됐다(한 user 레코드에 둘이 구분자 없이 이어짐).
#   코어가 이미 갖고 있던 것: 텍스트와 `C-m` 을 «따로» + 컴포저 대기 + 입력창 잔류 검사 후 재전송.
# 🔑 그래서 좌변이 `rc` 면 안 된다 — rc 는 「tmux 에 넣었다」지 「컴포저가 삼켰다」가 아니다.
# 🔑 폴백으로 raw 를 두지 않는다(「필수면 기본값 대신 에러」) — 폴백이 곧 방금 샌 경로다.
TMUX_SEND="${TMUX_SEND:-$HOME/yaksu-bot-core-live/tmux-send.sh}"
if [[ -n "$INJECT_CMD" ]]; then
  "$INJECT_CMD" "$MSG"; inject_rc=$?
elif [[ -x "$TMUX_SEND" ]]; then
  # `--pane` 을 명시한다 — 안 주면 `TMUX_SESSION` 과 `TMUX_SEND_PANE` 두 변수가 서로를 오염시킨다.
  err="$("$TMUX_SEND" "$MSG" --pane "$TMUX_SESSION:0.0" 2>&1)"; inject_rc=$?
  [[ -n "$err" ]] && echo "$(stamp) tmux-send-stderr: $err" >> "$FLUSH_LOG"
else
  echo "$(stamp) INJECT-FAIL rc=3 no-injector=$TMUX_SEND pending=$PENDING" >> "$FLUSH_LOG"
  echo "⚠️ 주입기 없음: $TMUX_SEND — 대기 ${PENDING}건이 «알려지지 않았다»" >&2
  exit 3
fi
if (( inject_rc != 0 )); then
  echo "$(stamp) INJECT-FAIL rc=$inject_rc pending=$PENDING" >> "$FLUSH_LOG"
  echo "⚠️ 주입 실패 rc=$inject_rc — 대기 ${PENDING}건이 «알려지지 않았다»" >&2
  exit "$inject_rc"
fi
