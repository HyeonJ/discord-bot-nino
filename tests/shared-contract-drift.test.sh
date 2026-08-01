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

echo
echo "  통과 $pass · 실패 $fail"
[ "$fail" -eq 0 ] || exit 1
