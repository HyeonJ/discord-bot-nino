#!/usr/bin/env bash
# shared-contract-drift.test.sh — 🤝 공유 계약 조항이 «말없이» 늘거나 줄었는지 잡는 검사
#
# 🔴 왜 (2026-08-02 실사고, inbox #110·#115·#116):
#   양봇 🤝 계약의 한 조항이 07-22 에 입주했다가 08-02 재편에서 사라졌다. 아무도 몰랐다.
#   내 쪽엔 애초에 안 옮겨진 조항도 있었다(12:38 합의 → 14:13 파일화 사이에 탈락).
#   ⇒ 두 층이 있다: ⓐ **미이관**(합의가 파일에 안 닿음) ⓑ **소실**(재편이 뺌).
#
# 🔑 축: 검사 대상은 「새 조항」이 아니라 **「조항 «수»의 변화」**다.
#   추가 커밋은 «무엇이 늘었나»가 보여 리뷰가 붙는데, **재편 커밋은 «정리»로 읽혀 안 붙는다.**
#   조항이 사라지는 건 정확히 거기다 ⇒ **늘든 줄든** 같은 무게로 소리내야 한다.
#
# ⚠️ 이 검사는 «내용이 같은가»를 판정하지 않는다(그건 사람·봇이 읽어야 한다).
#   판정하는 건 **「대조 없이 바뀌었나」** 하나다. 기준선은 대조를 마친 시점의 스냅샷이다.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECK="${SHARED_CONTRACT_CHECK:-$REPO/scripts/check-shared-contracts.sh}"

pass=0; fail=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; [ -n "${2:-}" ] && echo "     want: $2"; [ -n "${3:-}" ] && echo "     got:  $3"; fail=$((fail + 1)); }

[ -f "$CHECK" ] || { echo "❌ 없음: $CHECK"; exit 1; }

W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT

mk_src() {   # $1=파일 · 나머지=각 절의 조항 수
    local f="$1"; shift
    local i=0
    : > "$f"
    for n in "$@"; do
        i=$((i + 1))
        printf '## 🤝 절%s — 공유 계약\n\n' "$i" >> "$f"
        for ((j = 0; j < n; j++)); do printf -- '- 조항 %s-%s\n' "$i" "$j" >> "$f"; done
        printf '\n## 안 붙은 절 %s (🤝 없음 — 세면 안 된다)\n\n- 잡음\n\n' "$i" >> "$f"
    done
}

run() {  # $1=원본 $2=기준선 → rc, 출력은 stdout
    SHARED_CONTRACT_SRC="$1" SHARED_CONTRACT_BASELINE="$2" bash "$CHECK" 2>&1
}

echo "① 🔑 계측기 먼저 — 기준선을 만들 수 있고, 그 직후엔 조용한가"
mk_src "$W/src.md" 3 2
out="$(SHARED_CONTRACT_SRC="$W/src.md" SHARED_CONTRACT_BASELINE="$W/base.txt" bash "$CHECK" --write-baseline 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && [ -s "$W/base.txt" ] && ok "기준선을 쓴다 (rc=0, 파일 비어있지 않음)" \
  || bad "기준선 생성 실패" "rc=0 + 내용" "rc=$rc «${out}»"
out="$(run "$W/src.md" "$W/base.txt")"; rc=$?
[ "$rc" -eq 0 ] && ok "  → 바로 다시 돌리면 무음 (rc=0)" || bad "직후 재실행이 시끄럽다" 0 "${rc}«${out}»"

echo
echo "② 🔴 조항이 «줄면» 잡는다 — 재편이 조용히 빼는 자리"
mk_src "$W/less.md" 2 2
out="$(run "$W/less.md" "$W/base.txt")"; rc=$?
[ "$rc" -eq 1 ] && ok "줄어들면 rc=1" || bad "줄었는데 조용하다" 1 "$rc"
case "$out" in *"절1"*) ok "  → 어느 절인지 말한다" ;; *) bad "절을 안 짚는다" "절1 언급" "«${out}»" ;; esac
case "$out" in *3*2*|*"3 → 2"*|*"3→2"*) ok "  → 몇 개가 몇 개로 됐는지 말한다" ;; *) bad "수를 안 말한다" "3→2" "«${out}»" ;; esac

echo
echo "③ 🔴 조항이 «늘어도» 같은 무게로 잡는다 (한쪽만 잡으면 절반짜리다)"
mk_src "$W/more.md" 4 2
out="$(run "$W/more.md" "$W/base.txt")"; rc=$?
[ "$rc" -eq 1 ] && ok "늘어도 rc=1" || bad "늘었는데 조용하다" 1 "$rc"

echo
echo "④ 절이 통째로 «사라지거나» «생기는» 것도 변화다"
mk_src "$W/drop.md" 3
out="$(run "$W/drop.md" "$W/base.txt")"; rc=$?
[ "$rc" -eq 1 ] && ok "절이 사라지면 rc=1" || bad "절 소멸이 조용하다" 1 "$rc"
case "$out" in *"절2"*) ok "  → 사라진 절 이름을 말한다" ;; *) bad "사라진 절을 안 짚는다" "절2" "«${out}»" ;; esac
mk_src "$W/add.md" 3 2 1
out="$(run "$W/add.md" "$W/base.txt")"; rc=$?
[ "$rc" -eq 1 ] && ok "절이 생겨도 rc=1" || bad "절 신설이 조용하다" 1 "$rc"

