#!/usr/bin/env bash
# resolve-bin.sh 계약 시험
#
# 🔑 무엇을 잠그나 — cron 의 PATH 는 `/usr/bin:/bin` 뿐이라 nvm·`~/.local/bin` 이 안 보인다.
#   그래서 `check-core-drift.sh` 가 매 실행 `node: command not found`(rc=127) 로 떨어졌다.
#   문구는 "판정 불가" 라 정직했지만 **그 검사가 cron 에서 한 번도 안 돌았다.**
#   ⇒ 이 시험은 *메시지가 정직한가* 가 아니라 **능력을 되찾았는가** 를 잰다.
#
# ⚠️ 못 찾은 것을 **빈 문자열로 돌려주면 안 된다** — 호출부가 `""` 를 실행해 원인이
#    "도구 부재" 인데 "구문 오류" 로 보이는 자리가 된다. rc 로만 말한다.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB="$(cd "$SCRIPT_DIR/.." && pwd)/scripts/lib/resolve-bin.sh"

pass=0; fail=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; [ -n "${2:-}" ] && echo "     want: $2"; [ -n "${3:-}" ] && echo "     got:  $3"; fail=$((fail + 1)); }

[ -f "$LIB" ] || { echo "❌ 없음: $LIB"; exit 1; }
# shellcheck source=/dev/null
. "$LIB"

ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT

echo "① PATH 에 있으면 그 이름을 그대로 낸다"
out="$(resolve_bin sh)"; rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "sh" ] && ok "PATH 우선" || bad "PATH 해석" "sh (rc=0)" "$out (rc=$rc)"

echo "② 🔑 **cron PATH(/usr/bin:/bin)에서도 찾는다** — 이게 이 파일이 생긴 이유다"
mkdir -p "$ROOT/home/.local/bin"
printf '#!/bin/sh\necho fake\n' > "$ROOT/home/.local/bin/faketool"
chmod +x "$ROOT/home/.local/bin/faketool"
out="$(PATH=/usr/bin:/bin HOME="$ROOT/home" bash -c '. "$1"; resolve_bin faketool' _ "$LIB")"; rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "$ROOT/home/.local/bin/faketool" ] \
  && ok "~/.local/bin 을 찾는다" || bad "cron PATH 해석" "$ROOT/home/.local/bin/faketool" "$out (rc=$rc)"

echo "③ nvm 경로(버전 디렉터리 glob)도 찾는다 — 버전이 바뀌어도 자리를 안 고친다"
mkdir -p "$ROOT/home/.nvm/versions/node/v24.14.0/bin"
printf '#!/bin/sh\necho node\n' > "$ROOT/home/.nvm/versions/node/v24.14.0/bin/nvmtool"
chmod +x "$ROOT/home/.nvm/versions/node/v24.14.0/bin/nvmtool"
out="$(PATH=/usr/bin:/bin HOME="$ROOT/home" bash -c '. "$1"; resolve_bin nvmtool' _ "$LIB")"; rc=$?
[ "$rc" -eq 0 ] && ok "nvm 버전 디렉터리를 훑는다" || bad "nvm 해석" "경로 (rc=0)" "$out (rc=$rc)"

echo "③-b 🔑 nvm 버전이 여럿이면 **가장 높은 것**을 고른다(문자열 순이 아니라 숫자 순)"
# ⚠️ glob 확장은 문자열 순이라 그냥 첫 값을 쓰면 최신을 안 고른다 — 룬드 실측(2026-07-28):
#    `v18.19.0 · v20.11.0 · v8.17.0` 이 있으면 **v18 을 고른다**. `v8` 이 문자열 순으로 맨
#    뒤라 최악(가장 낮은 버전)은 피했지만, 고른 값이 `nvm use` 로 정한 것과 다를 수 있다.
#    ⇒ 픽스처에 `v8` 을 넣는 게 중요하다. 없으면 문자열 순과 숫자 순이 **같은 답**을 내서
#      갈래가 안 갈린다(오늘 ⑫에서 밟은 그 자리).
for v in v18.19.0 v20.11.0 v8.17.0; do
  mkdir -p "$ROOT/nvmhome/.nvm/versions/node/$v/bin"
  printf '#!/bin/sh\necho %s\n' "$v" > "$ROOT/nvmhome/.nvm/versions/node/$v/bin/multinode"
  chmod +x "$ROOT/nvmhome/.nvm/versions/node/$v/bin/multinode"
done
got="$(PATH=/usr/bin:/bin HOME="$ROOT/nvmhome" bash -c '. "$1"; n="$(resolve_bin multinode)" && "$n"' _ "$LIB" 2>&1)"
[ "$got" = "v20.11.0" ] && ok "v18·v20·v8 중 v20 을 고른다" \
  || bad "버전 정렬" "v20.11.0" "$got"

