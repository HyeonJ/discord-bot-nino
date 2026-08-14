#!/usr/bin/env bash
# delta-measure.sh 계약 — **base↔head 델타를 «같은 온도»에서 잰다**
#
# 왜 이 시험이 생겼나 (2026-08-14, 룬드 `dazebug/assistant#75` 리뷰 재현 중):
#   자기지시 예외 조건 ③(「실패집합·판정 불가·platform 등재를 안 늘린다」)을 재현하려고
#   그의 레포를 클론해 base·head 를 «각각 한 번씩» 돌렸다. 결과:
#       base 1회차  29 / 4 / 0     head  32 / 1 / 0
#   그대로 비교했으면 **「실패 4 → 1, 이 PR 이 개선했다」**를 approve 본문에 적었을 것이다.
#   🔴 문서 두 줄짜리 diff 가 파이썬 시험을 고칠 리 없다 — 그게 걸려서 base 를 «다시» 돌렸고
#   32/1/0 이 나왔다. 첫 회차가 `uv` 가상환경을 만드느라 셋이 같이 죽은 **순서 효과**였다.
#
#   ⚠️ **방향이 비대칭이라 더 나쁘다**: base 를 먼저 돌리는 «흔한 순서»가 head 를 좋아 보이게 한다
#      = **거짓 초록이라 조용하다.** 반대 순서는 시끄러워서 잡힌다.
#
#   🔑 처방을 «계약 한 줄»이 아니라 도구로 옮기는 이유: 같은 날 우리 둘이 **네 번** 밟은 병이
#      *「안 적었다」가 아니라 «적힌 것이 그 순간에 안 열린다»* 였다. 또 적으면 또 안 열린다.
#
# 격리: 진짜 러너를 안 쓴다(`--cmd` 로 가짜를 주입). git 도 안 건드린다(`--no-checkout`).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$BOT/scripts/delta-measure.sh"

pass=0; fail=0; skip=0
ok()   { echo "  ✅ $1"; pass=$((pass + 1)); }
# 🔴 «두 꼴»을 받는다: bad "설명" "출력"  ·  bad "설명" "기대" "실제"
#   옛 판은 `$3` 을 «안 읽어서** 3인자 호출 9곳의 «실제값»이 통째로 버려졌다. 더 나빴던 건
#   `$2`(기대값)를 출력인 양 찍어서 — `bad "rc" "2" "$rc"` 가 rc=7 일 때도 화면에 `2` 를 냈다.
#   그건 «통과 조건»이라 읽는 사람이 「맞는데 왜 빨갛지」로 간다.
#   🔑 **초록일 때는 이 결함이 절대 안 보인다** — 빨개지는 순간에만 드러나는데
#     그 순간이 정보가 가장 필요한 순간이다(룬드 `#218` 리뷰 ②).
bad()  {
  echo "  ❌ $1"; fail=$((fail + 1))
  if [ "$#" -ge 3 ]; then
    printf '     기대: %s\n     실제: %s\n' "$2" "$3"
  elif [ -n "${2:-}" ]; then
    printf '%s\n' "$2" | sed 's/^/     /'
  fi
}
und()  { echo "  ⛔ $1"; skip=$((skip + 1)); }

[ -f "$SCRIPT" ] || { echo "❌ 없음: $SCRIPT"; exit 1; }
ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT

# 가짜 러너 — 호출 «순서»대로 SCRIPTED 파일의 줄을 하나씩 낸다.
#   🔑 각 줄이 한 회차의 요약이다: `통과|실패수|실패집합|판불`
#   ⇒ 「같은 ref 를 두 번 돌리면 다른 값」을 **재현할 수 있는 유일한 모양**이다.
#     ref 로 답을 정하는 스텁을 쓰면 «온도»가 원리적으로 표현이 안 된다(그게 이 시험의 주제다).
cat > "$ROOT/fake-runner.sh" <<'FAKE'
#!/usr/bin/env bash
n=$(cat "$FAKE_N" 2>/dev/null || echo 0); n=$((n + 1)); printf '%s\n' "$n" > "$FAKE_N"
line="$(sed -n "${n}p" "$FAKE_SCRIPTED")"
[ -n "$line" ] || { echo "스텁 소진(회차 $n)"; exit 9; }
IFS='|' read -r p f fset u <<EOF
$line
EOF
echo "── 결과: 통과 $p · 실패 $f · 판정 불가 $u"
[ -n "$fset" ] && echo "   실패: $fset"
[ "$u" -gt 0 ] && echo "   판정 불가:"
[ "$f" -eq 0 ] && exit 0 || exit 1
FAKE
chmod +x "$ROOT/fake-runner.sh"

