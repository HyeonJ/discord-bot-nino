#!/usr/bin/env bash
# runner-glob-coverage.test.sh — 러너 글롭 «밖»에 시험 파일이 있으면 빨강.
#
# 🔴 왜 생겼나 (2026-08-02, 룬드 `M:lqpv` 왕복에서 내 쪽 구멍이 드러났다):
#   러너는 `tests/*.test.sh` 글롭 + jest + bun 을 돈다. 그런데 `tests/test_of_*.py` 7개는
#   **어느 쪽에도 안 걸려서 한 번도 안 돌고 있었다.** 그 사이 원장에 적힌 「통과 N」은
#   그 7개를 **분모에서 뺀 값**이었고, 실제로 그 안에 실패가 **1건** 숨어 있었다.
#
# 🔑 이 시험이 잠그는 것은 「지금 글롭이 맞나」가 아니라 **「글롭이 낡는 것」**이다.
#   글롭은 쓸 당시엔 정확했다 — `.py` 시험이 **나중에** 들어오며 분모 밖으로 떨어졌다.
#   ⇒ 한 번 고치는 것으로는 안 닫힌다. 다음 `.py`·`.ts` 에서 같은 자리가 다시 열린다.
#
# 🔑 형태: **적힌 것 + 벗어나면 시끄럽다.** 새 확장자를 들이려면 러너에 배선하거나
#   여기 «의도적 제외»로 적어야 한다. 둘 다 안 하면 이 시험이 빨개진다.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pass=0; fail=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; [ -n "${2:-}" ] && echo "     want: $2"; [ -n "${3:-}" ] && echo "     got:  $3"; fail=$((fail + 1)); }

# 🔸 의도적 제외 — 시험처럼 생겼지만 러너가 안 도는 것. **이유를 같이 적는다.**
#   여기 적히지 않은 채 글롭 밖에 있으면 빨강이다.
EXCLUDE_RE='^(__init__\.py|conftest\.py|.*\.obsolete)$'

echo "🔴 러너 분모 — 글롭 밖에 시험 파일이 남아 있나:"

# 러너가 실제로 무엇을 도는지 **선언에서** 읽는다 (하드코딩하면 러너가 바뀔 때 조용히 낡는다)
RUNNER_DECL="$(grep -oE "\-\-shell-glob '[^']+'" "$ROOT/tests/run-all.sh" 2>/dev/null)"
if [ -z "$RUNNER_DECL" ]; then
    bad "판정 불가 — run-all.sh 에서 글롭 선언을 못 읽었다" "--shell-glob '…'" "<없음>"
else
    ok "러너 글롭 선언을 읽었다: ${RUNNER_DECL}"
fi

# 시험처럼 생긴 파일 전부 (= 사람이 「이건 시험이다」라고 읽을 이름)
LOOKS_LIKE="$(ls -1 "$ROOT/tests" 2>/dev/null | grep -E '(^test_.*\.(py|ts)$|\.test\.(sh|js|ts|py)$|\.obsolete$|^conftest\.py$|^__init__\.py$)' || true)"

# 러너가 실제로 도는 것
COVERED="$(ls -1 "$ROOT/tests" 2>/dev/null | grep -E '\.test\.(sh|js)$' | grep -v '\.obsolete$' || true)"

ORPHAN=""
while IFS= read -r f; do
    [ -n "$f" ] || continue
    printf '%s\n' "$f" | grep -qE "$EXCLUDE_RE" && continue
    printf '%s\n' "$COVERED" | grep -qxF "$f" && continue
    ORPHAN="${ORPHAN}${f}"$'\n'
done <<< "$LOOKS_LIKE"

ORPHAN="$(printf '%s' "$ORPHAN" | sed '/^$/d')"
N="$(printf '%s' "$ORPHAN" | grep -c . || true)"

if [ "$N" -eq 0 ]; then
    ok "글롭 밖 시험 파일 0개 — 분모가 전체다"
else
    bad "글롭 밖 시험 파일 ${N}개 — 러너가 안 돈다(원장의 「통과 N」이 이만큼 좁다)" \
        "0개 (러너에 배선하거나 EXCLUDE_RE 에 이유와 함께 적을 것)" \
        "«$(printf '%s' "$ORPHAN" | tr '\n' ' ')»"
fi

# 🧪 [양성 대조군] 검사기가 살아 있나 — 있을 리 없는 이름을 넣어 «잡는지» 본다.
#   이게 없으면 위 초록이 「0개」인지 「안 셌다」인지 안 갈린다.
PROBE="$(printf 'test_probe_ghost.py\n' | grep -vxF -f <(printf '%s\n' "$COVERED") || true)"
if [ -n "$PROBE" ]; then
    ok "[대조군] 글롭 밖 이름을 실제로 걸러낸다"
else
    bad "[대조군] 검사기가 아무것도 안 거른다 — 위 판정은 못 믿는다" "걸러냄" "«$PROBE»"
fi

echo
echo "  통과 $pass · 실패 $fail"
[ "$fail" -eq 0 ]
