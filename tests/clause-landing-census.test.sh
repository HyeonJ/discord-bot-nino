#!/usr/bin/env bash
# clause-landing-census.test.sh — 재조직 PR 의 «규범 착지» 체가 조용히 틀리는 자리를 잰다.
#
# 🔴 왜 생겼나 (2026-08-11, 룬드 `#71` 를 재다가):
#   큰 재조직 PR 은 옮기면서 «다시 쓴다». 그래서 「그 줄이 안 보인다」와
#   「그 규칙이 없어졌다」가 텍스트로 안 갈린다 — 정확 대조는 거짓 양성을,
#   느슨한 대조는 거짓 음성을 낸다. 이 도구는 «증명»이 아니라 «체»이고,
#   체가 조용히 틀리는 자리가 셋이라 여기서 잰다.
#
#   ① 좌변 배타성 — 규범이 「~하면 ~가 된다」(인과형)로 적히면 «어떤» 명령형
#      좌변으로도 안 잡힌다. 둘이 배타적이어야 「둘 다 돌린다」가 값을 한다.
#   ② 부분집합 보존 — «거르고 추출»하면 `**` 짝이 줄을 넘어 조각 «경계»가
#      달라져 좁힌 집합이 넓은 집합의 부분집합이 아니게 된다. 그러면 교집합·잔여가
#      **조용히** 틀린다(실측: 285/81/13 으로 보고했는데 실제는 281/166/22).
#   ③ 빈 코퍼스 — 코퍼스를 못 읽으면 「없음 0」이 아니라 «판정 불가»여야 한다.
#      0 을 「아무것도 안 잃었다」로 읽는 것이 이 도구의 가장 나쁜 실패다.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$SCRIPT_DIR/../tools/clause-landing-census.py"

pass=0; fail=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; [ -n "${2:-}" ] && echo "     want: $2"; [ -n "${3:-}" ] && echo "     got:  $3"; fail=$((fail + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ── 픽스처 ────────────────────────────────────────────────────────────────
# 🔑 손으로 쓴다 — 도구가 만든 픽스처는 같은 결함을 공유해 대조군이 안 된다.
mkdir -p "$TMP/corpus"
cat > "$TMP/old.md" <<'FIX'
# 옛 문서

- 🤝 **분모를 안 적으면 「전부」가 거짓이 된다** — 인과형이고 표지 줄에 있다
- 🤝 **커밋 메시지는 heredoc 으로 적는다** — 명령형이고 표지 줄에 있다
- **재서술되어 살아남는 줄** 은 새 코퍼스에 낱말로 남는다
- **공유되는 조각** 이 여기 먼저 나온다
- 🤝 **공유되는 조각** 이 표지 줄에도 나온다
- 🤝 여는 별표만 있는 줄 **경계가 갈리는
- 표지 없는 사이 줄이 여기 끼어 있다
- 🤝 자리** 로 닫힌다
FIX
cat > "$TMP/corpus/new.md" <<'FIX'
# 새 문서
재서술되어 살아남는 문장이 여기 있고, 낱말은 그대로 쓴다.
FIX

echo "① 좌변 배타성 — 인과형과 명령형이 서로 다른 것을 잡는다:"
st="$(python3 "$TOOL" --selftest 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "--selftest rc=0" || bad "--selftest 가 실패했다" "0" "$rc"
case "$st" in
    *"5/5 통과"*) ok "대조군 5/5 (인과형 원형 3 · 명령형 1 · 서사 1)" ;;
    *)            bad "대조군이 다 안 선다" "5/5 통과" "«${st}»" ;;
esac
case "$st" in
    *"인과형 원형 ①: 인과형=True 지시어미=False"*)
        ok "인과형 원형을 «명령형 좌변이 못 본다»가 실측으로 선다" ;;
    *)  bad "배타성이 안 보인다" "인과형=True 지시어미=False" "«${st}»" ;;
esac

echo
echo "② 부분집합 보존 — 좁힌 집합(🤝)이 넓은 집합의 부분집합이어야 한다:"
python3 "$TOOL" --old "$TMP/old.md" --corpus "$TMP/corpus" --json > "$TMP/full.json"; rc_f=$?
python3 "$TOOL" --old "$TMP/old.md" --corpus "$TMP/corpus" --marker 🤝 --json > "$TMP/mark.json"; rc_m=$?
[ "$rc_f" -eq 0 ] && [ "$rc_m" -eq 0 ] && ok "두 판 다 rc=0" || bad "센서스가 죽었다" "0/0" "$rc_f/$rc_m"

full_n="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["분모_조각"])' "$TMP/full.json")"
mark_n="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["분모_조각"])' "$TMP/mark.json")"
[ "$mark_n" -le "$full_n" ] \
    && ok "🤝 분모 $mark_n ≤ 전체 분모 $full_n" \
    || bad "좁힌 집합이 «더 크다» — 추출기가 둘이다" "mark ≤ full" "$mark_n > $full_n"

# 🔴 회귀의 핵심: 「공유되는 조각」은 표지 «밖»에서 먼저 나온다 ⇒ 좁힌 집합에 있으면 안 된다
# 🔑 subprocess 가 아니라 importlib 로 «그 파일»을 불러 재는 것이 사본을 안 만든다
python3 - "$TOOL" "$TMP/old.md" > "$TMP/subset.txt" <<'PY'
import importlib.util, sys, pathlib
tool, old = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("cl", tool)
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
text = pathlib.Path(old).read_text(encoding="utf-8")
full = m.bold_fragments(text)
mark = m.bold_fragments(text, "🤝")
print("SUBSET" if set(mark) <= set(full) else "BROKEN")
print("SHARED_IN_MARK" if "공유되는 조각" in mark else "SHARED_NOT_IN_MARK")
PY
rc_s=$?
[ "$rc_s" -eq 0 ] && ok "부분집합 프로브가 돌았다" || bad "프로브가 죽었다 — 판정 불가" "0" "$rc_s"
grep -q '^SUBSET$' "$TMP/subset.txt" \
    && ok "🤝 집합 ⊆ 전체 집합 (조각 경계가 같다)" \
    || bad "부분집합이 깨졌다 — «거르고 추출»했다" "SUBSET" "$(head -1 "$TMP/subset.txt")"
grep -q '^SHARED_NOT_IN_MARK$' "$TMP/subset.txt" \
    && ok "첫 등장이 표지 «밖»인 조각은 좁힌 집합에 안 들어온다" \
    || bad "거르기 «전»에 seen 등록이 안 됐다" "SHARED_NOT_IN_MARK" "$(tail -1 "$TMP/subset.txt")"

echo
echo "③ 코퍼스가 비면 «0» 이 아니라 «판정 불가» 다:"
mkdir -p "$TMP/empty"
out="$(python3 "$TOOL" --old "$TMP/old.md" --corpus "$TMP/empty" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && ok "빈 코퍼스 → rc=2 (0 이 아니다)" || bad "빈 코퍼스를 «정상»으로 읽었다" "2" "$rc"
case "$out" in
    *"코퍼스가 비었다"*) ok "사유를 말한다" ;;
    *)                   bad "왜 못 쟀는지 안 말한다" "«코퍼스가 비었다» 포함" "«${out}»" ;;
esac

out="$(python3 "$TOOL" --corpus "$TMP/corpus" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "--old 없이 부르면 rc≠0" || bad "인자가 없는데 조용히 돈다" "rc≠0" "$rc"

echo
echo "통과 $pass · 실패 $fail"
[ "$fail" -eq 0 ]
