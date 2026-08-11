#!/usr/bin/env bash
# launcher-starts-daemon.test.sh — 「단일 실행 가드」가 «실제로 띄우나»
#
# 🔴 왜 생겼나 (실사고, 2026-08-11):
#   내 crontab 이 이랬다 —
#     `pgrep -f 'auto-approve-claude\.sh' >/dev/null || (… nohup bash …/auto-approve-claude.sh … &)`
#   **데몬이 0개인데 가드가 rc=0** 을 냈다. 크론이 그 줄 «전체»를 한 셸에 넘기고,
#   그 셸의 명령줄에 `auto-approve-claude.sh` 가 **`nohup` 인자로 또 들어 있어서**
#   `pgrep -f` 가 **자기 부모를 잡았다.** ⇒ `||` 가지가 **한 번도 안 돌았다.**
#   실측: `ps` 로 센 실제 데몬 **0건** · 가드 rc **0** · 잡힌 PID 는 자기 래퍼 셸.
#
# 🔑 이 병이 조용한 이유가 둘이다:
#   ① **가드가 참이면 아무 일도 안 일어난다** — 로그도 안 남고 에러도 없다.
#      「이미 돌고 있다」와 「한 번도 안 돌았다」가 **같은 화면**이다.
#   ② 로그 파일이 **비어 있는** 게 아니라 **없었다.** 「조용한 데몬」으로 읽히기 쉽다.
#
# ⚠️ **좌변을 「pgrep 을 쓰나」로 두지 않는다** — 그건 «꼴»이다. 물어야 할 것은
#   **「데몬 0개에서 이 줄을 돌리면 1개가 되나」**이고, 그건 수단과 무관하다.
#   (`flock` · pidfile · launchd KeepAlive · systemd Restart — 계약은 같고 수단은 갈린다)
#
# 🔸 이 시험은 **프로세스를 띄운다.** 진짜 훅이 아니라 «가짜 데몬»을 쓰고, 끝나면 죽인다.
set -uo pipefail

pass=0; fail=0; skip=0
ok()   { echo "  ✅ $1"; pass=$((pass + 1)); }
bad()  { echo "  ❌ $1"; [ -n "${2:-}" ] && echo "     want: $2"; [ -n "${3:-}" ] && echo "     got:  $3"; fail=$((fail + 1)); }
note() { echo "  ⛔ $1"; skip=$((skip + 1)); }

_T="$(mktemp -d)"
DAEMON="$_T/fake-daemon.sh"
LOCK="$_T/daemon.lock"
cleanup() {
    # 🔴 이름이 아니라 «우리가 적어둔 PID» 로 죽인다 — 이름으로 죽이면 이 시험이
    #   같은 함정(패턴이 남을 잡는다)을 반대 방향으로 밟는다.
    [ -f "$_T/pids" ] && while read -r p; do [ -n "$p" ] && kill -9 "$p" 2>/dev/null; done < "$_T/pids"
    rm -rf "$_T"
}
trap cleanup EXIT

cat > "$DAEMON" <<'EOF'
#!/usr/bin/env bash
# 가짜 데몬 — 뜬 것을 증명하려고 자기 PID 를 적고 잠든다
echo "$$" >> "$DAEMON_PIDFILE"
sleep 60
EOF
chmod +x "$DAEMON"

# 지금 도는 가짜 데몬 수를 «PID 로» 센다 (이름으로 안 센다)
count_live() {
    local n=0 p
    [ -f "$DAEMON_PIDFILE" ] || { echo 0; return; }
    while read -r p; do
        [ -n "$p" ] && kill -0 "$p" 2>/dev/null && n=$((n + 1))
    done < "$DAEMON_PIDFILE"
    echo "$n"
}

# 🔴 **크론과 «같은 모양»으로 돌린다** — 줄 전체를 한 셸에 넘긴다.
#   이게 없으면 병이 재현되지 않는다: 셸의 명령줄에 데몬 «경로»가 들어가는 것이
#   바로 자기-매칭의 원인이다. 시험이 `bash -c` 를 안 쓰면 **옛 판도 초록이 된다.**
run_launcher() { bash -c "$1" > /dev/null 2>&1; sleep 0.4; }

