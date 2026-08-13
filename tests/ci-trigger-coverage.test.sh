#!/usr/bin/env bash
# ci-trigger-coverage.test.sh — **열린 PR 은 «전부» CI 를 타야 한다.**
#
# 🔴 왜 생겼나 (2026-08-14, 룬드가 내 스택을 세어 알려줬다):
#   `on: pull_request: branches: [main]` 이라 **base 가 main 이 아닌 PR 엔 워크플로가 안 걸린다.**
#   실측 — 내 열린 PR 중 스택 넷이 `check-runs=0`, base=main 인 다섯은 `check-runs=1`:
#   ```
#   #201 base=feat/contract-clause-unit    0      #200 base=main  1
#   #199 base=fix/auth-grace-silent-window 0      #202 base=main  1
#   #196 base=contract/number-provenance   0      #203 base=main  1
#   #194 base=docs/contract-slim           0      #204 base=main  1
#   ```
#
# 🔑 **이게 왜 «잠김»인가** — 내 계약이 그 상태를 이미 예견해뒀다:
#   *「워크플로는 있는데 런이 안 도는 레포: 갈음은 발동 안 하고(디렉터리가 있으니)
#     `ci-fresh-green` 은 rc≠0 이라 정상 모드도 불가 → 동결인데 동결 통과 조건도
#     못 재서 잠긴다. **출구는 「CI 를 고친다」 하나뿐**」*
#   ⇒ 이 시험이 그 출구를 «잠근다». 필터가 다시 좁아지면 스택이 조용히 잠긴다.
#
# 🔴 **조용한 실패다.** 런이 «빨강»이면 보이지만 런이 «없으면» PR 화면이 그냥 비어 있다.
#   「CI 없음」과 「CI 통과」가 같은 얼굴이라 아무도 안 본다 — 부재는 조용하다.
#
# 🔑 좌변을 «문자열 모양»이 아니라 **「pull_request 트리거에 base 제한이 있나」**로 적는다.
#   `push` 쪽 `branches: [main]` 은 **있어야 한다**(머지 후 main 검사) — 두 자리를 안 가르면
#   push 필터를 지우는 오답이 초록으로 통과한다.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WF="${CI_WORKFLOW:-$ROOT/.github/workflows/ci.yml}"

pass=0; fail=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; [ -n "${2:-}" ] && echo "     want: $2"; [ -n "${3:-}" ] && echo "     got:  $3"; fail=$((fail + 1)); }

[ -f "$WF" ] || { echo "⛔ 판정 불가 — 워크플로가 없다: $WF"; exit 2; }

# `on:` 아래 특정 트리거의 «키 존재»와 «본문»을 «따로» 낸다 → `present<TAB>본문…`
#
# 🔴 **둘을 안 가르면 정답이 빨강이 된다.** YAML 에서 `pull_request:` 는 «값 없는 키»로
#   유효하고 그게 정확히 «모든 base 를 덮는다»는 뜻이다. 본문 유무로 키 존재를 판정하면
#   **고치고 나서 「트리거가 없다」**가 나온다 — 이 시험을 처음 돌렸을 때 실제로 그랬다.
#   🔑 「비어 있다」와 「없다」는 다른 관측이다(부재의 세 원인 중 «라벨»에 해당).
# 🔴 `head -1` 로 자르지 않는다 — 절 안에 여러 줄이 있고, 자르면 뒤가 조용히 사라진다.
trigger_scan() {
    WF="$WF" KEY="$1" python3 - <<'PYEOF'
import os
wf, key = os.environ["WF"], os.environ["KEY"]
lines = open(wf, encoding="utf-8").read().splitlines()
out, depth, inside, present = [], None, False, False
for ln in lines:
    stripped = ln.strip()
    if not stripped or stripped.startswith("#"):
        continue
    indent = len(ln) - len(ln.lstrip())
    if not inside:
        if stripped.startswith(key + ":"):
            inside, depth, present = True, indent, True
        continue
    if indent <= depth:          # 같은 층의 다음 키 → 절 끝
        break
    out.append(stripped)
print(("yes" if present else "no") + "\t" + "\n".join(out))
PYEOF
}
trigger_present() { trigger_scan "$1" | head -1 | cut -f1; }
trigger_body()    { trigger_scan "$1" | cut -f2- ; }

echo "🔴 CI 트리거 — 열린 PR 이 «전부» CI 를 타나 (스택 PR 이 조용히 빠진다)"

PR_HAS="$(trigger_present pull_request)";  PR_BODY="$(trigger_body pull_request)"
PUSH_HAS="$(trigger_present push)";        PUSH_BODY="$(trigger_body push)"

# ① 분모부터 — 키를 하나도 못 찾았으면 아래가 전부 «항진명제»다
if [ "$PR_HAS" != yes ] && [ "$PUSH_HAS" != yes ]; then
    bad "판정 불가 — on: 아래에서 트리거 «키»를 하나도 못 찾았다" \
        "pull_request 또는 push 키" "«둘 다 없음» (좌변·파서·파일을 다 의심할 것)"
else
    ok "트리거 키를 읽었다 (pull_request=${PR_HAS} 본문 ${#PR_BODY}자 · push=${PUSH_HAS} 본문 ${#PUSH_BODY}자)"
fi

