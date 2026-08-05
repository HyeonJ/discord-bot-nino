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
set -uo pipefail

FLAG="${DARREN_SLEEP_FLAG:-$HOME/discord-bot-nino/logs/darren-sleeping}"
WEEKDAY_WAKE=7
WEEKEND_WAKE=9

# 시험이 «내일 아침»을 고정할 수 있어야 해서 now 를 주입받는다(기본은 실제 시각).
now() { echo "${DARREN_SLEEP_NOW:-$(date +%s)}"; }

# 지금 이후로 오는 «첫 기상 시각»의 epoch. 오늘 기상 시각이 이미 지났으면 내일로 넘긴다.
next_wake() {
    local n d wake target base epoch
    n=$(now)
    # ⚠️ GNU date 는 «@epoch +1 day» 를 «한 인자로» 못 읽는다(invalid date).
    #    epoch → 날짜로 먼저 굳히고, 날짜에 더한다. 실측 2026-08-05.
    base=$(date -d "@$n" +%Y-%m-%d 2>/dev/null) || return 1
    for d in 0 1; do
        target=$(date -d "$base +$d day" +%Y-%m-%d 2>/dev/null) || return 1
        case "$(date -d "$target" +%u)" in
            6|7) wake=$WEEKEND_WAKE ;;
            *)   wake=$WEEKDAY_WAKE ;;
        esac
        epoch=$(date -d "$target $(printf '%02d' "$wake"):00:00" +%s 2>/dev/null) || return 1
        [ "$epoch" -gt "$n" ] && { echo "$epoch"; return 0; }
    done
    return 1
}

cmd="${1:-status}"
case "$cmd" in
    on)
        until_epoch=$(next_wake) || { echo "❌ 기상 시각 계산 실패" >&2; exit 1; }
        mkdir -p "$(dirname "$FLAG")" || exit 1
        printf '%s\n' "$until_epoch" > "$FLAG" || exit 1
        echo "🌙 취침 모드 ON — $(date -d "@$until_epoch" '+%m/%d %H:%M') 에 자동 해제"
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
            echo "🌙 자는 중 — $(date -d "@$u" '+%m/%d %H:%M') 까지"
        else
            echo "☀️ 안 자는 중 (만료됨)"
        fi
        ;;
    *)
        echo "usage: darren-sleep.sh [on|off|status]" >&2; exit 2 ;;
esac
