#!/usr/bin/env bash
# model-names-single-source.test.sh — 모델 id 사본이 «둘 이상» 생기는 걸 막는다.
#
# 🔴 왜 생겼나 (2026-08-10 실측): `claude-sonnet-4-6` 이 `scripts/vault-append.sh` 와
#   `scripts/vault-audit-llm.sh` 에 «따로» 박혀 있었다. 사본이 둘이면 한쪽만 고쳐지고
#   다른 쪽이 조용히 낡는다. 🔑 그리고 그 지적은 이미 적혀 있었다
#   (`memory/ref_yaksu_marketplace.md:86` 이 이 위치를 지목) — **적어둔 것과 도구가
#   잡는 것은 다르다.** 적힌 채로 방치돼 있던 걸 도구로 내린다.
#
# 🔑 이 시험이 «잠그는 것»과 «못 잠그는 것»을 갈라 적는다:
#   ✅ 잠근다   — 값이 «한 곳»에 사는가 (정적, 러너에서 잴 수 있다)
#   ⛔ 못 잠근다 — 그 한 곳이 «최신»인가 (조회라 CI 에선 판정 불가가 된다)
#   ⇒ 후자를 시험에 넣으면 상시 판정 불가가 되고 그 판불이 다음 PR 을 막는다.
#      대신 세대가 바뀔 때 «고칠 자리가 하나»인 것이 이 시험의 값이다.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_REL="config/models.sh"
pass=0; fail=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; [ -n "${2:-}" ] && echo "     want: ${2}"; [ -n "${3:-}" ] && echo "     got:  ${3}"; fail=$((fail + 1)); }

[ -f "$ROOT/$SRC_REL" ] || { echo "⛔ 판정 불가 — 단일 출처가 없다: $SRC_REL"; exit 2; }

echo "🧬 모델 id — 값이 한 곳에 사는가"

# 🔴 분모를 «열거»하지 않는다 — 열거로 적으면 열거 밖이 남는다(오늘만 세 번째 실물).
#   추적되는 셸 스크립트 «전부»가 분모다. git 이 없으면 조용히 좁히지 말고 판정 불가로 떨어진다.
if ! command -v git >/dev/null 2>&1 || ! git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    echo "⛔ 판정 불가 — git 이 없어 «추적되는 파일»을 못 센다 (find 로 좁히면 분모가 조용히 달라진다)"
    exit 2
fi
# 🔴 분모는 **추적되는 파일 전부**다. `'*.sh'` 로 좁혔던 게 카브아웃이었다 —
#   추적 327 중 93(28.4%)만 보고 있었고, 남은 리터럴 9건 중 `.sh` 는 0건이라 **미탐 100%**였다.
#   실물: 이 PR 이 «고치는» `CLAUDE.md` 자신이 분모 밖이었다(룬드 리뷰 `#155`).
#   🔑 확장자로 좁히는 것도 열거다 — 「셸에만 박힌다」가 전제인데 그 전제가 틀렸다.
# ⚠️ `mapfile` 은 bash 4+ 다 — 룬드 맥(3.2)에서 죽는다. while-read 로 담는다.
FILES=()
while IFS= read -r _f; do FILES+=("$_f"); done < <(git -C "$ROOT" ls-files)
[ "${#FILES[@]}" -gt 0 ] || { echo "⛔ 판정 불가 — 추적되는 파일을 하나도 못 찾았다"; exit 2; }
ok "분모: 추적되는 파일 ${#FILES[@]}개 «전부» (확장자로도 안 좁힌다 — 그것도 열거다)"

# 판별식: `--model` 뒤에 «리터럴 모델 id»가 오는 자리. 변수(`"$NINO_MODEL_…"`)는 통과.
detect() {  # $1=루트  $2…=파일들 → 위반 줄을 출력
    local root="$1"; shift
    local f
    for f in "$@"; do
        [ "$f" = "$SRC_REL" ] && continue          # 단일 출처 자신은 «정의하는 자리»다
        [ -f "$root/$f" ] || continue
        LC_ALL=C grep -InE -- '--model[= ]+["'"'"']?claude-[a-z0-9-]+' "$root/$f" 2>/dev/null \
            | grep -v '^[0-9]*: *#' | sed "s#^#${f}:#"
    done
}

