#!/usr/bin/env bash
# morning-briefing.sh 계약 테스트 (네트워크·Discord 전송 안 씀 — 전부 env 주입)
#
# 왜: 이전 판은 Vault 일간 파일을 읽었는데 **달을 넘는 주가 매칭 불가**여서 4월부터
#   조용히 실패했다(`W14_(3.30-4.3)` → `MONTH==3 && 30<=오늘<=3`). 아무도 몰랐던 이유는
#   실패가 출력되지 않았기 때문이다 — 같은 계열로 캘린더도 죽은 채 방치돼 있었다.
#   그래서 이 테스트의 본체는 **실패가 시끄러운가**다.
#
# 규약: 확인된 빈 상태(할 일 0건) → 섹션을 뺀다 / 소스 실패 → 반드시 줄을 낸다.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# ⚠️ 스텁이 PATH 를 가리기 **전에** 진짜 경로를 잡는다. 절대경로를 박으면 안 된다 —
#    `/usr/bin/date` 는 리눅스에만 있고 macOS 는 `/bin/date` 라 스텁이 죽는다
#    (룬드 맥 실측 2026-07-28 `폴백 실패` — 스크립트가 아니라 이 시험이 틀린 자리였다).
REAL_DATE="$(command -v date)"
export REAL_DATE
source "$SCRIPT_DIR/lib/timeshift.sh"   # 시각 조작은 정본 하나를 지난다(GNU/BSD 공용)
BOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$BOT_DIR/scripts/morning-briefing.sh"

pass=0; fail=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; fail=$((fail + 1)); [[ -n "${2:-}" ]] && printf '%s\n' "$2" | sed 's/^/     /'; }

[[ -f "$SCRIPT" ]] || { echo "❌ 대상 스크립트 없음: $SCRIPT"; exit 1; }

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT

cat > "$ROOT/weather.json" <<'JSON'
{"current_condition":[{"temp_C":"27","FeelsLikeC":"31","humidity":"100",
  "weatherDesc":[{"value":"Cloudy"}]}],
 "weather":[{"maxtempC":"33","mintempC":"25",
  "hourly":[{"time":"300","chanceofrain":"54"},{"time":"900","chanceofrain":"10"}]}]}
JSON
echo 'not json at all' > "$ROOT/broken.json"

cat > "$ROOT/todo.md" <<'MD'
# 할 일
- [ ] 첫째 항목
- [ ] 둘째 항목
- [ ] 셋째 항목
- [ ] 넷째 항목
- [x] 끝난 것
MD
printf '# 할 일\n- [x] 끝난 것만 있음\n' > "$ROOT/empty-todo.md"

run() {  # run <TODO_FILE> <WEATHER_JSON> [DRIFT_HEARTBEAT] — 항상 DRY_RUN
  # 하트비트를 안 주면 **신선한 것**을 기본으로 깐다 — 안 그러면 기존 시험 전부가
  # "하트비트 없음" 경고를 달고 나와서, 다른 섹션을 보는 단언이 흔들린다.
  # ⚠️ PR_LIST_CMD 를 안 주면 기본값이 **진짜 gh 를 친다** — 시험이 네트워크·계정에 매달리고,
  #    조회가 느리거나 실패하면 다른 단언까지 흔들린다. 기본은 항상 "0건 스텁"으로 막는다.
  #    (같은 자리를 룬드 `#35` 리뷰에서 잡았다: 시험이 진짜 API 를 치고 있었다.)
  DRY_RUN=1 TODO_FILE="$1" WEATHER_JSON="$2" \
    DRIFT_HEARTBEAT="${3:-$ROOT/hb-fresh}" \
    PR_LIST_CMD="${PR_LIST_CMD:-$ROOT/pr-none}" \
    DISCORD_SEND="$ROOT/should-not-be-called" \
    bash "$SCRIPT" 2>&1
}
printf '%s rc=0\n' "$(date '+%Y-%m-%d %H:%M:%S')" > "$ROOT/hb-fresh"

# 스텁 만들기 — `run()` 의 기본 스텁(pr-none)은 **여기서** 만들어야 한다.
# ⚠️ 처음엔 ⑪ 구간에서 만들었다가 앞쪽 시험이 전부 "PR 못 읽음" 경고를 달고 나왔고,
#    ④(빈 상태 ≠ 실패)가 그걸 잡았다 — **기본값이 없는 파일을 가리키면 조회 실패가 된다.**
_mk() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$ROOT/$1"; chmod +x "$ROOT/$1"; }
_mk pr-none 'exit 0'                                   # 조회 성공 · 0건

