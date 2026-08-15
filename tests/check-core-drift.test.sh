#!/usr/bin/env bash
# check-core-drift.sh 계약 테스트 — **세 상태가 서로 다른 출력·종료코드를 낸다**
#
# 왜 이 시험이 생겼나 (첫 실전 발동에서 실제로 틀렸다, 2026-07-28 11:15):
#   cron 알림이 `STALE: repo_behind=0 · process_behind=?파일 — 재시작 안 됨` 으로 나갔다.
#   `?` 는 "못 쟀다"인데 STALE(=미달, 조치는 재시작)로 접혀서, **값이 없는데 조치를 지시**했다.
#   판정은 우연히 맞았고(코어가 실제로 움직였다) 근거는 비어 있었다 — 그래서 안 들켰다.
#
# 🔑 종료코드 계약 (2026-07-28 양봇 합의 — 코어 run-tests 계열로 통일):
#     0 정상 · **1 위반**(조치 있음: pull/재시작) · **2 판정 불가**(못 쟀다)
#     그 외(126·127·128+) ⇒ 판정 불가로 접는다 — 래퍼가 정규화한다(core-drift-cron 시험 ⑧)
#   1과 2가 갈려야 래퍼가 다른 문장을 쓴다("조치 필요" vs "검사가 못 돌았다").
#   🔴 이전엔 1·2 가 반대였다. 같은 디렉터리의 check-runner-drift.sh 는 이미 `2=판정 불가`
#      였어서 한 레포에 두 규약이 있었다 — **이 시험 파일도 옛 계약의 독자였다**(㊽).
#      계약을 바꾸면 코드·래퍼·시험 셋이 같이 움직인다. 하나만 고치면 초록인 채로 어긋난다.
#
# 네트워크 안 쓴다: 로컬 bare 원격을 만들어 CORE_REPO 의 upstream 으로 붙인다.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$BOT/scripts/check-core-drift.sh"

. "$SCRIPT_DIR/lib/capture-rc.sh"

