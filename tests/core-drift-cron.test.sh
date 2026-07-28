#!/usr/bin/env bash
# core-drift-cron.sh 계약 테스트 — **언제 소리를 내는가**만 본다 (네트워크·전송 없음)
#
# 왜 이것만 보나: 이 래퍼는 판정을 하지 않는다(그건 check-core-drift.sh 몫).
#   래퍼가 틀릴 수 있는 건 *알릴 것을 안 알리거나 조용할 것을 시끄럽게 하는 것* 뿐이고,
#   그중 위험한 쪽은 **판정 불가(rc=2)를 조용히 넘기는 것**이다 — 괜찮음과 같아지니까.
#
# 🔑 종료코드 계약(2026-07-28 양봇 합의 — 코어 run-tests 계열로 통일):
#     0 정상 · 1 위반(조치 있음) · 2 판정 불가 · **그 외(126·127·128+) ⇒ 판정 불가로 접는다**
#   ⚠️ 마지막 항이 이 계약의 핵심이다. 셸이 내는 코드는 도구가 고른 게 아니라 *못 돈 것*이고,
#      그걸 정상으로 접으면 죽은 검사가 초록으로 보인다. ⑧이 그 자리를 잠근다.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$BOT/scripts/core-drift-cron.sh"

pass=0; fail=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; fail=$((fail + 1)); [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/     /'; }

[ -f "$SCRIPT" ] || { echo "❌ 없음: $SCRIPT"; exit 1; }
ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT

# 가짜 검사기 — 종료코드를 주입한다
mkfake() { printf '#!/usr/bin/env bash\necho "%s"\nexit %s\n' "$2" "$1" > "$ROOT/check.sh"; chmod +x "$ROOT/check.sh"; }

run() {  # run  → stdout(DRY_RUN 이라 전송 대신 출력), 종료코드는 $rc 로
    out="$(BOT_DIR="$BOT" CHECK="$ROOT/check.sh" DRY_RUN=1 \
        HEARTBEAT="$ROOT/hb" LOG="$ROOT/log" \
        DISCORD_SEND="$ROOT/should-not-exist" bash "$SCRIPT" 2>&1)"
    rc=$?
}

echo "① 충족(rc=0) — 조용하다"
mkfake 0 "OK: repo_behind=0 · process_behind=0"; run
[ -z "$out" ] && ok "출력 없음" || bad "조용해야 하는데 떠들었다" "$out"
[ "$rc" -eq 0 ] && ok "종료코드 0" || bad "종료코드 $rc"

echo "② 위반(rc=1) — 알리고, 검사기 출력을 그대로 담는다"
mkfake 1 "DRIFT: repo_behind=5커밋"; run
grep -q "코어 드리프트" <<<"$out" && ok "알림 생성" || bad "알림 없음" "$out"
grep -q "repo_behind=5커밋" <<<"$out" && ok "검사기 출력 포함" || bad "출력이 안 실렸다" "$out"
[ "$rc" -eq 1 ] && ok "종료코드 전달(1)" || bad "종료코드 $rc"

echo "③ 🔑 판정 불가(rc=2) — **조용히 넘기지 않는다** (이 시험의 본체)"
mkfake 2 "WARN: fetch 실패"; run
grep -q "판정 불가" <<<"$out" && ok "판정 불가를 명시" || bad "조용히 넘어갔다" "$out"
[ "$rc" -eq 2 ] && ok "종료코드 전달(2)" || bad "종료코드 $rc"

echo "④ 충족과 판정 불가가 **다른 출력**이다 (숫자만 보면 둘 다 '문제 없음'처럼 보임)"
mkfake 0 "OK"; run; quiet="$out"
mkfake 2 "WARN"; run; unknown="$out"
[ "$quiet" != "$unknown" ] && ok "두 상태가 구분된다" || bad "같은 출력" "$quiet"

echo "⑤ 하트비트 — rc 와 무관하게 **항상** 갱신된다 (cron 이 살아 있다는 증거)"
rm -f "$ROOT/hb"; mkfake 0 "OK"; run
[ -s "$ROOT/hb" ] && ok "충족일 때도 남는다" || bad "하트비트 없음"
rm -f "$ROOT/hb"; mkfake 2 "WARN"; run
[ -s "$ROOT/hb" ] && ok "판정 불가일 때도 남는다" || bad "하트비트 없음"
grep -q "rc=2" "$ROOT/hb" && ok "rc 를 기록한다" || bad "rc 미기록" "$(cat "$ROOT/hb")"

echo "⑥ 로그가 누적된다(덮어쓰지 않는다) — 이력이 있어야 언제부터 밀렸는지 안다"
before=$(wc -l < "$ROOT/log"); mkfake 0 "OK"; run
[ "$(wc -l < "$ROOT/log")" -gt "$before" ] && ok "append" || bad "덮어썼다"

echo "⑧ 🔴 **셸이 내는 코드(127·126)도 판정 불가로 접는다** — 계약의 마지막 항"
# 🔑 127(command not found)·126(permission denied)은 **도구가 고른 값이 아니다.** 셸이 낸다.
#    그래서 어떤 도구도 자기 헤더에 안 적어두고, 부르는 쪽이 `case 0|1|2` 로만 쓰면
#    **default 로 조용히 샌다.** 실제로 2026-07-28 cron 이 rc=127 로 한 번도 안 돌았다
#    (PATH 가 /usr/bin:/bin 이라 node 가 안 보였다) — 그때 안 묻힌 건 이 래퍼가 우연히
#    `else` 였기 때문이지 계약이 지켜준 게 아니다. 우연을 시험으로 바꾼다.
# ⚠️ 정상으로 접으면 죽은 검사가 초록이 되고, 위반으로 접으면 오탐이 쌓여 무시된다.
#    **모르는 코드는 모른다고 낸다.**
mkfake 2 "WARN: fetch 실패"; run; plain2="$out"
for code in 127 126; do
    if [ "$code" -eq 127 ]; then
        out="$(BOT_DIR="$BOT" CHECK="$ROOT/nonexistent-check.sh" DRY_RUN=1             HEARTBEAT="$ROOT/hb" LOG="$ROOT/log"             DISCORD_SEND="$ROOT/should-not-exist" bash "$SCRIPT" 2>&1)"; rc=$?
    else
        printf '#!/usr/bin/env bash
exit 0
' > "$ROOT/noexec.sh"; chmod -x "$ROOT/noexec.sh"
        out="$(BOT_DIR="$BOT" CHECK="$ROOT/noexec.sh" DRY_RUN=1             HEARTBEAT="$ROOT/hb" LOG="$ROOT/log"             DISCORD_SEND="$ROOT/should-not-exist" bash "$SCRIPT" 2>&1)"; rc=$?
    fi
    [ "$rc" -eq 2 ] && ok "rc=$code → 판정 불가(2)로 접힌다"         || bad "rc=$code 가 $rc 로 나갔다 — 정상·위반 어느 쪽으로도 접지 않는다" "$out"
    grep -q "판정 불가" <<<"$out" && ok "  → '판정 불가' 라고 말한다"         || bad "  rc=$code 인데 판정 불가라고 안 한다" "$out"
    # 🔑 **접되 왜 접었는지는 남긴다**(룬드 제안). 접기만 하면 *도구 부재*·*권한*·*시그널*
    #    셋이 한 문장이 되어, 오늘 `head -1` 이 근거를 버린 것과 같은 자리가 된다.
    #    ⚠️ 추측이 아니다 — **셸이 코드로 이미 구분해 준다.** 그대로 옮겨 적을 뿐이다.
    case "$code" in 127) want="명령을 못 찾음" ;; 126) want="실행 권한 없음" ;; esac
    grep -q "$want" <<<"$out" && ok "  → 🔑 왜 접었는지 말한다($want)" || bad "  rc=$code 인데 이유가 없다 — 세 원인이 한 문장이 된다" "$out"
    # 음성 검사: 계약 안의 판정 불가(2)에는 그 꼬리표가 **안 붙어야** 한다. 상시로 붙으면
    # "셸 코드였다"는 신호가 죽는다(오늘 MISSING/STALE 에 재부팅 안내를 안 붙인 것과 같은 축).
    grep -qE "명령을 못 찾음|실행 권한 없음|시그널" <<<"$plain2" && bad "  정상적 판정 불가(rc=2)에도 셸 코드 꼬리표가 붙는다" "$plain2" || ok "  → rc=2 에는 안 붙는다(상시 안내가 되지 않게)"
