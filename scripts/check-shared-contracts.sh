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
# 🔑 **계약의 단위 = 🤝 가 찍힌 «줄» 전부** (2026-08-02 룬드 확정 · Ⅲ 라 내가 못 정한다):
#     절 제목에 붙으면 → 그 절의 불릿들이 조항  (v1 부터의 형태)
#     본문·표 줄에 붙으면 → **그 줄 하나가 조항**
#     파일은 «루트 CLAUDE.md + memory/CLAUDE.md» 둘 다 본다
#   🔴 왜 줄 단위인가 — 실측: 절 단위(v1)로 두니 **하루 만에 세 번 밖으로 샜다.**
#     ⓐ 룬드가 「origin 조회까지가 완료형」을 **루트 CLAUDE.md 표 한 칸**에 세웠다
#     ⓑ 나는 같은 조항을 내 CLAUDE.md **하위 불릿**에 세웠다
#     ⓒ 그리고 **🤝 단위를 정의한 그 문장 자체**가 룬드 파일의 절 밖 blockquote 에 있다
#     ⇒ 합의가 사는 자리(실행 자리)와 계약 표시가 갈리면 **표시 쪽이 진다.**
#   ⚠️ 오탐(설명·인용 줄의 🤝 도 세어진다)은 **수용**이 합의다 — 인용 오탐은 시끄럽고 싸고
#     (대조 1회로 닫는다) 계약 소실 미탐은 조용하고 비싸다. 기본 엄격 쪽.
#
# 🔴 **이 도구가 못 잡는 자리** (적어두지 않으면 「검사했다」로 읽힌다):
#   ① **절 rename 은 「소실 + 신설」 두 줄로 나온다.** 조항 수가 같이 찍혀 유추는 되지만,
#      «진짜 소실 + 우연한 신설»과 모양이 같다. 두 줄이 붙어 나오면 rename 을 먼저 의심할 것.
#   ② 🔴 **절 안에서의 수 보존 교체는 무음이다** — 절의 조항 A 를 지우고 B 를 넣으면 수가
#      그대로라 안 울린다. 이건 ⚠️(내용 동일성은 안 본다)와 **다른 층**이다. 저건 «변화를 본 뒤
#      판정을 미루는 것»이고 이건 **변화 자체를 놓치는 것**이다.
#      🔸 **줄 조항엔 이 구멍이 없다** — 내용 해시로 세므로 교체가 곧 「소실+신설」이다.
#        절 조항에도 정규화 텍스트 해시를 병기하면 닫힌다(후속).
#   ③ 🔴 **줄 조항은 「고쳤다」와 「지우고 새로 썼다」를 구별 못 한다** — 둘 다 해시가 바뀌어
#      「소실+신설」로 보인다. 자리 이동은 조용하지만(해시가 같으면 파일이 달라도 같은 조항),
#      **한 글자만 고쳐도 새 조항으로 보인다.** 오탐 수용의 대가이고, 대조 1회로 닫는다.
#   ④ 🔴 **래핑된 논리 조항은 앞부분만 계약이 된다** — 뒷줄에 🤝 가 없으면 계약 밖이다.
#      08-02 실측 두 건(룬드 정의 문단의 「단위」 뒷부분 · 「파일 범위」 줄) — **내가 대조하고
#      등재한 조항이 이미 반쪽이었다.** 규약(「한 논리 조항 = 🤝 포함 한 물리 줄」)이 그의 파일에
#      🤝 조항으로 박혔고, 이쪽은 **`➖` 경고**로 보이게 한다(소리내진 않는다 — rc 불변).
#      ⚠️ 경고는 휴리스틱이라 완전하지 않다. 규약이 1차 방어고 경고는 2차다.
#
# rc: 0=변화 없음 · 1=변화 있음(대조 필요) · 2=판정 불가
set -uo pipefail

SRC="${SHARED_CONTRACT_SRC:-}"
BASE="${SHARED_CONTRACT_BASELINE:-$HOME/discord-bot-nino/config/shared-contracts.baseline}"
WRITE=0
[ "${1:-}" = "--write-baseline" ] && WRITE=1