echo
echo "⑤ 🔑 🤝 없는 절은 세지 않는다 — 분모를 넓히면 매번 시끄러워 가드가 죽는다"
{ cat "$W/src.md"; printf '## 그냥 절 (🤝 없음)\n\n- 잡음1\n- 잡음2\n'; } > "$W/noise.md"
out="$(run "$W/noise.md" "$W/base.txt")"; rc=$?
[ "$rc" -eq 0 ] && ok "🤝 아닌 절이 늘어도 무음" || bad "🤝 아닌 절에 반응한다" 0 "$rc «${out}»"

echo
echo "⑥ 🔴 판정 불가를 «이상 없음»으로 접지 않는다 (0건의 두 얼굴)"
out="$(run "$W/없는파일.md" "$W/base.txt")"; rc=$?
[ "$rc" -eq 2 ] && ok "원본이 없으면 rc=2 (판정 불가)" || bad "원본 부재를 통과시킨다" 2 "$rc"
out="$(run "$W/src.md" "$W/없는기준선.txt")"; rc=$?
[ "$rc" -eq 2 ] && ok "기준선이 없으면 rc=2" || bad "기준선 부재를 통과시킨다" 2 "$rc"
: > "$W/empty.md"
out="$(run "$W/empty.md" "$W/base.txt")"; rc=$?
[ "$rc" -eq 2 ] && ok "🤝 절이 0개면 rc=2 (파일 형식이 바뀐 것)" || bad "0개를 «다 사라짐»으로 읽는다" 2 "$rc"

echo
echo "⑦ 출력이 «무엇을 하라»를 말하나 (막기만 하면 사람이 기준선만 갱신한다)"
out="$(run "$W/less.md" "$W/base.txt")"
case "$out" in *대조*|*읽*) ok "대조하라고 말한다" ;; *) bad "처방이 없다" "대조 언급" "«${out}»" ;; esac
case "$out" in *--write-baseline*) ok "기준선 갱신 방법도 알려준다 (대조 «후»)" ;; *) bad "갱신법 미안내" "--write-baseline" "«${out}»" ;; esac

echo
echo "⑧ 🔴 임시파일을 남기지 않는다 (룬드 리뷰 실측 — 실행 1회당 tmp.* 1개 잔존)"
# 🔑 이 축은 **rc 로도 출력으로도 안 보인다.** 검사는 매번 초록이면서 파일만 쌓였다.
#    원인은 trap 이 SRC 만 지웠고 그 SRC 조차 «env 로 주면» trap 이 안 걸리는 경로였던 것.
#    ⇒ 대조군 없이는 「누수 0」과 「셀 곳을 잘못 봄」이 구별이 안 되므로 TMPDIR 를 갈라 쓴다.
T="$W/tmpdir"; mkdir -p "$T"
count_tmp() { find "$T" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' '; }
before="$(count_tmp)"
TMPDIR="$T" run "$W/src.md" "$W/base.txt" >/dev/null 2>&1     # 변화 없음 경로
TMPDIR="$T" run "$W/less.md" "$W/base.txt" >/dev/null 2>&1    # 변화 있음(조기 반환) 경로
TMPDIR="$T" run "$W/없는파일.md" "$W/base.txt" >/dev/null 2>&1 # 판정 불가(exit 2) 경로
after="$(count_tmp)"
[ "$before" = "$after" ] && ok "세 경로(0/1/2) 모두 임시파일 잔존 0 ($before → $after)" \
                         || bad "임시파일이 남는다" "$before" "$after"
# 🔑 대조군 — 위 「0 → 0」이 **셀 곳을 잘못 봐서** 나온 게 아닌지. 여기서 안 세지면 위 초록은 무의미하다
: > "$T/probe-$$"; [ "$(count_tmp)" != "$before" ] && ok "대조군: 이 자리에 파일이 생기면 세어진다" \
                                                   || bad "대조군 실패 — 세는 자리가 틀렸다" "증가" "그대로"
rm -f "$T/probe-$$"
# 🔴 **위 대조군도 맥에선 통과하면서 시험은 죽는다** — BSD mktemp 가 env TMPDIR 를 무시해서
#   주입이 checker 에 안 닿기 때문이다(룬드 실측: 구판으로 돌려도 0→0 초록 = **분모 0**).
#   대조군은 「내가 세는 자리」만 보고 「checker 가 쓰는 자리」는 안 봤다 — 두 자리가 갈릴 수 있다.
#   ⇒ checker 가 인자 없는 `mktemp` 로 돌아가면 이 시험이 조용히 무력해지므로 형태를 잠근다.
bare="$(LC_ALL=C grep -c 'mktemp)' "$CHECK" 2>/dev/null || true)"
[ "${bare:-0}" -eq 0 ] && ok "checker 가 mktemp 를 템플릿형으로 부른다 (BSD 도 TMPDIR 존중)" \
                       || bad "인자 없는 mktemp 가 있다 — 맥에서 ⑧이 분모 0이 된다" "0건" "${bare}건"