# 🔑 안전형 확장 — bash 3.2 + `set -u` 는 «빈 배열»의 맨 `${a[@]}` 에서 죽는다.
#   위 개수 검사가 있어도 «형태»가 남으면 portability 가드가 잡는다(그게 맞다 — 형태로 잰다).
VIOL="$(detect "$ROOT" "${FILES[@]+"${FILES[@]}"}")"
if [ -z "$VIOL" ]; then
    ok "--model 에 리터럴 모델 id 를 박은 추적 파일이 없다"
else
    bad "모델 id 사본이 있다 — 한쪽만 고쳐지고 다른 쪽이 조용히 낡는다" \
        "0건 (config/models.sh 를 source 해서 \$NINO_MODEL_* 사용)" "$(printf '%s' "$VIOL" | tr '\n' ' ')"
fi

# 🧪 대조군 — 위 0 이 «없어서»인지 «판별식이 눈이 먼 것»인지 가른다.
#   없으면 detect 를 `true` 로 바꿔도 초록이다.
_t="$(mktemp -d)"; trap 'rm -rf "$_t"' EXIT
mkdir -p "$_t/scripts"
# 🔑 미끼를 «리터럴로 안 적는다» — 적으면 이 파일이 자기 판별식에 걸린다.
#   카브아웃(이 파일 제외)으로 풀면 **분모가 깎이고**, 그게 이 시험이 막으려는 바로 그 병이다.
#   실물: `shared-contract-drift.test.sh:291` 은 주석 표식으로 풀었는데, 조립이 더 낫다.
printf 'claude -p x --model claude-%s-4-6 --dangerously-skip-permissions\n' sonnet > "$_t/scripts/violator.sh"
[ -n "$(detect "$_t" scripts/violator.sh)" ] \
  && ok "[대조군] 리터럴을 박으면 잡힌다" \
  || bad "[대조군] 판별식이 리터럴을 못 잡는다 — 위 0건은 못 믿는다" "1건 이상" "0건"

# 🔴 오탐 대조군 — 변수로 쓴 자리를 «잡으면» 안 된다. 잡으면 올바른 형태가 빨개져서
#   다음 사람이 시험을 끄거나 리터럴로 되돌린다.
printf 'claude -p x --model "$NINO_MODEL_SONNET" --dangerously-skip-permissions\n' > "$_t/scripts/good.sh"
[ -z "$(detect "$_t" scripts/good.sh)" ] \
  && ok "[오탐 대조군] 변수로 쓴 자리는 안 잡는다" \
  || bad "올바른 형태를 빨갛게 만든다 (오탐)" "0건" "$(detect "$_t" scripts/good.sh)"

# ── 🕳️ 유예 목록 — 「지금 안 고치기로 한 것」이 «PR 본문»이 아니라 «시험 출력»에 산다.
#   본문은 머지되면 사실상 조회 불가고, 여기 있으면 **매 실행마다 보인다**(`.gitignore` 에서 얻은 형태).
#   여기 실린 것은 판별식이 «구조적으로 못 보는» 자리다 — `--model` 접두가 없어서(`return "claude-…"`)
#   분모를 아무리 넓혀도 안 걸린다. ⇒ 분모 확장으로는 못 닫히는 구멍이라 «선언»으로 남긴다.
#
#   ⚠️ 좌변을 붙인다 — 항목이 **아직 실재하는가**를 매번 재고, 사라졌으면 「지웠어야 한다」로 빨개진다.
#      좌변 없는 유예 목록은 조용히 낡아서 **「고쳤는데 목록에 남은 것」과 구별이 안 된다.**
echo
echo "🕳️ 유예 — 판별식이 못 보는 자리(선언으로 남긴다)"
# 🔑 구분자로 «쪼개지» 않는다 — 정규식에 `|` 가 들어가서 `IFS='|' read` 가 패턴을 반토막 냈다
#   (`claude-(opus` 로 잘려 grep 이 오류를 내고 0줄이 됐다). 인자 셋짜리 함수면 그 축이 없다.
deferred() {  # $1=경로 $2=정규식 $3=사유
    local df="$1" dpat="$2" dwhy="$3" dn
    if ! git -C "$ROOT" ls-files --error-unmatch "$df" >/dev/null 2>&1; then
        bad "유예 항목의 파일이 추적에 없다 — 경로가 낡았다: $df" "추적됨" "없음"; return
    fi
    dn="$(LC_ALL=C grep -IcE -- "$dpat" "$ROOT/$df" 2>/dev/null || true)"
    if [ "${dn:-0}" -ge 1 ]; then
        ok "유예 ${df} (${dn}줄) — ${dwhy}"
    else
        bad "유예 항목이 이제 안 걸린다 — 목록에서 지웠어야 한다: $df" "1줄 이상" "0줄"
    fi
}
deferred src/bot.py 'claude-(opus|sonnet|haiku)-[0-9a-z-]+' \
    'Ⅲ 대기 — 이 파일을 지울지가 Darren 판단이다. 판별식도 못 본다(`return "claude-…"` 라 --model 접두가 없다)'