# 🔑 임시파일은 **한 곳에서** 치운다 — 원래는 SRC 를 받아올 때만 trap 을 걸어서
#   ⓐ SRC 를 env 로 주면 trap 이 아예 없고 ⓑ 나중에 만드는 NOWF 는 어느 경로에서도 안 지워졌다
#   (룬드 실측: 실행 1회당 TMPDIR 에 tmp.* 1개 잔존). trap 은 처음에 한 번만 건다.
#   ⚠️ SRC 를 env 로 받은 경우는 **내 파일이 아니므로** 지우지 않는다 (그래서 변수를 따로 둔다).
#   ⚠️ 배열을 안 쓴다 — 룬드 맥(bash 3.2)은 `a+=()` 가 없고 빈 배열 확장이 `set -u` 에서 죽는다.
#   🔴 **`mktemp` 를 인자 없이 부르지 말 것.** BSD(맥) mktemp 는 **env `TMPDIR` 를 무시**하고
#      `/var/folders/…` 에 만든다(룬드 실측). 그러면 TMPDIR 를 갈라 쓰는 누수 시험이 맥에서
#      **분모 0** 이 되어 — 구판 checker 로 돌려도 초록이었다. 「작성자 기계에서만 참인 시험」이다.
#      ⇒ 템플릿형으로 경로를 **명시**한다. 이식성과 시험 가능성이 같이 닫힌다.
#   ⚠️ TMP_SRC 는 이제 **여러 경로**다(파일이 둘이라). 인용하면 한 이름으로 붙으므로 안 지운다 —
#     mktemp 경로엔 공백이 없으므로 비인용 확장이 맞다. `set -u` 때문에 빈 값 초기화는 필수.
TMP_SRC=""; TMP_NOW=""
# shellcheck disable=SC2086
trap 'rm -f $TMP_SRC "$TMP_NOW"' EXIT

# 🔑 **파일이 둘이다** (합의). 하나만 보면 다른 하나에 세운 조항이 통째로 분모 밖이 된다 —
#   실측: 룬드의 「origin 조회」 조항이 루트 CLAUDE.md 에 있어서 v1 이 못 봤다.
#   SHARED_CONTRACT_SRC 는 `:` 로 여러 경로를 받는다(PATH 형). 안 주면 상대 레포에서 받아온다.
CONTRACT_PATHS="${SHARED_CONTRACT_REMOTE_PATHS:-CLAUDE.md memory/CLAUDE.md}"
if [ -z "$SRC" ]; then
    SRC=""
    for p in $CONTRACT_PATHS; do
        f="$(mktemp "${TMPDIR:-/tmp}/csc-src.XXXXXX")"
        TMP_SRC="$TMP_SRC $f"
        if ! gh api "repos/dazebug/assistant/contents/$p" --jq '.content' 2>/dev/null \
             | base64 -d > "$f" || [ ! -s "$f" ]; then
            echo "🔴 판정 불가 — 상대 계약 파일을 받지 못했다: $p (gh 인증·네트워크 확인)" >&2
            exit 2
        fi
        # 🔎 원본의 «이름»을 같이 넘긴다 — 표시용. 조항의 «신원»은 파일이 아니라 내용이다
        #   (그래야 조항이 파일 사이를 옮겨도 조용하다).
        SRC="${SRC:+$SRC:}$p=$f"
    done
fi

for spec in $(printf '%s' "$SRC" | tr ':' ' '); do
    f="${spec#*=}"
    [ -f "$f" ] || { echo "🔴 판정 불가 — 원본이 없다: $f" >&2; exit 2; }
done

# 🔴 **또 밟았다 — 세 번째다.** 목록을 파이프로 주면 `python3 - <<'PY'` 가 **스크립트를 stdin 으로
#   읽으므로** 그 값이 sys.stdin 에 안 남는다. 이 함정은 **이 파일 163행 주석에 내가 직접 적어뒀고**
#   #120 에서 한 번 밟았는데, 새 코드를 쓰면서 또 파이프로 줬다.
#   🔑 **적어둔 것이 다음 번을 막지 못한다** — 주석은 «읽을 때» 발동하고 실수는 «쓸 때» 난다.
#   ⇒ 값은 항상 argv 나 파일로. (도구로 박는 축 = 대전제 Ⅳ)
COUNTS="$(python3 - "$SRC" <<'PY'
import hashlib, re, sys