scripted() { printf '%s\n' "$@" > "$ROOT/scripted.txt"; : > "$ROOT/n.txt"; }
runs()     { local n; n="$(cat "$ROOT/n.txt" 2>/dev/null)"; printf '%s\n' "${n:-0}"; }
run() {
  FAKE_SCRIPTED="$ROOT/scripted.txt" FAKE_N="$ROOT/n.txt" \
  bash "$SCRIPT" --no-checkout --base BASE --head HEAD \
       --cmd "bash $ROOT/fake-runner.sh" --platform-base "$1" --platform-head "$2" 2>&1
}

# 🔑 **계측기를 먼저 먹인다** — 정답을 아는 입력으로 «가짜 러너 자신»을 검사한다.
#   (memory-lint-cron 시험에서 얻은 규칙: 대상만 검사하는 시험은 자기 오류를 못 본다)
scripted "10|0||0"
h="$(FAKE_SCRIPTED="$ROOT/scripted.txt" FAKE_N="$ROOT/n.txt" bash "$ROOT/fake-runner.sh")"
if printf '%s\n' "$h" | grep -qx '── 결과: 통과 10 · 실패 0 · 판정 불가 0'; then
  ok "하네스 자기검사 — 요약 줄이 러너 정본 형식과 «글자까지» 같다"
else
  bad "하네스 자기검사 — 요약 줄 형식이 다르다(도구가 못 읽으면 시험이 대상을 안 잰다)" "$h"
fi

# 🔴 **`bad()` 자신도 검사한다** — 이 결함은 «초록일 때» 절대 안 보인다.
#   서브셸에서 부르므로 `fail` 카운터는 안 올라간다.
hb="$( bad "자기검사(무시)" "2" "7" 2>&1 )"
if printf '%s\n' "$hb" | grep -q '실제: 7' && printf '%s\n' "$hb" | grep -q '기대: 2'; then
  ok "하네스 자기검사 — bad() 3인자에서 «기대와 실제가 둘 다» 찍힌다"
else
  bad "하네스 자기검사 — bad() 가 실제값을 버린다(빨간 순간에 정보가 사라진다)" "$hb"
fi
hb2="$( bad "자기검사(무시)" "출력본문" 2>&1 )"
if printf '%s\n' "$hb2" | grep -q '출력본문'; then
  ok "하네스 자기검사 — bad() 2인자 옛 꼴도 그대로 산다(①~⑥이 쓴다)"
else
  bad "하네스 자기검사 — 2인자 호환이 깨졌다" "$hb2"
fi

echo
echo "① 델타 0 이면 rc=0 — base·head 가 같다"
scripted "32|1|calendar-tool|0" "32|1|calendar-tool|0"
out="$(run 1 1)"; rc=$?
[ "$rc" -eq 0 ] && ok "rc=0" || bad "rc=$rc" "$out"
printf '%s\n' "$out" | grep -q '델타 0' && ok "「델타 0」이라 말한다" || bad "델타 0 을 안 말한다" "$out"
# 🔑 **회차 수를 잰다** — 델타가 0 이면 base 재실행은 «낭비»다(러너는 분 단위다).
[ "$(runs)" -eq 2 ] && ok "🔑 회차 2 — 델타 0 이면 base 를 다시 안 돌린다(비용)" \
                    || bad "회차가 2가 아니다 — 불필요한 재실행" "회차=$(runs)"

echo
echo "② 🔴 **온도 오염** — base 1회차만 나쁘다. 그대로 비교하면 «개선»으로 읽힌다"
# 실물 재현: base(냉) 29/4 → head 32/1 → base(온) 32/1
scripted "29|4|alarm calendar deco mail|0" "32|1|calendar-tool|0" "32|1|calendar-tool|0" "32|1|calendar-tool|0"
out="$(run 1 1)"; rc=$?
[ "$(runs)" -eq 4 ] && ok "🔑 델타가 «있어» 보이면 base·head 를 «둘 다» 다시 돌린다 (회차 4)" \
                    || bad "재실행이 빠졌다 — 오염·흔들림을 못 가른다" "회차=$(runs)"