echo
echo "⑨ 🔑 계약의 단위 = 🤝 가 찍힌 «줄» 전부 (2026-08-02 룬드 확정 · Ⅲ)"
# 🔴 왜 줄 단위인가 — 절 단위(v1)로 두니 **하루에 세 번 밖으로 샜다**:
#   ⓐ 룬드가 「origin 조회」 조항을 **루트 CLAUDE.md 표 한 칸**에 세움
#   ⓑ 나는 같은 조항을 내 CLAUDE.md **하위 불릿**에 세움
#   ⓒ 🤝 단위를 정의한 **그 문장 자체**가 절 밖 blockquote 에 있었다
#   ⇒ 합의가 사는 자리와 계약 표시가 갈리면 **표시 쪽이 진다.**
mk_line_src() {  # $1=파일 · $2.. = 절 밖 🤝 줄들
    local f="$1"; shift
    printf '# 문서\n\n' > "$f"
    for l in "$@"; do printf '%s\n' "$l" >> "$f"; done
    printf '\n## 🤝 진짜 절 — 공유 계약\n\n- 조항 A\n- 조항 B\n' >> "$f"
}

# 🔑 계측기 — 절 밖 줄이 «실제로 세어지나». 아니면 아래가 전부 항진명제다
mk_line_src "$W/L1.md" '> 🤝 표 밖 조항 하나'
run "$W/L1.md" "$W/L1.base" >/dev/null 2>&1
SHARED_CONTRACT_SRC="$W/L1.md" SHARED_CONTRACT_BASELINE="$W/L1.base" bash "$CHECK" --write-baseline >/dev/null 2>&1
nL="$(LC_ALL=C grep -ac '^L.*표 밖 조항' "$W/L1.base")"
[ "$nL" = "1" ] && ok "계측기: 절 밖 🤝 줄이 조항으로 잡힌다" || bad "절 밖 줄이 안 잡힌다" 1 "$nL"

# 표 한 칸의 🤝 (룬드가 실제로 세운 형태)
mk_line_src "$W/L2.md" '| 🔴 해시를 줬다 | origin 조회 200 (🤝 양봇 규칙) |'
SHARED_CONTRACT_SRC="$W/L2.md" SHARED_CONTRACT_BASELINE="$W/L2.base" bash "$CHECK" --write-baseline >/dev/null 2>&1
[ "$(LC_ALL=C grep -ac '^L.*origin 조회 200' "$W/L2.base")" = "1" ] && ok "표 한 칸의 🤝 도 조항이다" || bad "표 줄을 놓친다"

# 🔑 자리를 옮겨도 조용해야 한다 — 절 밖 줄은 원래 옮겨다닌다(합의)
mk_line_src "$W/L3.md" '- 앞줄' '> 🤝 표 밖 조항 하나'
out="$(run "$W/L3.md" "$W/L1.base")"; rc=$?
[ "$rc" -eq 0 ] && ok "같은 내용이 자리를 옮기면 조용하다 (해시 단위)" || bad "자리 이동에 울린다" 0 "$rc"

# 🔴 대조군 — 위 초록이 «아무것도 안 본다»가 아닌지. 내용이 바뀌면 반드시 울려야 한다
mk_line_src "$W/L4.md" '> 🤝 표 밖 조항 하나를 고쳤다'
out="$(run "$W/L4.md" "$W/L1.base")"; rc=$?
[ "$rc" -eq 1 ] && ok "대조군: 내용이 바뀌면 울린다" || bad "내용 변경이 조용하다" 1 "$rc"
case "$out" in *"줄 조항이 사라졌다"*) ok "사라진 줄을 짚는다" ;; *) bad "사라진 줄 미지목" "줄 조항이 사라졌다" "«${out}»" ;; esac
case "$out" in *"줄 조항이 생겼다"*)  ok "생긴 줄도 짚는다 (늘어도 같은 무게)" ;; *) bad "신설 줄 미지목" "줄 조항이 생겼다" "«${out}»" ;; esac

# 🔑 절 «안»의 불릿도 조항이다(08-02 룬드 판정 — 수 보존 교체 미탐 때문에 뒤집혔다).
#   단 «한 번만» 잡혀야 한다 — S 행은 개수, L 행은 어느 조항인지. 같은 불릿이 L 로 두 번 나오면 이중계산이다
mk_line_src "$W/L5.md" '> 🤝 표 밖 조항 하나'
printf -- '- 🤝 절 안 불릿\n' >> "$W/L5.md"
SHARED_CONTRACT_SRC="$W/L5.md" SHARED_CONTRACT_BASELINE="$W/L5.base" bash "$CHECK" --write-baseline >/dev/null 2>&1
[ "$(LC_ALL=C grep -ac '^L.*절 안 불릿' "$W/L5.base")" = "1" ] && ok "절 안 불릿은 L 로 정확히 한 번" \
    || bad "이중계산" "L 1개" "$(LC_ALL=C grep -ac '^L.*절 안 불릿' "$W/L5.base")개"

