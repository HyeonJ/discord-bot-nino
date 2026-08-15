#!/usr/bin/env bash
# 셔틀 코어 가드 계약 테스트 — **셔틀이 어느 클론을 보는지, 그 클론이 기대 브랜치인지**
#
# 왜 이 시험이 생겼나 (2026-08-01 실측):
#   lint 셔틀이 기본값 `~/yaksu-bot-core`(=dev, `feat/cli-guard`)를 실행하는 바람에
#   코어 #64~#74 의 lint 개선이 **하나도 안 돌고 있었다.** 그런데 에러가 없었다 —
#   셔틀 문구는 맞았고 **가리키는 자리**가 갈렸다. 내용 기반 대조로는 못 잡는다.
#
# 🔑 이 가드가 셔틀에 사는 이유: **검사가 검사 대상 안에 살면 안 된다.**
#   코어에 넣으면 "코어가 자기 클론이 맞는지"를 코어가 판정하게 된다 — 잘못된 클론을
#   실행 중이면 그 안의 가드도 잘못된 클론의 것이다. 그래서 3줄을 셔틀에 인라인한다.
#
# 🔑 이 레이아웃은 클론이 **둘**이고 역할이 다르다 (심링크·behind 체크를 쓰면 안 되는 이유):
#     ~/yaksu-bot-core       dev   main 에서 벗어나 있는 게 정상
#     ~/yaksu-bot-core-live  prod  main
#   ⇒ 가드는 **경로마다 다른 기대값**을 갖는다. "최신인가"가 아니라 "제 역할인가"를 묻는다.
#
# 계약: 기대와 같으면 조용하다(rc=0) · 다르면 stderr 에 경고 + 경로·역할을 같이 낸다(rc=0, 차단 아님)
#       기대값이 «-» 면 검사하지 않되 **그 사실을 표시**한다(무음 금지 — 안 재는 것과 통과가 같으면 안 된다)
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GUARD="$BOT/scripts/core-clone-guard.sh"

pass=0; fail=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; fail=$((fail + 1)); [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/     /'; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkrepo() { # $1=경로 $2=브랜치
    git init -q "$1" 2>/dev/null
    git -C "$1" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
    [ "$2" = "main" ] || git -C "$1" checkout -q -b "$2"
    [ "$2" = "main" ] && git -C "$1" branch -q -M main
}

echo "== 셔틀 코어 가드 =="

[ -f "$GUARD" ] || { bad "가드 스크립트 없음: $GUARD"; echo; echo "  통과 $pass · 실패 $fail"; exit 1; }
bash -n "$GUARD" && ok "구문 검사 통과" || bad "구문 오류"

# ① 기대와 같으면 조용하다
mkrepo "$TMP/prod" main
out="$(bash "$GUARD" "$TMP/prod" main 2>&1)"; rc=$?
[ $rc -eq 0 ] && [ -z "$out" ] && ok "기대=main·실제=main → 무음 rc=0" \
    || bad "기대 일치인데 출력이 있다 (rc=$rc)" "$out"

# ② 기대와 다르면 경고 — 그리고 **경로와 실제 브랜치가 문안에 있어야 한다**
mkrepo "$TMP/dev" feat/cli-guard
out="$(bash "$GUARD" "$TMP/dev" main 2>&1)"; rc=$?
if [ $rc -eq 0 ] && printf '%s' "$out" | grep -q 'feat/cli-guard' && printf '%s' "$out" | grep -q "$TMP/dev"; then
    ok "불일치 → 경고에 실제 브랜치와 경로가 같이 나온다"
else
    bad "불일치 경고에 브랜치 또는 경로가 빠졌다 (rc=$rc)" "$out"
fi

# ③ «-» 는 검사 안 하되 **표시한다** (무음이면 「안 잼」과 「통과」가 구분 안 된다)
out="$(bash "$GUARD" "$TMP/dev" - 2>&1)"; rc=$?
[ $rc -eq 0 ] && [ -n "$out" ] && ok "기대=«-» → 검사 생략을 표시한다(무음 아님)" \
    || bad "«-» 가 조용하다 — 안 잰 것과 통과가 같아진다 (rc=$rc)" "$out"

# ④ 없는 경로 → 판정 불가를 말한다 (조용히 통과하면 안 된다)
out="$(bash "$GUARD" "$TMP/nope" main 2>&1)"; rc=$?
[ -n "$out" ] && ok "없는 경로 → 판정 불가를 말한다" \
    || bad "없는 경로가 조용히 통과했다 (rc=$rc)"

# ⑤ git 아닌 디렉터리 → 판정 불가
mkdir -p "$TMP/plain"
out="$(bash "$GUARD" "$TMP/plain" main 2>&1)"; rc=$?
[ -n "$out" ] && ok "비-git 경로 → 판정 불가를 말한다" \
    || bad "비-git 이 조용히 통과했다 (rc=$rc)"

# ⑥ detached HEAD → 브랜치명 자리에 **읽을 수 있는 라벨**이 들어간다
# ⚠️ `[ -n "$out" ]` 만으로는 부족하다 — 라벨을 '' 로 바꿔도 「기대=main 실제= …」 로
#    출력은 비지 않아서 **변이가 살아남는다**(룬드 실측, 맥에서 8/0 통과). 라벨 자체를 본다.
git -C "$TMP/prod" checkout -q --detach 2>/dev/null
out="$(bash "$GUARD" "$TMP/prod" main 2>&1)"; rc=$?
case "$out" in
  *"(detached)"*) ok "detached → 브랜치 자리에 (detached) 라벨이 찍힌다" ;;
  # ⚠️ `${out}` 중괄호 필수 — bash 3.2 는 `"$out»"` 에서 `»` 의 선두 바이트를 변수명에 먹어
  #   `unbound variable` 로 죽는다(룬드 맥 실측). 잠금: tests/repo-hygiene.test.sh
  *) bad "detached 라벨이 없다 — 빈 브랜치명이 기대와 같아 보인다 (out=«${out}» rc=${rc})" ;;
esac

# ⑦ 가드는 **차단하지 않는다** — 경고만 하고 rc=0 (셔틀 본작업을 막으면 안 된다)
out="$(bash "$GUARD" "$TMP/dev" main 2>&1)"; rc=$?
[ $rc -eq 0 ] && ok "경고해도 rc=0 — 셔틀 본작업을 막지 않는다" \
    || bad "가드가 셔틀을 차단한다 (rc=$rc)"

echo
echo "  통과 $pass · 실패 $fail"
[ $fail -eq 0 ]