echo "① 정상 — 날씨 수치와 상위 3개가 들어간다"
out="$(run "$ROOT/todo.md" "$ROOT/weather.json")"
if grep -q '27°C (체감 31°C)' <<<"$out" && grep -q '최고 33 / 최저 25' <<<"$out"; then
  ok "날씨 수치 표시"; else bad "날씨 수치 없음" "$out"; fi
if grep -q '첫째 항목' <<<"$out" && grep -q '셋째 항목' <<<"$out" && ! grep -q '넷째 항목' <<<"$out"; then
  ok "상위 3개만 표시(4번째 제외)"; else bad "상위 N개 절단 실패" "$out"; fi
if grep -q '외 1건' <<<"$out"; then ok "남은 건수 표시"; else bad "남은 건수 없음" "$out"; fi
if grep -q '우산 챙겨' <<<"$out"; then ok "강수 54% → 우산 안내"; else bad "우산 안내 없음" "$out"; fi

echo "② 확인된 빈 상태 — 할 일 0건이면 **섹션 자체가 없다**(무음 = 없음)"
out="$(run "$ROOT/empty-todo.md" "$ROOT/weather.json")"
if ! grep -q '할 일' <<<"$out"; then ok "할 일 섹션 제거"; else bad "빈 섹션이 남았다" "$out"; fi
if grep -q '27°C' <<<"$out"; then ok "날씨는 그대로"; else bad "날씨가 사라졌다" "$out"; fi

echo "③ 소스 실패 — **반드시 시끄러워야** 한다"
out="$(run "$ROOT/없는파일.md" "$ROOT/weather.json")"
if grep -q '할 일 목록 못 읽음' <<<"$out"; then ok "목록 파일 없음 → 경고"; else bad "조용히 넘어갔다" "$out"; fi

out="$(run "$ROOT/todo.md" "$ROOT/broken.json")"
if grep -q '날씨 못 읽음' <<<"$out"; then ok "날씨 응답 깨짐 → 경고"; else bad "조용히 넘어갔다" "$out"; fi

out="$(run "$ROOT/todo.md" "$ROOT/없는날씨.json")"
if grep -q '날씨 못 읽음' <<<"$out"; then ok "날씨 응답 없음 → 경고"; else bad "조용히 넘어갔다" "$out"; fi

echo "④ 빈 상태와 실패가 **서로 다른 출력**이다 (이 시험의 본체)"
empty="$(run "$ROOT/empty-todo.md" "$ROOT/weather.json")"
broken="$(run "$ROOT/없는파일.md" "$ROOT/weather.json")"
if [[ "$empty" != "$broken" ]] && ! grep -q '못 읽음' <<<"$empty"; then
  ok "0건과 못읽음이 구분된다"; else bad "두 상태가 같은 출력" "empty:$empty
broken:$broken"; fi

echo "⑤ 오래된 목록 — 며칠째 안 바뀌었는지 덧붙인다"
touch_ago $(( 10 * DAY )) "$ROOT/todo.md"
out="$(run "$ROOT/todo.md" "$ROOT/weather.json")"
if grep -q '10일째 안 바뀜' <<<"$out"; then ok "정지 기간 표시"; else bad "정지 표시 없음" "$out"; fi
touch "$ROOT/todo.md"   # 인자 없는 touch = 지금 (POSIX)
out="$(run "$ROOT/todo.md" "$ROOT/weather.json")"
if ! grep -q '안 바뀜' <<<"$out"; then ok "최신이면 안 붙는다(수렴)"; else bad "최신인데 붙었다" "$out"; fi

echo "⑥ 날씨 설명 한글화 — 모르는 값은 **영어 그대로 노출**한다(조용히 지우지 않는다)"
out="$(run "$ROOT/todo.md" "$ROOT/weather.json")"
if grep -q '흐림' <<<"$out"; then ok "Cloudy → 흐림"; else bad "매핑 안 됨" "$out"; fi
sed 's/Cloudy/Blood rain of frogs/' "$ROOT/weather.json" > "$ROOT/unknown.json"
out="$(run "$ROOT/todo.md" "$ROOT/unknown.json")"
if grep -q 'Blood rain of frogs' <<<"$out"; then ok "모르는 값 원문 노출"; else bad "미지의 값이 사라졌다" "$out"; fi

