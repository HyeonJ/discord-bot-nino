#!/usr/bin/env bash
# 아침 브리핑 — 날씨 + 할 일 (평일 07:00, **시스템 crontab**)
#
# 🔴 세션 cron 이 아니다(2026-07-31 이전). 세션 전용이던 시절, 07-30 23:03 재시작에 등록이
#   같이 사라져 **금요일 브리핑이 말없이 안 나갔다.** 세션 cron 으로 다시 등록하면 두 번 온다.
#   ⚠️ 시각을 바꾸면 `crontab -e` 와 **이 주석을 같이** 고칠 것 — 07시로 옮긴 07-30 에
#     주석이 08:00 인 채로 남아 있었다. 사본이 둘이면 하나는 낡는다.
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

# 🤝 자동 발신엔 `[감시]` 를 붙인다 — 셔틀이 이 변수를 보고 «모든» 전송에 태그한다.
#    호출 자리마다 붙이지 않는 이유: 새 전송을 추가해도 자동으로 태그되게(환경에 건다).
export NINO_AUTOSEND=1

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

CHANNEL_ID="${CHANNEL_ID:-1480593132511826092}"
TODO_FILE="${TODO_FILE:-$HOME/yaksu-shared-data/todo-list.md}"
WTTR_URL="${WTTR_URL:-https://wttr.in/Seoul?format=j1}"
WEATHER_JSON="${WEATHER_JSON:-}"          # 있으면 curl 대신 이 파일을 읽는다(테스트용)
DISCORD_SEND="${DISCORD_SEND:-$BOT_DIR/src/discord-send}"
# ── 인자 계약 (코어 cli-guard) ───────────────────────────────────────────────
# 🔴 옛 형태는 `DRY_RUN="${DRY_RUN:-0}"` 였다 — **환경에서만** 켤 수 있는 dry-run 이라,
#   환경에 그 값이 있는 것만으로 브리핑이 **발송 0건 · rc=0** 으로 조용히 멈춘다.
#   그리고 인자 파싱이 없어 모르는 플래그를 조용히 먹었다(09:50 사고와 같은 형태).
#
# 🔴 **이 스크립트는 이미 한 번 조용히 안 나갔다.** 07-30 23:03 재시작에 세션 cron 이 같이
#   사라져 **금요일 07시 브리핑이 말없이 빠졌고 아무도 몰랐다**(CLAUDE.md 에 기록).
#   ⇒ 그래서 여기선 거절을 **반드시 파일로** 남긴다. 이 스크립트엔 로그가 없었다 —
#     무음이 기본값인 자리에 무음으로 실패하는 갈래를 하나 더 얹을 수 없다.
BRIEFING_LOG="${BRIEFING_LOG:-$BOT_DIR/logs/morning-briefing.log}"
cli_guard_usage() {
    echo "usage: $(basename "$0") [--dry-run] [-h|--help]"
    echo "  --dry-run   브리핑을 만들되 Discord 발송은 하지 않고 stdout 으로만 낸다"
}
cli_guard_reject_log() {
    mkdir -p "$(dirname "$BRIEFING_LOG")" 2>/dev/null || true
    printf '%s verdict=%s rc=2\n' "$(TZ=Asia/Seoul date '+%Y-%m-%d %H:%M:%S')" "$1" \
        >> "$BRIEFING_LOG" 2>/dev/null || true
}
CLI_GUARD_ON_REJECT=cli_guard_reject_log
# 🔴 `$0` 이 아니라 **`${BASH_SOURCE[0]}`** 로 유도한다. 이 파일은 **source 되기도 한다**
#   (`morning-briefing.test.sh` ⑪ 이 `file_mtime` 하나만 부르려고 source 한다).
#   `$0` 기반 `SCRIPT_DIR` 은 그때 `.` 이 되어 `<repo>/lib/` 를 가리켰다 — 실측으로 깨졌다.
# shellcheck source=scripts/lib/cli-guard-boot.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/cli-guard-boot.sh"
TODO_TOP="${TODO_TOP:-3}"                 # 상위 몇 개를 읽어줄지
STALE_DAYS="${STALE_DAYS:-3}"             # 며칠 이상 안 바뀌면 그 사실을 덧붙인다

