#!/usr/bin/env bash
# 아침 브리핑 — 날씨 + 할 일 (평일 08:00 세션 cron)
#
# 왜 일정이 없나: Darren 지시(2026-07-28 M:jzmx). 이전 판은 Vault 의 주간 일간 파일을
#   읽었는데 ① 그 파일이 4월 초에 끊겼고 ② **달을 넘는 주는 애초에 매칭 불가**였다
#   (`W14_(3.30-4.3)` → `MONTH==3 && 30<=오늘<=3`). 즉 "써도 브리핑이 안 오는 파일"이라
#   안 쓰게 된 것이고, 원인이 사람 습관이 아니었다. 그 경로를 통째로 걷어냈다.
#
# 🔑 출력 규약 — **무음이 "없음"을 뜻하려면 실패가 항상 시끄러워야 한다**:
#   확인된 빈 상태(할 일 0건) → 그 섹션을 **뺀다**
#   소스 실패(날씨/목록 못 읽음) → **반드시 줄을 낸다**
#   조건 없이 빈 줄만 빼면 *확인된 빈 날*과 *못 읽은 날*이 둘 다 무음이 된다.
#   실제로 캘린더가 죽어 있었는데 줄이 없어서 아무도 몰랐다.
#
# 테스트 격리: 경로·소스를 전부 env 로 받는다(기본값이 프로덕션). 네트워크·전송 없이 검증 가능.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

CHANNEL_ID="${CHANNEL_ID:-1480593132511826092}"
TODO_FILE="${TODO_FILE:-$HOME/yaksu-shared-data/todo-list.md}"
WTTR_URL="${WTTR_URL:-https://wttr.in/Seoul?format=j1}"
WEATHER_JSON="${WEATHER_JSON:-}"          # 있으면 curl 대신 이 파일을 읽는다(테스트용)
DISCORD_SEND="${DISCORD_SEND:-$BOT_DIR/src/discord-send}"
DRY_RUN="${DRY_RUN:-0}"                   # 1이면 전송하지 않고 stdout 으로만 낸다
TODO_TOP="${TODO_TOP:-3}"                 # 상위 몇 개를 읽어줄지
STALE_DAYS="${STALE_DAYS:-3}"             # 며칠 이상 안 바뀌면 그 사실을 덧붙인다
DRIFT_HEARTBEAT="${DRIFT_HEARTBEAT:-$BOT_DIR/logs/core-drift.heartbeat}"
# cron 은 `15 * * * *` = **매시 1회**. 임계 2시간은 곧 "두 번 연속 놓쳐야 경고" 다 —
# 1회 실패로는 안 울린다(단일 blip 오탐 방지 · health-checker 디바운스와 같은 이유).
# ⚠️ 이 값은 cron 주기와 짝이다. 주기를 바꾸면 여기도 같이 봐야 한다.
HEARTBEAT_STALE_HOURS="${HEARTBEAT_STALE_HOURS:-2}"   # 이 시간을 **넘으면** 낡은 것으로 본다

TODAY="$(TZ=Asia/Seoul date +%Y-%m-%d)"
DAY_NAMES=("" "월요일" "화요일" "수요일" "목요일" "금요일" "토요일" "일요일")
DAY_NAME="${DAY_NAMES[$(TZ=Asia/Seoul date +%u)]}"
HEADER="☀️ $(TZ=Asia/Seoul date +%-m/%-d) $DAY_NAME"