done

echo "⑨ 시그널로 죽은 것도 **시그널이라고** 말한다 (128+N)"
# 🔴 128+N 은 *도구가 판정을 낸 것*이 아니라 **중간에 끊긴 것**이다. 127(도구 부재)과 조치가
#    다르다 — 전자는 설치·PATH, 후자는 왜 죽었는지. 한 문장으로 뭉치면 매번 다시 조사한다.
printf '#!/usr/bin/env bash\nkill -TERM $$\n' > "$ROOT/sig.sh"; chmod +x "$ROOT/sig.sh"
out="$(BOT_DIR="$BOT" CHECK="$ROOT/sig.sh" DRY_RUN=1 HEARTBEAT="$ROOT/hb" LOG="$ROOT/log" DISCORD_SEND="$ROOT/should-not-exist" bash "$SCRIPT" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && ok "rc=143 → 판정 불가(2)" || bad "rc=$rc 로 나갔다" "$out"
grep -q "시그널 15" <<<"$out" && ok "  → 시그널 번호를 계산해서 준다(143-128)" || bad "  시그널 번호가 없다" "$out"

echo "⑦ DRY_RUN 은 전송하지 않는다"
[ ! -e "$ROOT/should-not-exist" ] && ok "discord-send 미호출" || bad "전송이 일어났다"

echo
echo "  통과 $pass · 실패 $fail"
[ "$fail" -eq 0 ]
