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
  || bad "기준선 생성 실패" "rc=0 + 내용" "rc=$rc «$out»"
out="$(run "$W/src.md" "$W/base.txt")"; rc=$?
[ "$rc" -eq 0 ] && ok "  → 바로 다시 돌리면 무음 (rc=0)" || bad "직후 재실행이 시끄럽다" 0 "$rc«$out»"

echo
echo "② 🔴 조항이 «줄면» 잡는다 — 재편이 조용히 빼는 자리"
mk_src "$W/less.md" 2 2
out="$(run "$W/less.md" "$W/base.txt")"; rc=$?
[ "$rc" -eq 1 ] && ok "줄어들면 rc=1" || bad "줄었는데 조용하다" 1 "$rc"
case "$out" in *"절1"*) ok "  → 어느 절인지 말한다" ;; *) bad "절을 안 짚는다" "절1 언급" "«$out»" ;; esac
case "$out" in *3*2*|*"3 → 2"*|*"3→2"*) ok "  → 몇 개가 몇 개로 됐는지 말한다" ;; *) bad "수를 안 말한다" "3→2" "«$out»" ;; esac

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
case "$out" in *"절2"*) ok "  → 사라진 절 이름을 말한다" ;; *) bad "사라진 절을 안 짚는다" "절2" "«$out»" ;; esac
mk_src "$W/add.md" 3 2 1
out="$(run "$W/add.md" "$W/base.txt")"; rc=$?
[ "$rc" -eq 1 ] && ok "절이 생겨도 rc=1" || bad "절 신설이 조용하다" 1 "$rc"

echo
echo "⑤ 🔑 🤝 없는 절은 세지 않는다 — 분모를 넓히면 매번 시끄러워 가드가 죽는다"
{ cat "$W/src.md"; printf '## 그냥 절 (🤝 없음)\n\n- 잡음1\n- 잡음2\n'; } > "$W/noise.md"
out="$(run "$W/noise.md" "$W/base.txt")"; rc=$?
[ "$rc" -eq 0 ] && ok "🤝 아닌 절이 늘어도 무음" || bad "🤝 아닌 절에 반응한다" 0 "$rc «$out»"

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
case "$out" in *대조*|*읽*) ok "대조하라고 말한다" ;; *) bad "처방이 없다" "대조 언급" "«$out»" ;; esac
case "$out" in *--write-baseline*) ok "기준선 갱신 방법도 알려준다 (대조 «후»)" ;; *) bad "갱신법 미안내" "--write-baseline" "«$out»" ;; esac

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
nL="$(LC_ALL=C grep -ac '^L	' "$W/L1.base")"
[ "$nL" = "1" ] && ok "계측기: 절 밖 🤝 줄이 조항으로 잡힌다" || bad "절 밖 줄이 안 잡힌다" 1 "$nL"

# 표 한 칸의 🤝 (룬드가 실제로 세운 형태)
mk_line_src "$W/L2.md" '| 🔴 해시를 줬다 | origin 조회 200 (🤝 양봇 규칙) |'
SHARED_CONTRACT_SRC="$W/L2.md" SHARED_CONTRACT_BASELINE="$W/L2.base" bash "$CHECK" --write-baseline >/dev/null 2>&1
[ "$(LC_ALL=C grep -ac '^L	' "$W/L2.base")" = "1" ] && ok "표 한 칸의 🤝 도 조항이다" || bad "표 줄을 놓친다"

# 🔑 자리를 옮겨도 조용해야 한다 — 절 밖 줄은 원래 옮겨다닌다(합의)
mk_line_src "$W/L3.md" '- 앞줄' '> 🤝 표 밖 조항 하나'
out="$(run "$W/L3.md" "$W/L1.base")"; rc=$?
[ "$rc" -eq 0 ] && ok "같은 내용이 자리를 옮기면 조용하다 (해시 단위)" || bad "자리 이동에 울린다" 0 "$rc"

