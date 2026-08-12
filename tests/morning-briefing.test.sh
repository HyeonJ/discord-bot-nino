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

# 🔴 코어 정본이 없으면 이 파일 «전체»가 판정 불가다 — 없으면 나머지 단언이 전부
#   *틀린 이유로* 빨개진다(원래 빨간 판 위의 빨강은 아무도 못 본다). 이유·경위는 헬퍼에.
REPO="${REPO:-$(cd "$SCRIPT_DIR/.." && pwd)}"
. "$REPO/tests/lib/require-core.sh"
# ⚠️ 스텁이 PATH 를 가리기 **전에** 진짜 경로를 잡는다. 절대경로를 박으면 안 된다 —
#    `/usr/bin/date` 는 리눅스에만 있고 macOS 는 `/bin/date` 라 스텁이 죽는다
#    (룬드 맥 실측 2026-07-28 `폴백 실패` — 스크립트가 아니라 이 시험이 틀린 자리였다).
REAL_DATE="$(command -v date)"
export REAL_DATE
source "$SCRIPT_DIR/../scripts/lib/timeshift.sh"   # 시각 조작은 정본 하나를 지난다(GNU/BSD 공용)
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

run() {  # run <TODO_FILE> <WEATHER_JSON> [DRIFT_HEARTBEAT] — 항상 --dry-run
  # 하트비트를 안 주면 **신선한 것**을 기본으로 깐다 — 안 그러면 기존 시험 전부가
  # "하트비트 없음" 경고를 달고 나와서, 다른 섹션을 보는 단언이 흔들린다.
  # ⚠️ PR_LIST_CMD 를 안 주면 기본값이 **진짜 gh 를 친다** — 시험이 네트워크·계정에 매달리고,
  #    조회가 느리거나 실패하면 다른 단언까지 흔들린다. 기본은 항상 "0건 스텁"으로 막는다.
  #    (같은 자리를 룬드 `#35` 리뷰에서 잡았다: 시험이 진짜 API 를 치고 있었다.)
  TODO_FILE="$1" WEATHER_JSON="$2" \
    DRIFT_HEARTBEAT="${3:-$ROOT/hb-fresh}" \
    PR_LIST_CMD="${PR_LIST_CMD:-$ROOT/pr-none}" \
    PENDING_FILE="${PENDING_FILE:-$ROOT/pending-none.md}" \
    DISCORD_SEND="$ROOT/should-not-be-called" \
    bash "$SCRIPT" --dry-run 2>"$ROOT/stderr"
}
printf '%s rc=0\n' "$(date '+%Y-%m-%d %H:%M:%S')" > "$ROOT/hb-fresh"
# 🔴 기본값은 «없는 파일»이 아니라 «존재하는 빈 파일»이라야 한다 — 없는 파일을 가리키면
#    앞쪽 시험 전부가 "승인 대기 못 읽음" 경고를 달고 나온다(위 pr-none 이 밟은 그 자리).
printf '# current tasks\n\n## 상태\n아무것도 대기 없음\n' > "$ROOT/pending-none.md"
cat > "$ROOT/pending-3.md" <<'PMD'
# current tasks

## 📮 Darren 승인 대기 — 검증 6권 래핑 해제
본문 아무거나

## 📮 Darren 께 물을 것 — check-auth 유예
본문

## 📮 Darren 께 보냄 — 답 대기
본문

## 🤝 이건 승인 대기가 아니다 (룬드 몫)
본문
PMD

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
out="$(PATH="$STUB:$PATH" TODO_FILE="$ROOT/todo.md" WEATHER_JSON="$ROOT/weather.json" \
        DRIFT_HEARTBEAT="$ROOT/hb-fresh" DISCORD_SEND="$ROOT/should-not-be-called" \
        bash "$SCRIPT" --dry-run 2>&1)"
if grep -q '판정 불가' <<<"$out"; then ok "못 읽으면 '판정 불가'가 브리핑에 뜬다"; else bad "조용히 넘어갔다" "$out"; fi

echo "⑨ --dry-run 은 전송하지 않는다"
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