printf '%s\n' "$out" | grep -qx 'DELTA_VERDICT=warm-contaminated' \
  && ok "🔴 표지가 «warm-contaminated» 다" \
  || bad "🔴 오염을 통과시켰다 — 이 도구의 존재 이유가 그 자리다" "$out"
[ "$rc" -eq 0 ] && ok "  → 2회차 base 를 좌변으로 삼아 델타 0 ⇒ rc=0" || bad "rc=$rc" "$out"
# 🔴 **좌변을 «산문»으로 두지 않는다 — 설명문에 반대말이 섞인다.** 이 시험의 첫 판이
#   `grep -q '온도 오염'` 이었는데 도구의 *「온도 오염«이 아니라» 진짜 변화다」*에 걸려
#   **옳은 구현을 빨갛게** 만들었다. 그래서 `DELTA_VERDICT=` 표지를 만들고 그것만 문다.
printf '%s\n' "$out" | grep -qx 'DELTA_VERDICT=clean' \
  && bad "🔴 좌변을 base 1회차로 삼아 «깨끗하다»고 했다 — 오염을 못 봤다" "$out" \
  || ok "  → 오염을 「깨끗함」으로 접지 않는다"

echo
echo "③ 진짜 델타(실패 늘어남)는 «오염이 아니라»고 가려준다"
scripted "32|1|calendar-tool|0" "31|2|calendar-tool newly-broken|0" "32|1|calendar-tool|0" "31|2|calendar-tool newly-broken|0"
out="$(run 1 1)"; rc=$?
[ "$rc" -eq 1 ] && ok "rc=1 (진짜 회귀)" || bad "rc=$rc — 회귀를 통과시켰다" "$out"
printf '%s\n' "$out" | grep -q 'newly-broken' && ok "  → 늘어난 항목을 이름으로 짚는다" \
  || bad "  → 무엇이 늘었는지 안 말한다" "$out"
printf '%s\n' "$out" | grep -qx 'DELTA_VERDICT=real' \
  && ok "🔑 base 두 회차가 «같으니» 표지가 «real» — 오염이 아니라고 가른다" \
  || bad "🔴 진짜 회귀를 «오염»으로 접었다 — 반대 방향 오탐" "$out"

echo
echo "③-b 🧪 ③의 «양성» — 같은 입력에서 base 2회차만 흔들면 오염으로 뒤집힌다"
# 🔑 없으면 ③은 항진명제다(어떤 구현이든 '온도 오염' 을 안 찍기만 하면 통과한다).
scripted "32|1|calendar-tool|0" "31|2|calendar-tool newly-broken|0" "31|2|calendar-tool newly-broken|0" "31|2|calendar-tool newly-broken|0"
out="$(run 1 1)"; rc=$?
printf '%s\n' "$out" | grep -qx 'DELTA_VERDICT=warm-contaminated' \
  && ok "🧪 base 2회차가 head 와 같아지면 표지가 뒤집힌다 — ③은 항진명제가 아니다" \
  || bad "🧪 뒤집히지 않는다 — ③이 아무것도 안 재고 있었다" "$out"
[ "$rc" -eq 0 ] && ok "  → 오염 판정 뒤 델타 0 ⇒ rc=0" || bad "rc=$rc" "$out"

echo
echo "④ 🔴 판정 불가는 «0 으로 접지» 않는다 — rc=2"
scripted "쓰레기" "쓰레기"
out="$(run 1 1)"; rc=$?
[ "$rc" -eq 2 ] && ok "요약 줄을 못 읽으면 rc=2" || bad "rc=$rc — 못 읽었는데 판정했다" "$out"
printf '%s\n' "$out" | grep -q '판정 불가' && ok "  → 사유를 말한다" || bad "  → 조용히 접었다" "$out"

