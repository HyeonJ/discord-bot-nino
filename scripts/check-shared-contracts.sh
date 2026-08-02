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
#   ② ~~절 안에서의 수 보존 교체는 무음이다~~ → **닫혔다 (08-02, 실물 미탐 1건 뒤)**.
#      룬드 `c5a97ff` 가 축약·이관 절의 두 불릿을 «다시 썼는데» 6→6 이라 **rc=0 으로 조용했다.**
#      계약 문구가 바뀐 걸 상대가 모르는 게 이 도구의 실패 ⇒ 절 안 불릿도 **행 해시**로 센다.
#      S 행(개수)은 남긴다 — 「절 자체가 사라졌다」는 다른 축이다.
#      🔑 판정 근거(룬드 08-02): **다듬을 때마다 울리는 건 소음이 아니라 «상대가 봐야 하는 사건»이다.**
#      ⚠️ 남는 대가: 절 안 조항도 이제 ③(고침 vs 지우고 새로 씀)과 **래핑 사각**(④)을 같이 진다.
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
# 🔴 기준선 경로는 **자기 위치**에서 유도한다 — `$HOME` 으로 잡으면 워크트리에서 돌릴 때
#   **main 트리의 기준선을 덮어쓴다**(2026-08-02 실측: 실제로 밟았다).
#   워크트리의 `git status` 는 그 파일을 안 보여주니 **그 트리만 보면 아무 일도 안 난 것처럼 보인다.**
#   그대로 main 에서 브랜치를 옮기면 기준선이 증발한다 — 같은 날 아침 이미 한 번 난 사고다.
#   🔑 「어디에 쓰는가」를 `$HOME` 으로 잡은 도구는 **사본이 여럿인 순간 남의 사본을 쓴다.**
#     우리는 「worktree 로 main 중단 없이 작업」을 규칙으로 쓰므로 상시 발동 조건이다.
#   ⚠️ `$0` 가 아니라 `${BASH_SOURCE[0]}` 다 — source 되어도 자기 파일을 가리킨다.
_CSC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_CSC_REPO="$(cd "$_CSC_DIR/.." && pwd)"
BASE="${SHARED_CONTRACT_BASELINE:-$_CSC_REPO/config/shared-contracts.baseline}"
WRITE=0
WRITE_TOKEN=""
[ "${1:-}" = "--write-baseline" ] && { WRITE=1; WRITE_TOKEN="${2:-}"; }

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
TMP_SRC=""; TMP_NOW=""; TMP_PY=""
# shellcheck disable=SC2086
# ⚠️ TMP_PY 도 «여러 경로»다(파서용·비교용 둘) — TMP_SRC 와 같은 이유로 **비인용** 확장이다.
#    인용하면 공백 포함 한 이름으로 붙어서 rm 이 조용히 실패한다(실측: 시험 ⑧이 4건 잔존으로 잡았다).
trap 'rm -f $TMP_SRC "$TMP_NOW" $TMP_PY' EXIT

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
# 🔴 **`$(...)` 안에 heredoc 을 두지 않는다 — 맥 bash 3.2 가 여기서 죽는다** (룬드 실측 08-02).
#   3.2 의 낡은 파서는 명령 치환 안의 heredoc **본문을 다시 토큰 스캔**해서, `<<'PY'` 로
#   인용했는데도 파이썬 정규식 안의 백틱 3개(``` 펜스 매칭)를 명령 치환 시작으로 읽고
#   `syntax error near unexpected token '('` 로 죽는다. 내 WSL(bash 5.2)은 재귀 파서라 **무증상**이라
#   여기까지의 모든 확인이 **WSL 축 하나**였다(맥 축 분모 0 — 63행에 내가 적어둔 «작성자 기계에서만
#   참인 시험»의 두 번째 발현이고, 이번엔 시험이 아니라 **도구 자체**가 안 돌았다).
#   ⇒ heredoc 을 치환 **밖**으로 빼서 파일로 쓰고, 실행만 치환 안에서 한다. 형태로 닫는다.
TMP_PY="$(mktemp "${TMPDIR:-/tmp}/csc-parse.XXXXXX")"
cat > "$TMP_PY" <<'PY'
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
            # 🔴 **개수만 세면 «수 보존 교체»가 조용하다** — 08-02 실물 미탐 1건(룬드 c5a97ff:
            #   축약·이관 절의 두 불릿을 다시 썼는데 6→6 이라 rc=0). 계약 문구가 바뀐 걸
            #   상대가 모르는 게 이 도구의 실패다. ⇒ 불릿도 **행 해시**로 센다(룬드 판정 08-02:
            #   «다듬을 때마다 울리는 건 소음이 아니라 상대가 봐야 하는 사건»).
            #   S 행(개수)은 남긴다 — 절 자체가 사라지는 것은 다른 축이다.
            n += 1
            t = norm(L)
            if t:
                out.append(("L", hashlib.sha1(t.encode()).hexdigest()[:10],
                            f"{name}/{cur}: {t[:70]}"))
            continue
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
COUNTS="$(python3 "$TMP_PY" "$SRC")"
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

