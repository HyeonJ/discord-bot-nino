#!/usr/bin/env bash
# heredoc-form.test.sh — `$( … <<TAG … )` (명령치환 **안**의 heredoc)이 남아 있는지 한 자리에서 잰다.
#
# 🔴 왜 이 형태만 보나 (2026-08-02):
#   bash 3.2 는 `$( … << 'X' … )` 안에서 **백틱이 홀수**면 파싱에서 죽는다. bash 5 는 둘 다 통과한다.
#   ⇒ 내 기계(bash 5)에서는 **영원히 조용하고**, 룬드 맥(3.2)에서만 터진다.
#   🔑 오늘 잰 9곳은 **전부 짝수**라 지금은 안 터진다. 그래서 이건 «버그»가 아니라 **뇌관**이다 —
#     방아쇠는 «시험이 자람»이 아니라 **«본문 편집»**이다. 누가 저 안의 파이썬을 고치다
#     백틱 하나를 넣는 순간 홀수가 되고, 넣은 사람 기계에서는 초록이다.
#   ⚠️ 그러니 고치는 방식은 «짝수를 지키자»가 아니라 **형태 자체를 없애는 것**이다.
#     패리티 규율은 사람이 매번 세어야 해서 지켜지지 않고, 형태 제거는 한 번이면 끝난다.
#
# 🔸 범위 — `tests/` 만 본다. `scripts/` 3곳(`check-auth.sh:188` · `nino-watchdog.sh:231·368`)은
#   이 판에서 **일부러 남긴다**(룬드 합의: tests/ 6 먼저, scripts/ 3 후).
#   ⚠️ 「scripts/ 는 터질 기계가 없다」는 **틀렸다** — 내 시험이 룬드 맥에서 scripts/ 를 직접 돌린다
#     (`nino-watchdog.test.sh:171·802·1267` · `check-auth.test.sh:20`). 좁힌 근거는 «안전»이 아니라
#     **«순서»**뿐이다. 조용히 좁히면 다음 사람이 안전으로 오독한다.
#
# 🔴 숫자를 여기 적지 않는다 — `portability.test.sh` 가 같은 자리에서 두 번 낡었다.
#   세는 자리는 아래 시험 하나다.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_DIR/lib/heredoc-form-guard.sh"

pass=0; fail=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; [ -n "${2:-}" ] && echo "     want: $2"; [ -n "${3:-}" ] && echo "     got:  $3"; fail=$((fail + 1)); }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

# 🔴 대조군을 **먼저** 돌린다 (2026-08-02 실측으로 순서를 바꿨다):
#   가드 파일이 아예 없는 상태로 이 시험을 돌렸더니 **7개 중 6개가 초록**이었다 —
#   `heredoc_subst_scan: command not found` 인데도 본 검사는 «출력이 비었다»로 통과하고,
#   음성 대조군 다섯은 «안 잡혔다»로 전부 통과한다.
#   🔑 **음성 대조군은 검사기가 죽어도 초록이다.** 짐을 지는 건 양성 대조군 하나뿐이다.
#   ⇒ 그 하나가 죽으면 본 검사의 초록은 «위반이 없다»가 아니라 **«못 쟀다»**이므로,
#     초록으로 세지 않고 **판정 불가**로 낸다. 빈 출력 두 뜻을 가르는 자리가 여기다.

# 🧪 [대조군] 검사기가 **일을 하는가**. 오탐 세 종류를 **전부** 심는다 —
#   같은 인벤토리를 스캐너 두 판본으로 재봤더니 셋 다 실물로 나왔고, 그중 ④(다른 heredoc
#   본문 속 opener 모양)는 `portability-guard.sh` 의 면제 ①②③에 **없다**.
#   하나만 심으면 나머지 면제가 죽어도 초록이다.
mkdir -p "$WORK/probe"

# ① 진짜 위반 — 잡혀야 한다
cat > "$WORK/probe/real.sh" <<'PROBE'
#!/bin/bash
n=$(python3 - "$F" <<'PY'
print(1)
PY
)
PROBE

# ② 주석 속 언급 — 호출이 아니다
cat > "$WORK/probe/comment.sh" <<'PROBE'
#!/bin/bash
# 3.2 는 $(...) 안 heredoc 을 못 씹어서 <<'PY' 로 인용해도 안 된다
echo hi
PROBE

# ③ 문자열 속 herestring — `<<<` 는 heredoc 이 아니다
cat > "$WORK/probe/herestring.sh" <<'PROBE'
#!/bin/bash
msg="$(cat <<< "예시: \$(설명) << 은 문자열일 뿐")"
PROBE

# ④ **다른 heredoc 본문 안**의 opener 모양 — 열림이 아니라 데이터다
cat > "$WORK/probe/nested.sh" <<'PROBE'
#!/bin/bash
python3 <<'OUTER'
src = re.sub(r"<<'PYEOF'.*?^PYEOF", "", src)
OUTER
PROBE

# ⑤ 명령치환 **밖**의 평범한 heredoc — 3.2 에서 안 터진다
cat > "$WORK/probe/plain.sh" <<'PROBE'
#!/bin/bash
python3 - <<'PY'
print(1)
PY
PROBE

# ⑥ 면제 표식이 붙은 위반 — 조용해야 한다
cat > "$WORK/probe/allowed.sh" <<'PROBE'
#!/bin/bash
n=$(python3 - <<'PY'  # hygiene:allow-heredoc-subst — 근거를 여기 적는다
print(1)
PY
)
PROBE

hits="$(heredoc_subst_scan "$WORK"/probe/*.sh | sed "s|$WORK/probe/||")"
live=0
case "$hits" in
    *real.sh*) ok "[대조군] real.sh — 진짜 위반을 잡는다"; live=1 ;;
    *)         bad "[대조군] real.sh 를 놓쳤다 — 검사기가 죽었다" \
                   "real.sh 가 목록에 있어야 한다" "«${hits}»" ;;
esac
for f in comment.sh herestring.sh nested.sh plain.sh allowed.sh; do
    case "$hits" in
        *"$f"*) bad "[대조군] $f 오탐" "$f 는 목록에 없어야 한다" "«${hits}»" ;;
        *)      ok "[대조군] $f — 오탐 없다" ;;
    esac
done

echo
echo "🔴 heredoc 형태 — 명령치환 안의 heredoc 은 bash 3.2 에서 뇌관이다:"
VIOL="$(heredoc_subst_scan "$REPO"/tests/*.sh)"
if [ "$live" -eq 0 ]; then
    bad "판정 불가 — 검사기가 죽어서 tests/ 를 못 쟀다" \
        "양성 대조군이 먼저 초록이어야 이 줄이 뜻을 갖는다" "«미측정이지 위반 없음이 아니다»"
elif [ -z "$VIOL" ]; then
    ok "tests/ 에 표식 없는 \$( … << ) 형태가 없다"
else
    bad "명령치환 heredoc 잔존" "<없음>" "$(printf '%s' "$VIOL" | sed 's|'"$REPO"/'||')"
fi

echo
echo "  통과 $pass · 실패 $fail"
[ "$fail" -eq 0 ]