pass=0; fail=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; fail=$((fail + 1)); [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/     /'; }

[ -f "$SCRIPT" ] || { echo "❌ 없음: $SCRIPT"; exit 1; }
ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT

# ── 가짜 코어 레포 + 로컬 원격 ──
git init -q --bare "$ROOT/remote.git"
git clone -q "$ROOT/remote.git" "$ROOT/core" 2>/dev/null
mkdir -p "$ROOT/core/relay"
cat > "$ROOT/core/relay/check-config.js" <<'JS'
process.exit(0);
JS
git -C "$ROOT/core" -c user.email=t@e -c user.name=t add -A
git -C "$ROOT/core" -c user.email=t@e -c user.name=t commit -qm init
git -C "$ROOT/core" push -q origin HEAD:main 2>/dev/null
git -C "$ROOT/core" branch -q --set-upstream-to=origin/main 2>/dev/null || \
  git -C "$ROOT/core" branch -q -u origin/main 2>/dev/null
printf 'LONG_MESSAGE_THRESHOLD=2200\n' > "$ROOT/.env"

run() { CORE_REPO="$ROOT/core" BOT_ENV="$ROOT/.env" RELAY_UNIT="$1" bash "$SCRIPT" 2>&1; }

echo "① 판정 불가 — 유닛을 못 찾으면 rc=2 이고 **재시작을 지시하지 않는다**"
out="$(run "does-not-exist-$$.service")"; rc=$?
[ "$rc" -eq 2 ] && ok "rc=2 (판정 불가)" || bad "rc=$rc — 2여야 한다" "$out"
grep -q "판정 불가" <<<"$out" && ok "판정 불가를 명시" || bad "판정 불가 문구 없음" "$out"
# 🔑 이 시험의 본체: 값이 없는데 조치를 지시하면 안 된다
grep -q "재시작 안 됨" <<<"$out" && bad "못 쟀는데 '재시작 안 됨'으로 단정했다" "$out" \
  || ok "재시작을 단정하지 않는다"
grep -q "?파일" <<<"$out" && bad "'?파일' 이 수치인 것처럼 출력됐다" "$out" \
  || ok "'?' 를 수치 자리에 넣지 않는다"

echo "② 판정 불가와 미달(STALE)은 **다른 출력**이다"
# STALE 은 유닛이 있어야 재현되므로, 여기선 '판정 불가가 STALE 문구를 쓰지 않는지'로 가른다
grep -q "^STALE" <<<"$out" && bad "판정 불가가 STALE 로 나갔다" "$out" || ok "STALE 로 접히지 않는다"

echo "③ repo_behind 는 유효하면 같이 낸다 (한 축이 죽어도 다른 축은 보고)"
grep -q "repo_behind=0커밋" <<<"$out" && ok "유효한 축은 그대로 보고" || bad "repo_behind 미표시" "$out"

echo "④ cron 환경 재현 — XDG_RUNTIME_DIR 이 없어도 **실제로 잰다**"
# ⚠️ 처음엔 "'No medium found' 가 출력에 없다"로 썼는데 **절대 실패할 수 없는 시험**이었다.
#    스크립트가 systemctl 의 stderr 를 `2>/dev/null` 로 죽이므로 그 문자열은 애초에 안 나온다.
#    export 를 통째로 지우는 변이(R2)가 7/7 통과로 살아남아서 들켰다.
#    → 문자열이 아니라 **값**으로 가른다: 못 재면 "판정 불가"(rc=2), 재면 다른 상태가 된다.
LIVE_UNIT="$(systemctl --user list-units --type=service --state=running --no-legend 2>/dev/null \
             | awk '{print $1}' | head -1)"
if [ -z "$LIVE_UNIT" ]; then
  echo "  ⏭️  건너뜀 — 살아있는 --user 유닛이 없어 '쟀다'를 관측할 수 없다"
else
  out2="$(env -u XDG_RUNTIME_DIR -u DBUS_SESSION_BUS_ADDRESS \
          CORE_REPO="$ROOT/core" BOT_ENV="$ROOT/.env" RELAY_UNIT="$LIVE_UNIT" \
          bash "$SCRIPT" 2>&1)"; rc2=$?
  [ "$rc2" -ne 2 ] && ok "cron 환경에서도 판정이 선다 (rc=$rc2, $LIVE_UNIT)" \
    || bad "cron 환경에서 판정 불가로 떨어졌다 — XDG_RUNTIME_DIR 미설정" "$out2"
  grep -q "판정 불가" <<<"$out2" && bad "살아있는 유닛인데 못 쟀다" "$out2" \
    || ok "MainPID 를 실제로 구했다"
fi

echo '④-b 🔴 재시작 분모 — relay/discord-send/ 는 «세지 않는다» (부를 때마다 새 프로세스인 CLI)'
# 🔴 실물 2026-08-15: `relay/discord-send/{cli,parser}.js` 가 바뀌자 **세 시간 동안 매시**
#   「재시작 안 됨」이 나갔다. 재시작해도 아무것도 안 바뀌는 상태였다 — 그 CLI 는 이미 새 파일을 읽는다.
#   ⚠️ 이 알림은 `process_behind>0` 이면 억제를 «끄는» 갈래라 **오탐이 곧 무제한 반복**이 된다.
#   ⚠️ 경로 함정: 그 CLI 는 최상위 `discord-send/` 가 «아니라» `relay/discord-send/` 에 산다 —
#     `find "$CORE_REPO/relay"` 로 좁히는 것만으로는 «안 빠진다»(내가 그렇게 고쳤다가 대조군에 걸렸다).
if [ -z "${LIVE_UNIT:-}" ]; then
  echo "  ⏭️  건너뜀 — 살아있는 --user 유닛이 없어 process_behind 를 못 잰다"
else
  # 🔴 **절대값으로 못 단언한다 — 픽스처가 만드는 relay/check-config.js 자체가 «지금» 만들어져
  #   유닛 시작보다 새롭다.** 기준선이 이미 1 이라 「0 이냐」로 물으면 항상 실패한다(내가 밟았다).
  #   ⇒ 좌변은 «델타»다: 파일을 더했을 때 그 수가 «변했나».
  pb() { printf '%s' "$1" | sed -n 's/.*process_behind=\([0-9]\{1,\}\).*/\1/p' | head -1; }
  base="$(pb "$(run "$LIVE_UNIT")")"
  mkdir -p "$ROOT/core/relay/discord-send"
  : > "$ROOT/core/relay/discord-send/cli.js"
  afterA="$(pb "$(run "$LIVE_UNIT")")"
  [ "$afterA" = "$base" ] \
    && ok "discord-send/*.js 를 더해도 process_behind 가 그대로다 ($base) — 재시작 사유가 아니다" \
    || bad "discord-send 를 재시작 사유로 세고 있다" "$base (그대로)" "$afterA"
  # 🔴 대조군 — 빼기만 재고 «검출력»을 안 재면 「무엇을 더해도 안 는다」와 구별이 0 이다.
  : > "$ROOT/core/relay/index.js"
  afterB="$(pb "$(run "$LIVE_UNIT")")"
  [ "$afterB" -gt "$base" ] 2>/dev/null \
    && ok "  → 대조군: relay/index.js 를 더하면 «는다» ($base → $afterB) — 빼기가 과하지 않다" \
    || bad "대조군 실패 — 진짜 런타임 파일도 안 센다(검출력 0)" ">$base" "$afterB"
  rm -f "$ROOT/core/relay/index.js" "$ROOT/core/relay/discord-send/cli.js"
fi

echo "⑤ 🔴 뒤처짐(DRIFT)은 **위반(rc=1)** 이다 — 0 으로 내면 래퍼가 알림 전에 빠져나간다"
# 실전에서 조용히 새고 있었다(2026-07-28 13:5x 발견). 로그:
#   12:08 rc=0 DRIFT: repo_behind=3커밋   ← 발견해놓고 rc=0
#   13:15 rc=0 DRIFT: repo_behind=4커밋
# core-drift-cron.sh 36행이 `[ "$RC" -eq 0 ] && exit 0` 이라 **알림이 한 번도 안 나갔다.**
# 래퍼 헤더엔 이미 이렇게 적혀 있었다 — *"없는 경고는 pull 을 미루게 해서 옛 코드로 계속
# 돌게 만든다"*. 래퍼는 이 사고를 예상했는데 **검사 쪽이 0을 내서 두 반쪽이 어긋났다.**
# 그래서 라이브 코어가 5커밋 뒤처진 채였고 내 lint 셔틀은 스테일 정본을 실행하고 있었다.
if [ -z "${LIVE_UNIT:-}" ]; then
  echo "  ⏭️  건너뜀 — 살아있는 --user 유닛이 없어 process_behind 를 못 재고, 그러면 rc=2 로 먼저 빠진다"
else
  # ⚠️ `--branch main` 필수: bare 레포의 HEAD 는 `master` 라 그냥 clone 하면 **빈 master** 를
  #    체크아웃하고, 거기서 커밋하면 새 루트 커밋이 되어 push 가 non-fast-forward 로 거절된다.
  #    처음에 그렇게 짜서 repo_behind=0 이 나왔고 시험이 STALE 갈래로 새어버렸다.
  git clone -q --branch main "$ROOT/remote.git" "$ROOT/pusher" 2>/dev/null
  echo "새 변경" > "$ROOT/pusher/newfile.txt"
  # 🔴 `.sh` 를 같이 넣는다 — **실사고를 재현하는 픽스처가 아니었다**(룬드 리뷰 `#87`).
  #    거짓 초록을 낸 실물은 `tmux-send.sh`(루트의 **셸 스크립트**)인데 픽스처는 `.txt` 뿐이라
  #    *루트 파일이 세지나*만 덮고 *셸 스크립트가 세지나*는 안 덮었다.
  # 🔑 그래서 "제외를 `*.sh` 로 넓히는" 변이(M2)를 e2e 가 못 물었다. 나는 그걸 *두 층이 서로를
  #    대신 못 한다* 로 읽었는데 틀렸다 — **같은 축을 안 재고 있었을 뿐**이다. 실측:
  #      원본  newfile.txt 런타임 · tmux-send.sh 런타임
  #      M2    newfile.txt **런타임 그대로** · tmux-send.sh 제외
  #    `.txt` 는 `*.sh` 에 안 걸리니 변이 전후가 같다. 픽스처는 직관적으로 세 보이는 값이 아니라
  #    **변이를 실제로 죽이는 값**이어야 한다.
  echo "#!/bin/sh" > "$ROOT/pusher/newfile.sh"
  git -C "$ROOT/pusher" -c user.email=t@e -c user.name=t add -A
  git -C "$ROOT/pusher" -c user.email=t@e -c user.name=t commit -qm "코어 신규 커밋"
  git -C "$ROOT/pusher" push -q origin main 2>/dev/null
  out5="$(run "$LIVE_UNIT")"; rc5=$?
  # 🔑 DRIFT 와 rc=1 을 **한 쌍으로** 본다. 따로 보면 STALE(이것도 rc=1)이 rc 단언을 대신
  #    통과시킨다 — 실제로 첫 판에 그랬다. 다른 갈래가 대신 통과시키는 형태(②).
  if grep -q "^DRIFT" <<<"$out5"; then
    ok "DRIFT 로 판정"
    [ "$rc5" -eq 1 ] && ok "그 DRIFT 가 rc=1 로 나간다 — 래퍼가 알린다" \
      || bad "DRIFT 인데 rc=$rc5 — 0 이면 래퍼가 36행에서 조용히 빠져나간다" "$out5"
  else
    bad "DRIFT 를 못 잡았다 (rc=$rc5) — 이 상태면 rc 단언은 의미가 없다" "$out5"
  fi
fi

echo "⑦ 🔴 **레포 루트의 새 파일이 런타임으로 세진다** — 옛 포함 목록이 거짓 초록을 낸 자리"
# 라이브 재현(2026-07-31): 코어가 `tmux-send.sh`(루트)를 바꾼 뒤처짐에서 **"런타임 파일 변경: 0건"**.
# 🔑 lib 단위시험(core-runtime-files.test.sh)이 분류를 보증해도 **배선이 끊기면 초록인 채로 틀린다** —
#    검사기가 lib 을 실제로 부르는지는 여기서만 갈린다. ⑤가 만든 뒤처짐이 루트 파일(newfile.txt)이라
#    그대로 쓴다: 옛 규칙이면 0건, 새 규칙이면 1건.
if [ -z "${out5:-}" ]; then
  echo "  ⏭️  건너뜀 — ⑤가 안 돌아 DRIFT 출력이 없다(런타임 카운트는 DRIFT 갈래에서만 나온다)"
else
  cnt="$(sed -n 's/.*런타임 파일 변경: \([0-9]\{1,\}\)건.*/\1/p' <<<"$out5" | head -1)"
  [ -n "$cnt" ] && ok "런타임 건수를 수치로 낸다" || bad "런타임 건수 줄이 없다" "$out5"
  [ "${cnt:-0}" -eq 2 ] && ok "루트의 .txt·.sh 둘 다 세진다 (${cnt}건)" \
    || bad "루트 파일 2개가 바뀌었는데 ${cnt}건 — 옛 포함 목록의 거짓 초록이다" "$out5"
  # 🔑 `.sh` 를 **따로** 단언한다 — 건수만 보면 `.txt` 하나로도 통과한다(옛 ⑦이 그랬다).
  #    실사고 파일이 `tmux-send.sh` 였으니 여기서 갈려야 한다.
  grep -q "· newfile.sh" <<<"$out5" && ok "루트의 **셸 스크립트**가 런타임으로 세진다 (실사고 축)" \
    || bad "루트 .sh 가 안 세졌다 — tmux-send.sh 거짓 초록이 그대로 남는다" "$out5"
  grep -q "· newfile.txt" <<<"$out5" && ok "어느 파일인지 이름까지 낸다" \
    || bad "건수만 있고 파일명이 없다 — 사람이 근거를 못 본다" "$out5"
fi

echo "⑥ 🔑 **모든 판정 불가 갈래가 2로 나간다** — 갈래마다 시험을 붙일 수 없으니 성질로 잠근다"
# 🔴 이 스크립트엔 판정 불가 갈래가 일곱 곳이다. ①은 그중 **하나**(유닛 부재)만 지난다 —
#    나머지 여섯은 시험이 안 닿는다. 실측: `워크트리 생성 실패` 갈래를 옛 코드(1)로 되돌려도
#    **10 pass 초록**이었다. 같은 계약이 여러 자리에서 실현되면 **한 자리만 덮고도 초록**이 된다
#    (2026-07-28 assistant#24 P1 과 같은 형태 — 그땐 내가 룬드 코드에서 잡았고 이번엔 내 코드다).
# ⇒ 갈래마다 케이스를 만드는 대신 **출력 문구와 종료코드의 짝**을 정적으로 본다.
#    ⚠️ `printf|echo` 같은 **통로를 열거하지 않는다** — 그건 자기 printer 를 정의하는 순간
#       뚫린다(assistant#24 P2). 여기선 *어떤 말을 하면서 어떤 코드로 나가는가* 만 본다.
_hf_viol="$(mktemp)"   # 🔴 3.2: $( … << ) 형태를 피한다 (heredoc-form-guard)
python3 - "$SCRIPT" <<'PYEOF' > "${_hf_viol}"
import re, sys
lines = open(sys.argv[1]).read().split('\n')
bad = []
for i, ln in enumerate(lines):
    m = re.search(r'\bexit ([0-9]+)', ln)
    if not m or ln.lstrip().startswith('#'):
        continue
    code = m.group(1)
    if code == '0':
        continue
    # 같은 줄 + 앞 4줄(주석 제외)에서 무슨 말을 하고 있었나
    ctx = '\n'.join(x for x in lines[max(0, i-4):i+1] if not x.lstrip().startswith('#'))
    unknown = re.search(r'판정 불가|WARN:|ERROR:', ctx)
    violation = re.search(r'\bSTALE\b|\bDRIFT\b', ctx)
    if unknown and not violation and code != '2':
        bad.append(f"{i+1}행: 판정 불가인데 exit {code} (2여야 한다)")
    if violation and not unknown and code != '1':
        bad.append(f"{i+1}행: 위반(STALE/DRIFT)인데 exit {code} (1이어야 한다)")
print('\n'.join(bad))
PYEOF
_hf_rc_viol=$?   # 🔴 PYEOF 바로 다음 줄 — 한 줄만 밀려도 딴 명령의 rc 다
viol="$(cat "${_hf_viol}")"; rm -f "${_hf_viol}"
if _hf_msg="$(hf_verdict "$_hf_rc_viol" "rc 계약")"; then
    [ -z "$viol" ] && ok "판정 불가는 전부 2, 위반은 전부 1" || bad "계약 위반 갈래" "$viol"
else
    bad "$_hf_msg" "rc=0" "«${viol}»"
fi
# 음성 검사 — 이 시험이 실제로 물 수 있는지(항상 초록인 시험이 아닌지)
probe="$(mktemp)"; sed 's/echo "  ⚠️ 영향 판정 불가 — 워크트리 생성 실패"; exit 2/echo "  ⚠️ 영향 판정 불가 — 워크트리 생성 실패"; exit 1/' "$SCRIPT" > "$probe"
probe_out="$(SCRIPT="$probe" bash -c 'python3 - "$SCRIPT" <<'"'"'PYEOF'"'"'
import re, sys
lines = open(sys.argv[1]).read().split("\n")
bad = []
for i, ln in enumerate(lines):
    m = re.search(r"\bexit ([0-9]+)", ln)
    if not m or ln.lstrip().startswith("#"): continue
    code = m.group(1)
    if code == "0": continue
    ctx = "\n".join(x for x in lines[max(0,i-4):i+1] if not x.lstrip().startswith("#"))
    if re.search(r"판정 불가|WARN:|ERROR:", ctx) and not re.search(r"\bSTALE\b|\bDRIFT\b", ctx) and code != "2":
        bad.append(str(i+1))
print(",".join(bad))
PYEOF')"
[ -n "$probe_out" ] && ok "  → 되돌림 변이를 실제로 잡는다(${probe_out}행)"   || bad "  이 시험은 어떤 변이로도 안 갈린다 — 빼는 게 맞다" "probe 무반응"
rm -f "$probe"

echo
echo "  통과 $pass · 실패 $fail"
[ "$fail" -eq 0 ]