export DAEMON_PIDFILE="$_T/pids"

# 두 후보 — 좌변은 같고 «수단»만 다르다
OLD="pgrep -f '$(basename "$DAEMON" .sh)' > /dev/null 2>&1 || (nohup bash $DAEMON </dev/null >/dev/null 2>&1 &)"
NEW="flock -n $LOCK -c 'exec bash $DAEMON' >/dev/null 2>&1 &"

# 🔴 **`pgrep -f` 의 «조상 매칭»이 구현마다 다르다 — 그래서 이 병은 호스트를 탄다.**
#   GNU procps: 자기 «자신»만 뺀다 ⇒ 부모 `bash -c` 의 명령줄을 **잡는다**(내 실사고)
#   BSD(macOS): 자기 **조상 전부**를 뺀다 ⇒ 안 잡는다 ⇒ **옛 판이 그냥 뜬다**
#   실측 2026-08-11(룬드 맥, `#187` 리뷰): `bash -c` 안에서 rc=1 인데 그 셸 명령줄엔 낱말이 있다.
#
# 🔑 **그래서 「옛 판이 떴다」는 «실패»가 아니라 «판정 불가»다** — 내가 어제 세운 조항 그대로:
#   *「관측 자체가 없으면 실패가 아니라 판정 불가」*. 여기서 관측된 건 「시험이 고장났다」가
#   아니라 **「이 호스트에선 옛 판이 안 아프다」**이고, 그러면 ②의 초록을 뒷받침할 증인이
#   **없는** 것이지 무언가가 **틀린** 게 아니다. (룬드 `#187` 리뷰)
#
# ⚠️ 그렇다고 «전부» note 로 접으면 「대조군이 진짜 고장난 경우」까지 숨는다.
#   ⇒ **가르는 좌변을 «잰다»**: 이 호스트의 `pgrep` 이 조상을 잡나?
_pgrep_matches_ancestor() {
    # 표식이 «그 bash -c 의 명령줄에만» 있다 — 잡히면 조상 매칭이다
    bash -c "pgrep -f 'zzancestor-probe-$$' > /dev/null 2>&1" 2>/dev/null
}

echo "① 🔴 [대조군] 옛 판 — 데몬 0개인데 «안 띄운다»(자기 부모를 잡는다)"
: > "$DAEMON_PIDFILE"
_before="$(count_live)"
if [ "$_before" -ne 0 ]; then
    note "출발점이 0이 아니다(${_before}개) — 이 축을 못 쟀다"
else
    run_launcher "$OLD"
    _after="$(count_live)"
    if [ "$_after" -eq 0 ]; then
        ok "옛 판은 0 → 0 (병이 재현된다 — 이 시험이 무언가를 «본다»는 증인)"
    elif _pgrep_matches_ancestor; then
        bad "옛 판이 떴는데 이 호스트의 pgrep 은 조상을 «잡는다» — 대조군이 진짜 고장났다" \
            "0개" "${_after}개"
    else
        note "이 호스트의 pgrep 은 조상을 «안» 잡는다(BSD 계열) — 옛 판이 안 아프므로 이 축을 못 쟀다"
        note "  ⇒ ②③ 의 초록에는 이 호스트에서 «증인이 없다»(틀린 게 아니라 못 잰 것)"
    fi
fi

echo
echo "② 🔑 새 판 — 데몬 0개에서 돌리면 «1개»가 된다"
if command -v flock > /dev/null 2>&1; then
    : > "$DAEMON_PIDFILE"
    run_launcher "$NEW"
    _n="$(count_live)"
    if [ "$_n" -eq 1 ]; then
        ok "0 → 1 (실제로 떴다)"
    else
        bad "안 떴거나 여럿 떴다" "1개" "${_n}개"
    fi

    echo
    echo "③ 🔴 그런데 «두 번 돌려도 1개»여야 한다 — 띄우기만 하면 가드가 아니다"
    # ⚠️ ② 만 있으면 「가드를 통째로 지운다」 변이가 안 죽는다. 단일성은 따로 잰다.
    run_launcher "$NEW"
    _n2="$(count_live)"
    if [ "$_n2" -eq 1 ]; then
        ok "1 → 1 (둘째가 락에 막혔다)"
    else
        bad "두 번 돌리니 ${_n2}개가 됐다 — 단일성이 없다" "1개" "${_n2}개"
    fi
