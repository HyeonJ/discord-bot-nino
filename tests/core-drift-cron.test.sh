#!/usr/bin/env bash
# core-drift-cron.sh 계약 테스트 — **언제 소리를 내는가**만 본다 (네트워크·전송 없음)
#
# 왜 이것만 보나: 이 래퍼는 판정을 하지 않는다(그건 check-core-drift.sh 몫).
#   래퍼가 틀릴 수 있는 건 *알릴 것을 안 알리거나 조용할 것을 시끄럽게 하는 것* 뿐이고,
#   그중 위험한 쪽은 **판정 불가(rc=2)를 조용히 넘기는 것**이다 — 괜찮음과 같아지니까.
#
# 🔑 종료코드 계약(2026-07-28 양봇 합의 — 코어 run-tests 계열로 통일):
#     0 정상 · 1 위반(조치 있음) · 2 판정 불가 · **그 외(126·127·128+) ⇒ 판정 불가로 접는다**
#   ⚠️ 마지막 항이 이 계약의 핵심이다. 셸이 내는 코드는 도구가 고른 게 아니라 *못 돈 것*이고,
#      그걸 정상으로 접으면 죽은 검사가 초록으로 보인다. ⑧이 그 자리를 잠근다.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$BOT/scripts/core-drift-cron.sh"