# ── 날씨 ────────────────────────────────────────────────────────────────────
# 수치가 필요하므로 j1(JSON)을 쓴다. 짧은 format 문자열은 체감·최고최저·강수확률을 못 준다.
weather_section() {
  local raw
  if [[ -n "$WEATHER_JSON" ]]; then
    raw="$(cat "$WEATHER_JSON" 2>/dev/null)"
  else
    raw="$(curl -sS --max-time 15 "$WTTR_URL" 2>/dev/null)"
  fi
  [[ -n "$raw" ]] || { echo "⚠️ 날씨 못 읽음 — wttr.in 응답 없음"; return; }

  local out
  out="$(printf '%s' "$raw" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    c, t = d["current_condition"][0], d["weather"][0]
    # wttr.in 은 `lang=ko` 를 줘도 lang_ko 값이 영어 그대로다(2026-07-28 실측) → 직접 옮긴다.
    # ⚠️ 모르는 값은 **영어 그대로 노출**한다. 빈 문자열로 지우면 새 날씨 표현이 조용히 사라진다.
    KO = {
        "Sunny": "맑음", "Clear": "맑음",
        "Partly cloudy": "구름 조금", "Cloudy": "흐림", "Overcast": "잔뜩 흐림",
        "Mist": "안개", "Fog": "안개", "Freezing fog": "짙은 안개",
        "Patchy rain nearby": "곳곳에 비", "Patchy rain possible": "비 올 수도",
        "Light rain": "약한 비", "Moderate rain": "비", "Heavy rain": "강한 비",
        "Light rain shower": "소나기", "Moderate or heavy rain shower": "강한 소나기",
        "Thundery outbreaks possible": "천둥 가능", "Patchy light drizzle": "이슬비",
        "Light drizzle": "이슬비", "Light snow": "약한 눈", "Moderate snow": "눈",
        "Heavy snow": "폭설", "Patchy snow nearby": "곳곳에 눈",
    }
    raw_desc = c["weatherDesc"][0]["value"].strip()
    desc = KO.get(raw_desc, raw_desc)
    rain = max(t["hourly"], key=lambda h: int(h["chanceofrain"]))
    hour = int(rain["time"]) // 100
    print("날씨   {}°C (체감 {}°C) · 습도 {}% · {}".format(
        c["temp_C"], c["FeelsLikeC"], c["humidity"], desc))
    print("       최고 {} / 최저 {} · 강수 최대 {}% ({}시)".format(
        t["maxtempC"], t["mintempC"], rain["chanceofrain"], hour))
    if int(rain["chanceofrain"]) >= 40:
        print("       → 우산 챙겨")
except Exception as e:
    print("⚠️ 날씨 못 읽음 — 응답 해석 실패 ({})".format(type(e).__name__))
' 2>/dev/null)"

  # 🔑 try/except 는 **파이썬이 살아서 돌 때만** 동작한다. 문법 오류·인터프리터 부재처럼
  #    프로그램 자체가 안 뜨면 stdout 이 비고, 그러면 날씨 줄이 통째로 조용히 사라진다.
  #    (이 테스트를 쓰면서 실제로 그렇게 됐다 — 출력 없음을 실패로 못 보면 규약이 깨진다.)
  [[ -n "$out" ]] || { echo "⚠️ 날씨 못 읽음 — 해석기 실행 실패"; return; }
  printf '%s\n' "$out"
}

# ── 할 일 ───────────────────────────────────────────────────────────────────
# 미완료 0건이면 **섹션 자체를 빼고**(무음=없음), 파일이 없으면 **반드시 알린다**.
todo_section() {
  if [[ ! -f "$TODO_FILE" ]]; then
    echo "⚠️ 할 일 목록 못 읽음 — $TODO_FILE 없음"
    return
  fi

  local items total
  mapfile -t items < <(grep '^- \[ \] ' "$TODO_FILE" 2>/dev/null | sed 's/^- \[ \] //')
  total="${#items[@]}"
  (( total > 0 )) || return   # 확인된 빈 상태 → 줄을 뺀다

  echo "할 일"
  local i
  for (( i = 0; i < total && i < TODO_TOP; i++ )); do
    printf '       %s\n' "${items[$i]}"
  done

  local rest=$(( total - TODO_TOP ))
  local tail=""
  (( rest > 0 )) && tail="외 ${rest}건"

  # 오래 안 바뀐 목록을 매일 그대로 읽어주면 낡은 것만 반복하게 된다 → 그 사실을 덧붙인다
  local age
  age=$(( ( $(date +%s) - $(date -r "$TODO_FILE" +%s) ) / 86400 ))
  if (( age >= STALE_DAYS )); then
    tail="${tail:+$tail · }목록 ${age}일째 안 바뀜"
  fi
  [[ -n "$tail" ]] && printf '       (%s)\n' "$tail"
}

