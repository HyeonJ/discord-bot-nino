#!/usr/bin/env bash
# 의존성 선언 계약 — **require 하는 외부 모듈은 package.json 에 선언돼 있어야 한다**
#
# 왜 생겼나 (2026-07-28, 내가 직접 깼다):
#   `npm ci` 한 번에 TV 제어 6개 스크립트가 죽었다. `lgtv2` 를 쓰는데 `package.json` 에
#   **선언된 적이 없었다.** 예전에 누가 `npm i lgtv2` 를 `--save` 없이 돌린 게 node_modules
#   안에 남아 있어서 돌던 거고, `npm ci` 는 lockfile 기준으로 싹 지우고 다시 깐다.
#
#   ⚠️ 더 조용한 형태가 `ws` 였다 — 선언은 없는데 **discord.js 가 전이 의존성으로 끌고 와서**
#      우연히 돌고 있었다. 이건 초록불이 아니라 **남의 초록불**이다. discord.js 가 내부
#      구현을 바꾸면 아무 상관 없어 보이는 커밋에 TV 가 죽는다.
#
# 계약을 `lgtv2` 하나가 아니라 일반형으로 잡는 이유: 다음에 누가 `--save` 를 빼먹어도
# 그 자리에서 빨간불이 뜨게. 재발을 사람의 기억에 맡기지 않는다.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$BOT" || exit 1

pass=0; fail=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; fail=$((fail + 1)); [[ -n "${2:-}" ]] && printf '%s\n' "$2" | sed 's/^/     /'; }

# 검사 대상: **이 레포가 소유한 코드**만.
#   claude-config/skills/ 는 제외한다 — 스킬은 자기 실행 환경을 따로 들고 다니고(마켓에서
#   설치되는 사본), 그 의존성을 봇 레포의 package.json 이 떠안으면 소유가 어긋난다.
SCAN_DIRS=(src media relay-addons of scripts tools tests)

mods="$(
  for d in "${SCAN_DIRS[@]}"; do
    [[ -d "$d" ]] || continue
    grep -rhoE "require\('[^']+'\)" "$d" --include="*.js" 2>/dev/null
  done \
  | sed "s/require('//;s/')//" \
  | grep -vE '^[./]' \
  | sed -E 's|^(@[^/]+/[^/]+).*|\1|; s|^([^@/]+)/.*|\1|' \
  | sort -u
)"

# node 내장 모듈과 bun 내장(`bun:*`)은 선언 대상이 아니다
builtins="$(node -e 'console.log(require("module").builtinModules.join("\n"))' 2>/dev/null)"
declared="$(python3 -c "
import json
d = json.load(open('package.json'))
print('\n'.join(list(d.get('dependencies', {})) + list(d.get('devDependencies', {}))))
")"

undeclared=""; unresolvable=""
while read -r m; do
  [[ -z "$m" ]] && continue
  [[ "$m" == bun:* ]] && continue
  grep -qxF "$m" <<<"$builtins" && continue
  grep -qxF "$m" <<<"$declared" || undeclared+="  $m — $(grep -rl "require('$m')" "${SCAN_DIRS[@]}" --include='*.js' 2>/dev/null | head -2 | tr '\n' ' ')"$'\n'
  node -e "require.resolve('$m')" >/dev/null 2>&1 || unresolvable+="  $m"$'\n'
done <<<"$mods"

echo "① require 하는 외부 모듈이 전부 package.json 에 선언돼 있다"
[[ -z "$undeclared" ]] && ok "미선언 0건" \
  || bad "미선언 — npm ci 한 번이면 사라진다(전이 의존성으로 우연히 돌고 있을 수도)" "$undeclared"

echo "② 그 모듈들이 지금 실제로 resolve 된다"
# ①을 통과해도 **이 기계에 깔려 있는가**는 다른 질문이다(계약 vs 상태).
if [[ ! -d node_modules ]]; then
  echo "  ⏭️  건너뜀 — node_modules 없음 (npm ci 필요). 계약 위반은 아니다"
else
  [[ -z "$unresolvable" ]] && ok "전부 resolve 됨" || bad "선언은 됐는데 안 깔렸다 — npm ci 필요" "$unresolvable"
fi

echo "③ 🔑 선언서 자체가 git 에 추적된다 (추적 안 되면 위 계약이 clone 에서 무의미하다)"
# ①②를 아무리 잘 지켜도 package.json 이 레포에 없으면 **clone 한 사람에겐 아무것도 안 남는다.**
# 실제로 fb334ca 가 `package.json`·`package-lock.json` 을 .gitignore 에 넣어놨었다 —
# 커밋 제목("Add logs/, node_modules/")에 언급조차 없이. 그래서 lgtv2 처럼 선언 없이
# node_modules 에만 살아 있던 모듈을 **아무도 볼 수 없었다.**
untracked_manifest=""
for f in package.json package-lock.json; do
  git ls-files --error-unmatch -- "$f" >/dev/null 2>&1 || untracked_manifest+="  $f"$'\n'
done
[[ -z "$untracked_manifest" ]] && ok "package.json · package-lock.json 둘 다 추적됨" \
  || bad "선언서가 추적 밖 — clone 하면 빌드 불가, 위 ①② 도 검증 불가" "$untracked_manifest"

echo
echo "  통과 $pass · 실패 $fail"
[[ "$fail" -eq 0 ]]