# 🔑 지금 상태의 «지문». 대조한 내용과 «쓰는 내용»이 같은지 형태로 잠근다.
NOW_TOKEN="$(printf '%s\n' "$COUNTS" | LC_ALL=C shasum 2>/dev/null | cut -c1-12)"
[ -n "$NOW_TOKEN" ] || NOW_TOKEN="$(printf '%s\n' "$COUNTS" | LC_ALL=C sha1sum | cut -c1-12)"

# 🔴 **기준선이 tracked 인데 커밋 안 됐으면 브랜치 전환에 «대조 작업이 증발»한다** (08-02 자기 실측:
#   07:00 에 4행을 읽고 대조한 뒤 갱신했는데 커밋을 안 해서, `git checkout` 이 되돌렸고 23분 뒤
#   같은 4행이 또 울렸다). 도구는 초록/빨강만 말하지 «내 대조가 저장됐는지»는 말하지 않는다.
#   ⇒ 보이게 한다(소리내진 않는다 — rc 불변). 「했다 vs 닿았다」 사각의 로컬판.
warn_uncommitted() {
    git -C "$(dirname "$BASE")" rev-parse --git-dir >/dev/null 2>&1 || return 0
    git -C "$(dirname "$BASE")" ls-files --error-unmatch "$BASE" >/dev/null 2>&1 || return 0
    git -C "$(dirname "$BASE")" diff --quiet -- "$BASE" 2>/dev/null && return 0
    # ⚠️ `${BASE}` — 중괄호 필수. bash 3.2 는 `$BASE»` 에서 »(0xC2…)의 첫 바이트를 **식별자로 먹어**
    #   `BASE?: unbound variable` 로 죽는다(맥 실측 08-02). WSL/bash 5.x 는 무증상이라 여기서도 안 보인다.
    echo "  ➖ 기준선이 **커밋되지 않았다** — 브랜치를 옮기면 이 대조가 사라진다: git add/commit «${BASE}»"
}

if [ "$WRITE" -eq 1 ]; then
    # 🔴 **CAS** — 기준선이 이미 있으면 «내가 읽은 시점의 지문»을 요구한다.
    #   08-02 실측: 상대 push 22:00:12Z · 내 --write-baseline 22:00:33Z — **21초 차로 안 읽은 변경이
    #   기준선에 접혔다.** 「읽고 갱신하라」가 문안으로만 있고 형태가 없어서 그렇다(Ⅱ 자리).
    #   ⚠️ 최초 생성(기준선 부재)은 토큰 없이 통과한다 — 부트스트랩까지 막으면 도구를 못 쓴다.
    if [ -s "$BASE" ] && [ "$WRITE_TOKEN" != "$NOW_TOKEN" ]; then
        echo "🔴 갱신 거부 — 대조한 시점과 지금이 다를 수 있다." >&2
        if [ -z "$WRITE_TOKEN" ]; then
            echo "   기준선이 이미 있으면 «읽은 시점의 지문»이 필요하다." >&2
        else
            echo "   준 지문: $WRITE_TOKEN / 지금 지문: $NOW_TOKEN — 그 사이에 원본이 바뀌었다." >&2
        fi
        echo "   ⇒ 다시 대조하고: $0 --write-baseline $NOW_TOKEN" >&2
        exit 2
    fi
    mkdir -p "$(dirname "$BASE")"
    printf '%s\n' "$COUNTS" > "$BASE"
    _ns=$(printf '%s\n' "$COUNTS" | grep -c '^S	')
    _nl=$(printf '%s\n' "$COUNTS" | grep -c '^L	')
    echo "✅ 기준선 기록: $BASE (절 ${_ns}개 · 줄 조항 ${_nl}개)"
    warn_uncommitted
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
# 🔴 여기도 «치환 밖»으로 뺀다 — 지금 이 본문엔 백틱이 없어서 3.2 가 «우연히» 통과하지만,
#   다음에 주석 한 줄만 넣어도 죽는다. 우연히 도는 형태를 남기면 **다음 편집이 지뢰**다.
TMP_PY2="$(mktemp "${TMPDIR:-/tmp}/csc-diff.XXXXXX")"; TMP_PY="$TMP_PY $TMP_PY2"
cat > "$TMP_PY2" <<'PY'
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
DIFF="$(python3 "$TMP_PY2" "$BASE" "$NOWF")"
drc=$?
if [ "$drc" -eq 3 ]; then
    echo "🔴 판정 불가 — 기준선이 옛 형식(v1: 제목+수)이다: $BASE" >&2
    echo "   v2 는 «종류\t키\t값» 3열이다. 내용을 읽고 대조한 뒤 다시 만들 것:" >&2
    echo "     $0 --write-baseline $NOW_TOKEN" >&2
    exit 2
fi

[ -z "$DIFF" ] && exit 0

echo "🤝 공유 계약이 대조 없이 바뀌었다 — $SRC"
printf '%s\n' "$DIFF"
cat <<EOF

  🔑 «늘어도» 소리낸다 — 재편 커밋은 「정리」로 읽혀 리뷰가 안 붙고, 조항은 거기서 사라진다.
  ⇒ 할 일: 바뀐 절을 **읽고 내 착지 파일과 대조**한 뒤, 대조가 끝나면 기준선을 갱신한다:
       $0 --write-baseline $NOW_TOKEN
     (읽지 않고 갱신하면 이 검사는 «변화를 기록하는 도구»가 되고 아무것도 안 막는다)
EOF
exit 1