# 📮 「형이 정할 것」 — 세션 시작 절차만 읽던 목록을 매일 내보낸다.
# 🔴 왜: 이 목록은 memory/current-tasks.md 에만 살고, 그걸 읽는 것은 **세션 시작 때뿐**이다.
#   세션이 길게 붙어 있으면 며칠씩 안 나온다(실물 2026-08-11 재검: 끝난 항목이 6시간 넘게
#   목록에 남아 있었고 아무도 지운 사람이 없었다). Darren 승인 2026-08-12 `M:4oqv`.
# ⚠️ 좌변은 「## 📮 」 줄이다 — 🤝(룬드 몫)는 **안** 센다. 수신자가 다르다.
PENDING_FILE="${PENDING_FILE:-$BOT_DIR/memory/current-tasks.md}"
PENDING_TOP="${PENDING_TOP:-3}"
DRIFT_HEARTBEAT="${DRIFT_HEARTBEAT:-$BOT_DIR/logs/core-drift.heartbeat}"
# cron 은 `15 * * * *` = **매시 1회**. 임계 2시간은 곧 "두 번 연속 놓쳐야 경고" 다 —
# 1회 실패로는 안 울린다(단일 blip 오탐 방지 · health-checker 디바운스와 같은 이유).
# ⚠️ 이 값은 cron 주기와 짝이다. 주기를 바꾸면 여기도 같이 봐야 한다.
HEARTBEAT_STALE_HOURS="${HEARTBEAT_STALE_HOURS:-2}"   # 이 시간을 **넘으면** 낡은 것으로 본다
# 리뷰가 하나도 안 달린 PR — 우리 둘 다 이걸 재는 게 없어서 `#29` 가 이틀 묻혔다(2026-07-31).
# ⚠️ 양쪽 레포를 본다: 내 레포 = 룬드 리뷰 대기 · assistant = **내** 리뷰 대기.
#    한쪽만 보면 "내가 밀린 것"이 안 보인다 — 실제로 묻힌 건 그쪽이었다.
PR_REPOS="${PR_REPOS:-HyeonJ/discord-bot-nino dazebug/assistant}"
PR_LIST_CMD="${PR_LIST_CMD:-}"            # 비면 gh 를 쓴다(시험은 스텁 경로를 준다)
# 오늘 연 PR 까지 매일 세면 목록이 상시로 차서 **배경이 된다** — 그게 오늘 밤 잡은
# "상시 빨간불" 과 같은 실패다. 하루 넘긴 것만 센다.
PR_STALE_DAYS="${PR_STALE_DAYS:-1}"
PR_TOP="${PR_TOP:-3}"                     # 몇 개까지 줄로 읽어줄지