# 🔑 조항의 «신원» — 절은 제목, 줄은 **정규화 내용의 해시**다.
#   해시로 두면 조항이 자리를 옮기거나 파일을 바꿔도 조용하다(그게 흔한 일이라서).
#   ⚠️ 대가: 한 글자만 고쳐도 「소실+신설」이다. 헤더 ③에 적었다.
def norm(s):
    s = re.sub(r"^[\s>]*", "", s)              # 인용부호·들여쓰기
    s = re.sub(r"^([-*+]|\d+\.)\s+", "", s)    # 리스트 마커
    s = s.strip().strip("|").strip()           # 표 줄의 바깥 파이프
    return re.sub(r"\s+", " ", s)

out = []
for spec in sys.argv[1].split(":"):
    spec = spec.strip()
    if not spec:
        continue
    name, _, path = spec.partition("=")
    if not path:
        name, path = path or name, name
    lines = open(path, encoding="utf-8", errors="replace").read().split("\n")
    cur, n, fence = None, 0, False
    for i, L in enumerate(lines):
        # 🔴 **코드펜스 안은 «글자»지 문서 구조가 아니다** (룬드 리뷰 실측 · request-changes).
        #   펜스를 모르면 블록 안의 `# 주석` 이 heading 으로 읽혀 **절이 거기서 끊긴다** —
        #   뒤따르는 조항이 통째로 소실되고 **조용하다**(미탐 방향).
        #   예시 블록에 🤝 를 쓰는 것도 «설명»이지 계약이 아니다 ⇒ 블록 전체를 건너뛴다.
        if re.match(r"^\s*(```|~~~)", L):
            fence = not fence
            continue
        if fence:
            continue
        if L.startswith("#"):
            if cur is not None:
                out.append(("S", cur, str(n)))
            # 🤝 가 «제목 맨 앞»에 붙은 절: 그 절의 불릿들이 조항이다
            m = re.match(r"^#+\s+🤝\s*(.*)$", L)
            cur, n = (m.group(1).strip() if m else None), 0
            continue
        if cur is not None and re.match(r"\s*[-*] ", L):
            n += 1
            continue                            # 절이 이미 세므로 줄로 또 세지 않는다
        # 절 밖(또는 절 안의 비불릿)에서 🤝 가 찍힌 줄 = 그 줄 하나가 조항
        if "🤝" in L:
            t = norm(L)
            if t:
                out.append(("L", hashlib.sha1(t.encode()).hexdigest()[:10],
                            f"{name}: {t[:70]}"))
                # 🔴 **래핑된 논리 조항은 앞부분만 계약이 된다 — 조용히 잘린다.**
                #   08-02 실측 두 건: 🤝 «단위» 조항의 뒷부분("본문·표 줄이면…")과
                #   «파일 범위» 줄이 둘 다 🤝 없는 다음 줄이라 **계약 밖**이었다.
                #   내가 어제 «대조하고 등재한» 조항이 이미 반쪽이었다는 뜻이다.
                #   ⇒ 규약(「한 논리 조항 = 🤝 포함 한 물리 줄」)은 룬드 파일에 박혔지만,
                #     규약만 두면 「사람이 기억한다」에 기댄다 ⇒ **보이게** 한다(소리내진 않는다).
                nxt = lines[i + 1] if i + 1 < len(lines) else ""
                if (nxt.strip() and "🤝" not in nxt
                        and not re.match(r"^\s*(#|```|~~~|[-*+]\s|\d+\.\s|\|)", nxt)
                        and nxt.lstrip().startswith(">") == L.lstrip().startswith(">")):
                    out.append(("W", "wrap", f"{name}: 🤝 줄 다음이 «이어지는 줄»로 보인다 — "
                                             f"래핑이면 뒷부분이 계약 밖이다 → 「{nxt.strip()[:50]}」"))
    if cur is not None:
        out.append(("S", cur, str(n)))

for kind, key, val in out:
    print(f"{kind}\t{key}\t{val}")
PY
)"
rc=$?
[ "$rc" -eq 0 ] || { echo "🔴 판정 불가 — 원본 파싱 실패: $SRC" >&2; exit 2; }

