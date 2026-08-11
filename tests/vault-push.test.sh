#!/usr/bin/env bash
# vault-push.sh 계약 테스트 (실제 vault·실제 원격 안 씀 — 전부 임시 루트)
#
# 왜: 이 스크립트는 **1시간마다 크론으로** 돌면서 `git add -A` 로 vault 를 통째로 쓸어담고
#   `sync: nino memory 동기화` 라는 **저자를 주장하는** 메시지로 커밋한다.
#   그런데 이 vault 는 **Darren 이 옵시디언에서 고치는 곳**이라, 그가 쓴 글이
#   author=Nino · 「nino memory 동기화」로 커밋된다 — **데몬이 남의 저작을 자기 것으로 적는다.**
#   `backup-to-nas.sh` 에서 같은 클래스를 고쳤고(#177), 여기가 **둘째 창**이다.
#
# 🔑 삼킴은 «조용하다» — 잘못 적힌 저자는 에러를 안 내고, 나중에 이력을 보는 사람이
#   「니노가 썼구나」로 읽는다. 그래서 **처방은 로그가 아니라 커밋 메시지 자체**여야 한다.
#
# 설계: 스크립트가 경로를 env 로 받는다(기본값은 프로덕션). 안 그러면 이 시험이
#   **진짜 vault 를 push** 한다. [[feedback_vault_script_test_isolation]]
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$BOT_DIR/scripts/vault-push.sh"

pass=0; fail=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; fail=$((fail + 1)); [[ -n "${2:-}" ]] && echo "$2" | sed 's/^/     /'; }

[[ -f "$SCRIPT" ]] || { echo "❌ 대상 스크립트 없음: $SCRIPT"; exit 1; }

ROOT=""
LAST_RC=0
setup() {
    ROOT="$(mktemp -d)"
    mkdir -p "$ROOT/vault" "$ROOT/logs"
    git -C "$ROOT/vault" init -q -b main
    git -C "$ROOT/vault" config user.name  "Seed"
    git -C "$ROOT/vault" config user.email "seed@test"
    echo "seed" > "$ROOT/vault/seed.md"
    git -C "$ROOT/vault" add -A
    git -C "$ROOT/vault" commit -q -m "seed"
    git init -q --bare "$ROOT/remote.git"
    git -C "$ROOT/vault" remote add origin "$ROOT/remote.git"
    git -C "$ROOT/vault" push -q origin main
}
teardown() { [[ -n "$ROOT" && -d "$ROOT" ]] && rm -rf "$ROOT"; ROOT=""; }

run_script() {
    VAULT_DIR="$ROOT/vault" \
    LOG_FILE="$ROOT/logs/vault-sync.log" \
        bash "$SCRIPT" > "$ROOT/out.txt" 2>&1
    LAST_RC=$?
}

msg_of_head() { git -C "$ROOT/vault" log -1 --format=%B; }

echo "== vault-push 계약 =="

# ── ① 격리 — 경로를 env 로 못 갈면 이 시험 자체가 «진짜 vault» 를 건드린다
setup
echo "새글" > "$ROOT/vault/새-노트.md"
run_script
if git -C "$ROOT/vault" log -1 --format=%H > /dev/null 2>&1 \
   && [ "$(git -C "$ROOT/vault" rev-list --count main)" -gt 1 ]; then
    ok "VAULT_DIR·LOG_FILE 을 env 로 받는다 — 임시 루트에서 돈다"
else
    bad "env 로 경로를 못 바꾼다 — 시험이 프로덕션 vault 를 건드리게 된다" \
        "rc=$LAST_RC / $(cat "$ROOT/out.txt")"
fi

# ── ② 삼킨 것을 «열거»한다 — 무엇이 들어갔는지가 메시지에 남아야 한다
if msg_of_head | grep -q '새-노트\.md'; then
    ok "커밋 메시지가 담긴 파일을 열거한다"
else
    bad "메시지에 파일 목록이 없다 — 「무엇을 쓸어담았나」가 사라진다" "$(msg_of_head)"
fi

# ── ③ 신규 파일은 상태 문자 A 로 구별된다 (수정과 추가가 안 섞인다)
if msg_of_head | grep -qE '^A[[:space:]]+새-노트\.md'; then
    ok "신규 파일이 상태 문자 A 로 열거된다"
else
    bad "상태 문자가 없다 — 추가와 수정이 구별 안 된다" "$(msg_of_head)"
fi

# ── ④ 🔴 저자를 주장하지 않는다 — 이 커밋은 «데몬이 쓸어담은» 것이라 저자를 모른다
if msg_of_head | grep -q '저자'; then
    ok "저자 미상을 명시한다 — 「니노가 썼다」로 안 읽힌다"
else
    bad "메시지가 저자를 주장한다 — Darren 의 글이 니노 것으로 적힌다" "$(msg_of_head)"
fi
teardown

# ── ⑤ 🔴 한글 파일명이 8진 이스케이프로 안 깨진다 (vault 는 대부분 한글이다)
setup
echo "회의" > "$ROOT/vault/회의록.md"
run_script
if msg_of_head | grep -q '회의록\.md'; then
    ok "한글 파일명이 그대로 열거된다 (core.quotepath=false)"
else
    bad "한글 파일명이 «\\354...» 8진으로 깨졌다 — 목록이 읽을 수 없게 된다" "$(msg_of_head)"
fi
teardown

# ── ⑥ push 실패가 «사유와 함께» 로그에 남는다 (지금은 2>/dev/null 로 삼킨다)
setup
git -C "$ROOT/vault" remote set-url origin "$ROOT/없는-원격.git"
echo "x" > "$ROOT/vault/x.md"
run_script
_log="$(cat "$ROOT/logs/vault-sync.log" 2>/dev/null)"
if printf '%s' "$_log" | grep -q 'failed'; then
    if printf '%s' "$_log" | grep -qiE 'repository|not a git|does not|fatal|없는-원격'; then
        ok "push 실패가 사유와 함께 남는다"
    else
        bad "「failed」만 남고 «왜» 가 없다 — 2>/dev/null 이 사유를 삼킨다" "$_log"
    fi
else
    bad "push 실패인데 로그가 조용하다" "rc=$LAST_RC / log=[$_log]"
fi
teardown

# ── ⑦ [대조군] 변경이 없으면 커밋을 «안» 만든다 (빈 커밋으로 이력을 더럽히지 않는다)
setup
_before="$(git -C "$ROOT/vault" rev-list --count main)"
run_script
_after="$(git -C "$ROOT/vault" rev-list --count main)"
if [ "$_before" = "$_after" ]; then
    ok "[대조군] 무변경이면 커밋이 안 생긴다 ($_before → $_after)"
else
    bad "무변경인데 커밋이 생겼다" "$_before → $_after"
fi
teardown

# ── ⑧ [대조군] 이 시험이 «항진명제»가 아니다 — 위 단언들이 빈 메시지를 통과시키지 않는다
#     ②③④⑤ 는 전부 grep 이라, 메시지가 비면 «전부 빨강»이 되어야 한다.
if printf '%s' "" | grep -q '저자'; then
    bad "[대조군] 빈 문자열이 「저자」 검사를 통과한다 — 단언이 항진명제다"
else
    ok "[대조군] 빈 메시지는 위 검사들을 통과 못 한다"
fi

echo ""
echo "  통과 $pass · 실패 $fail"
[ "$fail" -eq 0 ] || exit 1
