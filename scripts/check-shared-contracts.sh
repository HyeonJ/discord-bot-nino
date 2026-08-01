#!/bin/bash
# check-shared-contracts.sh — 🤝 공유 계약 조항이 «대조 없이» 늘거나 줄었는지 잡는다
#
# 🔴 왜 (2026-08-02 실사고 · inbox #110·#115·#116):
#   양봇 🤝 계약의 한 조항(「git log 는 복원용 최후 안전망」)이 07-22 에 입주했다가
#   08-02 재편에서 사라졌다. **아무도 몰랐다.** 그 조항이 없어진 뒤로는
#   「git 이 모든 하중을 받는다」가 그냥 정상으로 보였다.
#   내 쪽엔 애초에 안 옮겨진 조항도 있었다(12:38 합의 → 14:13 파일화 사이 탈락).
#
# 🔑 축: 검사 대상은 「새 조항」이 아니라 **「조항 «수»의 변화」**다.
#   추가 커밋은 «무엇이 늘었나»가 보여 리뷰가 붙는데, **재편 커밋은 «정리»로 읽혀 안 붙는다.**
#   조항이 사라지는 건 정확히 거기다 ⇒ **늘든 줄든** 같은 무게로 소리낸다.
#
# ⚠️ 이 검사는 «내용이 같은가»를 판정하지 않는다 — 그건 사람·봇이 읽어야 한다.
#   판정하는 건 **「대조 없이 바뀌었나」** 하나이고, 기준선은 «대조를 마친 시점»의 스냅샷이다.
#   그래서 처방이 「기준선을 갱신하라」가 아니라 **「읽고 대조한 «뒤» 갱신하라」** 다.
#
# rc: 0=변화 없음 · 1=변화 있음(대조 필요) · 2=판정 불가
set -uo pipefail

SRC="${SHARED_CONTRACT_SRC:-}"
BASE="${SHARED_CONTRACT_BASELINE:-$HOME/discord-bot-nino/config/shared-contracts.baseline}"
WRITE=0
[ "${1:-}" = "--write-baseline" ] && WRITE=1

# 원본을 안 주면 상대 봇 파일을 받아온다. 받기 실패는 **판정 불가**지 이상 없음이 아니다.
if [ -z "$SRC" ]; then
    SRC="$(mktemp)"; trap 'rm -f "$SRC"' EXIT
    if ! gh api repos/dazebug/assistant/contents/memory/CLAUDE.md \
         --jq '.content' 2>/dev/null | base64 -d > "$SRC" || [ ! -s "$SRC" ]; then
        echo "🔴 판정 불가 — 상대 계약 파일을 받지 못했다 (gh 인증·네트워크 확인)" >&2
        exit 2
    fi
fi

[ -f "$SRC" ] || { echo "🔴 판정 불가 — 원본이 없다: $SRC" >&2; exit 2; }

COUNTS="$(python3 - "$SRC" <<'PY'
import re, sys
lines = open(sys.argv[1], encoding="utf-8", errors="replace").read().split("\n")
cur, n, out = None, 0, []
for L in lines:
    if L.startswith("## "):
        if cur is not None:
            out.append((cur, n))
        # 🤝 가 «제목 맨 앞»에 붙은 절만 센다. 본문에 🤝 를 인용한 절까지 세면
        # 분모가 넓어져 매번 시끄럽고, 시끄러운 가드는 꺼진다.
        cur = L[3:].strip() if L.startswith("## 🤝") else None
        n = 0
        continue
    if cur is not None and re.match(r"\s*[-*] ", L):
        n += 1
if cur is not None:
    out.append((cur, n))
for name, c in out:
    print(f"{name}\t{c}")
PY
)"
rc=$?
[ "$rc" -eq 0 ] || { echo "🔴 판정 불가 — 원본 파싱 실패: $SRC" >&2; exit 2; }

# 🔑 0개는 «다 사라졌다»가 아니라 **파일 형식이 바뀐 것**일 가능성이 크다.
#   0 을 변화로 읽으면 형식 변경 때마다 「전부 소실」이라 외치고, 이상 없음으로 읽으면
#   진짜 소실을 놓친다 ⇒ 어느 쪽도 아닌 **판정 불가**로 낸다.
if [ -z "$COUNTS" ]; then
    echo "🔴 판정 불가 — 🤝 절이 0개다 (마커·제목 형식이 바뀌었나): $SRC" >&2
    exit 2
fi

if [ "$WRITE" -eq 1 ]; then
    mkdir -p "$(dirname "$BASE")"
    printf '%s\n' "$COUNTS" > "$BASE"
    echo "✅ 기준선 기록: $BASE ($(printf '%s\n' "$COUNTS" | wc -l)개 절)"
    exit 0
fi

[ -f "$BASE" ] || {
    echo "🔴 판정 불가 — 기준선이 없다: $BASE" >&2
    echo "   내용을 읽고 대조한 뒤 만들 것: $0 --write-baseline" >&2
    exit 2
}

# ⚠️ 현재값을 **파일로** 넘긴다. `python3 - <<'PY'` 는 **스크립트를 stdin 으로 읽으므로**
#   앞에 파이프를 붙여도 그 값은 `sys.stdin` 에 안 남는다(실측: 전 절이 「사라졌다」로 나왔다 —
#   즉 «판별식이 죽은 채 시끄러운» 형태라 초록/무음 어느 쪽으로도 안 보였다).
NOWF="$(mktemp)"; printf '%s\n' "$COUNTS" > "$NOWF"
DIFF="$(python3 - "$BASE" "$NOWF" <<'PY'
import sys
def load(p):
    d = {}
    for L in open(p, encoding="utf-8", errors="replace"):
        if "\t" in L:
            k, v = L.rstrip("\n").rsplit("\t", 1)
            d[k] = v
    return d
base = load(sys.argv[1])
now = load(sys.argv[2])
for k in base:
    if k not in now:
        print(f"  🔴 절이 사라졌다: 「{k}」 (기준선 {base[k]}개)")
    elif now[k] != base[k]:
        arrow = "줄었다" if int(now[k]) < int(base[k]) else "늘었다"
        print(f"  🔴 조항 수가 {arrow}: 「{k}」  {base[k]} → {now[k]}")
for k in now:
    if k not in base:
        print(f"  🔴 절이 생겼다: 「{k}」 ({now[k]}개)")
PY
)"

[ -z "$DIFF" ] && exit 0

echo "🤝 공유 계약이 대조 없이 바뀌었다 — $SRC"
printf '%s\n' "$DIFF"
cat <<EOF

  🔑 «늘어도» 소리낸다 — 재편 커밋은 「정리」로 읽혀 리뷰가 안 붙고, 조항은 거기서 사라진다.
  ⇒ 할 일: 바뀐 절을 **읽고 내 착지 파일과 대조**한 뒤, 대조가 끝나면 기준선을 갱신한다:
       $0 --write-baseline
     (읽지 않고 갱신하면 이 검사는 «변화를 기록하는 도구»가 되고 아무것도 안 막는다)
EOF
exit 1