# 🔑 경고(W)는 **조항이 아니다** — 기준선에도 안 들어가고 rc 도 안 바꾼다.
#   「보이게 하되 소리내지 않는다」 — 분모 0 을 위반으로 안 만든 것과 같은 축이다.
#   매번 시끄러우면 사람은 파일이 아니라 검사를 끈다.
NOTICE="$(printf '%s\n' "$COUNTS" | LC_ALL=C grep '^W	' | cut -f3-)"
COUNTS="$(printf '%s\n' "$COUNTS" | LC_ALL=C grep -v '^W	')"
[ -n "$NOTICE" ] && printf '%s\n' "$NOTICE" | sed 's/^/  ➖ /'

# 🔑 0개는 «다 사라졌다»가 아니라 **파일 형식이 바뀐 것**일 가능성이 크다.
#   0 을 변화로 읽으면 형식 변경 때마다 「전부 소실」이라 외치고, 이상 없음으로 읽으면
#   진짜 소실을 놓친다 ⇒ 어느 쪽도 아닌 **판정 불가**로 낸다.
if [ -z "$COUNTS" ]; then
    echo "🔴 판정 불가 — 🤝 조항이 0개다 (마커 형식이 바뀌었나): $SRC" >&2
    exit 2
fi

if [ "$WRITE" -eq 1 ]; then
    mkdir -p "$(dirname "$BASE")"
    printf '%s\n' "$COUNTS" > "$BASE"
    _ns=$(printf '%s\n' "$COUNTS" | grep -c '^S	')
    _nl=$(printf '%s\n' "$COUNTS" | grep -c '^L	')
    echo "✅ 기준선 기록: $BASE (절 ${_ns}개 · 줄 조항 ${_nl}개)"
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
NOWF="$(mktemp "${TMPDIR:-/tmp}/csc-now.XXXXXX")"; TMP_NOW="$NOWF"; printf '%s\n' "$COUNTS" > "$NOWF"
DIFF="$(python3 - "$BASE" "$NOWF" <<'PY'
import sys

# 🔴 형식이 v1(2열: 제목\t수)이면 **판정 불가**다. v2 는 3열(종류\t키\t값).
#   v1 기준선을 v2 로 읽으면 모든 절이 「사라졌다+생겼다」로 나와 **시끄럽게 거짓**이 된다 —
#   그건 「변화 있음」이 아니라 「비교 자체가 성립 안 함」이라 rc 를 갈라야 한다.
def load(p):
    d, bad = {}, 0
    for L in open(p, encoding="utf-8", errors="replace"):
        L = L.rstrip("\n")
        if not L.strip():
            continue
        parts = L.split("\t")
        if len(parts) < 3:
            bad += 1
            continue
        d[(parts[0], parts[1])] = "\t".join(parts[2:])
    return d, bad

base, bad = load(sys.argv[1])
if bad or not base:
    sys.exit(3)                       # v1 기준선 · 빈 기준선 → 판정 불가
now, _ = load(sys.argv[2])

def label(kind, key, val):
    return f"절 「{key}」" if kind == "S" else f"줄 「{val}」"

for (kind, key), val in base.items():
    if (kind, key) not in now:
        if kind == "S":
            print(f"  🔴 절이 사라졌다: 「{key}」 (기준선 {val}개)")
        else:
            print(f"  🔴 줄 조항이 사라졌다: 「{val}」")
    elif kind == "S" and now[(kind, key)] != val:
        new = now[(kind, key)]
        arrow = "줄었다" if int(new) < int(val) else "늘었다"
        print(f"  🔴 조항 수가 {arrow}: 「{key}」  {val} → {new}")
for (kind, key), val in now.items():
    if (kind, key) not in base:
        if kind == "S":
            print(f"  🔴 절이 생겼다: 「{key}」 ({val}개)")
        else:
            print(f"  🔴 줄 조항이 생겼다: 「{val}」")
PY
)"
drc=$?
if [ "$drc" -eq 3 ]; then
    echo "🔴 판정 불가 — 기준선이 옛 형식(v1: 제목+수)이다: $BASE" >&2
    echo "   v2 는 «종류\t키\t값» 3열이다. 내용을 읽고 대조한 뒤 다시 만들 것:" >&2
    echo "     $0 --write-baseline" >&2
    exit 2
fi

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