# 🔴 대조군 — 위 초록이 «아무것도 안 본다»가 아닌지. 내용이 바뀌면 반드시 울려야 한다
mk_line_src "$W/L4.md" '> 🤝 표 밖 조항 하나를 고쳤다'
out="$(run "$W/L4.md" "$W/L1.base")"; rc=$?
[ "$rc" -eq 1 ] && ok "대조군: 내용이 바뀌면 울린다" || bad "내용 변경이 조용하다" 1 "$rc"
case "$out" in *"줄 조항이 사라졌다"*) ok "사라진 줄을 짚는다" ;; *) bad "사라진 줄 미지목" "줄 조항이 사라졌다" "«$out»" ;; esac
case "$out" in *"줄 조항이 생겼다"*)  ok "생긴 줄도 짚는다 (늘어도 같은 무게)" ;; *) bad "신설 줄 미지목" "줄 조항이 생겼다" "«$out»" ;; esac

# 🔑 절 «안»의 불릿은 절이 이미 센다 — 줄로 또 세면 이중계산이다
mk_line_src "$W/L5.md" '> 🤝 표 밖 조항 하나'
printf -- '- 🤝 절 안 불릿\n' >> "$W/L5.md"
SHARED_CONTRACT_SRC="$W/L5.md" SHARED_CONTRACT_BASELINE="$W/L5.base" bash "$CHECK" --write-baseline >/dev/null 2>&1
[ "$(LC_ALL=C grep -ac '^L	' "$W/L5.base")" = "1" ] && ok "절 안 불릿은 줄로 또 세지 않는다" \
    || bad "이중계산" "L 1개" "$(LC_ALL=C grep -ac '^L	' "$W/L5.base")개"

# 🔴 파일이 둘이다 — 하나만 보면 다른 하나의 조항이 통째로 분모 밖이 된다 (룬드 rc=2 실측)
mk_line_src "$W/F1.md" '> 🤝 파일1 조항'
mk_line_src "$W/F2.md" '> 🤝 파일2 조항'
SHARED_CONTRACT_SRC="a=$W/F1.md:b=$W/F2.md" SHARED_CONTRACT_BASELINE="$W/F.base" bash "$CHECK" --write-baseline >/dev/null 2>&1
[ "$(LC_ALL=C grep -ac '^L	' "$W/F.base")" = "2" ] && ok "두 파일의 줄 조항을 다 센다" \
    || bad "파일 하나만 본다" "L 2개" "$(LC_ALL=C grep -ac '^L	' "$W/F.base")개"

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
case "$out" in *"래핑"*) ok "래핑 의심 줄을 ➖ 로 알린다" ;; *) bad "래핑을 못 본다" "래핑 언급" "«$out»" ;; esac
[ "$rc" -eq 0 ] && ok "경고는 rc 를 안 바꾼다 (조항이 아니다)" || bad "경고가 rc 를 바꾼다" 0 "$rc"
[ "$(LC_ALL=C grep -ac '^W' "$W/wrap.base")" = "0" ] && ok "경고는 기준선에 안 들어간다" || bad "경고가 기준선에 샌다"
# 🔴 대조군 — 규약대로 «한 줄»로 적으면 조용해야 한다. 아니면 상시 경고라 곧 무시된다
printf '> 🤝 조항이 한 줄에 다 있다.\n\n> 다른 문단\n' > "$W/nowrap.md"
out="$(SHARED_CONTRACT_SRC="$W/nowrap.md" SHARED_CONTRACT_BASELINE="$W/nowrap.base" bash "$CHECK" --write-baseline 2>&1)"
case "$out" in *"래핑"*) bad "대조군 실패 — 한 줄짜리에도 경고한다" "무음" "«$out»" ;; *) ok "대조군: 한 줄로 적으면 조용하다" ;; esac

# 🔴 옛 기준선(v1: 2열)을 «변화 있음»으로 읽으면 시끄럽게 거짓이다 — 판정 불가여야 한다
printf '🤝 어떤 절\t3\n' > "$W/v1.base"
out="$(run "$W/L1.md" "$W/v1.base")"; rc=$?
[ "$rc" -eq 2 ] && ok "v1 기준선은 rc=2 (비교 자체가 성립 안 함)" || bad "v1 을 변화로 읽는다" 2 "$rc"

echo
echo "  통과 $pass · 실패 $fail"
[ "$fail" -eq 0 ] || exit 1
