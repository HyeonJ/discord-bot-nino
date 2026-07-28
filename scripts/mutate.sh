#!/usr/bin/env bash
# mutate.sh — 변이 하나를 안전하게 넣었다 빼고, 시험이 그걸 잡는지 판정한다
#
# 왜 도구로 만들었나:
#   변이시험 절차 자체는 세 줄이다 — 고친 줄을 되돌린다 / 시험을 돌린다 / 되돌린 걸 복구한다.
#   문제는 마지막 복구를 `git checkout` 으로 한다는 것. **기준선이 커밋돼 있지 않으면
#   되돌리기가 내 수정까지 지운다.** 2026-07-28 하루에 니노가 세 번, 룬드가 한 번 밟았다.
#   메모를 적고 서로 알려준 뒤에도 또 밟았다 ⇒ 규칙을 아는 것과 손이 그렇게 움직이는 건
#   다른 일이다. 그래서 **판단을 없애는 게 아니라 옮긴다** — 사람이 기억하는 대신 도구가 막는다.
#
#   단, 옮긴 판단은 옮긴 자리에서 다시 검증해야 한다. 오늘 본 사고의 대부분이 *안전망이
#   조용히 안 도는 것*이었으므로(몇 달째 죽어 있던 훅 · 발동 0건 데몬 · 아무도 안 읽던
#   하트비트), tests/mutate.test.sh 는 "거부한다"가 아니라 **"거부하면서 시험 명령을
#   실제로 실행하지 않는다"**와 **"미커밋 수정이 그대로 남아 있다"**를 값으로 잰다.
#
# 사용법:
#   scripts/mutate.sh --file <경로> --old <원본문자열> --new <바꿀문자열> \
#                     --test <시험명령> [--name <변이이름>]
#
# 종료코드 — 세 상태를 접지 않는다(check-core-drift.sh 와 같은 계약):
#   0  잡힘     — 변이를 넣으니 시험이 빨개졌다. 그 줄은 실제로 지켜지고 있다.
#   1  살아남음 — 변이를 넣었는데도 초록. 구멍이거나 등가변이다. **왜 등가인지까지 적을 것.**
#   3  판정 불가 — 아예 재지 못했다(미커밋 · 주입 MISS · 다중 매치 · 미추적).
#      ⚠️ 3을 1로 접으면 "못 쟀다"가 "구멍 없다"로 읽힌다. 0/1 과 반드시 갈라야 한다.
set -uo pipefail

die_unmeasurable() { echo "⛔ 판정 불가 — $1"; shift; for l in "$@"; do echo "   $l"; done; exit 3; }

FILE=""; OLD=""; NEW=""; TESTCMD=""; NAME="변이"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --file) FILE="${2:-}"; shift 2 ;;
    --old)  OLD="${2:-}";  shift 2 ;;
    --new)  NEW="${2:-}";  shift 2 ;;
    --test) TESTCMD="${2:-}"; shift 2 ;;
    --name) NAME="${2:-}"; shift 2 ;;
    -h|--help) sed -n '1,30p' "$0"; exit 0 ;;
    *) die_unmeasurable "모르는 인자: $1" "사용법은 --help" ;;
  esac
done

[[ -n "$FILE" && -n "$OLD" && -n "$TESTCMD" ]] || \
  die_unmeasurable "--file · --old · --test 는 필수다" "지금: file='$FILE' old='$OLD' test='$TESTCMD'"

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || \
  die_unmeasurable "git 레포 안이 아니다 — 되돌릴 기준선이 없다"
cd "$ROOT" || die_unmeasurable "레포 루트로 못 들어갔다: $ROOT"

[[ -f "$FILE" ]] || die_unmeasurable "대상 파일이 없다: $FILE"

# ── 가드 ① 추적되지 않는 파일: 기준선이 아예 없어서 복구를 보장할 수 없다 ──
git ls-files --error-unmatch -- "$FILE" >/dev/null 2>&1 || \
  die_unmeasurable "git 이 추적하지 않는 파일이다: $FILE" \
                   "커밋되지 않은 파일은 되돌릴 기준선이 없다 — 먼저 add + commit 할 것"

