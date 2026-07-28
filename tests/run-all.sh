#!/usr/bin/env bash
# run-all.sh — 이 레포의 시험을 러너에 넘긴다. **목록은 여기서만 바뀐다.**
#
# 🔑 왜 파일인가: 전에는 `package.json` 의 한 줄이었다. 문자열이라
#   ① CI 갈래를 나눌 수 없고 ② **넘기는 인자를 시험할 수 없었다.**
#   붙이는 것 자체가 시험 대상이라(코어 `#91` 추세를 안 붙이면 조용히 안 잰다)
#   호출부를 파일로 뺀다. 계약(집계·rc 판정)은 러너에만 있다 — 여기 두면 사본이 된다.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNNER="${RUNNER:-$ROOT/scripts/run-tests.sh}"

if [ ! -f "$RUNNER" ]; then
    echo "⛔ 판정 불가 — 러너가 없다: $RUNNER"
    exit 2
fi

# 판정 불가 **추세** 상태 파일(코어 `#91`). 안 주면 추세를 안 잰다.
#   ⚠️ CI 는 매번 새 컨테이너라 직전 값이 없다 → `CI` 가 설정돼 있으면 안 붙인다.
#      붙여도 해는 없지만 매 실행 `ℹ️ 첫 기록` 이 떠서 **"첫 기록"이 상시가 되어 신호가 죽는다.**
#   🔸 `state/` 는 `.gitignore` 에 있다(기계마다 다른 값이라 추적하지 않는다).
#
# 🔴 `set --` 로 위치인자에 쌓는다. 문자열에 담아 `$VAR` 로 펼치면 **경로의 공백에서 쪼개져**
#    러너가 `모르는 인자` 로 죽는다(rc=2 라 조용하진 않지만, 원인은 *공백* 인데 메시지는
#    *모르는 인자* 라 엉뚱한 데를 판다). 배열은 bash 3.2 의 빈 확장 + `set -u` 와 부딪히므로
#    위치인자를 쓴다 — `shellcheck disable=SC2086` 을 붙이는 대신 **경고가 안 나게** 한다.
set --
if [ -z "${CI:-}" ]; then
    set -- --unmeasured-state "${UNMEASURED_STATE:-$ROOT/state/unmeasured.tsv}"
fi

exec bash "$RUNNER" \
    --root "$ROOT" \
    "$@" \
    --shell-glob 'tests/*.test.sh' \
    --cmd 'npx jest --runInBand'
