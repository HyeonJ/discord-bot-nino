#!/usr/bin/env bash
# scripts/pr-precheck.sh 시험 — gh 를 «주입»해서 진짜 API 를 안 때린다.
set -uo pipefail
S="$(cd "$(dirname "$0")/.." && pwd)/scripts/pr-precheck.sh"
R="$(mktemp -d)"; trap 'rm -rf "$R"' EXIT
pass=0; fail=0
ok(){ echo "  ✅ $1"; pass=$((pass+1)); }
bad(){ echo "  ❌ $1"; echo "     기대: $2"; echo "     실제: $3"; fail=$((fail+1)); }

# 가짜 gh — 호출 argv 를 전부 기록해서 «무엇을 안 불렀나»도 잴 수 있게 한다
mkgh(){
  cat > "$R/gh" <<GHEOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$R/calls"
case "\$*" in
  *"repo view"*)            echo "o/r" ;;
  *"pr list"*)              cat "$R/prlist" ;;
  *"check-runs"*)           cat "$R/checkruns" ;;
  *compare*)                echo "\${COMPARE_N:-1}" ;;
  *"--json commits"*)
      n=\$(printf '%s\n' "\$@" | sed -n '3p')   # gh pr view <N> ... → 3번째
      cat "$R/commits.\$n" 2>/dev/null || echo "" ;;
  *) echo "" ;;
esac
GHEOF
  chmod +x "$R/gh"
}
mkgh
: > "$R/checkruns"; echo "success" > "$R/checkruns"

run(){ GH_BIN="$R/gh" bash "$S" --repo o/r 2>&1; }

echo "── ① 못 재면 «판정 불가»로 시끄럽게 (rc=2) ──"
out="$(GH_BIN="$R/no-such-gh" bash "$S" --repo o/r 2>&1)"; rc=$?
[[ "$rc" -eq 2 ]] && [[ "$out" == *"판정 불가"* ]] && ok "gh 부재 = rc=2 + 판정 불가 표시" \
  || bad "gh 부재" "rc=2 · 판정 불가" "rc=$rc out=$out"

echo "── ② 열린 PR 이 없으면 조용히 rc=0 ──"
: > "$R/prlist"; : > "$R/calls"
out="$(run)"; rc=$?
[[ "$rc" -eq 0 ]] && [[ "$out" == *"열린 PR 없음"* ]] && ok "PR 0건 = rc=0" \
  || bad "PR 0건" "rc=0 · 열린 PR 없음" "rc=$rc out=$out"

echo "── ③ 🔴 순변화는 «compare»(세 점)로 잰다 — pulls/files 는 부푼다 ──"
printf '7\tmain\tbr7\toid7\tMERGEABLE\n' > "$R/prlist"
echo "" > "$R/commits.7"
: > "$R/calls"; out="$(run)"
command grep -q 'compare/main\.\.\.br7' "$R/calls" && ok "compare 로 순변화를 잰다" \
  || bad "compare 미사용" "compare/main...br7 호출" "$(cat "$R/calls")"
# 🔴 대조군 — 오늘 밤 나를 틀리게 한 그 경로를 «안» 부르는지
command grep -q 'pulls/7/files' "$R/calls" \
  && bad "부푸는 좌변 사용" "pulls/<n>/files 미호출" "$(cat "$R/calls")" \
  || ok '대조군: pulls/<n>/files 는 안 부른다'   # 🔴 홑따옴표 — 큰따옴표 안 백틱은 명령치환된다

echo "── ④ 🔴 check-run 이 없으면 「판정불가」다 (빨강 아님·초록 아님) ──"
: > "$R/checkruns"   # 빈 결과 = 런 없음
: > "$R/calls"; out="$(run)"
[[ "$out" == *"판정불가"* ]] && ok "런 없음 = 판정불가" \
  || bad "런 없음을 접었다" "판정불가 표시" "$out"
echo "success" > "$R/checkruns"
out="$(run)"
[[ "$out" == *"success"* ]] && [[ "$out" != *"판정불가"* ]] && ok "대조군: 런 있으면 결론이 그대로" \
  || bad "대조군" "success · 판정불가 없음" "$out"

echo "── ⑤ 🔴 base=main 끼리 «공유 커밋» 을 잡고 «순서»를 낸다 ──"
printf '191\tmain\tbr191\toid191\tMERGEABLE\n192\tmain\tbr192\toid192\tMERGEABLE\n' > "$R/prlist"
echo "ddddddd1111111" > "$R/commits.191"
echo "ddddddd1111111 aaaaaaa2222222 bbbbbbb3333333" > "$R/commits.192"
out="$(run)"
[[ "$out" == *"ddddddd"* ]] && ok "공유 커밋을 찾는다" \
  || bad "공유 미탐지" "ddddddd 언급" "$out"
# 🔑 방향이 값이다 — 커밋 적은 쪽(포함되는 쪽)이 먼저다
[[ "$out" == *"먼저 #191"* ]] && [[ "$out" == *"뒤 #192"* ]] && ok "포함 방향으로 머지 순서를 낸다" \
  || bad "순서 방향" "먼저 #191 · 뒤 #192" "$out"

echo "── ⑥ 대조군 — 공유가 없으면 «없음» 이라고 말한다 ──"
echo "ccccccc9999999" > "$R/commits.191"
out="$(run)"
[[ "$out" == *"없음"* ]] && [[ "$out" != *"공유 —"* ]] && ok "대조군: 공유 없으면 «없음»" \
  || bad "대조군" "«없음» · 공유 줄 없음" "$out"

echo "── ⑦ base 가 main 이 «아닌» PR 은 공유 대조에서 뺀다 (스택은 순서가 이미 명시적) ──"
printf '194\tbr192\tbr194\toid194\tMERGEABLE\n192\tmain\tbr192\toid192\tMERGEABLE\n' > "$R/prlist"
echo "eeeeeee7777777" > "$R/commits.194"; echo "eeeeeee7777777" > "$R/commits.192"
out="$(run)"
[[ "$out" == *"없음"* ]] && ok "스택 PR 은 공유 대조 분모 밖" \
  || bad "스택을 공유로 셌다" "«없음»" "$out"

echo; echo "  통과 $pass · 실패 $fail"
[[ "$fail" -eq 0 ]]
