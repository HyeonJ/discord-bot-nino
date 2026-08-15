#!/bin/bash
# 「⛔ 판정 불가」를 찍고도 «러너에 안 알리는» 자리를 잡는다.
#
# 🔴 왜: 러너 집계의 「판정 불가 N」은 각 시험이 **rc=2** 로 신고한 것만 센다.
#   시험 안에서 ⛔ 를 찍어놓고 계수기를 안 올리면 그 시험은 **rc=0(통과)** 로 나가고,
#   원장의 판정 불가 칸에 **안 뜬다.** 즉 「못 쟀다」가 「됐다」로 적힌다.
#   🔑 이건 «실패를 판정 불가로 미는 것»의 거울이다 — 그쪽은 사전식 뒷가지가 출구를 주는데
#      이쪽은 **아예 안 보여서** 출구를 물을 자리조차 없다.
#
# 🔑 실물 (2026-08-15): `morning-briefing.test.sh` 가 ⛔ 를 **둘** 찍고 **하나**만 신고했다.
#   전수로 훑으니 같은 모양이 **8자리 · 5파일**이었다(이 시험이 잡은 첫 분모).
#
# 잠그는 축은 둘이고 성질이 다르다:
#   ① ⛔ 를 «찍는» 줄이 계수기를 거치나        — 새는 자리(자리 잠금)
#   ② 계수기가 있으면 요약에 싣고 rc=2 로 내보내나 — 새는 통로(통로 잠금)
#   ①만 두면 **계수는 맞는데 러너가 못 본다**(`check-usage-alert` 가 실제로 그 상태였다).
#
# 🔴 이 시험이 «못 보는» 축 — 초록을 「신고가 옳다」로 읽지 않기 위해 적어둔다:
#   ⓐ ⛔ 가 «변수»로 들어가면 못 본다(`echo "$MSG"`). 좌변이 리터럴이다.
#   ⓑ 계수기를 올리고도 «조건»이 틀려 안 올라가는 경우는 정적으로 못 본다.
#   ⓒ 분모는 이 레포 `tests/*.test.sh` 뿐이다 — `.test.js` 는 러너 계약이 달라 안 본다.
#   ⓓ 🔴 **축②의 좌변이 「줄머리 echo 로 ⛔ 를 찍나」라, 도우미 «정의» 안의 ⛔ 를 못 본다.**
#      `und() { echo "  ⛔ $1"; skip=$((skip+1)); }` 꼴이 가장 흔한데 그 파일은 통째로 분모 밖이다.
#      실측 2026-08-15 — 좌변을 「이 파일이 판정 불가를 «낼 수 있나»」로 넓히면 **9파일**이 걸리고,
#      그중 둘(`merge-ledger-selfcheck` · `nino-watchdog`)은 **지금 실제로 판불을 찍고 rc=0 으로 나간다.**
#      🔑 **여기서 안 넓힌 이유는 「모르겠다」가 아니라 «순서»다** — 고치면 러너 판불이 늘어(로컬 3→5)
#      원장이 **동결**로 간다. 동결에선 사전식이 중립 PR 을 막고, 「은닉 해제 PR 이 관측기 예외를
#      타나」가 **아직 미정**이라(원장 머리말 § 관측기 열거) 지금 넓히면 **탈출로를 정하기 전에
#      자신을 가둔다.** ⇒ 경계가 정해지면 별 PR 로 넓힌다. 룬드 `M:74mq` 가 같은 자리를 짚었다.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${GUARD_ROOT:-$SCRIPT_DIR}"

pass=0; fail=0; skip=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; [ -n "${2:-}" ] && echo "     want: $2"; [ -n "${3:-}" ] && echo "     got:  $3"; fail=$((fail + 1)); }
nom() { echo "  ⛔ $1 (판정 불가)"; skip=$((skip + 1)); }

command -v python3 >/dev/null || { nom "python3 이 없다"; echo; echo "  통과 $pass · 실패 $fail · 판정 불가 $skip"; exit 2; }

N_FILES="$(command ls "$ROOT"/*.test.sh 2>/dev/null | command grep -c .)"
if [ "$N_FILES" -eq 0 ]; then
  nom "분모가 0이다 — $ROOT 에 *.test.sh 가 없다"
  echo; echo "  통과 $pass · 실패 $fail · 판정 불가 $skip"; exit 2
fi
echo "  분모: $ROOT/*.test.sh ${N_FILES}개"
echo