# 🔴 파일이 둘이다 — 하나만 보면 다른 하나의 조항이 통째로 분모 밖이 된다 (룬드 rc=2 실측)
mk_line_src "$W/F1.md" '> 🤝 파일1 조항'
mk_line_src "$W/F2.md" '> 🤝 파일2 조항'
SHARED_CONTRACT_SRC="a=$W/F1.md:b=$W/F2.md" SHARED_CONTRACT_BASELINE="$W/F.base" bash "$CHECK" --write-baseline >/dev/null 2>&1
nF="$(LC_ALL=C grep -ac '^L.*파일[12] 조항' "$W/F.base")"
[ "$nF" = "2" ] && ok "두 파일의 줄 조항을 다 센다" \
    || bad "파일 하나만 본다" "L 2개" "${nF}개"

# 🔴 **같은 조항이 봇마다 다른 «장식»으로 산다** — 룬드는 표 한 칸, 나는 하위 불릿에 세웠다.
#   장식이 다르다고 다른 조항이면 양봇 대조가 매번 「소실+신설」이라 도구가 못 쓴다.
#   ⚠️ 이 픽스처가 없을 때 「인용부호·리스트마커 제거를 빼는」 변이(N7)가 **안 죽었다** —
#     정규화가 하중을 받는 자리를 어느 시험도 안 밟고 있었다.
mk_line_src "$W/D1.md" '> 🤝 해시를 남에게 줄 땐 origin 조회까지'
mk_line_src "$W/D2.md" '  - 🤝 해시를 남에게 줄 땐 origin 조회까지'
SHARED_CONTRACT_SRC="$W/D1.md" SHARED_CONTRACT_BASELINE="$W/D.base" bash "$CHECK" --write-baseline >/dev/null 2>&1
out="$(run "$W/D2.md" "$W/D.base")"; rc=$?
[ "$rc" -eq 0 ] && ok "장식(인용/불릿/표)이 달라도 같은 조항이다" || bad "장식 차이를 조항 변경으로 읽는다" 0 "$rc"

# 🔴 **코드펜스 안의 `#` 이 절을 끊는다** (룬드 리뷰 실측 · request-changes).
#   조용한 미탐이다 — 블록 뒤 조항이 통째로 소실되는데 아무 소리도 안 난다.
#   🔑 ⑨절을 쓸 때 펜스 픽스처가 «하나도» 없었다. 픽스처가 축을 안 가른 **네 번째**다
#     (#119 ⑤절 · #131 M7·M10 · #121 N7). 같은 PR 안에서 그 습관을 자백하고 또 밟았다.
printf '## 🤝 절A — 공유 계약\n\n- 조항1\n\n```sh\n# 주석\n```\n\n- 조항2\n' > "$W/fence.md"
SHARED_CONTRACT_SRC="$W/fence.md" SHARED_CONTRACT_BASELINE="$W/fence.base" bash "$CHECK" --write-baseline >/dev/null 2>&1
got="$(LC_ALL=C grep -a '^S' "$W/fence.base" | cut -f3)"
[ "$got" = "2" ] && ok "펜스 안 # 이 절을 안 끊는다 (조항2 보존)" || bad "펜스가 절을 끊는다" 2 "$got"

# 예시 블록 안의 🤝 는 «설명»이지 계약이 아니다 — 실행되지 않는 글자와 같은 취급
printf '## 보통 절\n\n```md\n> 🤝 예시 조항\n```\n' > "$W/fence2.md"
out="$(SHARED_CONTRACT_SRC="$W/fence2.md" SHARED_CONTRACT_BASELINE="$W/fence2.base" bash "$CHECK" --write-baseline 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && ok "펜스 안 🤝 만 있으면 조항 0개 → rc=2 (판정 불가)" || bad "펜스 안 🤝 를 조항으로 센다" 2 "$rc"