pass=0; fail=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; fail=$((fail + 1)); [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/     /'; }

[ -f "$SCRIPT" ] || { echo "❌ 없음: $SCRIPT"; exit 1; }
ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT

# 가짜 검사기 — 종료코드를 주입한다
mkfake() { printf '#!/usr/bin/env bash\necho "%s"\nexit %s\n' "$2" "$1" > "$ROOT/check.sh"; chmod +x "$ROOT/check.sh"; }

run() {  # run  → stdout(DRY_RUN 이라 전송 대신 출력), 종료코드는 $rc 로
    out="$(BOT_DIR="$BOT" CHECK="$ROOT/check.sh" DRY_RUN=1 \
        HEARTBEAT="$ROOT/hb" LOG="$ROOT/log" NOTIFY_STATE="$ROOT/notify-state" \
        RENOTIFY_AFTER="${RENOTIFY_AFTER:-43200}" \
        DISCORD_SEND="$ROOT/should-not-exist" bash "$SCRIPT" 2>&1)"
    rc=$?
}
no_state() { rm -f "$ROOT/notify-state"; }

echo "① 충족(rc=0) — 조용하다"
mkfake 0 "OK: repo_behind=0 · process_behind=0"; run
[ -z "$out" ] && ok "출력 없음" || bad "조용해야 하는데 떠들었다" "$out"
[ "$rc" -eq 0 ] && ok "종료코드 0" || bad "종료코드 $rc"

echo "② 위반(rc=1) — 알리고, 검사기 출력을 그대로 담는다"
mkfake 1 "DRIFT: repo_behind=5커밋"; run
grep -q "코어 드리프트" <<<"$out" && ok "알림 생성" || bad "알림 없음" "$out"
grep -q "repo_behind=5커밋" <<<"$out" && ok "검사기 출력 포함" || bad "출력이 안 실렸다" "$out"
[ "$rc" -eq 1 ] && ok "종료코드 전달(1)" || bad "종료코드 $rc"

echo "③ 🔑 판정 불가(rc=2) — **조용히 넘기지 않는다** (이 시험의 본체)"
mkfake 2 "WARN: fetch 실패"; run
grep -q "판정 불가" <<<"$out" && ok "판정 불가를 명시" || bad "조용히 넘어갔다" "$out"
[ "$rc" -eq 2 ] && ok "종료코드 전달(2)" || bad "종료코드 $rc"

echo "④ 충족과 판정 불가가 **다른 출력**이다 (숫자만 보면 둘 다 '문제 없음'처럼 보임)"
mkfake 0 "OK"; run; quiet="$out"
mkfake 2 "WARN"; run; unknown="$out"
[ "$quiet" != "$unknown" ] && ok "두 상태가 구분된다" || bad "같은 출력" "$quiet"

echo "⑤ 하트비트 — rc 와 무관하게 **항상** 갱신된다 (cron 이 살아 있다는 증거)"
rm -f "$ROOT/hb"; mkfake 0 "OK"; run
[ -s "$ROOT/hb" ] && ok "충족일 때도 남는다" || bad "하트비트 없음"
rm -f "$ROOT/hb"; mkfake 2 "WARN"; run
[ -s "$ROOT/hb" ] && ok "판정 불가일 때도 남는다" || bad "하트비트 없음"
grep -q "rc=2" "$ROOT/hb" && ok "rc 를 기록한다" || bad "rc 미기록" "$(cat "$ROOT/hb")"

echo "⑥ 로그가 누적된다(덮어쓰지 않는다) — 이력이 있어야 언제부터 밀렸는지 안다"
before=$(wc -l < "$ROOT/log"); mkfake 0 "OK"; run
[ "$(wc -l < "$ROOT/log")" -gt "$before" ] && ok "append" || bad "덮어썼다"

echo "⑧ 🔴 **셸이 내는 코드(127·126)도 판정 불가로 접는다** — 계약의 마지막 항"
# 🔑 127(command not found)·126(permission denied)은 **도구가 고른 값이 아니다.** 셸이 낸다.
#    그래서 어떤 도구도 자기 헤더에 안 적어두고, 부르는 쪽이 `case 0|1|2` 로만 쓰면
#    **default 로 조용히 샌다.** 실제로 2026-07-28 cron 이 rc=127 로 한 번도 안 돌았다
#    (PATH 가 /usr/bin:/bin 이라 node 가 안 보였다) — 그때 안 묻힌 건 이 래퍼가 우연히
#    `else` 였기 때문이지 계약이 지켜준 게 아니다. 우연을 시험으로 바꾼다.
# ⚠️ 정상으로 접으면 죽은 검사가 초록이 되고, 위반으로 접으면 오탐이 쌓여 무시된다.
#    **모르는 코드는 모른다고 낸다.**
mkfake 2 "WARN: fetch 실패"; run; plain2="$out"
for code in 127 126; do
    if [ "$code" -eq 127 ]; then
        out="$(BOT_DIR="$BOT" CHECK="$ROOT/nonexistent-check.sh" DRY_RUN=1             HEARTBEAT="$ROOT/hb" LOG="$ROOT/log"             DISCORD_SEND="$ROOT/should-not-exist" bash "$SCRIPT" 2>&1)"; rc=$?
    else
        printf '#!/usr/bin/env bash
exit 0
' > "$ROOT/noexec.sh"; chmod -x "$ROOT/noexec.sh"
        out="$(BOT_DIR="$BOT" CHECK="$ROOT/noexec.sh" DRY_RUN=1             HEARTBEAT="$ROOT/hb" LOG="$ROOT/log"             DISCORD_SEND="$ROOT/should-not-exist" bash "$SCRIPT" 2>&1)"; rc=$?
    fi
    [ "$rc" -eq 2 ] && ok "rc=$code → 판정 불가(2)로 접힌다"         || bad "rc=$code 가 $rc 로 나갔다 — 정상·위반 어느 쪽으로도 접지 않는다" "$out"
    grep -q "판정 불가" <<<"$out" && ok "  → '판정 불가' 라고 말한다"         || bad "  rc=$code 인데 판정 불가라고 안 한다" "$out"
    # 🔑 **접되 왜 접었는지는 남긴다**(룬드 제안). 접기만 하면 *도구 부재*·*권한*·*시그널*
    #    셋이 한 문장이 되어, 오늘 `head -1` 이 근거를 버린 것과 같은 자리가 된다.
    #    ⚠️ 추측이 아니다 — **셸이 코드로 이미 구분해 준다.** 그대로 옮겨 적을 뿐이다.
    case "$code" in 127) want="명령을 못 찾음" ;; 126) want="실행 권한 없음" ;; esac
    grep -q "$want" <<<"$out" && ok "  → 🔑 왜 접었는지 말한다($want)" || bad "  rc=$code 인데 이유가 없다 — 세 원인이 한 문장이 된다" "$out"
    # 음성 검사: 계약 안의 판정 불가(2)에는 그 꼬리표가 **안 붙어야** 한다. 상시로 붙으면
    # "셸 코드였다"는 신호가 죽는다(오늘 MISSING/STALE 에 재부팅 안내를 안 붙인 것과 같은 축).
    grep -qE "명령을 못 찾음|실행 권한 없음|시그널" <<<"$plain2" && bad "  정상적 판정 불가(rc=2)에도 셸 코드 꼬리표가 붙는다" "$plain2" || ok "  → rc=2 에는 안 붙는다(상시 안내가 되지 않게)"
