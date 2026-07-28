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

pass=0; fail=0; unk=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
# 🔑 판정 불가는 통과도 실패도 아니다 — 이 시험은 **설치된 유닛**을 보는 갈래가 있어서,
#    정본 체크아웃이 아니거나 유닛이 없으면 *못 쟀다* 가 정답이다. 실패로 접으면 worktree 에서
#    헛빨간불이 뜨고(실측: 2026-07-28), 통과로 접으면 배선이 끊겨도 초록이 된다.
unmeasured() { echo "  ⛔ 판정 불가 — $1"; unk=$((unk + 1)); }
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
# 주입 가능하게 둔다 — 이 갈래(유닛 배선)를 값으로 재려면 세 경우를 다 먹여봐야 한다:
#   정본 일치 / 다른 체크아웃(worktree) / 엉뚱한 대상. 기본값은 실제 유닛이다.
UNIT="${MDWEB_UNIT:-$HOME/.config/systemd/user/nino-mdweb.service}"
if [ -f "$UNIT" ]; then
  EXEC_PATH="$(sed -n 's/^ExecStart=//p' "$UNIT" | head -1 | awk '{print $1}')"
  if [ "$EXEC_PATH" = "$BOT/scripts/start-md-web.sh" ]; then
    ok "ExecStart 가 이 래퍼를 가리킨다"
  elif [ "${EXEC_PATH%/scripts/start-md-web.sh}" != "$EXEC_PATH" ] && [ -x "$EXEC_PATH" ]; then
    # 같은 이름의 래퍼를 가리키지만 **다른 체크아웃**이다 — worktree 에서 돌리면 항상 이렇게 된다.
    # 여기서 "실패"라고 하면 정본이 멀쩡한데도 빨간불이 뜬다. 정답은 *못 쟀다* 다.
    unmeasured "유닛은 다른 체크아웃의 래퍼를 가리킨다(정본에서 재야 한다)
     유닛: $EXEC_PATH
     지금: $BOT/scripts/start-md-web.sh"
  else
    bad "ExecStart 가 이 래퍼가 아닌 것을 가리킨다" "$(grep ExecStart "$UNIT")"
  fi
  grep -q '^Restart=always' "$UNIT" && ok "Restart=always" || bad "Restart 설정 없음"
else
  # ⏭️ 로 조용히 넘기면 "배선을 안 쟀다"가 "배선이 정상"으로 읽힌다
  unmeasured "이 기계에 유닛이 설치돼 있지 않다(레포만 clone 한 경우) — 배선을 못 쟀다"
fi

echo
echo "  통과 $pass · 실패 $fail · 판정 불가 $unk"
# 종료코드 3층 (check-core-drift.sh · check-relay-present.sh 와 같은 계약)
#   0 전부 쟀고 통과 · 1 실패 · 2 **못 쟀다**(0/1 로 접지 않는다)
[ "$fail" -gt 0 ] && exit 1
[ "$unk" -gt 0 ] && exit 2
exit 0