# ── 코어 드리프트 감시 하트비트 ──────────────────────────────────────────────
# 🔑 core-drift-cron.sh 는 이상이 없으면 **조용한 게 정상**이다. 그래서 *cron 이 죽어서
#    아무 말이 없는 것*과 *이상이 없어서 조용한 것*이 같은 모양이 된다. 하트비트는 그
#    둘을 가르려고 남기는 파일인데, **읽는 쪽이 없으면 파일만 쌓이고 구분이 안 선다.**
#    (core-drift-cron.sh 의 `TODO(승인 ③ 후속)` 이 이것 — 여기서 닫는다.)
# ⚠️ "없음"과 "낡음"은 원인이 다르다: 없음=한 번도 안 돎(cron 미등록) · 낡음=돌다 멈춤.
#    조치가 다르므로 문구를 갈라야 한다. 합치면 "왜 안 도는지"를 매번 다시 조사하게 된다.
# 신선하면 아무 것도 출력하지 않는다 — 위의 출력 규약(확인된 정상은 섹션을 뺀다) 그대로.
# 파일 mtime(epoch) — GNU/BSD 양쪽 (룬드 리뷰 2026-07-28).
#   GNU  `date -r FILE`  = 파일 mtime
#   BSD  `date -r SECS`  = epoch 를 날짜로   ← **인자 의미가 다르다**(파일명을 주면 에러)
# ⚠️ 폴백 `stat -f` 는 GNU 에선 --file-system 이라 **다른 걸 조용히 찍는다**. 그래서
#    값이 정수인지 검사하고 아니면 **실패로 낸다** — 못 쟀는데 0 을 돌려주면 "방금 갱신됨"이
#    되어 죽은 cron 이 신선하게 보인다.
file_mtime() {
  local m
  m="$(date -r "$1" +%s 2>/dev/null)" || m=""
  [[ "$m" =~ ^[0-9]+$ ]] || m="$(stat -f %m "$1" 2>/dev/null)"
  [[ "$m" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$m"
}

drift_heartbeat_section() {
  # 🔑 순서가 중요하다: **볼 수 있나 → 있나 → 언제인가**.
  #    처음엔 `[[ ! -f ]]` 를 먼저 봤는데, 디렉터리를 못 뒤지면 `-f` 도 실패해서
  #    **"한 번도 안 돌았다"로 단정**했다 — *없는 것*과 *못 보는 것*을 합친 것이다.
  #    같은 날 `check-core-drift.sh` 에서 `?`(못 쟀다)를 STALE(미달)로 접었던 것과
  #    같은 부류이고, 시험 ⑩-6 이 잡았다.
  local dir mt age_h
  dir="$(dirname "$DRIFT_HEARTBEAT")"
  if [[ ! -r "$dir" || ! -x "$dir" ]]; then
    echo "⚠️ 코어 드리프트 하트비트를 볼 수 없다 — 신선한지 판정 불가 (디렉터리 접근 불가)"
    return
  fi
  if [[ ! -f "$DRIFT_HEARTBEAT" ]]; then
    echo "⚠️ 코어 드리프트 감시가 한 번도 안 돌았다 — cron 미등록일 수 있어 (하트비트 없음)"
    return
  fi
  if ! mt="$(file_mtime "$DRIFT_HEARTBEAT")"; then
    echo "⚠️ 코어 드리프트 하트비트의 시각을 못 읽었다 — 신선한지 판정 불가"
    return
  fi
  age_h=$(( ( $(date +%s) - mt ) / 3600 ))
  if (( age_h > HEARTBEAT_STALE_HOURS )); then
    echo "⚠️ 코어 드리프트 감시가 ${age_h}시간째 안 돌았다 — cron 이 멈췄을 수 있어"
  fi
}

# ── 인사 ────────────────────────────────────────────────────────────────────
# Darren 요청(2026-07-28 M:44r9). 매일 같은 문장이면 안 읽게 되므로 **요일·날씨로 갈린다**.
# ⚠️ 인사는 정보가 아니다 — 날씨/할 일을 못 읽어도 인사는 나온다. 그래서 인사의 유무로
#    상태를 판단하면 안 되고, 판단은 위 두 섹션의 경고 줄이 한다.
greeting() {
  local dow="$1" rain="$2"
  case "$dow" in
    1) echo "월요일이다… 천천히 시작하자" ;;
    5) echo "금요일! 오늘만 버티면 돼" ;;
    6|7) echo "주말이야, 푹 쉬어~" ;;
    *) if [[ -n "$rain" ]] && (( rain >= 60 )); then
         echo "오늘 비 많이 온대. 조심해서 다녀와"
       elif [[ -n "$rain" ]] && (( rain >= 40 )); then
         echo "오늘 비 올 수도 있어"
       else
         echo "좋은 아침~ 오늘도 화이팅"
       fi ;;
  esac
}

WEATHER="$(weather_section)"
# 인사 분기에 쓸 강수확률 — 못 읽었으면 빈 값이고, 그러면 날씨 기반 분기를 안 탄다
RAIN_PCT="$(sed -n 's/.*강수 최대 \([0-9]\+\)%.*/\1/p' <<<"$WEATHER" | head -1)"

MSG="$HEADER
$(greeting "$(TZ=Asia/Seoul date +%u)" "$RAIN_PCT")

$WEATHER

$(todo_section)

$(drift_heartbeat_section)"

# 섹션이 빠지면서 생긴 3줄 이상의 빈 줄을 정리한다(내용이 없는 건 티 안 나야 한다)
MSG="$(printf '%s\n' "$MSG" | cat -s)"

if [[ "$DRY_RUN" == "1" ]]; then
  printf '%s\n' "$MSG"
  exit 0
fi

"$DISCORD_SEND" "$CHANNEL_ID" "$MSG"