echo "③-c 🔑 **마이너 자리**가 진짜 시험이다 — 그리고 고르는 짝이 중요하다"
# 룬드가 짚었다: `v8` 은 문자열 순으로 맨 뒤라 *최악을 피하는* 자리인데, 마이너는 `9 > 11` 로
# 정면으로 뒤집힌다. 맞는 말인데 — **재보니 `20.9 vs 20.11` 로는 변이가 안 잡힌다.**
#
# 🔴 실측(2026-07-28): 정렬 키를 `-k1,1nr` (메이저만) 로 깎아도
#      v20.9.0 vs v20.11.0   → v20.11.0  (정답! 안 갈린다)
#      v20.2.0 vs v20.10.0   → v20.10.0  (정답! 안 갈린다)
#      v20.1.0 vs v20.9.0    → v20.1.0   🔴 **여기서만 갈린다**
#    이유: `sort` 는 지정한 키가 동률이면 **줄 전체를 최후수단으로** 비교한다. 그 비교는
#    문자열 오름차순이라 `20.11.0` < `20.9.0` 이 되어 head -1 이 **우연히 정답을 집는다.**
#    ⇒ 뒤집힌 자리를 골라도, 최후수단이 반대 방향으로 뒤집어 **두 번 뒤집혀 맞는다.**
#
# 🔑 그래서 픽스처는 *직관적으로 세 보이는 값*이 아니라 **변이를 실제로 죽이는 값**이어야 한다.
#    "이 값이면 갈리겠지" 는 짐작이고, 갈리는지는 **변이를 태워봐야** 안다(오늘 세 번째다).
for v in v20.1.0 v20.9.0; do
  mkdir -p "$ROOT/minorhome/.nvm/versions/node/$v/bin"
  printf '#!/bin/sh\necho %s\n' "$v" > "$ROOT/minorhome/.nvm/versions/node/$v/bin/minornode"
  chmod +x "$ROOT/minorhome/.nvm/versions/node/$v/bin/minornode"
done
got="$(PATH=/usr/bin:/bin HOME="$ROOT/minorhome" bash -c '. "$1"; n="$(resolve_bin minornode)" && "$n"' _ "$LIB" 2>&1)"
[ "$got" = "v20.9.0" ] && ok "v20.1.0 vs v20.9.0 → v20.9.0 (마이너를 숫자로 본다)" \
  || bad "마이너 자리 정렬" "v20.9.0" "$got"

echo "④ 못 찾으면 **rc=1 이고 아무것도 안 낸다**(빈 문자열을 돌려주지 않는다)"
out="$(PATH=/usr/bin:/bin HOME="$ROOT/home" bash -c '. "$1"; resolve_bin no-such-tool-xyz' _ "$LIB")"; rc=$?
[ "$rc" -ne 0 ] && ok "rc≠0" || bad "부재 종료코드" "1" "$rc"
[ -z "$out" ] && ok "  → 출력이 비어 있다(호출부가 \"\" 를 실행할 일이 없다)" \
  || bad "부재인데 값을 냈다" "(빈 출력)" "$out"

echo "⑤ 명시적으로 준 경로가 이긴다 — 시험이 실패 경로를 태울 수 있어야 한다"
# ⚠️ 이 갈래가 없으면 "도구가 없을 때" 를 재는 시험을 **쓸 수가 없다**.
#    검증 가능성은 설계 속성이다(룬드 assistant#20).
out="$(resolve_bin sh "$ROOT/home/.local/bin/faketool")"; rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "$ROOT/home/.local/bin/faketool" ] \
  && ok "주어진 경로가 PATH 를 이긴다" || bad "명시 경로" "faketool" "$out (rc=$rc)"

echo "⑥ 준 경로가 틀리면 **조용히 PATH 로 새지 않는다**"
# 🔑 여기서 폴백하면 "내가 준 것을 쓴다" 는 계약이 깨지고, 시험은 엉뚱한 바이너리를 잰다.
out="$(resolve_bin sh /definitely/not/here/sh)"; rc=$?
[ "$rc" -ne 0 ] && ok "rc≠0 (폴백하지 않는다)" || bad "틀린 명시 경로" "rc≠0" "$out (rc=$rc)"

echo "⑦ 이름을 안 주면 rc≠0 — 무엇을 찾는지 모른 채 답하지 않는다"
out="$(resolve_bin)"; rc=$?
[ "$rc" -ne 0 ] && ok "rc≠0" || bad "이름 없음" "rc≠0" "rc=$rc"

echo "⑧ bash 3.2 에서도 돈다(macOS 기본 셸) — 4 전용 빌트인 없이"
cat > "$ROOT/no-bash4" <<'NB4'
enable -n mapfile 2>/dev/null
enable -n readarray 2>/dev/null
NB4
out="$(BASH_ENV="$ROOT/no-bash4" PATH=/usr/bin:/bin HOME="$ROOT/home" \
       bash -c '. "$1"; resolve_bin faketool' _ "$LIB")"; rc=$?
[ "$rc" -eq 0 ] && ok "bash 4 빌트인 없이도 같은 답" || bad "bash 3.2 갈래" "경로 (rc=0)" "$out (rc=$rc)"

echo ""
echo "  통과 $pass · 실패 $fail"
[ "$fail" -eq 0 ] || exit 1
