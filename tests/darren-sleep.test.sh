#!/usr/bin/env bash
# darren-sleep.sh 계약 테스트
#
# 이 스크립트가 정하는 값은 «만료 epoch» 하나다. 그 값이 틀리면 훅은 조용히 옳게 동작한다 —
# 즉 잘못된 시각까지 «자는 중»이 되거나, 켜자마자 풀린다. 둘 다 출력이 조용하다.
# ⇒ 「켜진다」가 아니라 **«언제까지»가 맞나**를 고정한다.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SH="$SCRIPT_DIR/../scripts/darren-sleep.sh"

pass=0; fail=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; echo "     want: $2"; echo "     got : $3"; fail=$((fail + 1)); }
eq()  { [[ "$2" == "$3" ]] && ok "$1" || bad "$1" "$2" "$3"; }

export DARREN_SLEEP_FLAG="$(mktemp -u /tmp/darren-sleep-test.XXXXXX)"
trap 'rm -f "${DARREN_SLEEP_FLAG:-}"' EXIT

# 주입한 now 기준으로 만료 시각을 'YYYY-MM-DD HH:MM' 으로 돌려준다.
until_at() {
  DARREN_SLEEP_NOW="$(date -d "$1" +%s)" bash "$SH" on >/dev/null 2>&1
  date -d "@$(head -1 "$DARREN_SLEEP_FLAG")" '+%Y-%m-%d %H:%M'
}

echo "만료 시각이 «다음 기상»인가:"
# 2026-08-05 는 수요일 → 평일 07:00
eq "평일 밤 23:30 → 다음날 07:00"        "2026-08-06 07:00" "$(until_at '2026-08-05 23:30')"
# 같은 평일인데 «기상 전 새벽» — 오늘 07:00 이 아직 안 지났으니 오늘로 잡아야 한다
eq "평일 새벽 02:00 → 같은 날 07:00"     "2026-08-05 07:00" "$(until_at '2026-08-05 02:00')"
# 2026-08-07 은 금요일 → 다음날은 토요일이라 09:00
eq "금요일 밤 → 토요일 09:00(주말)"      "2026-08-08 09:00" "$(until_at '2026-08-07 23:30')"
# 2026-08-08 토요일 새벽 → 같은 날 09:00
eq "토요일 새벽 → 같은 날 09:00"         "2026-08-08 09:00" "$(until_at '2026-08-08 03:00')"
# 🧪 [경계] 기상 시각 «정각»은 이미 지난 것으로 본다(안 그러면 켜자마자 만료라 무의미)
eq "🧪 [경계] 평일 07:00 정각 → 다음날"  "2026-08-06 07:00" "$(until_at '2026-08-05 07:00')"

echo ""
echo "on/off/status 계약:"
DARREN_SLEEP_NOW="$(date -d '2026-08-05 23:30' +%s)" bash "$SH" on >/dev/null 2>&1
st=$(DARREN_SLEEP_NOW="$(date -d '2026-08-06 01:00' +%s)" bash "$SH" status)
[[ "$st" == 🌙* ]] && ok "켜고 만료 전 → 자는 중" || bad "켜고 만료 전 → 자는 중" "🌙*" "$st"
st=$(DARREN_SLEEP_NOW="$(date -d '2026-08-06 08:00' +%s)" bash "$SH" status)
[[ "$st" == ☀️* ]] && ok "만료 후 → 안 자는 중" || bad "만료 후 → 안 자는 중" "☀️*" "$st"
bash "$SH" off >/dev/null 2>&1
[[ ! -f "$DARREN_SLEEP_FLAG" ]] && ok "off → 플래그 삭제" || bad "off → 플래그 삭제" "없음" "있음"
st=$(bash "$SH" status)
[[ "$st" == ☀️* ]] && ok "플래그 없음 → 안 자는 중" || bad "플래그 없음 → 안 자는 중" "☀️*" "$st"

# 🧪 [미탐 대조군] 깨진 플래그를 «자는 중»으로 읽으면, 파일이 잘못 생긴 순간부터
#   멘션이 조용히 사라진다. 훅과 같은 방향(안 자는 중)으로 떨어지는지 여기서도 고정한다.
printf 'garbage\n' > "$DARREN_SLEEP_FLAG"
st=$(bash "$SH" status)
[[ "$st" == ☀️* ]] && ok "🧪 [폴백] 깨진 플래그 → 안 자는 중" || bad "🧪 [폴백] 깨진 플래그" "☀️*" "$st"

bash "$SH" bogus >/dev/null 2>&1
eq "모르는 인자 → rc 2" "2" "$?"

echo ""
echo "결과: $pass pass, $fail fail"
[[ $fail -eq 0 ]]
