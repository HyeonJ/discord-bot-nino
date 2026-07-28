#!/usr/bin/env bash
# 레포 위생 계약 — **커밋된 심볼릭 링크가 레포를 망가뜨리지 않는다**
#
# 왜 생겼나 (2026-07-28, 조용히 몇 달):
#   `node_modules` 가 **자기 자신을 가리키는 심링크인 채로** 커밋돼 있었다(mode 120000,
#   내용 `/home/bpx27/discord-bot-nino/node_modules`). 결과:
#     · `.gitignore` 는 **이미 추적 중인 파일에는 안 먹는다** → 무시되지 않는다
#     · `git checkout` 할 때마다 되살아나 **진짜 설치본을 덮는다**
#     · 그래서 `npx jest` 가 "Too many levels of symbolic links" 로 죽는데,
#       종료코드를 `| tail` 뒤에서 읽으면 **0 으로 보인다** → JS 시험이 몇 달간 안 돌았다
#
#   🔑 이 병의 지독한 점: 증상이 "테스트가 실패한다"가 아니라 **"테스트가 없어진다"** 였다.
#      실패는 시끄럽지만 부재는 조용하다. 오늘 addon 시험을 살리려다 우연히 걸렸다.
#
# 계약은 node_modules 하나가 아니라 **일반형**으로 잡는다 — 같은 사고를 다른 이름으로
# 다시 내지 않게. 커밋된 심링크는 (1) 자기 자신을 가리키면 안 되고 (2) 절대경로면 안 된다
# (다른 기계·다른 워크트리에서 의미가 달라지거나 깨진다).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$BOT" || exit 1

pass=0; fail=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; fail=$((fail + 1)); [[ -n "${2:-}" ]] && printf '%s\n' "$2" | sed 's/^/     /'; }

echo "① 의존성 디렉터리는 git 이 추적하지 않는다"
tracked_dep="$(git ls-files | grep -xE 'node_modules|node_modules/.*|\.venv|\.venv/.*' || true)"
[[ -z "$tracked_dep" ]] && ok "node_modules · .venv 추적 0건" \
  || bad "추적되고 있다 — .gitignore 는 이미 추적 중인 파일엔 안 먹는다" "$tracked_dep"

echo "② .gitignore 가 그것들을 덮는다"
grep -qE '^node_modules/?$' .gitignore && ok ".gitignore 에 node_modules" || bad ".gitignore 미포함"

echo "③ 🔑 커밋된 심볼릭 링크는 자기 자신을 가리키지 않는다"
# git ls-files -s 의 mode 120000 = 심링크. blob 내용이 링크 대상 경로다.
selfref=""; abspath=""
while read -r mode _ _ path; do
  [[ "$mode" == "120000" ]] || continue
  target="$(git cat-file -p ":$path" 2>/dev/null)"
  [[ "$target" == "$BOT/$path" || "$target" == "$path" ]] && selfref+="$path -> $target"$'\n'
  [[ "$target" == /* ]] && abspath+="$path -> $target"$'\n'
done < <(git ls-files -s)
[[ -z "$selfref" ]] && ok "자기참조 심링크 0건" \
  || bad "자기참조 심링크 — checkout 마다 되살아나 실체를 덮는다" "$selfref"

echo "④ 커밋된 심볼릭 링크는 절대경로를 가리키지 않는다 (기계마다 뜻이 달라진다)"
[[ -z "$abspath" ]] && ok "절대경로 심링크 0건" || bad "절대경로 심링크" "$abspath"

echo "⑤ 작업트리의 node_modules 가 실제로 쓸 수 있는 상태다"
# ①~④ 를 통과해도 **지금 이 기계에서 도는가**는 다른 질문이다(계약 vs 상태).
# ⚠️ `-e` 는 링크를 **따라간다** — 루프면 ELOOP 라 `! -e` 가 참이 되어 "아직 설치 안 함"으로
#    읽힌다. 정확히 이 사고를 못 잡는 폴백이다. **깨진 링크와 부재를 먼저 가른다.**
if [[ -L node_modules && ! -e node_modules ]]; then
  bad "node_modules 가 깨진 링크다 (루프이거나 대상 없음) — '미설치'가 아니라 **고장**이다" \
      "$(ls -ld node_modules 2>&1)"
elif [[ ! -e node_modules && ! -L node_modules ]]; then
  echo "  ⏭️  건너뜀 — node_modules 없음 (npm ci 필요). 계약 위반은 아니다"
elif [[ -x node_modules/.bin/jest ]]; then
  ok "jest 실행 파일이 살아 있다"
else
  bad "node_modules 는 있는데 jest 가 안 잡힌다 — 링크 루프이거나 설치 미완" \
      "$(ls -ld node_modules 2>&1)"
fi

echo
echo "  통과 $pass · 실패 $fail"
[[ "$fail" -eq 0 ]]