echo
echo "⑩ ➖ 래핑 경고 — «보이게 하되 소리내지 않는다»"
# 🔴 실측 두 건: 룬드 정의 문단에서 🤝 «단위» 조항의 뒷부분과 «파일 범위» 줄이
#   둘 다 🤝 없는 다음 줄이라 **계약 밖**이었다. 내가 대조하고 등재한 조항이 이미 반쪽이었다.
printf '> 🤝 조항 앞부분이고\n>    이어지는 뒷부분이다\n' > "$W/wrap.md"
out="$(SHARED_CONTRACT_SRC="$W/wrap.md" SHARED_CONTRACT_BASELINE="$W/wrap.base" bash "$CHECK" --write-baseline 2>&1)"; rc=$?
case "$out" in *"래핑"*) ok "래핑 의심 줄을 ➖ 로 알린다" ;; *) bad "래핑을 못 본다" "래핑 언급" "«${out}»" ;; esac
[ "$rc" -eq 0 ] && ok "경고는 rc 를 안 바꾼다 (조항이 아니다)" || bad "경고가 rc 를 바꾼다" 0 "$rc"
[ "$(LC_ALL=C grep -ac '^W' "$W/wrap.base")" = "0" ] && ok "경고는 기준선에 안 들어간다" || bad "경고가 기준선에 샌다"
# 🔴 대조군 — 규약대로 «한 줄»로 적으면 조용해야 한다. 아니면 상시 경고라 곧 무시된다
printf '> 🤝 조항이 한 줄에 다 있다.\n\n> 다른 문단\n' > "$W/nowrap.md"
out="$(SHARED_CONTRACT_SRC="$W/nowrap.md" SHARED_CONTRACT_BASELINE="$W/nowrap.base" bash "$CHECK" --write-baseline 2>&1)"
case "$out" in *"래핑"*) bad "대조군 실패 — 한 줄짜리에도 경고한다" "무음" "«${out}»" ;; *) ok "대조군: 한 줄로 적으면 조용하다" ;; esac

# 🔴 옛 기준선(v1: 2열)을 «변화 있음»으로 읽으면 시끄럽게 거짓이다 — 판정 불가여야 한다
printf '🤝 어떤 절\t3\n' > "$W/v1.base"
out="$(run "$W/L1.md" "$W/v1.base")"; rc=$?
[ "$rc" -eq 2 ] && ok "v1 기준선은 rc=2 (비교 자체가 성립 안 함)" || bad "v1 을 변화로 읽는다" 2 "$rc"

echo
echo "⑪ 🔴 🤝 절 «안» 불릿도 조항이다 — 수 보존 교체 미탐 회귀 (c5a97ff 실물)"
# 실측: 룬드가 축약·이관 절의 ③⑤ 두 불릿을 «다시 써서» 올렸는데(c5a97ff) 불릿 수가 6→6 이라
#   개수만 세던 판정은 **rc=0 으로 조용했다**. 계약 문구가 바뀐 걸 상대가 모르는 게 이 도구의 실패다.
#   ⇒ 룬드 판정(08-02): 다듬을 때마다 울리는 건 소음이 아니라 «상대가 봐야 하는 사건»이다.
printf '## 🤝 절A — 공유 계약\n\n- 조항 하나\n- 조항 둘\n' > "$W/b1.md"
out="$(SHARED_CONTRACT_SRC="$W/b1.md" SHARED_CONTRACT_BASELINE="$W/b1.base" bash "$CHECK" --write-baseline 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "절 안 불릿으로 기준선을 쓴다" || bad "기준선 실패" 0 "${rc}«${out}»"

# 🔑 핵심 회귀: 개수는 그대로(2 → 2), 내용만 바뀐다
printf '## 🤝 절A — 공유 계약\n\n- 조항 하나\n- 조항 둘을 «다시 썼다»\n' > "$W/b2.md"
out="$(run "$W/b2.md" "$W/b1.base")"; rc=$?
[ "$rc" -eq 1 ] && ok "수 보존 교체가 울린다 (2→2 인데 내용이 다르다)" \
  || bad "c5a97ff 미탐 재현 — 내용이 바뀌었는데 조용하다" 1 "${rc}«${out}»"

# 🔴 대조군 — 안 바꾸면 조용해야 한다. 아니면 매번 울려서 곧 무시된다
out="$(run "$W/b1.md" "$W/b1.base")"; rc=$?
[ "$rc" -eq 0 ] && ok "  대조군: 그대로면 조용하다" || bad "안 바꿨는데 울린다" 0 "${rc}«${out}»"

# 장식만 다른 같은 조항은 같다 — 줄 조항(⑨)과 같은 정규화가 절 안에도 걸려야 한다
printf '## 🤝 절A — 공유 계약\n\n*  조항 하나\n-   조항 둘\n' > "$W/b3.md"
out="$(run "$W/b3.md" "$W/b1.base")"; rc=$?
[ "$rc" -eq 0 ] && ok "  불릿 기호·공백 차이는 같은 조항 (정규화)" || bad "장식 차이를 변경으로 읽는다" 0 "${rc}«${out}»"

# 개수가 «줄어드는» 자리는 여전히 잡힌다 — 새 축이 옛 축을 먹으면 안 된다
printf '## 🤝 절A — 공유 계약\n\n- 조항 하나\n' > "$W/b4.md"
out="$(run "$W/b4.md" "$W/b1.base")"; rc=$?
[ "$rc" -eq 1 ] && ok "  불릿이 사라지는 것도 여전히 잡는다" || bad "소실을 놓친다" 1 "${rc}«${out}»"

