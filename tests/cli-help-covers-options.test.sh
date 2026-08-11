#!/usr/bin/env bash
# cli-help-covers-options.test.sh — `--help` 가 «파서가 받는 모든 옵션»을 담나
#
# 🔴 왜 이 시험이 있나: `--help` 의 범위를 `sed -n '2,30p'` 처럼 **손으로 적으면**
#   옵션이 늘어도 그 숫자는 «안 늘어난다». 실측 2026-08-11 — `scripts/ci-verdict.sh`
#   가 받는 4개 중 `--help` 자신이, 코어 `run-tests.sh` 는 3개가 help 에서 빠져 있었고
#   **하나는 그 옵션을 추가한 PR 부터 계속** 그랬다.
#
# ⚠️ 이 어긋남이 조용한 이유 (룬드 08-11):
#   **안내의 검증 빈도는 그 기능의 «사용 빈도»와 반대다.** 많이 쓰는 사람일수록 안내를
#   안 열어보고, 그 썩음은 **«새 사용자»한테만** 청구돼 고치는 사람에겐 영영 안 보인다.
#
# 🔑 좌변을 **파서의 `case` 절**에서 뽑는다 — help 를 눈으로 읽고 대조하면 그 대조가
#   또 손이라 같이 낡는다.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO" || exit 1

pass=0; fail=0; skip=0
ok()   { echo "  ✅ $1"; pass=$((pass + 1)); }
bad()  { echo "  ❌ $1"; [ -n "${2:-}" ] && echo "     want: $2"; [ -n "${3:-}" ] && echo "     got:  $3"; fail=$((fail + 1)); }
note() { echo "  ⛔ $1"; skip=$((skip + 1)); }

