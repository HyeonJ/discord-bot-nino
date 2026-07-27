#!/usr/bin/env bash
# catchup-hint.sh — 세션 시작·재시작 때 "놓친 대화 따라잡기" 지시문 한 줄을 만든다.
#
# 왜 별 스크립트인가:
#   같은 지시문이 start-nino.sh와 restart-nino.sh에 **사본 두 벌**로 있었다. 한쪽만 고치면 드리프트가 난다.
#   (2026-07-27: discord-send 문법·yaksu-history 버전이 정확히 그 형태로 4개월씩 갈렸다)
#
# 왜 jsonl 경로 주입에서 CLI로 바꾸나 (Tim 지시 M:qf4k):
#   조회 정본이 yaksu-history CLI다. jsonl 경로를 주입하면 세션이 파일을 직접 읽어야 하고,
#   그 파일에 구멍이 있어도(2026-07-26 07~10시 실측 0행) 알 방법이 없다.
#
# 🔴 설계 원칙: 중단 시각을 모를 때 조용히 기본값으로 넘어가지 않는다.
#   모르면 기본 창을 쓰되 **모른다는 사실을 지시문에 남긴다** — 조용한 기본값이 오늘 사고들의 공통 형태였다.
#
# 시각 표기: 접미사 없는 시각을 쓰지 않는다(`14:55+09` / `05:55Z`). 룬드가 하루에 세 번 KST/UTC를 뒤집은 뒤 합의한 규칙.
set -uo pipefail

BOT_DIR="${CATCHUP_BOT_DIR:-/home/bpx27/discord-bot-nino}"
CLI="${CATCHUP_CLI:-$HOME/.local/bin/yaksu-history}"
STATE="$BOT_DIR/logs/last-stop-utc"
NOTIFY="$BOT_DIR/logs/pending-restart-notify.txt"

MIN_WINDOW=5        # 방금 멈췄어도 최소 5분은 훑는다(경계 메시지 유실 방지)
MAX_WINDOW=2880     # 48시간. 그보다 길면 따라잡기가 아니라 별도 복구 작업이다
DEFAULT_WINDOW=120  # 중단 시각을 모를 때

reboot=0
[[ "${1:-}" == "--reboot" ]] && reboot=1

# ── 창 계산 ────────────────────────────────────────────────
window=""; note=""
if [[ -r "$STATE" ]]; then
    stop_raw="$(head -1 "$STATE" 2>/dev/null)"
    stop_epoch="$(date -u -d "$stop_raw" +%s 2>/dev/null || true)"
    if [[ -n "$stop_epoch" ]]; then
        elapsed=$(( ( $(date -u +%s) - stop_epoch ) / 60 ))
        if (( elapsed > MAX_WINDOW )); then
            window=$MAX_WINDOW
            note=" 실제로는 ${elapsed}분 꺼져 있었는데 48시간으로 잘랐어 — 그 앞 구간은 따라잡기가 아니라 별도 복구가 필요해."
        elif (( elapsed < MIN_WINDOW )); then
            window=$MIN_WINDOW
        else
            window=$elapsed
        fi
    fi
fi
if [[ -z "$window" ]]; then
    window=$DEFAULT_WINDOW
    # 여기서 "모른다"를 말하지 않으면, 기본 창이 실제 중단 시간인 것처럼 읽힌다.
    note=" 중단 시각을 몰라서(logs/last-stop-utc 없음·해석 불가) 기본 ${DEFAULT_WINDOW}분으로 잡았어 — 빠진 게 있어 보이면 창을 넓혀서 다시 봐."
fi

# ── 앞머리 ────────────────────────────────────────────────
if (( reboot )) && [[ -f "$NOTIFY" ]]; then
    head_msg="재부팅했어. logs/pending-restart-notify.txt 있으니까 처리해줘."
elif (( reboot )); then
    head_msg="재부팅했어."
else
    head_msg="재시작됐어."
fi

# ── 따라잡기 수단: CLI → jsonl → current-tasks 순서로 폴백 ──
# 폴백이 있는 이유: CLI가 없을 때 "yaksu-history 돌려줘"를 주면 세션이 실패한 명령을 보고 헤맨다.
if [[ -x "$CLI" ]]; then
    printf '%s\n' "$head_msg $CLI --after ${window}m 돌려서 못 봤던 대화 파악해줘 (출력 timestamp는 UTC니까 KST는 +9).${note}"
    exit 0
fi

TODAY="$(TZ=Asia/Seoul date +%Y-%m-%d)"
HISTORY_FILE="$BOT_DIR/memory/discord-history/$TODAY.jsonl"
if [[ -f "$HISTORY_FILE" ]]; then
    printf '%s\n' "$head_msg 조회 CLI가 없어서($CLI 실행 불가) memory/discord-history/$TODAY.jsonl 읽고 못 봤던 대화 파악해줘. CLI 부재도 같이 확인해줘 — 조회 정본이 빠진 상태야."
else
    printf '%s\n' "$head_msg 조회 CLI도 오늘 jsonl도 없어서 따라잡을 소스가 없어. memory/current-tasks.md 읽고 이어서 진행하고, 기록 경로가 왜 비었는지 확인해줘."
fi