deferred src/botctl.py 'Claude Opus [0-9.]+' \
    '산문형 표시 이름(모델 id 아님). bot.py 와 «한 묶음»으로 Darren 께 물었다 — 따로 물으면 이 산문형이 남는다'
deferred config/bots.json 'Claude Opus [0-9.]+' '위와 같음'
deferred claude-config/skills/agent-browser/SKILL.md 'claude-sonnet-4\.6' \
    '스킬 게이트웨이의 «다른 이름 공간» — config/models.sh 와 같은 값이 아니다'

# 🧪 대조군 — 유예 검사가 «낡음»에 실제로 반응하나. 없으면 위 초록 넷은 장식이고,
#   항목을 고친 뒤 목록에 남겨둬도 아무도 안 알려준다. 셈은 되돌린다(대조군은 계약이 아니다).
_p0=$pass; _f0=$fail
deferred config/models.sh 'zz절대없는패턴zz' '대조군' >/dev/null 2>&1
if [ "$fail" -gt "$_f0" ]; then
    pass=$_p0; fail=$_f0
    ok "[대조군] 유예 항목이 낡으면 실제로 빨개진다 (목록이 장식이 아니다)"
else
    pass=$_p0; fail=$_f0
    bad "[대조군] 유예 검사가 낡음에 반응 안 한다 — 위 초록 넷은 못 믿는다" "빨강" "초록"
fi

# ── 단일 출처가 «실제로 값을 싣는가». 이름만 있고 빈 값이면 `--model ""` 이 나간다.
echo
echo "🧬 단일 출처가 값을 싣는가"
for v in NINO_MODEL_OPUS NINO_MODEL_SONNET NINO_MODEL_HAIKU; do
    got="$(env -u NINO_MODEL_OPUS -u NINO_MODEL_SONNET -u NINO_MODEL_HAIKU \
           bash -uc ". '$ROOT/$SRC_REL'; printf '%s' \"\${$v}\"" 2>/dev/null)"
    [ -n "$got" ] && ok "$v = $got" || bad "$v 가 비어 있다 — \`--model \"\"\` 이 나간다" "비지 않음" "빈 값"
done

# ── source 하는 쪽이 «실제로» 그 파일을 집는가 (경로 배선).
echo
echo "🔗 소비자가 단일 출처에 닿는가"
consumers="$(grep -lE '\$NINO_MODEL_' -r "$ROOT/scripts" 2>/dev/null | sed "s#^$ROOT/##" | sort)"
[ -n "$consumers" ] || { echo "⛔ 판정 불가 — \$NINO_MODEL_* 를 쓰는 스크립트가 하나도 없다"; exit 2; }
for c in $consumers; do
    grep -q "$SRC_REL" "$ROOT/$c" \
      && ok "$c 가 $SRC_REL 를 source 한다" \
      || bad "$c 가 \$NINO_MODEL_* 를 쓰는데 단일 출처를 안 부른다 — 미설정으로 빈 값이 나간다" \
             "$SRC_REL source" "없음"
done

echo
echo "  통과 $pass · 실패 $fail"
[ "$fail" -eq 0 ]