# ── 대상: `-h|--help)` 분기를 가진 추적 중인 셸 CLI 전부 ──
# 🔑 목록을 손으로 안 적는다 — 새 CLI 가 생기면 **저절로** 분모에 든다.
#
# 🔴 **`tests/` 는 분모 밖이다 — 안 그러면 이 시험이 «자기 자신»을 CLI 로 집는다.**
#   실물 2026-08-11: 이 파일을 커밋하자 `git ls-files` 에 잡혔고, 본문의 `-h|--help)`
#   문자열(변이 심기용) 때문에 대상이 되어 `bash <자기> --help` 로 **무한 재귀**했다.
#   러너가 매달려 죽었고 프로세스를 손으로 죽여야 했다.
#   🔑 「가드가 자기 픽스처를 문다」의 세 번째다(`#180` 주석 오탐 · `#183` 대조군 문자열).
#     축은 **「좌변이 자기 본문을 훑나」**이고, 훑는 순간 «설명·시험한 줄»이 대상이 된다.
#   ⚠️ 「자기 파일만 뺀다」로는 부족하다 — 다음 시험이 같은 문자열을 쓰면 또 난다.
#     시험은 CLI 가 아니므로 **디렉터리 단위로** 가른다(좁아지는 쪽으로 실패한다).
CLIS=""
for f in $(git ls-files '*.sh'); do
    [ -f "$f" ] || continue
    case "$f" in tests/*) continue ;; esac
    command grep -q -- '-h|--help)' "$f" 2>/dev/null && CLIS="$CLIS $f"
done

# 🔴 코어에서 그대로 받아온 사본은 여기서 고칠 수 없다 — 고치면 사본이 갈린다.
#   ⚠️ **면제를 «조용히» 하지 않는다**: 어느 파일이 왜 빠졌는지와 그 수를 찍는다.
#
# 🔴 **좌변을 «로컬 코어 체크아웃과 diff» 로 두면 안 된다 — 분모가 «환경 따라» 갈린다.**
#   첫 판이 `diff -q "$1" "$HOME/yaksu-bot-core-live/$1"` 이었다. 내 WSL 엔 그 트리가 있어
#   면제됐고, **CI 컨테이너엔 없어 면제가 안 돼 빨개졌다**(실측 2026-08-11, `#184` 런
#   `31456463121`: 로컬 5/0 ↔ CI `cli-help-covers-options rc=1`).
#   🔑 **로컬 초록이 CI 를 대변 못 하는 그 자리**고, 원인은 시험이 «레포 밖 파일»을 좌변에
#     넣은 것이다. 레포 밖은 러너마다 다르다.
#   ⇒ **파일이 «스스로» 밝히게 한다** — 사본에 `코어-사본:` 표지를 두고 그것만 읽는다.
#     표지는 파일과 «같이 이동»하므로 어느 러너에서도 같은 답이 나온다.
#   🔸 표지는 «선언»이라 거짓일 수 있다. 그래도 이름 목록보다 낫다 — 목록은 파일이 사라져도
#     남지만 표지는 **파일과 함께 지워진다**. 그리고 면제 수를 찍으므로 조용히 늘지 않는다.
is_core_copy() {
    command grep -q '코어-사본:' "$1" 2>/dev/null
}

echo "① 분모 — 검사 대상 CLI"
_n=0; _exempt=""; _targets=""
for f in $CLIS; do
    if is_core_copy "$f"; then
        _exempt="$_exempt $f"
    else
        _targets="$_targets $f"; _n=$((_n + 1))
    fi
done
if [ "$_n" -ge 1 ]; then
    ok "검사 대상 ${_n}개:$_targets"
else
    bad "대상이 0개다 — \`-h|--help)\` 꼴이 바뀌었거나 전부 면제됐다" "1개 이상" "$_n"
fi
_en="$(printf '%s' "$_exempt" | wc -w | tr -d ' ')"
echo "  ℹ️ 면제 ${_en}개(코어 사본 — 수리가 코어에서 흘러온다):${_exempt:- 없음}"

echo
echo "② 파서가 받는 옵션이 전부 --help 에 나온다"
for f in $_targets; do
    _help="$(bash "$f" --help 2>&1)"
    # `--opt)` · `-h|--help)` 둘 다에서 긴 이름을 뽑는다
    _flags="$(command grep -oE '^[[:space:]]*(-[a-zA-Z]\|)?--[a-z-]+\)' "$f" \
              | command grep -oE -- '--[a-z-]+' | sort -u)"
    _nf="$(printf '%s' "$_flags" | command grep -c . || true)"; _nf="${_nf:-0}"
    # 🔴 좌변이 «비면» 아래 검사가 상수 참이 되어 매번 초록이다 — 분모를 따로 단언한다.
    if [ "$_nf" -lt 2 ]; then
        bad "$f — 파서에서 뽑은 옵션이 ${_nf}개다(좌변이 비었다)" "2개 이상" "$_nf"
        continue
    fi
    _missing=""
    for _fl in $_flags; do
        case "$_help" in *"$_fl"*) ;; *) _missing="$_missing $_fl" ;; esac
    done
    if [ -z "$_missing" ]; then
        ok "$f — 옵션 ${_nf}개가 전부 --help 에 있다"
    else
        bad "$f — --help 에 없는 옵션이 있다" "없음" "$_missing"
    fi
done

echo
echo "③ 🔴 [대조군] 이 검사가 실제로 «무언가를» 잡나 — 옛 상수 범위를 심는다"
# 없으면 ② 의 초록이 「검사가 아무것도 안 본다」와 구별이 안 된다.
_T="$(mktemp -d)"; trap 'rm -rf "$_T"' EXIT
_probe="$_T/const-range.sh"
for f in $_targets; do
    # 🔸 `sed` 로 안 심는다 — awk 프로그램이 여러 줄이라 한 줄 치환이 구문을 깬다
    #   (첫 판이 정확히 그래서 «판정 불가»를 냈고, 그러면 ② 에 증인이 없다).
    #   파이썬으로 `-h|--help)` **분기 전체**를 옛 상수 범위 판으로 갈아끼운다.
    python3 - "$f" "$_probe" <<'PY' 2>/dev/null
import re, sys
src, dst = sys.argv[1], sys.argv[2]
s = open(src, encoding="utf-8").read()
# `-h|--help)` 부터 그 분기를 닫는 `;;` 까지를 통째로 대체한다
s2, n = re.subn(
    r"-h\|--help\).*?;;",
    "-h|--help)   sed -n '2,12p' \"${BASH_SOURCE[0]}\" | sed 's/^# \\{0,1\\}//'; exit 0 ;;",
    s, count=1, flags=re.S)
open(dst, "w", encoding="utf-8").write(s2 if n else "")
PY
    if [ ! -s "$_probe" ] || ! bash -n "$_probe" 2>/dev/null; then
        note "$f — 변이 심기가 구문을 깼다(이 파일은 이 축을 못 쟀다)"
        continue
    fi
    _mhelp="$(bash "$_probe" --help 2>&1)"
    _mflags="$(command grep -oE '^[[:space:]]*(-[a-zA-Z]\|)?--[a-z-]+\)' "$f" \
               | command grep -oE -- '--[a-z-]+' | sort -u)"
    _mmiss=""
    for _fl in $_mflags; do
        case "$_mhelp" in *"$_fl"*) ;; *) _mmiss="$_mmiss $_fl" ;; esac
    done
    if [ -n "$_mmiss" ]; then
        ok "$f — 범위를 12줄로 줄이니 ②가 빨개진다 (빠짐:$_mmiss)"
    else
        bad "$f — 범위를 줄여도 ②가 초록이다. ② 는 아무것도 안 지킨다" "빠진 옵션 있음" "없음"
    fi
done

echo
echo "④ 🔴 머리 주석의 «맨 빈 줄»이 help 를 자르지 않는다"
# 🔑 「첫 비주석 줄에서 멈춘다」로 유도하면 **전제가 옮겨갈 뿐**이다 — 문단 나누려고
#   빈 줄 하나 넣으면 거기서 잘리고, 그것도 조용하다. 실측(코어 #156): help 57→53줄,
#   예시 절이 통째로 사라졌는데 그쪽 시험은 초록이었다(잘린 게 그 시험의 분모 밖이라).
_blank="$_T/blank.sh"
for f in $_targets; do
    _before="$(bash "$f" --help 2>&1 | command grep -c '' || true)"; _before="${_before:-0}"
    # 사용법 절 «앞»에 맨 빈 줄 하나 — 사람이 제일 흔히 하는 편집
    awk 'BEGIN{done=0} /^# 사용법:/ && !done {print ""; done=1} {print}' "$f" > "$_blank"
    if ! bash -n "$_blank" 2>/dev/null; then
        note "$f — 빈 줄 삽입이 구문을 깼다(이 축을 못 쟀다)"
        continue
    fi
    _after="$(bash "$_blank" --help 2>&1 | command grep -c '' || true)"; _after="${_after:-0}"
    # 빈 줄 하나가 늘었으니 1줄 증가는 정상. 줄어들면 «잘린» 것이다.
    if [ "$_after" -ge "$_before" ]; then
        ok "$f — 빈 줄을 넣어도 안 잘린다 (${_before}줄 → ${_after}줄)"
    else
        bad "$f — 빈 줄 하나에 help 가 잘렸다" "${_before}줄 이상" "${_after}줄"
    fi
done

echo
echo "⑤ [대조군] --help 는 rc=0 이고 무언가를 «찍는다»"
for f in $_targets; do
    _o="$(bash "$f" --help 2>&1)"; _rc=$?
    _l="$(printf '%s' "$_o" | command grep -c '' || true)"; _l="${_l:-0}"
    if [ "$_rc" -eq 0 ] && [ "$_l" -ge 5 ]; then
        ok "$f — rc=0 · ${_l}줄"
    else
        bad "$f — --help 가 rc=$_rc · ${_l}줄" "rc=0 · 5줄 이상" "rc=$_rc · ${_l}줄"
    fi
done

echo
echo "  통과 $pass · 실패 $fail · 판정 불가 $skip"
[ "$fail" -eq 0 ] || exit 1