# ⑪-11b 🔴 iso_epoch 은 «자정»을 뜻해야 한다 — BSD `date -j -f` 는 빠진 필드를
#   «현재 시각»으로 채워서 값이 벽시계를 따라 흐른다(룬드 맥 33% 플레이키의 기전).
#   🔑 좌변이 «두 층»이다. 리눅스 러너에선 GNU 갈래만 도니 ②가 여기서 죽고,
#      ①은 맥에서 죽는다. 하나만 두면 각자 자기 OS 에서 조용하다.
# ① 동작: 같은 날짜는 «언제 물어도» 같은 값이고, 그 값은 자정이다
_d="2026-08-08"
_e1="$(iso_epoch "$_d")"; _e2="$(iso_epoch "${_d}T16:02:24Z")"
if [ "$_e1" = "$_e2" ]; then ok "iso_epoch: 시각이 붙어 있어도 같은 값(날짜만 본다)"; else
  bad "같은 날짜인데 값이 다르다 — 시각이 새어들어간다" "$_e1 vs $_e2"; fi
# 🔴 `date -d @…` 로 되읽지 «않는다» — 그건 GNU 전용이라 이 파일이 맥에서 죽는다
#    (실물: 첫 판이 그렇게 썼다가 portability 가드에 걸렸다 — 이식성 시험을 이식 불가로 썼다).
#    자정 여부는 «산술»로 잰다: 지역 자정이면 `(epoch + UTC오프셋) % 86400 == 0`.
#    `date +%z` 는 GNU·BSD 둘 다 `+0900` 꼴을 준다.
_z="$(date +%z)"; _off=$(( 10#${_z:1:2} * 3600 + 10#${_z:3:2} * 60 ))
[ "${_z:0:1}" = "-" ] && _off=$(( -_off ))
if [ $(( (_e1 + _off) % 86400 )) -eq 0 ]; then
  ok "iso_epoch: 값이 «자정»이다 (벽시계가 안 섞인다)"; else
  bad "자정이 아니다 — 값이 실행 시각을 따라 흐른다" "epoch=$_e1 tz=$_z"; fi
# ② 형태: BSD 갈래가 시·분·초를 «명시»하나. 리눅스에선 그 갈래가 안 돌아 동작으로 못 잰다
if command grep -q "date -j -f '%Y-%m-%d %H:%M:%S'" "$SCRIPT"; then
  ok "iso_epoch: BSD 갈래가 자정을 명시한다 (리눅스에선 이 형태 검사가 유일한 좌변)"; else
  bad "BSD 갈래가 날짜만 준다 — 맥에서 «그 날의 지금 시각»이 된다" \
      "$(command grep -n 'date -j -f' "$SCRIPT" | head -1)"; fi

echo "⑫ 🔴 인자 계약 (코어 cli-guard) — 09:50 사고의 형태를 막는다"
# 🔴 이 스크립트는 **이미 한 번 말없이 안 나갔다** (07-30 23:03 재시작에 세션 cron 이 같이
#   사라져 금요일 07시 브리핑이 조용히 빠졌고 아무도 몰랐다 — CLAUDE.md 기록).
#   무음이 기본값인 자리라, 무음으로 실패하는 갈래를 하나도 더 얹을 수 없다.
# 🔴 옛 형태는 `DRY_RUN="${DRY_RUN:-0}"` — **환경으로만** 켤 수 있었고 끄는 길이 플래그로
#   존재하지도 않았다. 환경에 그 값이 있는 것만으로 브리핑이 발송 0건 · rc=0 이 된다.
#
# 🔸 이 절 전용 발송 스텁 — **호출 1회 = 1줄.** 브리핑 본문은 여러 줄이라 본문을 적으면
#   1건이 수십 건으로 보인다.
cat > "$ROOT/send-1" <<'STUB'
#!/usr/bin/env bash
printf 'SEND\t%s\n' "$1" >> "$G_SENT"
STUB
chmod +x "$ROOT/send-1"
g_sends() { grep -c '^SEND' "$G_SENT" 2>/dev/null | head -1; }
gr() {   # gr <스크립트 인자…>   (GUARD_ENV 를 세우면 CLI_DRY_RUN 을 환경으로 물려준다)
  G_SENT="$ROOT/g-sent.txt"; : > "$G_SENT"
  G_LOG="$ROOT/g-briefing.log"; : > "$G_LOG"
  # 🔴 stderr 를 **따로 받는다.** 합치면 코어의 DRY-RUN 안내에 본문이 통째로 들어가
  #   본문 집계가 오염된다 — 이 파일에서 실제로 `grep -c 'b#'` 가 3 대신 4 를 셌다.
  g_out="$(env G_SENT="$G_SENT" TODO_FILE="$ROOT/todo.md" WEATHER_JSON="$ROOT/weather.json" \
      DRIFT_HEARTBEAT="$ROOT/hb-fresh" PR_LIST_CMD="$ROOT/pr-none" \
      BRIEFING_LOG="$G_LOG" DISCORD_SEND="$ROOT/send-1" \
      ${GUARD_ENV:+CLI_DRY_RUN="$GUARD_ENV"} \
      bash "$SCRIPT" "$@" 2>"$ROOT/g-err")"
  G_RC=$?
  return 0
}

# 🧪 [대조군] **먼저 이것부터.** 아래 "발송 0건"들이 가드 덕인지 이 픽스처가 애초에
#   아무것도 안 보내는 건지 못 가른다 — 대조군이 초록이 아니면 나머지 빨간불은 증거가 아니다.
GUARD_ENV="" gr
[[ "$(g_sends)" -eq 1 ]] && ok "🧪 [대조군] 인자 없이 부르면 실제로 1건 나간다" \
  || bad "대조군 — 이 픽스처는 원래 안 보낸다. 아래 0건은 증거가 아니다" "$(g_sends)건 / $g_out"

GUARD_ENV="" gr --report
[[ "$G_RC" -eq 2 ]] && ok "모르는 인자 --report 를 rc=2 로 거절한다 (1 아님 — 못 쟀다)" || bad "모르는 인자 rc" "want 2 / got $G_RC"
[[ "$(g_sends)" -eq 0 ]] && ok "  🔑 거절되면 발송 0건 (사고 재현 차단)" || bad "거절인데 발송" "$(g_sends)건"
# 🔑 **거절도 파일로 남긴다.** 이 스크립트엔 로그가 없었다 — cron 이 stderr 를 버리므로
#   안 남기면 crontab 오타 하나에 브리핑이 **또** 말없이 안 나간다.
grep -q 'verdict=bad_args' "$G_LOG" && ok "  🔑 거절이 로그 파일에 남는다 (verdict=bad_args)" \
  || bad "거절 로그" "$(cat "$G_LOG" 2>/dev/null || echo '<로그 없음>')"

GUARD_ENV="" gr --dry-run
[[ "$(g_sends)" -eq 0 ]] && ok "--dry-run 이면 발송 0건" || bad "dry-run 발송" "$(g_sends)건"
grep -q '날씨' <<<"$g_out" && ok "  → 브리핑 본문을 stdout 으로 보여준다" \
  || bad "dry-run 가시성 — 조용하면 고장과 구별이 안 된다" "$g_out"

# 🔴 환경 상속은 **거절**한다(코어 계약 ④) — 어느 쪽으로 접어도 조용히 틀리는 자리.
GUARD_ENV=1 gr
[[ "$G_RC" -eq 2 ]] && ok "🔴 CLI_DRY_RUN 을 환경에서 물려받으면 rc=2 로 거절한다" || bad "환경 상속" "want rc=2 / got $G_RC"
[[ "$(g_sends)" -eq 0 ]] && ok "  → 거절이므로 발송 0건" || bad "상속 거절 발송" "$(g_sends)건"
grep -q 'verdict=bad_env' "$G_LOG" && ok "  🔑 bad_args 와 갈라 센다 (고칠 곳이 환경이라서)" \
  || bad "bad_env 표지" "$(cat "$G_LOG" 2>/dev/null || echo '<로그 없음>')"

GUARD_ENV="" gr --help
[[ "$(g_sends)" -eq 0 ]] && ok "--help 는 발송 0건" || bad "help 발송" "$(g_sends)건"
grep -q 'usage:' <<<"$g_out" && ok "  → 사용법을 stdout 으로 낸다" || bad "usage 출력" "$g_out"

# 🔴 **source 해도 인자 파싱이 돌지 않는다** — 이 파일은 실제로 source 된다(⑪이 `file_mtime`
#   하나를 부르려고 그렇게 한다). 파싱을 최상위에 뒀더니 그쪽 `"$@"` 가 모르는 인자로
#   판정돼 **exit 2** 가 됐다. 🔑 코어 계약 ⑦(source 는 부작용이 없다)은 **소비자 쪽에서도**
#   지켜야 한다 — 계약을 지키는 라이브러리를 부작용 있는 자리에 배선하면 계약이 사라진다.
src_out="$(bash -c 'source "$1" 2>&1; echo "SOURCED_RC=$?"' _ "$SCRIPT" --아무거나 2>&1)"
grep -q 'SOURCED_RC=0' <<<"$src_out" && ok "🔴 source 해도 인자 파싱이 안 돈다 (부작용 0)" \
  || bad "source 시 부작용" "SOURCED_RC=0" "$src_out"

echo "── ⑫ 📮 승인 대기 — «세션이 안 돌아도» 매일 나온다 ──"
#
# 🔴 왜: 📮 목록은 memory/current-tasks.md 에만 살고 그걸 읽는 것은 **세션 시작 절차뿐**이다.
#   세션이 길게 붙어 있으면 며칠씩 안 나온다 — 실물로 끝난 항목이 6시간, 다른 건 하루를 넘겼고
#   **아무도 지운 사람이 없었다**(2026-08-11 재검 「8건 중 6건」).
# 🔑 룬드 브리핑 구멍(*「이미 해둔 걸 묻는다」*)의 **부호 반대판**이다 — 그의 것은 시끄럽고
#   내 것은 **안 묻는다(무음)**. Darren 기준으로 무음이 더 나쁘다 ⇒ 칸을 만든다.
# ⚠️ 좌변은 「## 📮 」 줄이다. 🤝(룬드 몫)는 **안** 센다 — 수신자가 다르다.
out="$(PENDING_FILE="$ROOT/pending-3.md" run "$ROOT/todo.md" "$ROOT/weather.json")"
grep -q '형이 정할 것 3건' <<<"$out" && ok "📮 건수를 낸다 (🤝 는 안 센다)" \
  || bad "📮 건수" "형이 정할 것 3건" "$out"
grep -q '검증 6권 래핑 해제' <<<"$out" && ok "제목을 읽어준다" \
  || bad "📮 제목" "검증 6권 래핑 해제" "$out"

# 확인된 빈 상태 → 섹션을 뺀다(무음 = 없음). 이 규약은 할 일 섹션과 같다.
out="$(run "$ROOT/todo.md" "$ROOT/weather.json")"
grep -q '형이 정할 것' <<<"$out" && bad "0건인데 줄이 나온다" "줄 없음" "$out" \
  || ok "0건이면 섹션을 통째로 뺀다"

# 🔴 그러나 «못 읽은 것»은 빈 상태와 갈라야 한다 — 이게 없으면 파일이 사라져도 조용하다.
out="$(PENDING_FILE="$ROOT/no-such-pending.md" run "$ROOT/todo.md" "$ROOT/weather.json")"
grep -q '승인 대기 못 읽음' <<<"$out" && ok "🔴 파일 부재는 시끄럽다 (빈 상태와 안 뭉친다)" \
  || bad "부재 무음 금지" "승인 대기 못 읽음" "$out"

# 상위 N 개만 읽고 나머지는 「외 N건」 — 목록이 길어져도 브리핑이 안 부푼다
# ⚠️ 좌변을 «출력 전체»로 두면 항진명제다 — 할 일 픽스처가 4건이라 TODO_TOP=3 이
#    「외 1건」을 «이미» 내고 있었다(첫 판이 그래서 구현 없이 초록이었다).
#    ⇒ 📮 줄 «이후»로 잘라서 본다.
out="$(PENDING_FILE="$ROOT/pending-3.md" PENDING_TOP=2 run "$ROOT/todo.md" "$ROOT/weather.json")"
blk="$(sed -n '/형이 정할 것/,$p' <<<"$out")"
grep -q '외 1건' <<<"$blk" && ok "상위 N 초과는 「외 N건」으로 접는다" \
  || bad "외 N건(📮 블록 안)" "외 1건" "$out"
# 대조군 — 같은 좌변을 «구현 없는» 0건 판에 대면 빨개져야 한다(항진명제 재발 방지)
blk0="$(sed -n '/형이 정할 것/,$p' <<<"$(run "$ROOT/todo.md" "$ROOT/weather.json")")"
[[ -z "$blk0" ]] && ok "0건이면 그 블록 자체가 없다 (위 단언의 대조군)" \
  || bad "0건 대조군" "빈 블록" "$blk0"

echo
echo "  통과 $pass · 실패 $fail"
[[ "$fail" -eq 0 ]]
