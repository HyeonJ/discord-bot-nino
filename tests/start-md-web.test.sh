#!/usr/bin/env bash
# start-md-web.sh 계약 — **유닛이 부르는 래퍼가 조용히 실패하지 않는다**
#
# 왜 이 시험이 생겼나 (2026-07-28):
#   md-web(포트 58082)은 니노 Claude 세션의 **자식 프로세스**로 떠 있었다. 세션이 죽으면
#   같이 죽고, Caddy 가 502 를 뱉는다 — 7/17 에 실제 사고가 났고 그 뒤로도 세션 재시작이
#   md-web 을 끊었다. systemd --user 유닛으로 부모를 바꿨고, 유닛은 이 래퍼를 부른다.
#
#   래퍼가 조용히 죽으면 유닛은 Restart=always 로 **무한 재시작**을 돌면서 502 를 유지한다.
#   그래서 전제(디렉터리·bun 존재)가 깨졌을 때 **이유를 말하고 0 이 아닌 코드로** 죽어야 한다.
#
# 격리: 실제 bun 을 실행하지 않는다(가짜 bun 을 만들어 exec 대상으로 쓴다).
#       실제 ~/md-web·~/.env 를 건드리지 않게 MD_WEB_DIR·BUN·BOT_ENV 를 전부 주입한다.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$BOT/scripts/start-md-web.sh"

pass=0; fail=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; fail=$((fail + 1)); [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/     /'; }

[ -f "$SCRIPT" ] || { echo "❌ 없음: $SCRIPT"; exit 1; }
ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT

mkdir -p "$ROOT/md-web/src"
printf 'console.log("stub")\n' > "$ROOT/md-web/src/cli.ts"
# 가짜 bun — 받은 인자와 cwd 를 찍는다. exec 대상이므로 이게 마지막 프로세스가 된다.
cat > "$ROOT/bun" <<'FAKE'
#!/usr/bin/env bash
echo "BUN_ARGS=$*"
echo "BUN_CWD=$PWD"
echo "SAW_ENV=${MDWEB_TEST_MARKER:-none}"
FAKE
chmod +x "$ROOT/bun"

run() { MD_WEB_DIR="$1" BUN="$2" BOT_ENV="$3" bash "$SCRIPT" 2>&1; }

echo "① 정상 경로 — 가짜 bun 을 md-web 디렉터리에서 실행한다"
out="$(run "$ROOT/md-web" "$ROOT/bun" "$ROOT/none.env")"; rc=$?
[ "$rc" -eq 0 ] && ok "rc=0" || bad "rc=$rc" "$out"
grep -q 'BUN_ARGS=run src/cli.ts serve' <<<"$out" && ok "인자가 'run src/cli.ts serve'" || bad "인자가 다르다" "$out"
grep -q "BUN_CWD=$ROOT/md-web" <<<"$out" && ok "md-web 디렉터리에서 실행" || bad "cwd 가 다르다" "$out"

echo "② .env 가 있으면 읽는다 (없으면 그냥 넘어간다)"
printf 'MDWEB_TEST_MARKER=loaded\n' > "$ROOT/with.env"
out="$(run "$ROOT/md-web" "$ROOT/bun" "$ROOT/with.env")"
grep -q 'SAW_ENV=loaded' <<<"$out" && ok ".env 의 값이 자식에 전달됨" || bad ".env 를 안 읽었다" "$out"
out="$(run "$ROOT/md-web" "$ROOT/bun" "$ROOT/absent.env")"; rc=$?
[ "$rc" -eq 0 ] && ok ".env 가 없어도 기동한다" || bad ".env 부재로 죽었다(rc=$rc)" "$out"

echo "③ 🔑 전제가 깨지면 **이유를 말하고** 0 이 아닌 코드로 죽는다"
# 조용히 죽으면 유닛이 Restart=always 로 무한 재시작하며 502 를 유지한다
out="$(run "$ROOT/absent-dir" "$ROOT/bun" "$ROOT/none.env")"; rc=$?
[ "$rc" -ne 0 ] && ok "디렉터리 없음 → rc=$rc" || bad "디렉터리가 없는데 rc=0" "$out"
grep -q 'md-web 디렉터리 없음' <<<"$out" && ok "이유를 말한다(디렉터리)" || bad "이유가 없다" "$out"

out="$(run "$ROOT/md-web" "$ROOT/absent-bun" "$ROOT/none.env")"; rc=$?
[ "$rc" -ne 0 ] && ok "bun 없음 → rc=$rc" || bad "bun 이 없는데 rc=0" "$out"
grep -q 'bun 실행 파일 없음' <<<"$out" && ok "이유를 말한다(bun)" || bad "이유가 없다" "$out"

echo "④ 유닛 파일이 이 래퍼를 부른다 (배선이 실제로 이어져 있나)"
UNIT="$HOME/.config/systemd/user/nino-mdweb.service"
if [ -f "$UNIT" ]; then
  grep -q "ExecStart=$BOT/scripts/start-md-web.sh" "$UNIT" && ok "ExecStart 가 이 래퍼를 가리킨다" \
    || bad "ExecStart 가 다른 것을 가리킨다" "$(grep ExecStart "$UNIT")"
  grep -q '^Restart=always' "$UNIT" && ok "Restart=always" || bad "Restart 설정 없음"
else
  echo "  ⏭️  건너뜀 — 이 기계에 유닛이 설치돼 있지 않다(레포만 clone 한 경우)"
fi

echo
echo "  통과 $pass · 실패 $fail"
[ "$fail" -eq 0 ]