echo
echo "⑫ 🔴 맥 bash 3.2 에서 «도구 자체»가 도나 (룬드 실측 — main 이 문법에러로 죽었다)"
# 🔴 3.2 의 낡은 파서는 `$(...)` 안 heredoc **본문을 다시 토큰 스캔**해서, `<<'PY'` 로 인용해도
#   파이썬 정규식의 백틱 3개를 명령 치환으로 읽고 죽는다. WSL(5.2)은 재귀 파서라 **무증상**이라,
#   여기까지의 모든 확인이 **WSL 축 하나**였다(맥 축 분모 0). 시험이 아니라 **도구가** 안 돌았다.
# 🔑 형태를 잠근다 — 문법검사는 3.2 가 있어야 도는데 시험 기계엔 없을 수 있다.
#   ⇒ ⓐ 이 기계의 bash -n 은 항상 돌리고 ⓑ 3.2 가 죽는 «형태»는 문자열로 막는다.
bash -n "$CHECK" 2>/dev/null && ok "bash -n 통과 (이 기계)" || bad "문법 에러" "rc=0" "rc=$?"
# 🔴 **맥 실측 두 번째 형태(08-02)**: `$VAR»` 는 bash 3.2 가 »(0xC2…) 첫 바이트를 식별자로 먹어
#   `VAR?: unbound variable` 로 죽는다. WSL 은 무증상 — ⑭가 맥에서만 떨어져서 알았다.
#   ⇒ 중괄호로 경계를 명시하는 형태를 잠근다(우리 문서가 « » 를 상시로 쓰므로 상시 위험).
# 🔑 **주석은 뺀다 — 안 그러면 «경고문이 자기 판별식을 울린다».** 오늘 두 번 났다:
#   이 판별식을 설명하는 주석에 그 형태를 쓰면 그대로 걸린다. 형태를 «말하는 줄»과
#   «실행하는 줄»은 다른 것이므로, 판별식의 분모는 실행되는 줄이다.
# 🔑 판별식의 분모 = «실행되는 줄». 세 층을 먼저 걷어낸다:
#   ⓐ 주석 — 형태를 «말하는 줄»이지 그 형태가 아니다(#149: 경고문이 자기 판별식을 울렸다)
#   ⓑ 이스케이프된 \$VAR — 확장되지 않는다(같은 축, 세 번째 형태)
#   ⓒ herestring `<<<` — 재스캔과 무관한 다른 구문이다(룬드 코퍼스 오탐 4곳, 네 번째 형태)
#   ⚠️ ⓒ를 `<<[^<]` 로 좁히는 건 **부족하다** — `<<< hi` 는 둘째 `<` 부터 `<<`+공백으로도 매치된다.
#     (룬드 제안을 그대로 받았다가 «오탐 대조군» 픽스처가 잡았다 — 안 잡아야 할 것도 세운 값)
code_only() { LC_ALL=C grep -v '^[[:space:]]*#' "$1" | LC_ALL=C sed -e 's/\\\$//g' -e 's/<<<//g'; }
# ⚠️ 이스케이프된 `\$VAR»` 는 «말하는 줄»이라 확장되지 않는다 — 주석 제외(#149)와 같은 축의
#   오탐이므로 같이 뺀다. 안 빼면 이 판별식을 «설명하는 실패 메시지»가 스스로를 울린다.
# 🔴 `$VAR»` 판별식은 `tests/lib/portability-guard.sh` 로 «이사»했다 (2026-08-10).
#   여기 있을 땐 분모가 `$CHECK` **한 파일**이었고, 그래서 `#153` 의 `«$want_msg»` 가
#   **판별식이 이 레포에 있는 채로** 룬드 맥에서 죽었다. 판별식이 아니라 «분모»가 문제였다.
#   ⇒ 분모가 명제(「모든 시험이 상대 봇 기계에서 돈다」)에 맞는 집으로 옮기고 여기선 지운다.
#     사본을 남기면 셋째가 따로 낡는다.
# ⚠️ `<<<`(herestring)는 **재스캔과 무관**한데 `<<` 패턴에 걸린다 — 룬드 코퍼스에서 오탐 4곳
#   (판별식 오탐 네 번째 형태). 내 코퍼스엔 0건이지만 **없다고 판별식이 맞는 건 아니다.**
nHD="$(code_only "$CHECK" | LC_ALL=C grep -c '\$(.*<<' || true)"
[ "${nHD:-0}" -eq 0 ] && ok "명령 치환 안에 heredoc 이 없다 (3.2 파서가 죽는 형태)" \
  || bad "\$() 안 heredoc — 맥 bash 3.2 가 문법에러로 죽는다" "0건" "${nHD}건"
# 🔑 대조군 — 위 0 이 «셀 곳을 잘못 봐서» 나온 게 아닌지. 그 형태를 만들면 세어져야 한다
printf 'X="$(python3 - <<%sPY\nprint(1)\nPY\n)"\n' "'" > "$W/hd-probe.sh"
[ "$(code_only "$W/hd-probe.sh" | LC_ALL=C grep -c '\$(.*<<')" -ge 1 ] && ok "  대조군: 그 형태가 있으면 세어진다" \
  || bad "대조군 실패 — 판별식이 그 형태를 못 잡는다" "1건 이상" "0건"
