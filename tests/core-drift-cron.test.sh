#!/usr/bin/env bash
# core-drift-cron.sh 계약 테스트 — **언제 소리를 내는가**만 본다 (네트워크·전송 없음)
#
# 왜 이것만 보나: 이 래퍼는 판정을 하지 않는다(그건 check-core-drift.sh 몫).
#   래퍼가 틀릴 수 있는 건 *알릴 것을 안 알리거나 조용할 것을 시끄럽게 하는 것* 뿐이고,
#   그중 위험한 쪽은 **판정 불가(rc=1)를 조용히 넘기는 것**이다 — 괜찮음과 같아지니까.
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

echo "② 미달(rc=2) — 알리고, 검사기 출력을 그대로 담는다"
mkfake 2 "DRIFT: repo_behind=5커밋"; run
grep -q "코어 드리프트" <<<"$out" && ok "알림 생성" || bad "알림 없음" "$out"
grep -q "repo_behind=5커밋" <<<"$out" && ok "검사기 출력 포함" || bad "출력이 안 실렸다" "$out"
[ "$rc" -eq 2 ] && ok "종료코드 전달(2)" || bad "종료코드 $rc"

echo "③ 🔑 판정 불가(rc=1) — **조용히 넘기지 않는다** (이 시험의 본체)"
mkfake 1 "WARN: fetch 실패"; run
grep -q "판정 불가" <<<"$out" && ok "판정 불가를 명시" || bad "조용히 넘어갔다" "$out"
[ "$rc" -eq 1 ] && ok "종료코드 전달(1)" || bad "종료코드 $rc"

echo "④ 충족과 판정 불가가 **다른 출력**이다 (숫자만 보면 둘 다 '문제 없음'처럼 보임)"
mkfake 0 "OK"; run; quiet="$out"
mkfake 1 "WARN"; run; unknown="$out"
[ "$quiet" != "$unknown" ] && ok "두 상태가 구분된다" || bad "같은 출력" "$quiet"

echo "⑤ 하트비트 — rc 와 무관하게 **항상** 갱신된다 (cron 이 살아 있다는 증거)"
rm -f "$ROOT/hb"; mkfake 0 "OK"; run
[ -s "$ROOT/hb" ] && ok "충족일 때도 남는다" || bad "하트비트 없음"
rm -f "$ROOT/hb"; mkfake 1 "WARN"; run
[ -s "$ROOT/hb" ] && ok "판정 불가일 때도 남는다" || bad "하트비트 없음"
grep -q "rc=1" "$ROOT/hb" && ok "rc 를 기록한다" || bad "rc 미기록" "$(cat "$ROOT/hb")"

echo "⑥ 로그가 누적된다(덮어쓰지 않는다) — 이력이 있어야 언제부터 밀렸는지 안다"
before=$(wc -l < "$ROOT/log"); mkfake 0 "OK"; run
[ "$(wc -l < "$ROOT/log")" -gt "$before" ] && ok "append" || bad "덮어썼다"

echo "⑦ DRY_RUN 은 전송하지 않는다"
[ ! -e "$ROOT/should-not-exist" ] && ok "discord-send 미호출" || bad "전송이 일어났다"

echo
echo "  통과 $pass · 실패 $fail"
[ "$fail" -eq 0 ]