scan() {
  python3 - "$ROOT" "$1" <<'PY'
import glob, os, re, sys
root, axis = sys.argv[1], sys.argv[2]

# 🔴 계수기로 «인정»하는 꼴. 이름은 레포마다 갈려서 열거가 아니라 «증가 연산»으로 읽는다.
INC = re.compile(r'\b(skip|unk|unknown|nom|skipt|nomeasure)\b\s*=\s*\$\(\(\s*\1\s*\+')
CALL = re.compile(r'^\s*(nom|skipt|nomeasure)\b')          # 계수하는 도우미 호출
DEFN = re.compile(r'^\s*(nom|skipt|nomeasure)\s*\(\)')     # 그 도우미의 «정의» 줄 — 분모 밖
EMIT = re.compile(r'^\s*(echo|printf)\b')
# 🔑 «명령으로서의» exit 2 만 센다 — 줄머리·`||`·`&&`·`;`·`{` 뒤. 문자열 안의 「exit 2」는 안 걸린다.
EXIT2 = re.compile(r'(?:^|\|\||&&|;|\{|\bthen\b|\belse\b|\bdo\b)\s*exit\s+2\b')

out = []
for f in sorted(glob.glob(os.path.join(root, '*.test.sh'))):
    lines = open(f, encoding='utf-8').read().splitlines()
    rel = os.path.basename(f)

    if axis == '1':
        for i, l in enumerate(lines):
            s = l.strip()
            if '⛔' not in s or not EMIT.match(s):
                continue
            if DEFN.search(s) or DEFN.search(lines[i - 1] if i else ''):
                continue                                    # 도우미 정의 안의 ⛔
            # 🔑 창은 «앞뒤»로 연다. 뒤로만 보면 거짓 양성이 둘씩 났다:
            #   앞 3줄 — `unk=$((unk+1))` 를 ⛔ «위»에 쓰는 꼴(backup-to-nas · discord-send-callers)
            #   뒤 8줄 — 「⛔ → 안내 몇 줄 → 요약 → exit 2」 꼴(clock-independence · discord-send-mention)
            win = [l for l in lines[max(0, i - 4):i + 8] if not l.lstrip().startswith('#')]
            if any(INC.search(l) or EXIT2.search(l) for l in win):
                continue
            out.append("%s:%d  %s" % (rel, i + 1, s[:80]))

    elif axis == '2':
        # 🔴 좌변은 「계수기가 있나」가 아니라 «rc=2 로 나갈 «경로»가 있나»다.
        #   계수기 이름·꼴로 읽으면 `exit 2` 를 «그 자리»에서 내는 파일이 거짓 양성이 되고
        #   (실측: `ci-aggregate-coverage` 가 그랬다), 이름이 바뀌면 또 뚫린다.
        emits = [l for l in lines if '⛔' in l and EMIT.match(l.strip())]
        if not emits:
            continue                                        # 판정 불가를 낼 일이 없다
        # 🔴 «주석과 문자열»을 걷고 찾는다. 안 걷으면 `# … exit 2 …` 한 줄이 경로 노릇을 해서
        #   구조적 상시 참이 된다 — 실측: `check-usage-alert` 의 `exit 2` 셋이 전부 주석·문자열이라
        #   안 걷은 판이 그 파일을 «통과»시켰다(그 파일엔 rc=2 경로가 실제로 «없다»).
        if any(EXIT2.search(l) for l in lines if not l.lstrip().startswith('#')):
            continue                                        # 경로가 있다
        out.append("%s  ⛔ 를 %d자리에서 찍는데 rc=2 로 나갈 경로가 없다" % (rel, len(emits)))
print("\n".join(out))
PY
}

# ── ① 자리 잠금 ────────────────────────────────────────────────────────────
A1="$(scan 1)"
if [ -z "$A1" ]; then
  ok "① ⛔ 를 찍는 줄이 «전부» 계수기를 거친다"
else
  n="$(printf '%s\n' "$A1" | command grep -c .)"
  bad "① ⛔ 를 찍는데 계수기를 안 거치는 줄이 있다" \
      "그 자리에서 nom/skipt 를 부르거나 계수기를 직접 올린다" \
      "${n}자리 — 찍히기만 하고 러너엔 «통과»로 나간다"
  printf '%s\n' "$A1" | command sed 's/^/       /'
fi

# ── ② 통로 잠금 ────────────────────────────────────────────────────────────
A2="$(scan 2)"
if [ -z "$A2" ]; then
  ok "② 계수기가 있는 파일은 «전부» rc=2 로 러너에 알린다"
else
  n="$(printf '%s\n' "$A2" | command grep -c .)"
  bad "② 계수기가 러너까지 안 닿는다" \
      "꼬리에 [ \"\$skip\" -eq 0 ] || exit 2" \
      "${n}파일 — 세기는 세는데 rc 가 0이라 원장에 안 뜬다"
  printf '%s\n' "$A2" | command sed 's/^/       /'
fi

echo
echo "  통과 $pass · 실패 $fail · 판정 불가 $skip"
[ "$fail" -eq 0 ] || exit 1
[ "$skip" -eq 0 ] || exit 2