echo
echo "⑤ platform 등재는 «러너 밖»이라 따로 받는다 — 늘면 rc=1"
scripted "32|1|calendar-tool|0" "32|1|calendar-tool|0"
out="$(run 1 2)"; rc=$?
[ "$rc" -eq 1 ] && ok "platform 0→1 이면 rc=1" || bad "rc=$rc — platform 증가를 놓쳤다" "$out"
printf '%s\n' "$out" | grep -q 'platform' && ok "  → platform 축을 이름으로 짚는다" \
  || bad "  → 어느 축인지 안 말한다" "$out"
# 🔴 **platform 은 판불보다 «센 하수구»다** — 「영구·줄지 않는다」라 한 방향으로만 자란다.
#   그래서 러너 델타가 0 이어도 이 축 하나로 빨강이 되어야 한다.
scripted "32|1|calendar-tool|0" "32|1|calendar-tool|0"
out="$(run 2 1)"; rc=$?
[ "$rc" -eq 0 ] && ok "🔑 platform 이 «줄면» 막지 않는다 (조건은 「안 늘린다」다)" || bad "rc=$rc" "$out"

echo
echo "⑥ 판정 불가 증가도 잡는다 — 「실패를 판불로 밀기」가 여기서 막힌다"
# 🔸 델타가 «있어» 보이므로 도구가 base 를 다시 돌린다 ⇒ 스텁도 3회차를 줘야 한다.
scripted "32|1|calendar-tool|0" "31|0||2" "32|1|calendar-tool|0" "31|0||2"
out="$(run 1 1)"; rc=$?
[ "$rc" -eq 1 ] && ok "실패 1→0 인데 판불 0→2 면 rc=1" || bad "rc=$rc — 실패를 판불로 민 것을 통과시켰다" "$out"

echo
echo "⑦ 🔴 head 도 «두 번» 잰다 — 한쪽만 두 번 재면 나머지 흔들림이 «진짜»로 승격된다"
# 🔴 첫 실사용에서 밟았다(2026-08-14, `#219` 델타): head 가 «한 회차»에만 `mdweb-link-guard` 로
#   빨갰고 base 두 회차는 깨끗해서 이 도구가 `real` 을 냈다. head 를 두 번 더 재니 둘 다 깨끗했다
#   — 원격 의존(live md-web)이 그 회차에만 흔들린 것이다.
# 🔑 옛 판은 «base 가 차가웠나»만 물었다. 그건 대칭이 아니다.
# 회차: base① → head① → base② → head②
scripted "32|1|calendar-tool|0" "31|2|calendar-tool flaky-one|0" "32|1|calendar-tool|0" "32|1|calendar-tool|0"
out="$(run 1 1)"; rc=$?
printf '%s\n' "$out" | grep -qx 'DELTA_VERDICT=flaky-head' \
  && ok "🔴 head 두 회차가 다르면 표지가 «flaky-head»" \
  || bad "🔴 흔들림을 «진짜 회귀»로 승격시켰다 — 이 절이 생긴 실물이 그 자리다" "$out"
[ "$rc" -eq 2 ] && ok "  → rc=2 (real 도 clean 도 아니다 — 못 쟀다)" || bad "⑦ flaky-head 는 rc=2 여야 한다" "2" "$rc"
[ "$(runs)" -eq 4 ] && ok "  → 회차 4 (base 둘 · head 둘)" || bad "⑦ 회차는 4 여야 한다 (base 둘 · head 둘)" "4" "$(runs)"
printf '%s\n' "$out" | grep -q 'flaky-one' && ok "  → 흔들린 항목을 이름으로 짚는다" \
  || bad "항목 미표시" "flaky-one" "$out"

# 🧪 ⑦의 «양성» — head 두 회차가 «같으면» 그대로 real 이다(⑦이 real 을 통째로 삼키지 않는다)
scripted "32|1|calendar-tool|0" "31|2|calendar-tool newly-broken|0" "32|1|calendar-tool|0" "31|2|calendar-tool newly-broken|0"
out="$(run 1 1)"; rc=$?
printf '%s\n' "$out" | grep -qx 'DELTA_VERDICT=real' \
  && ok "🧪 head 가 «안정적으로» 나쁘면 여전히 real — 회귀 탐지가 안 죽었다" \
  || bad "🧪 real 을 삼켰다 — 수리가 원래 기능을 껐다" "$out"
