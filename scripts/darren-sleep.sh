#!/usr/bin/env bash
# darren-sleep.sh — Darren 취침 모드 on/off/status
#
# 무엇을 하나: `logs/darren-sleeping` 에 «만료 epoch» 한 줄을 쓰거나 지운다.
#   그 파일을 읽는 것은 PreToolUse 훅(darren-mention-guard.sh)이고, 훅은 «지났나»만 본다.
#   ⇒ 요일·기상시각 계산은 «여기»에만 있다. 훅에 두면 판단이 두 곳으로 갈린다.
#
# 왜 만료를 «파일에» 박나 (Darren 승인 2026-08-05):
#   해제를 사람이나 내가 기억해야 하면, 잊었을 때 «멘션이 영영 조용히 안 간다».
#   만료를 파일에 넣으면 잊어도 아침에 저절로 풀린다 — 잊어도 «시끄러운 쪽»으로 떨어진다.
#
# 기상 시각: 평일 07:00 (아침 브리핑 cron 과 같은 시각) · 주말 09:00
#   ⚠️ 브리핑 시각을 바꾸면 여기도 같이 본다 — 두 값이 갈리면 브리핑이 취침 모드 안에서 돈다.
#
# 🔴 시각 변환은 «정본»을 지난다 — `scripts/lib/timeshift.sh`.
#   초판은 `date -d` 로 직접 계산했는데 그건 **GNU 전용**이라 룬드 맥에서 `next_wake` 가
#   `|| return 1` 로 죽어 **플래그가 아예 안 만들어졌다**(맥 실측 2026-08-05, `#149`).
#   ⚠️ 그때 `tests/portability.test.sh` 는 **초록이었다** — 그 시험의 판정 분모가 `tests/` 뿐이라
#     여기 6곳은 「세어서 보고」만 됐다. 🔑 **초록이 증명한 것은 「시험에 GNU 토큰이 없다」이지
#     「맥에서 돈다」가 아니다.** 게이트를 조회하는 것으로는 부족하고 **분모끼리 대조**해야 한다.
set -uo pipefail

SLEEP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SLEEP_DIR/lib/timeshift.sh"

FLAG="${DARREN_SLEEP_FLAG:-$HOME/discord-bot-nino/logs/darren-sleeping}"
WEEKDAY_WAKE=7
WEEKEND_WAKE=9

# 요일(1=월 … 7=일) → 그날의 기상 시각
wake_hour() {
    case "$1" in
        6|7) echo "$WEEKEND_WAKE" ;;
        *)   echo "$WEEKDAY_WAKE" ;;
    esac
}

# 시험이 «내일 아침»을 고정할 수 있어야 해서 now 를 주입받는다(기본은 실제 시각).
now() { echo "${DARREN_SLEEP_NOW:-$(date +%s)}"; }

# 지금 이후로 오는 «첫 기상 시각»의 epoch. 오늘 기상 시각이 이미 지났으면 내일로 넘긴다.
next_wake() {
    local n parts dow hh mm ss midnight epoch
    n=$(now)
    # 🔑 GNU/BSD 로 갈리는 조회는 «epoch → 필드» 하나뿐이다. 그것만 정본(ts_fmt)에 맡기고
    #   나머지는 **산술**로 푼다 — 날짜 «문자열»을 다시 date 에 먹이는 순간 또 갈린다.
    parts=$(ts_fmt "$n" '+%u %H %M %S') || return 1
    set -- $parts
    dow=$1; hh=$2; mm=$3; ss=$4
    # 10# 이 없으면 08·09 가 «8진수»로 읽혀 죽는다
    midnight=$(( n - (10#$hh * 3600 + 10#$mm * 60 + 10#$ss) ))

    epoch=$(( midnight + $(wake_hour "$dow") * 3600 ))
    [ "$epoch" -gt "$n" ] && { echo "$epoch"; return 0; }

    # 오늘 기상 시각이 지났으면 내일.
    # ⚠️ **+86400 이 「다음날 같은 시각」인 것은 DST 가 없을 때만**이다 — 한국(Asia/Seoul)에도
    #   러너(UTC)에도 DST 가 없어서 성립한다. DST 지역으로 옮기면 여기가 첫 자리다.
    dow=$(( 10#$dow % 7 + 1 ))
    echo $(( midnight + 86400 + $(wake_hour "$dow") * 3600 ))
}

cmd="${1:-status}"
case "$cmd" in
    on)
        until_epoch=$(next_wake) || { echo "❌ 기상 시각 계산 실패" >&2; exit 1; }
        mkdir -p "$(dirname "$FLAG")" || exit 1
        printf '%s\n' "$until_epoch" > "$FLAG" || exit 1
        echo "🌙 취침 모드 ON — $(ts_fmt "$until_epoch" "+%m/%d %H:%M") 에 자동 해제"
        ;;
    off)
        rm -f "$FLAG"
        echo "☀️ 취침 모드 OFF"
        ;;
    status)
        if [ ! -f "$FLAG" ]; then
            echo "☀️ 안 자는 중 (플래그 없음)"; exit 0
        fi
        u=$(head -1 "$FLAG" 2>/dev/null | tr -d '[:space:]')
        case "$u" in
            ''|*[!0-9]*) echo "☀️ 안 자는 중 (플래그가 깨졌다: '${u}')"; exit 0 ;;
        esac
        if [ "$(now)" -lt "$u" ]; then
            echo "🌙 자는 중 — $(ts_fmt "$u" "+%m/%d %H:%M") 까지"
        else
            echo "☀️ 안 자는 중 (만료됨)"
        fi
        ;;
    *)
        echo "usage: darren-sleep.sh [on|off|status]" >&2; exit 2 ;;
esac
