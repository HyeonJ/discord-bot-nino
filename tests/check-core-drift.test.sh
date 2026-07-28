#!/usr/bin/env bash
# check-core-drift.sh 계약 테스트 — **세 상태가 서로 다른 출력·종료코드를 낸다**
#
# 왜 이 시험이 생겼나 (첫 실전 발동에서 실제로 틀렸다, 2026-07-28 11:15):
#   cron 알림이 `STALE: repo_behind=0 · process_behind=?파일 — 재시작 안 됨` 으로 나갔다.
#   `?` 는 "못 쟀다"인데 STALE(=미달, 조치는 재시작)로 접혀서, **값이 없는데 조치를 지시**했다.
#   판정은 우연히 맞았고(코어가 실제로 움직였다) 근거는 비어 있었다 — 그래서 안 들켰다.
#
# 종료코드 계약: 0=충족 · 2=요건 미달/재시작 필요 · 1=**판정 불가**
#   1과 2가 갈려야 래퍼가 다른 문장을 쓴다("조치 필요" vs "검사가 못 돌았다").
#
# 네트워크 안 쓴다: 로컬 bare 원격을 만들어 CORE_REPO 의 upstream 으로 붙인다.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$BOT/scripts/check-core-drift.sh"

pass=0; fail=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; fail=$((fail + 1)); [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/     /'; }

[ -f "$SCRIPT" ] || { echo "❌ 없음: $SCRIPT"; exit 1; }
ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT

# ── 가짜 코어 레포 + 로컬 원격 ──
git init -q --bare "$ROOT/remote.git"
git clone -q "$ROOT/remote.git" "$ROOT/core" 2>/dev/null
mkdir -p "$ROOT/core/relay"
cat > "$ROOT/core/relay/check-config.js" <<'JS'
process.exit(0);
JS
git -C "$ROOT/core" -c user.email=t@e -c user.name=t add -A
git -C "$ROOT/core" -c user.email=t@e -c user.name=t commit -qm init
git -C "$ROOT/core" push -q origin HEAD:main 2>/dev/null
git -C "$ROOT/core" branch -q --set-upstream-to=origin/main 2>/dev/null || \
  git -C "$ROOT/core" branch -q -u origin/main 2>/dev/null
printf 'LONG_MESSAGE_THRESHOLD=2200\n' > "$ROOT/.env"

run() { CORE_REPO="$ROOT/core" BOT_ENV="$ROOT/.env" RELAY_UNIT="$1" bash "$SCRIPT" 2>&1; }

echo "① 판정 불가 — 유닛을 못 찾으면 rc=1 이고 **재시작을 지시하지 않는다**"
out="$(run "does-not-exist-$$.service")"; rc=$?
[ "$rc" -eq 1 ] && ok "rc=1 (판정 불가)" || bad "rc=$rc — 1이어야 한다" "$out"
grep -q "판정 불가" <<<"$out" && ok "판정 불가를 명시" || bad "판정 불가 문구 없음" "$out"
# 🔑 이 시험의 본체: 값이 없는데 조치를 지시하면 안 된다
grep -q "재시작 안 됨" <<<"$out" && bad "못 쟀는데 '재시작 안 됨'으로 단정했다" "$out" \
  || ok "재시작을 단정하지 않는다"
grep -q "?파일" <<<"$out" && bad "'?파일' 이 수치인 것처럼 출력됐다" "$out" \
  || ok "'?' 를 수치 자리에 넣지 않는다"

echo "② 판정 불가와 미달(STALE)은 **다른 출력**이다"
# STALE 은 유닛이 있어야 재현되므로, 여기선 '판정 불가가 STALE 문구를 쓰지 않는지'로 가른다
grep -q "^STALE" <<<"$out" && bad "판정 불가가 STALE 로 나갔다" "$out" || ok "STALE 로 접히지 않는다"

echo "③ repo_behind 는 유효하면 같이 낸다 (한 축이 죽어도 다른 축은 보고)"
grep -q "repo_behind=0커밋" <<<"$out" && ok "유효한 축은 그대로 보고" || bad "repo_behind 미표시" "$out"

echo "④ cron 환경 재현 — XDG_RUNTIME_DIR 이 없어도 스스로 채운다"
out2="$(env -u XDG_RUNTIME_DIR -u DBUS_SESSION_BUS_ADDRESS \
        CORE_REPO="$ROOT/core" BOT_ENV="$ROOT/.env" RELAY_UNIT="does-not-exist-$$.service" \
        bash "$SCRIPT" 2>&1)"
# 유닛이 없으니 판정 불가인 건 같지만, **버스 연결 실패가 원인이면 안 된다**
grep -q "No medium found" <<<"$out2" && bad "XDG_RUNTIME_DIR 미설정이 새어나왔다" "$out2" \
  || ok "버스 오류가 새지 않는다"

echo
echo "  통과 $pass · 실패 $fail"
[ "$fail" -eq 0 ]