echo "⑦ wttr.in 은 설명 끝에 **공백을 붙여** 준다 (룬드 실측: \"Partly Cloudy \")"
sed 's/"Cloudy"/"Cloudy "/' "$ROOT/weather.json" > "$ROOT/trailing.json"
out="$(run "$ROOT/todo.md" "$ROOT/trailing.json")"
if grep -q '흐림' <<<"$out"; then ok "공백 붙어도 매핑된다(strip)"; else bad "공백 때문에 매핑 미스" "$out"; fi

echo "⑧ 인사줄 — 요일·강수로 갈리고, **정보가 아니라 인사다**"
out="$(run "$ROOT/todo.md" "$ROOT/weather.json")"
if [[ "$(sed -n '2p' <<<"$out")" != "" ]]; then ok "둘째 줄에 인사가 있다"; else bad "인사줄 없음" "$out"; fi
# 강수 54% → "비 올 수도" (평일 기준). 주말이면 주말 인사가 이기므로 요일로 기대값을 나눈다
dow="$(TZ=Asia/Seoul date +%u)"
case "$dow" in
  1) want="월요일" ;; 5) want="금요일" ;; 6|7) want="주말" ;; *) want="비 올 수도" ;;
esac
if grep -q "$want" <<<"$out"; then ok "요일/날씨 분기 일치($want)"; else bad "분기 불일치(기대 $want)" "$out"; fi

# ⑧-2 **BSD sed 에서도 강수를 읽는다** — `\+` 는 GNU 확장이라 BSD 는 매칭 자체가 실패한다
#   왜: 실패하면 RAIN_PCT 이 비고 인사가 강수 갈래를 못 타 **평일 기본 인사로 조용히 떨어진다.**
#   룬드 맥 실측(2026-07-28)에서 `분기 불일치` 로 나온 자리다.
#   ⚠️ 환경을 통째로 흉내 내지 않는다 — **가설 하나만 겨냥한다**(GNU 확장을 끈 sed).
#      두 겹 스텁으로 BSD 를 흉내 냈다가 부분집합이 돼서 못 잡은 적이 있다(#50 ⑤-4).
if sed --posix -n 's/x\([0-9][0-9]*\)y/\1/p' </dev/null >/dev/null 2>&1; then
  REAL_SED="$(command -v sed)"; export REAL_SED
  mkdir -p "$ROOT/posixsed"
  printf '#!/bin/bash\nexec "$REAL_SED" --posix "$@"\n' > "$ROOT/posixsed/sed"
  chmod +x "$ROOT/posixsed/sed"
  if [[ "$dow" != "1" && "$dow" != "5" && "$dow" != "6" && "$dow" != "7" ]]; then
    out="$(PATH="$ROOT/posixsed:$PATH" run "$ROOT/todo.md" "$ROOT/weather.json")"
    if grep -q '비 올 수도' <<<"$out"; then ok "GNU 확장 없는 sed 로도 강수를 읽는다(BSD 갈래)"; else bad "BSD sed 에서 강수를 잃었다 — 인사가 갈래를 못 탔다" "$out"; fi
  else
    echo "  ⛔ 판정 불가 — 오늘은 요일 인사가 이겨서 강수 갈래를 못 잰다(평일에 재야 한다)"
  fi
else
  echo "  ⛔ 판정 불가 — 이 기계의 sed 가 --posix 를 안 받아 GNU 확장을 끌 수 없다"
fi
# 인사는 소스가 죽어도 나온다 — 인사의 유무로 상태를 판단하면 안 된다는 규약
out="$(run "$ROOT/없는파일.md" "$ROOT/없는날씨.json")"
if [[ "$(sed -n '2p' <<<"$out")" != "" ]] && grep -q '못 읽음' <<<"$out"; then
  ok "소스 실패해도 인사는 나오고, 판단은 경고 줄이 한다"; else bad "실패 시 인사/경고 조합이 깨짐" "$out"; fi

echo "⑪ file_mtime 이식성 — BSD 흉내 + 쓰레기값 (변이 M7·M8 이 살아남아서 추가)"
# 🔑 왜 스텁이 필요한가: 이 기계는 GNU 라 `date -r FILE` 이 그냥 성공한다. 즉 **폴백
#    경로와 실패 경로에 닿는 시험이 없었고**, 그래서 정수 검사를 지우는 변이가 살아남았다.
#    로케일·OS 처럼 "여기선 안 밟히는 갈래"는 스텁으로 밟아줘야 잠긴다.
STUB="$ROOT/stub"; mkdir -p "$STUB"
cat > "$STUB/date" <<'EOF'
#!/bin/bash
# BSD 흉내 — `date -r` 는 epoch 를 받는다. 파일명을 주면 실패.
if [[ "${1:-}" == "-r" && ! "${2:-}" =~ ^[0-9]+$ ]]; then
  echo "date: illegal time format" >&2; exit 1