done

echo "⑨ 시그널로 죽은 것도 **시그널이라고** 말한다 (128+N)"
# 🔴 128+N 은 *도구가 판정을 낸 것*이 아니라 **중간에 끊긴 것**이다. 127(도구 부재)과 조치가
#    다르다 — 전자는 설치·PATH, 후자는 왜 죽었는지. 한 문장으로 뭉치면 매번 다시 조사한다.
printf '#!/usr/bin/env bash\nkill -TERM $$\n' > "$ROOT/sig.sh"; chmod +x "$ROOT/sig.sh"
out="$(BOT_DIR="$BOT" CHECK="$ROOT/sig.sh" DRY_RUN=1 HEARTBEAT="$ROOT/hb" LOG="$ROOT/log" DISCORD_SEND="$ROOT/should-not-exist" bash "$SCRIPT" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && ok "rc=143 → 판정 불가(2)" || bad "rc=$rc 로 나갔다" "$out"
grep -q "시그널 15" <<<"$out" && ok "  → 시그널 번호를 계산해서 준다(143-128)" || bad "  시그널 번호가 없다" "$out"

echo "⑩ 🔑 **로그가 판정의 근거를 버리지 않는다** — 헤드라인만 남으면 왜 를 못 되짚는다"
# 🔴 `head -1` 만 남기고 있었다. 실측(4줄 중 3줄이 버려졌다):
#      DRIFT: repo_behind=1커밋 · process_behind=0파일   ← 남음
#        cc2c43a feat(ci): …                              ← 버림
#        런타임 파일 변경: 0건                             ← 버림  **재시작 필요 여부의 근거**
#        ✅ 받아도 설정 요건 충족                          ← 버림  **최종 판정**
#    2026-07-28 Darren 승인을 받을 때 내가 댄 근거(*"런타임 변경 0건이라 재시작 불필요"*)가
#    정확히 그 버려지는 줄이다 — 로그만으로는 *"그때 왜 재시작 안 했지"* 를 못 되짚는다.
# ⚠️ 헤드라인 **형식은 그대로 둔다.** 기존 로그를 날짜로 세는 grep 이 깨지면 "언제부터
#    밀렸나" 를 못 세게 되고, 그건 이 수정이 지키려는 것과 같은 것을 부순다.
mkmulti() {  # $1=rc  $2..=줄들
    local rc="$1"; shift
    { printf '#!/usr/bin/env bash\n'
      for l in "$@"; do printf 'printf %%s\\\\n %s\n' "$(printf '%q' "$l")"; done
      printf 'exit %s\n' "$rc"
    } > "$ROOT/check.sh"; chmod +x "$ROOT/check.sh"
}
: > "$ROOT/log"
# 🔑 픽스처에 **날짜로 시작하는 줄**을 넣는다. 커밋 목록엔 실제로 날짜가 섞이고, 무엇보다
#    이 값이 없으면 들여쓰기 단언이 **어떤 변이로도 안 갈린다**(실측: 들여쓰기를 빼도
#    `head -2` 로 바꿔도 전부 초록이었다). 원래 결함을 재현한 값이 아니라 **구조를 깨는 값**
#    이 필요한 자리 — `#53` ③-c 와 같다.
mkmulti 1 "DRIFT: repo_behind=1커밋 · process_behind=0파일" "  abc1234 feat(ci): 뭔가" "  2026-01-02 03:04:05 커밋된 항목" "  런타임 파일 변경: 0건" "  ✅ 받아도 설정 요건 충족"
run
head1="$(head -1 "$ROOT/log")"
printf '%s' "$head1" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} rc=1 DRIFT: repo_behind=1커밋' \
  && ok "헤드라인 형식이 그대로다(기존 grep 안 깨짐)" || bad "헤드라인" "STAMP rc=1 DRIFT…" "$head1"