# ② pull_request 트리거 «키»가 있어야 한다 — 본문이 비는 것은 «정상»이다(= 모든 base)
if [ "$PR_HAS" != yes ]; then
    bad "pull_request 트리거가 없다 — PR 에 CI 가 아예 안 걸린다" "on: pull_request:" "«키 없음»"
else
    ok "pull_request 트리거가 있다"

    # ③ 🔴 본체 — base 제한이 있으면 스택 PR 이 빠진다
    if printf '%s\n' "$PR_BODY" | grep -q '^branches'; then
        limit="$(printf '%s\n' "$PR_BODY" | grep '^branches' | head -1)"
        bad "pull_request 에 base 제한이 있다 — base 가 그 밖인 PR 은 «런이 0» 이고 조용하다" \
            "branches 필터 없음 (모든 base 를 덮는다)" "«${limit}»"
    else
        ok "pull_request 에 base 제한이 없다 — 스택 PR 도 CI 를 탄다"
    fi
fi

# ④ 🔑 대조군 — push 쪽 필터는 «살아 있어야» 한다.
#    이게 없으면 「둘 다 지운다」는 오답이 ③ 만 보고 초록이 된다.
# 🔴 여기도 «키»와 «본문»을 가른다 — 위 ② 를 고치면서 이 자리를 그대로 두면
#   「필터가 없다」가 「트리거가 없다」로 보고된다(라벨이 틀린 빨강). 같은 계약이
#   여러 자리에 있으면 한 자리만 덮고도 초록이 되는 그 형태다(룬드 #204 리뷰 ②).
if [ "$PUSH_HAS" != yes ]; then
    bad "push 트리거가 없다 — 머지 후 main 을 아무도 안 잰다" "on: push: branches: [main]" "«키 없음»"
elif printf '%s\n' "$PUSH_BODY" | grep -q '^branches.*main'; then
    ok "대조군: push 쪽 main 필터는 살아 있다 (전면 해제가 아니다)"
else
    bad "push 필터가 main 을 안 가린다 — 모든 브랜치 push 마다 런이 돈다(월 한도)" \
        "branches: [main]" "«${PUSH_BODY}»"
fi

# 🧪 [양성 대조군] 검사기를 실제로 태운다 — 위반 파일을 만들어서 같은 코드로.
#   이게 없으면 위 초록이 「통과」인지 「안 봤다」인지 안 갈린다.
if [ "${CI_TRIGGER_SELFTEST:-1}" = "1" ]; then
    echo
    echo "🧪 대조군 — 위반 워크플로를 만들어 같은 검사기를 태운다"
    _tmp="$(mktemp -d)"; trap 'rm -rf "$_tmp"' EXIT

    # ⓐ pull_request 에 base 제한이 «있는» 판 (= 고치기 전 우리 파일)
    printf 'name: CI\n\non:\n  pull_request:\n    branches: [main]\n  push:\n    branches: [main]\n\njobs:\n  a:\n    runs-on: ubuntu-latest\n' > "$_tmp/bad.yml"
    _o="$(CI_WORKFLOW="$_tmp/bad.yml" CI_TRIGGER_SELFTEST=0 bash "${BASH_SOURCE[0]}" 2>&1)"; _rc=$?
    if [ "$_rc" -ne 0 ] && printf '%s\n' "$_o" | grep -q 'base 제한이 있다'; then
        ok "[대조군ⓐ] base 제한을 잡고 빨강이 된다 (rc=${_rc})"
    else
        bad "[대조군ⓐ] 위반 파일을 못 잡는다 — 위 판정은 못 믿는다" "rc≠0 + 'base 제한이 있다'" "rc=${_rc}"
    fi

    # ⓑ 🔴 «둘 다 지운» 판 — ③ 은 통과하는데 ④ 가 잡아야 한다.
    #   이 칸이 없으면 ④ 가 「있으나 마나」인지 알 수 없다.
    printf 'name: CI\n\non:\n  pull_request:\n  push:\n\njobs:\n  a:\n    runs-on: ubuntu-latest\n' > "$_tmp/loose.yml"
    _o2="$(CI_WORKFLOW="$_tmp/loose.yml" CI_TRIGGER_SELFTEST=0 bash "${BASH_SOURCE[0]}" 2>&1)"; _rc2=$?
    # 🔴 좌변을 «④ 가 낸 문장»으로 좁힌다. `grep -q 'push'` 로 두면 ① ② 가 낸 빨강까지
    #   같은 초록을 내서 **ⓑ 가 ④ 를 재는지 알 수 없다**(이 파일 초판이 실제로 그랬다).
    if [ "$_rc2" -ne 0 ] && printf '%s\n' "$_o2" | grep -q 'push 필터가 main 을 안 가린다'; then
        ok "[대조군ⓑ] push 필터까지 지운 판을 «④ 가» 잡는다 (rc=${_rc2})"
    else
        bad "[대조군ⓑ] 전면 해제를 ④ 가 못 잡는다 — ④ 는 무증인이다" \
            "rc≠0 + 'push 필터가 main 을 안 가린다'" "rc=${_rc2} · 출력: $(printf '%s' "$_o2" | tr '\n' ' ')"
    fi
fi

echo
echo "  통과 $pass · 실패 $fail"
[ "$fail" -eq 0 ]
