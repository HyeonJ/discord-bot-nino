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

run() {  # run <TODO_FILE> <WEATHER_JSON> — 항상 DRY_RUN
  DRY_RUN=1 TODO_FILE="$1" WEATHER_JSON="$2" \
    DISCORD_SEND="$ROOT/should-not-be-called" \
    bash "$SCRIPT" 2>&1
}

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

echo "⑦ DRY_RUN 은 전송하지 않는다"
if [[ ! -e "$ROOT/should-not-be-called" ]]; then ok "discord-send 미호출"; else bad "전송이 일어났다"; fi

echo
echo "  통과 $pass · 실패 $fail"
[[ "$fail" -eq 0 ]]