# 🔴 **오탐 대조군 — herestring `<<<` 은 재스캔과 무관하다**(룬드 코퍼스 오탐 4곳).
#   판별식이 «잡는 것»만 보면 오탐을 못 본다 — 안 잡아야 할 것도 픽스처로 세운다.
# 🔴 **이스케이프 층엔 대조군이 없었다**(룬드 질문 ②, 08-02). 지금까지 이 층은 checker 자기
#   내용으로만 «우연히» 밟혔다 — 픽스처가 없으면 sed 를 망가뜨려도 초록이다.
#   ⇒ 한 파일에 «진짜 1 + 이스케이프 1»을 같이 두어 **양방향**을 한 번에 잰다.
# 🔸 이스케이프 대조군도 같이 갔다 — 픽스처는 판별식을 따라간다.
#   여기 남기면 «검사기 없는 대조군»이 되어 아무것도 안 지킨다.

printf 'X="$(tr a b <<%s hi)"\n' '<' > "$W/hs-probe.sh"
[ "$(code_only "$W/hs-probe.sh" | LC_ALL=C grep -c '\$(.*<<')" -eq 0 ] \
  && ok "  오탐 대조군: herestring(<<<) 은 안 센다" \
  || bad "herestring 을 heredoc 으로 읽는다 (오탐)" "0건" "1건 이상"

echo
echo "⑬ 🔴 기준선 갱신 무결성 — «읽고 갱신하라»를 문안이 아니라 형태로 (08-02 21초 레이스)"
# 🔴 실측: 룬드 push 22:00:12Z · 내 --write-baseline 22:00:33Z. **21초 차로 안 읽은 변경이
#   기준선에 접혔다.** 도구는 경고문으로 「읽지 않고 갱신하면 아무것도 안 막는다」고 말하고 있었고,
#   그 문장을 쓴 내가 23초 뒤에 그대로 실행했다. ⇒ 문안이 아니라 **CAS(지문 대조)**로 잠근다.
mk_src "$W/cas.md" 2 1
out="$(SHARED_CONTRACT_SRC="$W/cas.md" SHARED_CONTRACT_BASELINE="$W/cas.base" bash "$CHECK" --write-baseline 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "부트스트랩: 기준선이 없으면 토큰 없이 만든다 (막으면 도구를 못 쓴다)" \
  || bad "최초 생성이 막힌다" 0 "${rc}«${out}»"

mk_src "$W/cas2.md" 3 1                       # 원본이 바뀌었다 → 울린다 + 지문을 준다
out="$(run "$W/cas2.md" "$W/cas.base")"; rc=$?
tok="$(printf '%s' "$out" | LC_ALL=C sed -n 's/.*--write-baseline \([0-9a-f]\{12\}\).*/\1/p' | head -1)"
[ "$rc" -eq 1 ] && [ -n "$tok" ] && ok "울릴 때 «읽은 시점의 지문»을 같이 준다 ($tok)" \
  || bad "지문을 안 준다" "rc=1 + 12자 지문" "rc=$rc tok=«${tok}»"

out="$(SHARED_CONTRACT_SRC="$W/cas2.md" SHARED_CONTRACT_BASELINE="$W/cas.base" bash "$CHECK" --write-baseline 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && ok "기준선이 있는데 지문 없이 갱신하면 **거부** (rc=2)" || bad "맨손 갱신이 통과한다" 2 "${rc}«${out}»"

out="$(SHARED_CONTRACT_SRC="$W/cas2.md" SHARED_CONTRACT_BASELINE="$W/cas.base" bash "$CHECK" --write-baseline deadbeef1234 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && ok "틀린 지문도 거부" || bad "아무 지문이나 통과한다" 2 "${rc}«${out}»"

# 🔴 핵심 회귀 — «지문을 받은 뒤 원본이 또 바뀌면» 거부해야 한다. 그게 21초 레이스다
mk_src "$W/cas3.md" 4 1
out="$(SHARED_CONTRACT_SRC="$W/cas3.md" SHARED_CONTRACT_BASELINE="$W/cas.base" bash "$CHECK" --write-baseline "$tok" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && ok "21초 레이스 회귀: 지문을 받은 «뒤» 원본이 바뀌면 거부" \
  || bad "레이스가 그대로 통과한다" 2 "${rc}«${out}»"

# 🔑 대조군 — 맞는 지문이면 반드시 통과해야 한다. 아니면 위 셋은 «항상 거부»의 그림자다
out="$(SHARED_CONTRACT_SRC="$W/cas2.md" SHARED_CONTRACT_BASELINE="$W/cas.base" bash "$CHECK" --write-baseline "$tok" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "  대조군: 맞는 지문이면 갱신된다" || bad "맞는 지문도 거부한다 — 항상 거부다" 0 "${rc}«${out}»"

