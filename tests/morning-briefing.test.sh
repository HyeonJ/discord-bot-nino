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
  DRY_RUN=1 TODO_FILE="$1" WEATHER_JSON="$2" \
    DRIFT_HEARTBEAT="${3:-$ROOT/hb-fresh}" \
    DISCORD_SEND="$ROOT/should-not-be-called" \
    bash "$SCRIPT" 2>&1
}
printf '%s rc=0\n' "$(date '+%Y-%m-%d %H:%M:%S')" > "$ROOT/hb-fresh"

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
touch -d '10 days ago' "$ROOT/todo.md"
out="$(run "$ROOT/todo.md" "$ROOT/weather.json")"
if grep -q '10일째 안 바뀜' <<<"$out"; then ok "정지 기간 표시"; else bad "정지 표시 없음" "$out"; fi
touch -d 'now' "$ROOT/todo.md"
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
# 인사는 소스가 죽어도 나온다 — 인사의 유무로 상태를 판단하면 안 된다는 규약
out="$(run "$ROOT/없는파일.md" "$ROOT/없는날씨.json")"
if [[ "$(sed -n '2p' <<<"$out")" != "" ]] && grep -q '못 읽음' <<<"$out"; then
  ok "소스 실패해도 인사는 나오고, 판단은 경고 줄이 한다"; else bad "실패 시 인사/경고 조합이 깨짐" "$out"; fi

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

# ⑩-2 낡으면 반드시 줄을 낸다 + 얼마나 낡았는지
touch -d '5 hours ago' "$ROOT/hb-fresh.stale" 2>/dev/null || touch -t "$(date -d '5 hours ago' +%Y%m%d%H%M)" "$ROOT/hb-fresh.stale"
printf 'old rc=0\n' >> /dev/null
: > "$ROOT/hb-stale"; printf '%s rc=0\n' "$(date -d '5 hours ago' '+%Y-%m-%d %H:%M:%S')" > "$ROOT/hb-stale"
touch -d '5 hours ago' "$ROOT/hb-stale"
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
: > "$ROOT/hb-edge"; touch -d '2 hours ago' "$ROOT/hb-edge"
out="$(HEARTBEAT_STALE_HOURS=2 run "$ROOT/todo.md" "$ROOT/weather.json" "$ROOT/hb-edge")"
if ! grep -q '드리프트 감시' <<<"$out"; then ok "경계값은 아직 신선(초과만 낡음)"; else bad "경계에서 오탐" "$out"; fi

# ⑩-5 한 축이 죽어도 다른 축은 그대로 보고한다 (오늘 반복된 원칙)
out="$(run "$ROOT/todo.md" "$ROOT/weather.json" "$ROOT/hb-stale")"
if grep -q '27°C' <<<"$out" && grep -q '첫째 항목' <<<"$out"; then
  ok "하트비트가 낡아도 날씨·할 일은 그대로"; else bad "다른 섹션이 같이 죽었다" "$out"; fi

echo
echo "  통과 $pass · 실패 $fail"
[[ "$fail" -eq 0 ]]