else
    # 🔴 여기에 백틱을 쓰면 «명령 치환»이 돌아 낱말이 사라지고 stderr 가 샌다.
    #   그리고 이 가지가 도는 유일한 조건이 **`flock` 이 없는 호스트**라, 정확히 그 호스트에서
    #   `flock: command not found` 가 stderr 로 나간다 — 러너의 「rc=0 인데 stderr 있음」 축이
    #   이 파일을 실패로 센다. 🔑 **판정 불가를 정직하게 내려던 가지가 «왜 못 쟀는지»를 지운다.**
    #   실측 2026-08-11 룬드 맥(`#187` 리뷰): 메시지가 「 이 없다」로 찍혔다.
    note "«flock» 이 없다 — 이 호스트에선 ②③ 을 못 쟀다 (수단이 갈리는 자리다: launchd·systemd)"
    note "  (같은 이유로 ③ 도 못 쟀다)"
fi

echo
echo "④ 🔑 판정이 «수단»과 무관한지 — 열린 낱말 목록이 아니라 «닫힌» 좌변으로"
# 🔴 첫 판은 `ok|bad` 줄에 `pgrep|flock` 이라는 **낱말 목록**이 없는지 봤다. 룬드 지적:
#   **그건 열린 집합**이라 다음 수단(`launchctl`·`systemd-run`·`daemonize`)이 들어오면
#   그냥 통과한다 — 잠기는 게 아니라 «지금 아는 것»으로 닫힌다.
# 🔑 닫힌 좌변은 **「판정 함수가 수단을 «인자로» 안 받는다」**다. 인자가 없으면
#   무엇으로 띄웠든 판정이 달라질 «경로 자체»가 없다. 수단 목록이 늘어도 이 단언은 안 낡는다.
_body="$(sed -n '/^count_live() {/,/^}/p' "${BASH_SOURCE[0]}")"
if [ -z "$_body" ]; then
    bad "판정 함수를 못 찾았다 — 이름이 바뀌었으면 이 단언부터 고칠 것" "count_live 정의" "없음"
elif printf '%s' "$_body" | command grep -qE '\$[1-9@*]|\$\{[1-9@*]'; then
    bad "판정 함수가 «인자»를 받는다 — 수단이 판정에 흘러들 경로가 있다" "인자 0개" "$(printf '%s' "$_body" | command grep -oE '\$[1-9@*]' | tr '\n' ' ')"
else
    ok "판정 함수 count_live 가 인자를 안 받는다 — 수단이 판정에 닿을 «경로»가 없다"
fi

# 🔴 그리고 판정 함수가 «외부 명령»으로 세지 않는지 — `pgrep`·`ps` 로 세면 이름 매칭이
#   다시 들어오고, 그게 이 시험이 잡으려는 바로 그 병이다. `kill -0` 은 PID 만 본다.
if printf '%s' "$_body" | command grep -qE '\bkill -0\b' && \
   ! printf '%s' "$_body" | command grep -qE '\b(pgrep|pkill|ps)\b'; then
    ok "판정이 «PID 로만» 난다 (이름 매칭이 판정에 안 들어간다)"
else
    bad "판정 함수가 이름으로 센다 — 잡으려는 병을 자기가 앓는다" "kill -0 만" "$(printf '%s' "$_body" | command grep -oE '\b(pgrep|pkill|ps)\b' | tr '\n' ' ')"
fi

echo "  통과 $pass · 실패 $fail · 판정 불가 $skip"
[ "$fail" -eq 0 ] || exit 1