# ── 가드 ② 🔑 미커밋 변경: 이 도구가 존재하는 이유 ──
if [[ -n "$(git status --porcelain -- "$FILE")" ]]; then
  die_unmeasurable "대상 파일에 미커밋 변경이 있다: $FILE" \
                   "변이시험은 파일을 되돌렸다 복구하는 절차라, 지금 돌리면 그 수정이 사라진다." \
                   "→ 먼저 커밋하고 다시 돌릴 것 (git add -A && git commit)" \
                   "  파일은 손대지 않았다. 시험 명령도 실행하지 않았다."
fi

# 대상 밖이 더러운 건 막지 않는다(정상 작업 흐름) — 다만 시험 결과에 섞일 수 있으니 알린다
DIRTY_ELSE="$(git status --porcelain | grep -v -- " ${FILE}\$" | head -3)"
[[ -n "$DIRTY_ELSE" ]] && echo "ℹ️  대상 밖에 미커밋 변경이 있다(그대로 둔다 · 시험 결과에 섞일 수 있음)"

# ── 가드 ③ 주입 가능성: MISS 도 다중매치도 "잰 것"이 아니다 ──
count=0
while IFS= read -r line || [[ -n "$line" ]]; do
  rest="$line"
  while [[ "$rest" == *"$OLD"* ]]; do
    count=$((count + 1)); rest="${rest#*"$OLD"}"
  done
done < "$FILE"

if [[ "$count" -eq 0 ]]; then
  die_unmeasurable "주입 MISS — --old 문자열을 $FILE 에서 못 찾았다" \
                   "찾던 것: '$OLD'" \
                   "이대로 시험을 돌리면 **원본 결과를 변이 결과로 읽게 된다**(가장 흔한 오판)."
fi
if [[ "$count" -gt 1 ]]; then
  die_unmeasurable "--old 가 ${count}건 매치된다 — 어디를 바꿨는지 모르는 변이는 근거가 안 된다" \
                   "찾던 것: '$OLD'" \
                   "→ 앞뒤를 더 붙여 유일해지게 만들 것"
fi

# ── 여기서부터 파일을 건드린다. 어떤 경로로 빠져나가도 원상복구한다 ──
BACKUP="$(mktemp)"
cp -p "$FILE" "$BACKUP"
restore() {
  cp -p "$BACKUP" "$FILE"; rm -f "$BACKUP"
  # 되돌림이 진짜 됐는지까지 본다 — 복구 실패를 조용히 넘기면 다음 시험이 오염된다
  if [[ -n "$(git status --porcelain -- "$FILE")" ]]; then
    echo "🔴 복구 실패 — $FILE 이 원본과 다르다. 직접 확인할 것: git diff -- $FILE"
  fi
}
trap restore EXIT INT TERM

TMPNEW="$(mktemp)"
: > "$TMPNEW"
while IFS= read -r line || [[ -n "$line" ]]; do
  printf '%s\n' "${line//"$OLD"/"$NEW"}" >> "$TMPNEW"
done < "$FILE"
[[ -s "$FILE" && "$(tail -c1 "$FILE" | wc -l)" -eq 0 ]] && truncate -s -1 "$TMPNEW"
cat "$TMPNEW" > "$FILE"; rm -f "$TMPNEW"

# 주입OK 를 값으로 확인한다 — 조용한 치환 실패는 결론을 뒤집는다
if ! git diff --quiet -- "$FILE"; then
  echo "🧪 [$NAME] 주입OK: '$OLD' → '$NEW' ($FILE)"
else
  die_unmeasurable "치환했는데 파일이 안 바뀌었다 — --old 와 --new 가 같은가?"
fi

set +e
bash -c "$TESTCMD"
TEST_RC=$?
set -e

echo "── 시험 종료코드: $TEST_RC"
if [[ "$TEST_RC" -ne 0 ]]; then
  echo "✅ [$NAME] 잡힘 — 변이를 넣자 시험이 빨개졌다. 그 줄은 실제로 지켜진다."
  exit 0
fi
echo "🔴 [$NAME] 살아남음 — 변이를 넣었는데도 시험이 초록이다."
echo "   구멍이거나 등가변이다. **값으로 가를 것**: 이 변이로도 동작이 같은가?"
echo "   등가라면 *왜 등가인지*까지 적는다 — '다른 분기가 덮어서'라면 그 분기가 미검증이라는 신호다."
exit 1
