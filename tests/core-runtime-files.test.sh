#!/usr/bin/env bash
# core-runtime-files.sh 계약 테스트 — **런타임 파일 분류는 제외 목록이다**
#
# 왜 이 시험이 생겼나 (라이브에서 거짓 초록이 났다, 2026-07-31 00:3x):
#   check-core-drift.sh:93 이 손으로 적은 **포함 목록**이었다.
#     RUNTIME=$(git diff --name-only HEAD..@{u} | grep -cE '^(relay|discord-send)/')
#   코어가 `tmux-send.sh`(레포 루트)를 바꾼 뒤처짐에서 **"런타임 파일 변경: 0건"** 이 나왔다.
#   하필 셸 스크립트라 재시작 없이 pull 즉시 동작이 바뀌는 파일인데 "런타임이 아니다"로 분류됐다.
#
# 🔴 그리고 두 번째 결함이 같이 있었다 — `^discord-send/` 는 **아무것도 안 잡는다.**
#    `discord-send` 는 코어 레포 **루트의 파일**이지 디렉터리가 아니다(실측: `git ls-files
#    | grep -c '^discord-send/'` = 0). 목록에 이름이 적혀 있어서 덮인 줄 알았는데, 전송 도구가
#    바뀌어도 이 카운터는 태어나서 한 번도 1을 낸 적이 없다.
#    ⇒ **손목록은 낡기만 하는 게 아니라 처음부터 틀려 있어도 조용하다.**
#
# 🔑 그래서 포함이 아니라 **제외**로 뒤집는다. 실패 방향이 반대가 된다:
#     포함 목록  새 파일 → 0건(조용히 과소보고)  ← 못 본다
#     제외 목록  새 파일 → 1건(시끄럽게 과대보고) ← 보인다. 숨기려면 명시해야 한다
#   감지되는 단점을 감지되지 않는 단점보다 택한다.
#
# ⚠️ 제외 목록도 손으로 적은 목록이다 — 이 시험은 *목록이 낡지 않음*을 증명하지 못한다.
#    증명하는 것은 **낡았을 때 어느 쪽으로 틀리는가** 뿐이다.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB="$BOT/scripts/lib/core-runtime-files.sh"

pass=0; fail=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; fail=$((fail + 1)); [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/     /'; }

[ -f "$LIB" ] || { echo "❌ 없음: $LIB"; exit 1; }
# shellcheck source=/dev/null
. "$LIB"

echo "① 런타임으로 세야 하는 것 — **레포 루트의 실행 파일이 핵심**"
# 실제 코어 레포의 파일들이다(git ls-files 로 확인한 것만 쓴다 — 가상의 경로로 시험하면
# 목록이 실물과 어긋나도 초록이 된다)
for p in tmux-send.sh discord-send bootstrap.sh package.json bun.lock \
         relay/index.js relay/tmux-bridge.js scripts/label-verdict.sh \
         adapters/discord.js addons/presence.js config/bots.json; do
    if core_is_runtime_path "$p"; then
        ok "$p"
    else
        bad "$p 가 런타임이 아닌 것으로 분류됐다 — 바뀌면 동작이 바뀌는 파일이다"
    fi
done

echo "② 제외해야 하는 것 — 받아도 동작이 안 바뀐다"
for p in docs/relay.md tests/tmux-send.test.sh .github/workflows/ci.yml \
         CLAUDE.md .gitignore .env.example eslint.config.js; do
    if core_is_runtime_path "$p"; then
        bad "$p 가 런타임으로 분류됐다 — 과대보고"
    else
        ok "$p"
    fi
done

echo "③ 🔑 **모르는 경로는 런타임으로 센다** — 제외로 뒤집은 이유가 여기다"
# 이 시험이 이 PR 의 본체다. 옛 포함 목록에선 전부 0건이었다.
for p in newdir/thing.js brand-new-root-file.sh memory-schema/schema.json db/init.sql; do
    if core_is_runtime_path "$p"; then
        ok "$p → 런타임(기본값)"
    else
        bad "$p 가 조용히 빠졌다 — 새 항목이 투명해지는 형태" \
            "제외 목록에 명시적으로 없는데 제외됐다면 패턴이 너무 넓다"
    fi
done

echo "④ 세는 쪽 — stdin 의 목록에서 런타임 건수만 낸다"
got="$(printf '%s\n' docs/a.md tests/b.test.sh tmux-send.sh discord-send | count_runtime_paths)"
[ "$got" = "2" ] && ok "4줄 중 런타임 2건" || bad "런타임 건수가 $got — 2여야 한다"

got0="$(printf '%s\n' docs/a.md CLAUDE.md | count_runtime_paths)"
[ "$got0" = "0" ] && ok "문서만이면 0건" || bad "문서만인데 $got0 건"

# 🔴 빈 입력에서 0 이 나와야 한다 — `grep -c` 는 매치가 없으면 rc=1 이라 `set -e` 아래서
#    스크립트를 죽인다. 호출부가 `$(...)` 안이라 지금은 안 죽지만, 값 자체는 0 이어야 한다.
gote="$(printf '' | count_runtime_paths)"
[ "$gote" = "0" ] && ok "빈 입력 → 0" || bad "빈 입력에서 '$gote' — 0이어야 한다"

echo "⑤ 음성 검사 — 이 시험이 옛 동작을 실제로 문다"
# 옛 포함 목록을 흉내 낸 함수로 갈아끼우고 ①③ 이 실패하는지 본다.
# 이걸 안 하면 *"통과했다"* 가 *"어떤 변이도 안 잡는다"* 와 구별되지 않는다.
core_is_runtime_path_OLD() { case "$1" in relay/*|discord-send/*) return 0 ;; *) return 1 ;; esac; }
caught=0
for p in tmux-send.sh discord-send newdir/thing.js; do
    core_is_runtime_path_OLD "$p" || caught=$((caught + 1))
done
[ "$caught" -eq 3 ] && ok "옛 목록은 세 파일 모두 놓친다 — 시험이 문다(3/3)" \
    || bad "옛 목록 변이를 $caught/3 만 잡는다 — 시험이 헐겁다"

echo
echo "  통과 $pass · 실패 $fail"
[ "$fail" -eq 0 ]