[ "$rc" -eq 1 ] && ok "  → rc=1" || bad "⑦양성 진짜 델타는 rc=1 이어야 한다" "1" "$rc"

echo
echo "⑧ 🔴 checkout 안전 — 시험이 여태 «이 경로를 통째로» 안 봤다(전부 --no-checkout 이었다)"
# 🔑 결함 둘이 여기 살아 있었다: ①원래 ref 를 안 되돌린다 ②더러운 트리를 안 본다.
#   ⚠️ 되돌리기는 예의가 아니라 «안전»이다 — 내 크론이 작업트리의 `scripts/check-auth.sh` 를
#     직접 읽어서, ref 를 옮기는 동안 **운영이 같이 옮겨 다닌다**(2026-08-14 실물).
GR="$ROOT/gitrepo"; mkdir -p "$GR"
( cd "$GR" && git init -q -b main && git config user.email t@t && git config user.name t \
  && echo base > f.txt && git add f.txt && git commit -q -m base \
  && git checkout -q -b feat && echo head > f.txt && git commit -q -am head \
  && git checkout -q main ) >/dev/null 2>&1
if [ -d "$GR/.git" ]; then
  grun() {   # 진짜 레포에서 checkout 모드로 돈다
    FAKE_SCRIPTED="$ROOT/scripted.txt" FAKE_N="$ROOT/n.txt" \
    bash "$SCRIPT" --repo-dir "$GR" --base main --head feat \
         --cmd "bash $ROOT/fake-runner.sh" 2>&1
  }
  scripted "32|1|calendar-tool|0" "32|1|calendar-tool|0"
  out="$(grun)"; rc=$?
  now="$( cd "$GR" && git symbolic-ref -q --short HEAD || echo '<detached>' )"
  [ "$now" = main ] && ok "🔴 끝나면 «원래 ref»로 돌아온다 (main)" \
    || bad "ref 를 안 되돌렸다 — 작업트리를 가리키는 크론·서비스가 같이 끌려다닌다" "main" "$now"
  [ "$rc" -eq 0 ] && ok "  → 그러면서 판정은 정상으로 낸다 (rc=0)" || bad "⑧ ref 복귀 뒤 판정은 rc=0 이어야 한다" "0" "$rc"

  # 🔴 더러운 트리 — checkout 이 덮거나 거부한다. «시작하기 전에» 막는다
  ( cd "$GR" && echo dirty >> f.txt )
  scripted "32|1|calendar-tool|0" "32|1|calendar-tool|0"
  out="$(grun)"; rc=$?
  [ "$rc" -eq 2 ] && ok "🔴 커밋 안 된 수정이 있으면 rc=2 로 «시작을 거절»한다" \
    || bad "더러운 트리에서 그냥 돌았다" "rc=2" "rc=$rc"
  [ "$(runs)" -eq 0 ] && ok "  🔑 거절이면 러너를 «한 번도» 안 돌린다 (부작용 0)" \
    || bad "거절인데 돌았다" "0회" "$(runs)회"
  printf '%s\n' "$out" | grep -q 'f.txt' && ok "  → 무엇이 더러운지 이름으로 짚는다" \
    || bad "파일명 미표시" "f.txt" "$out"
  ( cd "$GR" && git checkout -q -- f.txt )
else
  und "git 레포 픽스처를 못 세웠다 — checkout 축을 못 쟀다(0 으로 접지 않는다)"
  und "  (같은 이유로 더러운 트리 축도 못 쟀다)"
fi

echo
echo "⑨ 🔴 --no-checkout 의 「델타 0」은 «안 늘었다»가 아니라 «안 갈랐다» — 표지가 말해야 한다"
# 🔴 룬드 `#218` 리뷰 ①: 같은 인자에 «플래그 하나만» 더하면 빨강이 초록으로 뒤집히는데
#   출력에도 표지에도 그 사실이 없었다. 「없다」와 「0」을 접는 것과 같은 병이고,
#   이 도구 머리말이 그 병을 «자기 논거로» 적어두고 있었다.
# 🔑 좌변은 «트리 내용»으로 답을 정하는 러너다 — 회차 스텁으로는 «ref 를 갈랐나»를 원리적으로 못 잰다.
cat > "$ROOT/tree-runner.sh" <<'TR'
#!/usr/bin/env bash
c="$(cat f.txt 2>/dev/null || echo none)"
if [ "$c" = head ]; then
  echo "── 결과: 통과 31 · 실패 2 · 판정 불가 0"
  echo "   실패: calendar-tool broken-by-head"