for want in "런타임 파일 변경: 0건" "받아도 설정 요건 충족" "abc1234"; do
    grep -qF "$want" "$ROOT/log" && ok "  → 근거가 남는다: $want" || bad "  버려졌다: $want" "$(cat "$ROOT/log")"
done
# 🔑 이어지는 줄은 **들여쓰기**로 헤드라인과 갈린다 — 헤드라인 개수 세기가 안 깨지게.
n_head="$(grep -cE '^[0-9]{4}-[0-9]{2}-[0-9]{2} ' "$ROOT/log")"
[ "$n_head" -eq 1 ] && ok "  → 헤드라인은 여전히 1건으로 세어진다(이어지는 줄은 들여쓰기)" \
  || bad "  헤드라인이 $n_head 건으로 세어진다 — 이력 집계가 깨진다" "$(cat "$ROOT/log")"
# 🔑 그리고 **2번째 줄부터는 전부 접두사를 가진다.** 위 개수 단언만으로는 부족하다 —
#    헤드라인 printf 가 여러 줄을 삼켜도(예: `head -2`) 새어나온 줄이 날짜로 시작하진
#    않아서 개수가 안 변한다(실측: `head -1`→`head -2` 변이가 안 걸렸다).
#    "한 실행 = 헤드라인 한 줄 + 접두사 붙은 근거들" 이 규칙이므로 그걸 직접 단언한다.
stray="$(tail -n +2 "$ROOT/log" | grep -vcE '^    · ' || true)"
[ "$stray" -eq 0 ] && ok "  → 2번째 줄부터는 전부 '    · ' 접두사를 가진다" \
  || bad "  접두사 없는 줄이 $stray 건 — 헤드라인 경계가 흐려진다" "$(cat "$ROOT/log")"

echo "⑩-b 출력이 **한 줄이면** 이어지는 줄을 안 붙인다 (조용한 게 정상인 자리에 잡음 금지)"
: > "$ROOT/log"; mkfake 0 "OK: repo_behind=0 · process_behind=0"; run
[ "$(wc -l < "$ROOT/log")" -eq 1 ] && ok "한 줄짜리는 한 줄로 남는다" \
  || bad "잡음이 붙었다" "$(cat "$ROOT/log")"

echo "⑩-c 판정 불가·셸 코드일 때도 **근거가 남는다** (원인 조사가 제일 필요한 자리다)"
: > "$ROOT/log"
mkmulti 2 "WARN: fetch 실패 — 뒤처짐 판정 불가" "  흔한 원인: 네트워크·인증"
run
grep -qF "흔한 원인: 네트워크·인증" "$ROOT/log" && ok "판정 불가의 근거도 남는다" \
  || bad "판정 불가인데 근거가 버려졌다" "$(cat "$ROOT/log")"

echo "⑦ DRY_RUN 은 전송하지 않는다"
[ ! -e "$ROOT/should-not-exist" ] && ok "discord-send 미호출" || bad "전송이 일어났다"

echo
echo "  통과 $pass · 실패 $fail"
[ "$fail" -eq 0 ]

echo
echo "🔴 같은 말을 매시간 반복하지 않는다 — 알림은 **사실이 아니라 변화**로 (2026-07-29, 룬드 지적)"
# 🔑 실사고: 이 래퍼가 **하루 30건**을 보냈다(매시 :15, 전부 동일).
#   내용은 *"코어가 2커밋 뒤처졌다"* 인데 그건 **승인 대기로 일부러 안 당기는 상태**였다.
#   거짓 호출이 반복되면 사람이 알림을 끈다 ⇒ 진짜가 왔을 때 묻힌다(워치독 #64 와 같은 논리).
# 🔴 그리고 **급한 것과 안 급한 것이 안 갈렸다** — 30건 전부 process_behind=0(재시작 불필요)인데
#   실행 파일이 바뀐 날에도 문구가 같았다. "이 값이 두 상태를 갈라주나" 에 걸린 자리.
no_state
mkfake 1 "DRIFT: repo_behind=2커밋 · process_behind=0파일 (aaa → bbb)"; run
grep -q "코어 드리프트" <<<"$out" && ok "처음 본 드리프트는 알린다" || bad "첫 알림 없음" "$out"
run
[ -z "$out" ] && ok "같은 상태가 이어지면 **조용하다**" || bad "같은 상태 반복 알림" "$out"
[ "$rc" -eq 1 ] && ok "조용해도 종료코드는 그대로 1 (억제는 알림만, 판정이 아니다)" || bad "종료코드 $rc"