echo
echo "⑭ ➖ 커밋 안 된 기준선을 짚는다 (08-02 자기 실측 — 대조가 브랜치 전환에 증발했다)"
G="$W/repo"; mkdir -p "$G/config"
git -C "$G" init -q 2>/dev/null; git -C "$G" config user.email t@t; git -C "$G" config user.name t
mk_src "$G/src.md" 2 1
SHARED_CONTRACT_SRC="$G/src.md" SHARED_CONTRACT_BASELINE="$G/config/b.base" bash "$CHECK" --write-baseline >/dev/null 2>&1
git -C "$G" add -f config/b.base >/dev/null 2>&1; git -C "$G" commit -qm init >/dev/null 2>&1
# 커밋된 직후엔 조용해야 한다 (상시 경고면 곧 무시된다)
mk_src "$G/src2.md" 3 1
tok2="$(SHARED_CONTRACT_SRC="$G/src2.md" SHARED_CONTRACT_BASELINE="$G/config/b.base" bash "$CHECK" 2>&1 \
        | LC_ALL=C sed -n 's/.*--write-baseline \([0-9a-f]\{12\}\).*/\1/p' | head -1)"
out="$(SHARED_CONTRACT_SRC="$G/src2.md" SHARED_CONTRACT_BASELINE="$G/config/b.base" bash "$CHECK" --write-baseline "$tok2" 2>&1)"
case "$out" in *"커밋되지 않았다"*) ok "갱신 후 커밋 전이면 ➖ 로 짚는다" ;; *) bad "미커밋을 안 짚는다" "커밋되지 않았다" "«${out}»" ;; esac
git -C "$G" add config/b.base >/dev/null 2>&1; git -C "$G" commit -qm base >/dev/null 2>&1
out="$(SHARED_CONTRACT_SRC="$G/src2.md" SHARED_CONTRACT_BASELINE="$G/config/b.base" bash "$CHECK" 2>&1)"
case "$out" in *"커밋되지 않았다"*) bad "대조군 실패 — 커밋했는데도 경고한다" "무음" "«${out}»" ;; *) ok "  대조군: 커밋하면 조용하다" ;; esac

echo
echo "── ⑮ 기준선 경로는 «자기 위치»에서 유도한다 (워크트리 오염 방지) ──"
# 🔴 2026-08-02 실측: `BASE` 가 `$HOME/discord-bot-nino/config/...` 로 **하드코딩**돼 있어서
#   워크트리에서 `--write-baseline` 을 돌리면 **main 트리의 기준선이 바뀌었다.**
#   워크트리의 `git status` 는 그 파일을 안 보여주니 **그 트리만 보면 아무 일도 안 난 것처럼 보인다.**
#   그대로 main 에서 브랜치를 옮기면 기준선이 증발한다 — 오늘 아침 이미 한 번 난 사고다.
#   🔑 「어디에 쓰는가」를 `$HOME` 으로 잡은 도구는 **사본이 여럿인 순간 남의 사본을 쓴다.**
#     우리는 「worktree 로 main 중단 없이 작업」을 규칙으로 쓰므로 **상시 발동 조건**이다.
#   경위 [[inbox-2026-07-31]] #158
W15="$(mktemp -d "${TMPDIR:-/tmp}/scpath.XXXXXX")"
mkdir -p "$W15/tree/scripts" "$W15/tree/config" "$W15/fakehome/discord-bot-nino/config"
cp "$CHECK" "$W15/tree/scripts/"
printf '# 계약\n\n## 🤝 절\n\n- 🤝 조항 하나\n' > "$W15/src.md"

# 기준선 경로를 «주지 않고» 돌린다 — 도구가 스스로 어디에 쓸지 정하는 갈래다.
_o15="$(env -u SHARED_CONTRACT_BASELINE HOME="$W15/fakehome" \
        SHARED_CONTRACT_SRC="$W15/src.md" bash "$W15/tree/scripts/check-shared-contracts.sh" 2>&1)"
_tok15="$(printf '%s' "$_o15" | LC_ALL=C sed -n 's/.*--write-baseline \([0-9a-f]*\).*/\1/p' | head -1)"
env -u SHARED_CONTRACT_BASELINE HOME="$W15/fakehome" SHARED_CONTRACT_SRC="$W15/src.md" \
    bash "$W15/tree/scripts/check-shared-contracts.sh" --write-baseline "${_tok15:-x}" >/dev/null 2>&1

if [ -s "$W15/tree/config/shared-contracts.baseline" ]; then
  ok "사본 트리에서 돌리면 «그 트리»의 config/ 에 쓴다"
else
  bad "자기 트리에 기록" "$W15/tree/config/shared-contracts.baseline 존재" "없음 — 경로를 자기 위치에서 안 잡는다"
fi

# 🧪 [대조군] 그리고 «남의 트리»($HOME 쪽)에는 **안 써야** 한다. 위 검사만으론 둘 다 쓰는 경우를 못 가른다.
if [ -e "$W15/fakehome/discord-bot-nino/config/shared-contracts.baseline" ]; then
  bad "🧪 남의 트리 오염" "격리 HOME 쪽에 안 씀" "$W15/fakehome/discord-bot-nino/config/ 에 썼다 — 워크트리 오염 재현"
else
  ok "  🧪 [대조군] \$HOME/discord-bot-nino/config/ 에는 안 쓴다"
fi
rm -rf "$W15"

echo
echo "  통과 $pass · 실패 $fail"
[ "$fail" -eq 0 ] || exit 1