else
  echo "── 결과: 통과 32 · 실패 1 · 판정 불가 0"
  echo "   실패: calendar-tool"
fi
TR
chmod +x "$ROOT/tree-runner.sh"

GR2="$ROOT/repo2"
( mkdir -p "$GR2" && cd "$GR2" && git init -q -b main \
  && git config user.email t@t && git config user.name t \
  && echo base > f.txt && git add f.txt && git commit -q -m base \
  && git checkout -q -b feat && echo head > f.txt && git commit -q -am head \
  && git checkout -q main ) >/dev/null 2>&1

if [ -d "$GR2/.git" ]; then
  trun() { bash "$SCRIPT" --repo-dir "$GR2" --base main --head feat \
                --cmd "bash $ROOT/tree-runner.sh" "$@" 2>&1; }

  outA="$(trun)"; rcA=$?
  outB="$(trun --no-checkout)"; rcB=$?

  # ⓐ 진짜로 갈랐을 때 — 델타가 «보여야» 한다 (이 절이 항진명제가 아니라는 양성 대조군)
  [ "$rcA" -eq 1 ] && ok "🧪 ⓐ checkout 모드는 진짜 델타를 본다 (rc=1)" \
    || bad "⑨ⓐ checkout 모드에서 델타를 못 봤다 — 이 절의 대조군이 죽는다" "1" "$rcA"
  printf '%s\n' "$outA" | grep -qx 'DELTA_SCOPE=ref' \
    && ok "  → 표지 DELTA_SCOPE=ref" || bad "⑨ⓐ 범위 표지" "DELTA_SCOPE=ref" "$outA"

  # ⓑ 플래그 하나로 초록이 된다 — 그런데 «그 사실이 표지에 있다»
  [ "$rcB" -eq 0 ] && ok "ⓑ --no-checkout 은 같은 트리라 델타가 0 이다 (rc=0)" \
    || bad "⑨ⓑ rc" "0" "$rcB"
  printf '%s\n' "$outB" | grep -qx 'DELTA_SCOPE=no-checkout' \
    && ok "🔴 → 표지가 «안 갈랐다»를 말한다 (DELTA_SCOPE=no-checkout)" \
    || bad "⑨ⓑ 범위 표지가 침묵한다 — clean 이 「안 늘었다」로 읽힌다" "DELTA_SCOPE=no-checkout" "$outB"
  printf '%s\n' "$outB" | grep -q '안 갈랐다' \
    && ok "  → 산문에도 말한다 (표지만 고치면 산문 읽는 사람은 계속 속는다)" \
    || bad "⑨ⓑ 산문 미표시" "「안 갈랐다」 문구" "$outB"

  # 🔑 **이 절의 핵심 좌변** — 두 판정이 «같은 필드»로 구별 가능한가
  sA="$(printf '%s\n' "$outA" | sed -n 's/^DELTA_SCOPE=//p')"
  sB="$(printf '%s\n' "$outB" | sed -n 's/^DELTA_SCOPE=//p')"
  [ -n "$sA" ] && [ -n "$sB" ] && [ "$sA" != "$sB" ] \
    && ok "🔑 플래그가 판정을 뒤집을 때 «범위 표지»도 같이 갈린다 — 인용하는 쪽이 그 자리에서 갈 수 있다" \
    || bad "⑨ 범위가 두 모드에서 구별되지 않는다" "서로 다른 값" "ⓐ=$sA ⓑ=$sB"
else
  und "⑨ git 픽스처를 못 세웠다 — 범위 표지 축을 못 쟀다(0 으로 접지 않는다)"
fi

echo
printf '  통과 %d · 실패 %d · 판정 불가 %d\n' "$pass" "$fail" "$skip"
[ "$fail" -gt 0 ] && exit 1
[ "$skip" -gt 0 ] && exit 2
exit 0