fi
exec "$REAL_DATE" "$@"
EOF
chmod +x "$STUB/date"
mk_stat() { printf '#!/bin/bash
echo %q
' "$1" > "$STUB/stat"; chmod +x "$STUB/stat"; }

# ⑪-1 BSD 에서 폴백(stat)이 정수를 주면 성공한다
mk_stat "1785400000"
out="$(PATH="$STUB:$PATH" bash -c 'source "$1"; file_mtime "$2"' _ "$SCRIPT" "$ROOT/hb-fresh" 2>&1)"
if [[ "$out" == "1785400000" ]]; then ok "BSD 흉내 — stat 폴백으로 mtime 을 얻는다"; else bad "폴백 실패" "$out"; fi

# ⑪-2 🔑 폴백이 **정수가 아닌 값**을 주면 실패로 낸다 (GNU 의 stat -f 는 딴 걸 찍는다)
mk_stat "?"
if PATH="$STUB:$PATH" bash -c 'source "$1"; file_mtime "$2"' _ "$SCRIPT" "$ROOT/hb-fresh" >/dev/null 2>&1; then
  bad "쓰레기값을 성공으로 돌려줬다 — 0 으로 계산되면 '방금 갱신됨'이 된다"
else ok "정수가 아니면 실패(rc≠0)로 낸다"; fi

# ⑪-3 그 실패가 브리핑에서 **조용히 신선**이 되면 안 된다
out="$(PATH="$STUB:$PATH" DRY_RUN=1 TODO_FILE="$ROOT/todo.md" WEATHER_JSON="$ROOT/weather.json" \
        DRIFT_HEARTBEAT="$ROOT/hb-fresh" DISCORD_SEND="$ROOT/should-not-be-called" \
        bash "$SCRIPT" 2>&1)"
if grep -q '판정 불가' <<<"$out"; then ok "못 읽으면 '판정 불가'가 브리핑에 뜬다"; else bad "조용히 넘어갔다" "$out"; fi

echo "⑨ DRY_RUN 은 전송하지 않는다"
if [[ ! -e "$ROOT/should-not-be-called" ]]; then ok "discord-send 미호출"; else bad "전송이 일어났다"; fi

echo "⑩ 코어 드리프트 하트비트 — cron 이 죽은 상태가 무음이면 안 된다 (승인 ③ 후속)"
# 🔑 왜 여기 붙나: core-drift-cron.sh 는 rc=0 이면 **조용한 게 정상**이다. 그래서
#    "cron 이 죽어서 아무 말이 없는 것"과 "이상이 없어서 조용한 것"이 같은 모양이 된다.
#    하트비트는 그 둘을 가르려고 남기는데, **읽는 쪽이 없으면 파일만 쌓이고 구분이 안 선다.**
#    이 브리핑이 그 읽는 쪽이다.

# ⑩-1 신선하면 아무 말도 안 한다 (확인된 정상 → 섹션을 뺀다)
out="$(run "$ROOT/todo.md" "$ROOT/weather.json" "$ROOT/hb-fresh")"
if ! grep -q '드리프트 감시' <<<"$out"; then ok "신선하면 조용하다"; else bad "정상인데 떠들었다" "$out"; fi

# ⑤-3 mtime 을 **못 읽으면 그렇게 말한다** — 조용하면 "최신이라 안 붙었다" 와 구별이 안 된다
#   왜: 이 자리는 `date -r FILE` 을 직접 써서 macOS 에서 산술 에러로 안내가 통째로 사라졌다.
#   폴백을 태운 뒤에도 **읽는 경로가 둘 다 실패**할 수 있으니(권한·이상한 FS) 그 갈래를 잠근다.
mkdir -p "$ROOT/nomtime"
cat > "$ROOT/nomtime/date" <<'NOMT'
#!/bin/bash
[ "$1" = "-r" ] && exit 1     # 파일 mtime 읽기만 막는다
exec /bin/date "$@"
NOMT
cat > "$ROOT/nomtime/stat" <<'NOMT'
#!/bin/bash
[ "$1" = "-f" ] && exit 1     # BSD 폴백도 막는다
exec /usr/bin/stat "$@"
NOMT
chmod +x "$ROOT/nomtime/date" "$ROOT/nomtime/stat"
out="$(PATH="$ROOT/nomtime:$PATH" run "$ROOT/todo.md" "$ROOT/weather.json")"
if grep -q '못 읽음' <<<"$out"; then ok "갱신일을 못 읽으면 못 읽었다고 말한다"; else bad "못 읽었는데 조용하다(최신과 구별 불가)" "$out"; fi
if ! grep -qE '일째 안 바뀜' <<<"$out"; then ok "못 잰 것을 일수로 단정하지 않는다"; else bad "못 쟀는데 일수를 말했다" "$out"; fi

# ⑤-4 **BSD 갈래를 가른다** — `date -r FILE` 이 안 되는 기계에서도 mtime 을 읽어야 한다
#   ⚠️ ⑤-3 은 두 경로를 **동시에** 막아서, 폴백이 있는 코드와 없는 코드가 같은 답을 낸다
#      (실측: 폴백을 떼는 변이가 ⑤-3 만으로는 살아남았다). 존재 검사는 등가변이에 먹힌다 —
#      **한쪽만 막고 다른 쪽이 살아 있는** 상태라야 갈래가 갈린다.
#   macOS: `date -r` 은 인자 의미가 달라 파일에 못 쓰고, `stat -f %m` 이 동작하는 기계다.
mkdir -p "$ROOT/bsdlike"
cat > "$ROOT/bsdlike/date" <<'BSDD'
#!/bin/bash
[ "$1" = "-r" ] && { echo "date: illegal time format" >&2; exit 1; }   # BSD 는 파일을 못 받는다
exec /bin/date "$@"
BSDD
cat > "$ROOT/bsdlike/stat" <<'BSDS'
#!/bin/bash
# BSD `stat -f %m` = mtime epoch. GNU 기계에서는 -c %Y 로 같은 값을 낸다(폴백이 사는 조건).
# ⚠️ GNU 를 **먼저** 시도한다 — GNU 의 `-f` 는 --file-system 이라 실패하지 않고 마운트포인트를
#    조용히 찍는다(`||` 가 안 걸린다). 실제로 이 스텁을 그 순서로 썼다가 한 번 밟았다.
if [ "$1" = "-f" ] && [ "$2" = "%m" ]; then
  /usr/bin/stat -c %Y "$3" 2>/dev/null || /usr/bin/stat -f %m "$3"
  exit $?
fi
exec /usr/bin/stat "$@"
BSDS
chmod +x "$ROOT/bsdlike/date" "$ROOT/bsdlike/stat"
touch_ago $(( 10 * DAY )) "$ROOT/todo.md"
out="$(PATH="$ROOT/bsdlike:$PATH" run "$ROOT/todo.md" "$ROOT/weather.json")"
if grep -q '10일째 안 바뀜' <<<"$out"; then ok "date -r 이 막혀도 폴백으로 mtime 을 읽는다(BSD 갈래)"; else bad "BSD 갈래에서 정지 기간을 잃었다" "$out"; fi
touch "$ROOT/todo.md"

# ⑤-5 **bash 3.2 에서도 돈다** — macOS 기본 /bin/bash 가 3.2 다
#   왜: `mapfile` 은 bash 4 전용이라 3.2 에선 목록 읽기가 죽고 **섹션이 통째로 사라진다.**
#   룬드 맥 실측 8 fail 중 6건이 그 한 줄에서 나왔다(2026-07-28) — 8개가 아니라 한 뿌리였다.
#   ⚠️ 문구를 grep 하지 않고 **동작으로 판정**한다: bash 4 전용 빌트인을 꺼서 실제로 돌려본다.
#      (grep 은 `mapfile` 만 잡지만, 이 검사는 그 경로에 들어오는 3.2 미지원 빌트인을 다 잡는다)
cat > "$ROOT/no-bash4" <<'NB4'
enable -n mapfile 2>/dev/null
enable -n readarray 2>/dev/null
NB4
out="$(BASH_ENV="$ROOT/no-bash4" run "$ROOT/todo.md" "$ROOT/weather.json")"
if grep -q '첫째 항목' <<<"$out"; then ok "bash 4 빌트인 없이도 할 일 섹션이 나온다(3.2 호환)"; else bad "bash 3.2 에서 섹션이 사라진다" "$out"; fi

# ⑤-6 날짜 헤더에 **포맷 문자가 새어나오지 않는다** — `%-m` 은 GNU 전용이라 BSD 에선 안 풀린다
out="$(run "$ROOT/todo.md" "$ROOT/weather.json")"
hdr="$(printf '%s\n' "$out" | head -1)"
if ! grep -q '%' <<<"$hdr"; then ok "헤더에 미해석 포맷 문자가 없다"; else bad "헤더에 % 가 남았다(GNU 전용 포맷)" "$hdr"; fi

# ⑩-2 낡으면 반드시 줄을 낸다 + 얼마나 낡았는지
touch_ago $(( 5 * HOUR )) "$ROOT/hb-fresh.stale"
printf 'old rc=0\n' >> /dev/null
: > "$ROOT/hb-stale"; printf '%s rc=0\n' "$(fmt_ago $(( 5 * HOUR )) '+%Y-%m-%d %H:%M:%S')" > "$ROOT/hb-stale"
touch_ago $(( 5 * HOUR )) "$ROOT/hb-stale"
out="$(run "$ROOT/todo.md" "$ROOT/weather.json" "$ROOT/hb-stale")"
if grep -q '드리프트 감시' <<<"$out"; then ok "낡으면 줄을 낸다"; else bad "낡았는데 무음" "$out"; fi
if grep -qE '5시간|[0-9]+시간' <<<"$out"; then ok "얼마나 낡았는지 수치가 나온다"; else bad "수치 없음" "$out"; fi

# ⑩-3 파일이 아예 없으면 = cron 이 한 번도 안 돌았다. 이것도 시끄러워야 한다
out="$(run "$ROOT/todo.md" "$ROOT/weather.json" "$ROOT/hb-none")"
if grep -q '드리프트 감시' <<<"$out"; then ok "파일 없음도 알린다(한 번도 안 돎)"; else bad "무음" "$out"; fi
# 🔑 "없음"과 "낡음"은 원인이 다르다(cron 미등록 vs 죽음) → 문구가 갈려야 조치가 갈린다
# ⚠️ 처음엔 `none_line != stale_line` 으로 썼는데 **숫자만 달라도 통과**했다 —
#    "N시간째 안 돌았다" 를 없음 쪽에 그대로 붙이는 변이가 살아남았다. 문구가 다른지가
#    아니라 **원인을 맞게 말하는지**를 봐야 한다: 없음은 "돌다 멈췄다"가 아니다.
none_line="$(grep '드리프트 감시' <<<"$out")"
if grep -qE '미등록|한 번도' <<<"$none_line"; then ok "'없음'은 미등록/한 번도 안 돎으로 말한다"; else bad "원인이 안 드러남" "$none_line"; fi
if grep -q '시간째' <<<"$none_line"; then bag=1; else bag=0; fi
if [[ "$bag" -eq 0 ]]; then ok "'없음'을 '시간째 안 돌았다'로 말하지 않는다(돌다 멈춘 게 아니다)"; else bad "없음을 낡음처럼 말했다" "$none_line"; fi
stale_out="$(run "$ROOT/todo.md" "$ROOT/weather.json" "$ROOT/hb-stale")"
if grep -qE '멈췄|시간째' <<<"$(grep '드리프트 감시' <<<"$stale_out")"; then ok "'낡음'은 멈춤으로 말한다"; else bad "낡음 문구 이상" "$stale_out"; fi

# ⑩-4 경계값 — 정확히 임계면 아직 신선(초과만 낡음)
: > "$ROOT/hb-edge"; touch_ago $(( 2 * HOUR )) "$ROOT/hb-edge"
out="$(HEARTBEAT_STALE_HOURS=2 run "$ROOT/todo.md" "$ROOT/weather.json" "$ROOT/hb-edge")"
if ! grep -q '드리프트 감시' <<<"$out"; then ok "경계값은 아직 신선(초과만 낡음)"; else bad "경계에서 오탐" "$out"; fi

# ⑩-6 mtime 을 **못 읽으면** 조용히 "신선"이 되면 안 된다 (판정 불가는 세 번째 상태)
# 실제 실패를 만든다: 디렉터리를 탐색 불가로 만들면 그 안 파일의 mtime 을 못 구한다.
# (스텁이 아니라 진짜 실패 — 오늘 배운 "재는 채널이 막혀 있으면 안 된다"를 지킨다)
mkdir -p "$ROOT/locked"; : > "$ROOT/locked/hb"; chmod 000 "$ROOT/locked"
out="$(run "$ROOT/todo.md" "$ROOT/weather.json" "$ROOT/locked/hb")"
chmod 755 "$ROOT/locked"
if grep -q '판정 불가' <<<"$out"; then ok "못 읽으면 '판정 불가'를 낸다"; else bad "못 읽었는데 조용하다" "$out"; fi
if grep -qE '시간째|한 번도' <<<"$(grep '드리프트' <<<"$out")"; then
  bad "못 쟀는데 낡음/없음으로 단정했다" "$out"; else ok "못 쟀을 때 원인을 단정하지 않는다"; fi

# ⑩-5 한 축이 죽어도 다른 축은 그대로 보고한다 (오늘 반복된 원칙)
out="$(run "$ROOT/todo.md" "$ROOT/weather.json" "$ROOT/hb-stale")"
if grep -q '27°C' <<<"$out" && grep -q '첫째 항목' <<<"$out"; then
  ok "하트비트가 낡아도 날씨·할 일은 그대로"; else bad "다른 섹션이 같이 죽었다" "$out"; fi

echo
echo "⑪ 리뷰 안 달린 PR — 조용한 큐를 소리 내게 한다"
# 🔑 이 섹션의 본체도 ⑩ 과 같다: **0건(확인된 정상)과 못 읽음(판정 불가)을 가르는가.**
#    실사고 — 룬드 `#29` 가 이틀 묻혔고, 같은 시각 내 레포에 리뷰 0건이 6개 있었다.

D2="$(fmt_ago $(( 2 * DAY )) '+%Y-%m-%d')T09:00:00Z"
D0="$(fmt_ago 0            '+%Y-%m-%d')T09:00:00Z"

_mk pr-fail 'exit 1'                                   # 조회 실패
_mk pr-two  "printf '91\t$D2\t버킷 하나가 죽으면\n80\t$D2\t미응답 리마인더\n'"
_mk pr-today "printf '99\t$D0\t오늘 연 것\n'"
_mk pr-bad  "printf '77\tnot-a-date\t날짜가 깨진 것\n'"
_mk pr-five "for n in 1 2 3 4 5; do printf '%s\t$D2\t제목 %s\n' \"\$n\" \"\$n\"; done"
_mk pr-echo 'printf "%s\n" "$1" >> '"$ROOT/repos-seen"

# ⑪-1 0건이면 **줄이 없다** (확인된 정상은 조용하다)
out="$(PR_LIST_CMD="$ROOT/pr-none" run "$ROOT/todo.md" "$ROOT/weather.json")"
if ! grep -q '리뷰 안 달린' <<<"$out"; then ok "0건이면 섹션을 뺀다"; else bad "0건인데 줄이 났다" "$out"; fi

# ⑪-2 있으면 번호·나이가 보인다
out="$(PR_LIST_CMD="$ROOT/pr-two" PR_REPOS=a/b run "$ROOT/todo.md" "$ROOT/weather.json")"
if grep -q 'b#91' <<<"$out" && grep -q '2일째' <<<"$out"; then
  ok "PR 번호와 묵은 날수를 낸다"; else bad "번호/나이 누락" "$out"; fi
if grep -q '리뷰 안 달린 PR 2건' <<<"$out"; then ok "총 건수를 낸다"; else bad "건수 없음" "$out"; fi

# ⑪-3 🔴 조회 실패는 **0건과 달라야 한다** — 이 시험 하나가 이 섹션의 존재 이유다
out="$(PR_LIST_CMD="$ROOT/pr-fail" PR_REPOS=a/b run "$ROOT/todo.md" "$ROOT/weather.json")"
if grep -q '못 읽음' <<<"$out"; then ok "조회 실패는 소리를 낸다(0건과 안 섞인다)"; else
  bad "못 읽었는데 조용하다 — 0건과 구별 불가" "$out"; fi

# ⑪-4 오늘 연 PR 은 안 센다 (임계 미만) — 상시로 차면 배경이 된다
out="$(PR_LIST_CMD="$ROOT/pr-today" PR_REPOS=a/b run "$ROOT/todo.md" "$ROOT/weather.json")"
if ! grep -q '리뷰 안 달린' <<<"$out"; then ok "오늘 연 것은 아직 안 센다"; else bad "임계가 안 먹는다" "$out"; fi

# ⑪-5 나이를 **못 쟀다고 빼면 안 된다** — 빼면 그 PR 이 사라진다(무음이 곧 없음이 된다)
out="$(PR_LIST_CMD="$ROOT/pr-bad" PR_REPOS=a/b run "$ROOT/todo.md" "$ROOT/weather.json")"
if grep -q 'b#77' <<<"$out"; then ok "나이를 못 재도 목록에 남긴다"; else bad "못 쟀다고 통째로 빠졌다" "$out"; fi
if grep -q '못 읽음' <<<"$(grep 'b#77' <<<"$out")"; then ok "못 쟀다고 적는다(0일째로 단정 안 함)"; else
  bad "못 쟀는데 나이를 단정했다" "$out"; fi

# ⑪-6 상위 N 개만 읽고 나머지는 건수로 — 할 일 섹션과 같은 규약
out="$(PR_LIST_CMD="$ROOT/pr-five" PR_REPOS=a/b PR_TOP=3 run "$ROOT/todo.md" "$ROOT/weather.json")"
if [[ "$(grep -c 'b#' <<<"$out")" -eq 3 ]] && grep -q '외 2건' <<<"$out"; then
  ok "상위 3개 + 나머지 건수"; else bad "상위/나머지 규약 어긋남" "$out"; fi

# ⑪-7 레포를 **둘 다** 본다 — 한쪽만 보면 "내가 밀린 것"이 안 보인다(#29 가 그 자리였다)
: > "$ROOT/repos-seen"
PR_LIST_CMD="$ROOT/pr-echo" PR_REPOS="x/one y/two" run "$ROOT/todo.md" "$ROOT/weather.json" >/dev/null
if grep -q '^x/one$' "$ROOT/repos-seen" && grep -q '^y/two$' "$ROOT/repos-seen"; then
  ok "설정된 레포를 전부 조회한다"; else bad "일부 레포를 안 봤다" "$(cat "$ROOT/repos-seen")"; fi

# ⑪-8 한 레포가 죽어도 다른 레포는 그대로 보고한다 (오늘 반복된 원칙)
_mk pr-mixed 'case "$1" in dead/one) exit 1 ;; *) printf "55\t'"$D2"'\t살아있는 쪽\n" ;; esac'
out="$(PR_LIST_CMD="$ROOT/pr-mixed" PR_REPOS="dead/one live/two" run "$ROOT/todo.md" "$ROOT/weather.json")"
if grep -q '못 읽음' <<<"$out" && grep -q 'two#55' <<<"$out"; then
  ok "한 레포가 죽어도 나머지는 보고한다"; else bad "한쪽 실패가 전체를 삼켰다" "$out"; fi

# ⑪-9 이 섹션이 죽어도 날씨·할 일은 그대로 (섹션 격리)
if grep -q '27°C' <<<"$out" && grep -q '첫째 항목' <<<"$out"; then
  ok "PR 조회가 실패해도 다른 섹션은 살아있다"; else bad "다른 섹션이 같이 죽었다" "$out"; fi

# ⑪-10·11 은 함수를 직접 부른다 — 아래 두 이유로 프로세스를 새로 띄우면 안 된다.
#   ⚠️ PATH 를 비워 gh 부재를 만들면 **bash·date 까지 사라진다**. 처음에 `PATH=/nonexistent`
#      로 스크립트를 통째로 돌렸다가 `bash: command not found` 로 시험 자체가 죽었다 —
#      *재려던 조건(gh 없음)이 아니라 재는 도구를 없앤 것*이다.
#   ⇒ 소스해서 함수만 부르면 `command -v` 는 빌트인이라 PATH 가 비어도 돈다.
# shellcheck source=/dev/null
source "$SCRIPT"   # main 은 소스 가드가 막는다 — 순수 함수만 꺼내 쓴다

# ⑪-10 gh 가 없으면 **조용히 넘어가지 않는다**
mkdir -p "$ROOT/empty"
out="$(PATH="$ROOT/empty" PR_LIST_CMD="" unreviewed_pr_section 2>&1)"
if grep -q 'gh 없음' <<<"$out"; then ok "gh 부재는 판정 불가로 낸다"; else bad "gh 가 없는데 조용하다" "$out"; fi

# ⑪-11 iso_epoch 단위 — 못 쟀을 때 **0 을 돌려주면 안 된다**(file_mtime 과 같은 함정)
if iso_epoch "$(fmt_ago 0 '+%Y-%m-%d')" >/dev/null; then ok "iso_epoch: 정상 날짜는 재진다"; else
  bad "iso_epoch 이 정상 날짜를 못 잰다" "GNU/BSD 분기 확인"; fi
if ! iso_epoch "not-a-date" >/dev/null 2>&1; then ok "iso_epoch: 못 재면 실패로 낸다(0 아님)"; else
  bad "못 쟀는데 값을 돌려줬다" "$(iso_epoch 'not-a-date')"; fi

echo
echo "  통과 $pass · 실패 $fail"
[[ "$fail" -eq 0 ]]