TODAY="$(TZ=Asia/Seoul date +%Y-%m-%d)"
DAY_NAMES=("" "월요일" "화요일" "수요일" "목요일" "금요일" "토요일" "일요일")
DAY_NAME="${DAY_NAMES[$(TZ=Asia/Seoul date +%u)]}"
# ⚠️ `%-m`(0 제거)는 GNU 전용 — BSD strftime 은 안 받는다. 0 을 셸에서 떼면 양쪽에서 같다.
_MON="$(TZ=Asia/Seoul date +%m)"; _DAY="$(TZ=Asia/Seoul date +%d)"
HEADER="☀️ ${_MON#0}/${_DAY#0} $DAY_NAME"

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

  # ⚠️ `mapfile` 은 **bash 4 전용**이다. macOS 기본 `/bin/bash` 는 3.2 라 여기서 죽고,
  #    죽는 자리가 목록 읽기라 **이 섹션 전체가 조용히 사라진다** — 룬드 맥 실측 8 fail 중
  #    6건이 이 한 줄에서 나왔다(2026-07-28, `enable -n mapfile` 로 재현). 한 뿌리였다.
  #    ⇒ while-read 로 읽는다. `IFS=` 와 `-r` 로 공백·역슬래시를 보존하는 건 mapfile 과 같다.
  local items=() total line
  while IFS= read -r line; do
    items[${#items[@]}]="$line"     # bash 3.2 는 `+=` 가 배열에 없다
  done < <(grep '^- \[ \] ' "$TODO_FILE" 2>/dev/null | sed 's/^- \[ \] //')
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
  # ⚠️ 여기도 `date -r FILE` 을 직접 쓰고 있었다 — 아래 file_mtime 의 폴백이 **한 자리에만**
  #    들어가서, macOS 에선 이 줄이 빈 값으로 산술 에러를 내고 안내가 통째로 사라졌다.
  #    (2026-07-28 BSD 흉내 실측: `( 1785233421 -  ) / 86400 : syntax error`)
  #    🔑 폴백을 자리마다 넣지 말고 **읽는 경로를 하나로** 모은다 — 개별로 고치면 다음 자리가 남는다.
  local age mt
  if mt="$(file_mtime "$TODO_FILE")"; then
    age=$(( ( $(date +%s) - mt ) / 86400 ))
    if (( age >= STALE_DAYS )); then
      tail="${tail:+$tail · }목록 ${age}일째 안 바뀜"
    fi
  else
    # 못 쟀는데 조용하면 "최신이라 안 붙었다" 와 구별이 안 된다 — 확인된 정상만 조용하다.
    tail="${tail:+$tail · }목록 갱신일 못 읽음"
  fi
  [[ -n "$tail" ]] && printf '       (%s)\n' "$tail"
}

# ── 📮 승인 대기 ─────────────────────────────────────────────────────────────
# 규약은 할 일 섹션과 같다 — **확인된 빈 상태는 조용**하고 **못 읽은 것은 시끄럽다.**
# 🔑 이 목록이 낡아 있는 것 자체가 매일 보이는 게 값이다(지운 사람이 없으면 계속 뜬다).
pending_section() {
  if [[ ! -f "$PENDING_FILE" ]]; then
    echo "⚠️ 승인 대기 못 읽음 — $PENDING_FILE 없음"
    return
  fi

  # bash 3.2 호환 — mapfile 금지, 배열 `+=` 금지 (위 할 일 섹션과 같은 이유)
  local items=() total line
  while IFS= read -r line; do
    items[${#items[@]}]="$line"
  done < <(grep '^## 📮 ' "$PENDING_FILE" 2>/dev/null | sed 's/^## 📮 //')
  total="${#items[@]}"
  (( total > 0 )) || return   # 확인된 빈 상태 → 줄을 뺀다

  echo "📮 형이 정할 것 ${total}건"
  local i
  for (( i = 0; i < total && i < PENDING_TOP; i++ )); do
    printf '       %s\n' "${items[$i]}"
  done
  local rest=$(( total - PENDING_TOP ))
  (( rest > 0 )) && printf '       (외 %d건)\n' "$rest"
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

# ── 리뷰가 안 달린 PR ────────────────────────────────────────────────────────
# 🔑 **리뷰 없는 PR 은 아무 신호도 안 낸다.** 알림은 열 때 한 번 오고 끝이라, 그때 못 보면
#    그 뒤로는 영원히 조용하다. 룬드 `#29` 는 그렇게 이틀 묻혔고, 그가 브랜치를 정리하다
#    **우연히** 찾았다. 같은 시각에 내 레포에도 리뷰 0건이 6개 있었는데 나는 몰랐다.
#    ⇒ 오늘 밤 내내 잡은 *못 쟀는데 정상으로 보인다* 의 프로세스 판이다. 여기서 소리를 낸다.
# ISO 날짜(2026-07-30) → epoch. GNU 는 `-d`, BSD 는 `-j -f`. 인자 의미가 아예 다르다.
# ⚠️ 정수 검사를 꼭 한다 — 못 쟀는데 빈 값을 넘기면 산술이 0 을 만들어 **"오늘 열림"**이
#    되고, 가장 오래 묵은 PR 이 임계에 걸려 조용히 빠진다(file_mtime 과 같은 자리).
# ⚠️ BSD 쪽은 시:분이 없으면 **현재 시각**을 채운다 — 하루 미만의 오차가 생기지만
#    임계가 일 단위라 판정이 갈리지 않는다. 시 단위로 볼 일이 생기면 여기부터 고친다.
# 🔴 BSD `date -j -f` 는 «빠진 필드를 현재 시각으로 채운다** — 날짜만 주면
#    「그 날 자정」이 아니라 **「그 날의 지금 시각」**이 나온다(룬드 맥 실측:
#    `2026-08-08` → `2026-08-08 16:02:24`). GNU `date -d` 는 자정을 준다.
#    ⇒ 같은 함수가 두 OS 에서 «다른 뜻»이었고, 맥에서만 값이 벽시계를 따라 흘렀다.
#    실피해: 호출부가 `now` 를 먼저 재고 `e` 를 나중에 재는데(:263 vs :273) 그 사이
#    초가 넘어가면 나이가 2일→1일로 떨어져 **PR 줄이 사라진다** — 맥 33% 플레이키.
#    🔑 리눅스 CI 는 이걸 «구조적으로» 못 본다. GNU 쪽은 결정적이라 늘 초록이다.
#    ⇒ BSD 에도 **시·분·초를 명시**해 두 갈래가 같은 뜻(자정)이 되게 한다.
iso_epoch() {
  local d="${1%%T*}" e
  e="$(date -d "$d" +%s 2>/dev/null)" || e=""
  [[ "$e" =~ ^[0-9]+$ ]] || e="$(date -j -f '%Y-%m-%d %H:%M:%S' "$d 00:00:00" +%s 2>/dev/null)"
  [[ "$e" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$e"
}

# gh 조회를 한 자리에 모은다 — 시험은 PR_LIST_CMD 로 통째로 갈아끼운다.
# ⚠️ `timeout` 은 GNU coreutils 라 macOS 엔 기본이 없다. 있으면 쓰고 없으면 그냥 돈다 —
#    **없다고 조회를 포기하면** 맥에서 이 섹션이 통째로 사라진다(무음=없음 규약 위반).
_gh_unreviewed() {
  local t=()
  command -v timeout >/dev/null 2>&1 && t=(timeout 20)
  "${t[@]}" gh pr list --repo "$1" --limit 50 --json number,title,createdAt,reviews \
    --jq '.[] | select(.reviews|length==0) | [.number, .createdAt, .title] | @tsv'
}

unreviewed_pr_section() {
  local cmd="$PR_LIST_CMD"
  if [[ -z "$cmd" ]]; then
    # 🔑 gh 부재는 "PR 이 없다"가 아니라 **못 쟀다**다. 조용히 넘기면 둘이 같아진다.
    command -v gh >/dev/null 2>&1 || { echo "⚠️ 리뷰 대기 PR 못 읽음 — gh 없음(판정 불가)"; return; }
    cmd=_gh_unreviewed
  fi

  local now items=() repo out rc num created title e age label short
  now="$(date +%s)"
  for repo in $PR_REPOS; do
    out="$("$cmd" "$repo" 2>/dev/null)"; rc=$?
    if (( rc != 0 )); then
      echo "⚠️ 리뷰 대기 PR 못 읽음 — $repo 조회 실패(rc=$rc)"
      continue
    fi
    short="${repo##*/}"
    while IFS=$'\t' read -r num created title; do
      [[ -n "$num" ]] || continue
      if e="$(iso_epoch "$created")"; then
        age=$(( (now - e) / 86400 ))
        (( age >= PR_STALE_DAYS )) || continue
        label="${age}일째"
      else
        # 나이를 못 쟀다고 빼면 그 PR 이 사라진다 — 넣되 **못 쟀다고 적는다**.
        label="열린 날 못 읽음"
      fi
      items[${#items[@]}]="$short#$num ($label) ${title:0:34}"   # bash 3.2 는 배열 += 없음
    done <<< "$out"
  done

  (( ${#items[@]} > 0 )) || return   # 확인된 0건 → 줄을 뺀다(무음=없음)

  echo "리뷰 안 달린 PR ${#items[@]}건"
  local i
  for (( i = 0; i < ${#items[@]} && i < PR_TOP; i++ )); do
    printf '       %s\n' "${items[$i]}"
  done
  local rest=$(( ${#items[@]} - PR_TOP ))
  (( rest > 0 )) && printf '       (외 %d건)\n' "$rest"
  return 0
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

# 🔑 아래를 main() 으로 묶고 소스 가드를 둔다 — 그래야 file_mtime 같은 순수 함수를
#    **단위로 부를 수 있다**. 묶기 전에는 `file_mtime` 의 실패 경로(정수 아님 → rc=1)에
#    닿는 시험이 없어서 변이가 살아남았다(M7·M8). 실행 경로는 그대로다:
#    `bash morning-briefing.sh` 면 BASH_SOURCE[0] == $0 이라 main 이 돈다.
main() {
WEATHER="$(weather_section)"
# 인사 분기에 쓸 강수확률 — 못 읽었으면 빈 값이고, 그러면 날씨 기반 분기를 안 탄다
# ⚠️ `\+` 는 **GNU sed 확장**이다 — BSD sed 는 BRE 에서 안 받아 매칭이 통째로 실패한다.
#    그러면 RAIN_PCT 이 비고, 인사가 강수 갈래를 못 타고 평일 기본 인사로 조용히 떨어진다
#    (룬드 맥 실측 2026-07-28 `분기 불일치`). `[0-9][0-9]*` 는 POSIX BRE 라 양쪽에서 같다.
RAIN_PCT="$(sed -n 's/.*강수 최대 \([0-9][0-9]*\)%.*/\1/p' <<<"$WEATHER" | head -1)"

MSG="$HEADER
$(greeting "$(TZ=Asia/Seoul date +%u)" "$RAIN_PCT")

$WEATHER

$(todo_section)

$(drift_heartbeat_section)

$(unreviewed_pr_section)

$(pending_section)"

# 섹션이 빠지면서 생긴 3줄 이상의 빈 줄을 정리한다(내용이 없는 건 티 안 나야 한다)
MSG="$(printf '%s\n' "$MSG" | cat -s)"

# 🔴 **억제와 가시성을 갈라 둔다** — 억제는 `cli_guard_send` 한 곳, 여기는 *보여주기*만.
#   갈래에서 `exit` 까지 하면 억제 기제가 두 벌이 되고, 뒤엣것은 갈래에 가려
#   **아무 시험도 안 밟는다**(`#103` 변이 M2 실측).
if [[ "$CLI_DRY_RUN" == "1" ]]; then
  printf '%s\n' "$MSG"
fi

cli_guard_send "$DISCORD_SEND" "$CHANNEL_ID" "$MSG"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # 🔴 인자 파싱은 **실행할 때만** 한다. 최상위에 두면 이 파일을 `source` 하는 쪽
  #   (시험이 `file_mtime` 하나를 부르려고 그렇게 한다)에서도 파싱이 돌고,
  #   그쪽 `"$@"` 는 전혀 다른 것이라 **모르는 인자로 판정돼 exit 2** 가 된다.
  #   🔑 코어 계약 ⑦(*source 는 부작용이 없다*)은 **소비자 쪽에서도 지켜야 한다** —
  #     계약을 지키는 라이브러리를 부작용 있는 자리에 배선하면 계약이 사라진다.
  cli_guard_boot "$@"
  main "$@"
fi