mkfake 1 "DRIFT: repo_behind=3커밋 · process_behind=0파일 (aaa → ccc)"; run
grep -q "repo_behind=3커밋" <<<"$out" && ok "상태가 바뀌면 다시 알린다(2→3커밋)" || bad "변화를 못 알렸다" "$out"

echo "  🔑 실행 파일이 바뀌면 = 재시작이 필요하다 = **매번 알린다**"
no_state
mkfake 1 "DRIFT: repo_behind=3커밋 · process_behind=2파일 (aaa → ccc)"; run
grep -q "코어 드리프트" <<<"$out" && ok "process_behind>0 첫 알림" || bad "첫 알림 없음" "$out"
run
grep -q "코어 드리프트" <<<"$out" && ok "process_behind>0 는 같은 상태여도 **억제하지 않는다**" \
  || bad "행동이 필요한 알림을 억제했다" "${out:-<조용>}"

echo "  🔑 판정 불가(rc≠1)도 억제하지 않는다 — 검사기가 **못 돈 것**이라 접으면 죽은 검사가 조용해진다"
# 변이 ②(`[ "$RC" -eq 1 ] || FORCE=1` 제거)가 안 물어서 추가했다.
# 기존 rc=2 시험은 매번 **다른 서명**이라 억제 경로를 아예 안 지나갔다 — 같은 것을 두 번 돌려야 잡힌다.
no_state
mkfake 2 "UNKNOWN: 검사기가 못 돌았다"; run
grep -q "판정 불가" <<<"$out" && ok "판정 불가 첫 알림" || bad "첫 알림 없음" "${out:-<조용>}"
run
grep -q "판정 불가" <<<"$out" && ok "판정 불가는 **반복돼도 억제하지 않는다**" \
  || bad "죽은 검사가 조용해졌다" "${out:-<조용>}"

echo "  🟡 해소되면 상태를 지운다 — 재발 시 즉시 부를 수 있게"
no_state
mkfake 1 "DRIFT: repo_behind=2커밋 · process_behind=0파일 (aaa → bbb)"; run
mkfake 0 "OK: repo_behind=0 · process_behind=0"; run
[ -z "$out" ] && ok "해소는 조용하다(rc=0)" || bad "해소인데 떠들었다" "$out"
mkfake 1 "DRIFT: repo_behind=2커밋 · process_behind=0파일 (aaa → bbb)"; run
grep -q "코어 드리프트" <<<"$out" && ok "해소 뒤 재발하면 **즉시** 알린다" || bad "재발을 놓쳤다" "${out:-<조용>}"

echo "  🟡 오래 이어지면 다시 한 번 부른다 — 영영 잊지는 않는다"
no_state
mkfake 1 "DRIFT: repo_behind=2커밋 · process_behind=0파일 (aaa → bbb)"; run
RENOTIFY_AFTER=0 run
grep -q "코어 드리프트" <<<"$out" && ok "재알림 간격이 지나면 같은 상태여도 부른다" \
  || bad "영영 조용해졌다" "${out:-<조용>}"

echo "  🟡 상태 파일이 깨졌으면 **부르는 쪽**으로 — 못 부른 사고가 헛부름보다 비싸다"
no_state
mkfake 1 "DRIFT: repo_behind=2커밋 · process_behind=0파일 (aaa → bbb)"; run
printf 'garbage\n' > "$ROOT/notify-state"; run
grep -q "코어 드리프트" <<<"$out" && ok "손상된 상태 파일 → 알린다(fail-open)" || bad "손상 시 침묵" "${out:-<조용>}"

echo
echo "  통과 $pass · 실패 $fail"
[[ "$fail" -eq 0 ]]
