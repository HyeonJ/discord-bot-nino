#!/usr/bin/env bash
# discord-send 계약 테스트 (DISCORD_SEND_DRY_RUN 하네스)
# 2026-07-25 단계2 전환: 실물 bash → 코어 셔틀로 정본 교체.
#   - 멘션 변환 10케이스는 **전환 전후 동일 기대값** = 동작 보존(behavior-preserving) 증거.
#   - DRY_RUN 출력 포맷이 legacy(`msg=`) → 코어(`POST /channels/<id>/messages {json}`)로 변경돼
#     추출부만 JSON 파싱으로 교체했다. 기대값은 손대지 않았다.
#   - §13.4 신동작 3건 + §14-④⑤도 여기서 고정한다(니노 레벨 계약).
# 격리: SHIM_LOG를 임시파일로 덮어써 §8 7일 카운터(logs/discord-send-shim.log)를 오염시키지 않는다.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SEND="$BOT_DIR/src/discord-send"
CH=1479813609499394169  # 일반 (raw ID — channel-map 조회 우회)

NODE_BIN="$(command -v node || true)"
[[ -n "$NODE_BIN" ]] || NODE_BIN=/home/bpx27/.nvm/versions/node/v24.14.0/bin/node

SHIM_TMP="$(mktemp)"
trap 'rm -f "$SHIM_TMP"' EXIT
export DISCORD_SEND_SHIM_LOG="$SHIM_TMP"

pass=0; fail=0; skipped=0
# ⚠️ ((pass++))는 pass=0일 때 exit 1을 반환해 `check && ok || bad`가 둘 다 실행된다 → 산술 대입으로 회피
ok()   { echo "  ✅ $1"; pass=$((pass + 1)); }
bad()  { echo "  ❌ $1"; echo "     want: [$2]"; echo "     got:  [$3]"; fail=$((fail + 1)); }

# DRY_RUN 본문(JSON)에서 필드 하나 추출. $1=필드 경로(예: content, message_reference.message_id)
field_of() {
  "$NODE_BIN" -e '
    let s = ""; process.stdin.on("data", d => s += d).on("end", () => {
      const line = s.split("\n").find(l => l.startsWith("DRY_RUN POST"));
      if (!line) return;
      const body = line.slice(line.indexOf("{"));
      let v; try { v = JSON.parse(body); } catch { return; }
      for (const k of process.argv[1].split(".")) v = v?.[k];
      process.stdout.write(v == null ? "" : String(v));
    });
  ' "$1"
}

# $1=설명 $2=입력 메시지 $3=기대 content
check() {
  local desc="$1" input="$2" want="$3" got
  got=$(DISCORD_SEND_DRY_RUN=1 "$SEND" -c "$CH" "$input" 2>&1 | field_of content)
  [[ "$got" == "$want" ]] && ok "$desc" || bad "$desc" "$want" "$got"
}

echo "discord-send 멘션 변환 (전환 전후 동일 기대값 = 동작 보존):"
check "@룬드 → <@ID>"              "@룬드 안녕"                  "<@1479854253462781962> 안녕"
check "@Darren → <@ID>"           "@Darren 봐봐"               "<@353914579929268226> 봐봐"
check "@충재(본명) → Tim ID"      "@충재 형"                   "<@265454241387249665> 형"
check "@현인(본명) → Darren ID"   "@현인 뭐해"                 "<@353914579929268226> 뭐해"
check "이미 <@ID>면 보존(중복변환X)" "<@265454241387249665> 안녕" "<@265454241387249665> 안녕"
check "이메일 @는 안전(미매칭)"    "메일 test@x.com 확인"       "메일 test@x.com 확인"
check "조사 붙으면 미변환(nuance)" "@룬드가 말했어"             "@룬드가 말했어"
check "멘션 없는 평문 불변"        "그냥 텍스트"                "그냥 텍스트"
check "긴 이름 우선(부분일치 방지)" "@니노 야"                   "<@1479865978803195976> 야"
check "다중 멘션"                  "@룬드 @Darren 회의"         "<@1479854253462781962> <@353914579929268226> 회의"

echo ""
echo "코어 전환 신동작 (§13.4 3건 + §14-④⑤):"

# ① 리터럴 \n → 실개행 (legacy는 리터럴 유지, 코어는 치환 — §12-3)
got=$(DISCORD_SEND_DRY_RUN=1 "$SEND" -c "$CH" '첫줄\n둘째줄' 2>&1 | field_of content)
[[ "$got" == "첫줄"$'\n'"둘째줄" ]] && ok "① 리터럴 \\n → 실개행" || bad "① 리터럴 \\n → 실개행" '첫줄<LF>둘째줄' "$got"

# ① escape: 이중 백슬래시는 리터럴 \n 유지 (§7 표기 의도)
got=$(DISCORD_SEND_DRY_RUN=1 "$SEND" -c "$CH" '첫줄\\n둘째줄' 2>&1 | field_of content)
[[ "$got" == '첫줄\n둘째줄' ]] && ok "① \\\\n escape → 리터럴 유지" || bad "① \\\\n escape → 리터럴 유지" '첫줄\n둘째줄' "$got"

# ② channel-map miss → 조용한 404 대신 명시 에러 (exit≠0 + stderr)
err=$(DISCORD_SEND_DRY_RUN=1 "$SEND" -c 없는채널이름 "hi" 2>&1 >/dev/null); code=$?
[[ $code -ne 0 && -n "$err" ]] && ok "② channel-map miss → exit≠0 + stderr" || bad "② channel-map miss → exit≠0 + stderr" "exit≠0 + stderr" "exit=$code err=[$err]"

# ③ target 생략 → 기본채널 폴백 폐지, 명시 에러 (§12-4)
err=$(DISCORD_SEND_DRY_RUN=1 "$SEND" 2>&1 >/dev/null); code=$?
[[ $code -ne 0 && -n "$err" ]] && ok "③ target 생략 → exit≠0 + stderr" || bad "③ target 생략 → exit≠0 + stderr" "exit≠0 + stderr" "exit=$code err=[$err]"

# ④ -r <해시> → message_reference 세팅 (해시 역조회, §14-④ 계열)
BUN_BIN="$(command -v bun || true)"
[[ -n "$BUN_BIN" ]] || BUN_BIN=/home/bpx27/.nvm/versions/node/v24.14.0/bin/bun
HASH=$("$BUN_BIN" -e '
  const { Database } = require("bun:sqlite");
  const path = process.env.YAKSU_HISTORY_DB || `${process.env.HOME}/.local/share/yaksu-history/messages.db`;
  const db = new Database(path, { readonly: true });
  const row = db.query("SELECT message_hash FROM messages WHERE message_hash IS NOT NULL ORDER BY timestamp DESC LIMIT 1").get();
  process.stdout.write(row ? row.message_hash : "");
' 2>/dev/null)
if [[ -n "$HASH" ]]; then
  got=$(DISCORD_SEND_DRY_RUN=1 "$SEND" -c "$CH" -r "$HASH" "답장" 2>&1 | field_of message_reference.message_id)
  [[ -n "$got" ]] && ok "④ -r 해시 → message_reference 역조회" || bad "④ -r 해시 → message_reference 역조회" "message_id 있음" "빈값"
else
  # 조용한 스킵은 "CI 그린 = 검증됨"이라는 착각을 만든다(룬드 M:bzqi) → 이유를 stderr로 시끄럽게.
  # 근본 해결은 fixture DB(후속). 그때까지는 최소한 스킵 사실이 눈에 띄게 한다.
  skipped=$((skipped + 1))
  echo "  ⏭️  ④ -r 해시 역조회 — **스킵됨**"
  echo "     이유: 실DB($([[ -n "${YAKSU_HISTORY_DB:-}" ]] && echo "$YAKSU_HISTORY_DB" || echo "$HOME/.local/share/yaksu-history/messages.db"))에 message_hash 행이 없음" >&2
  echo "     ⚠️ 이 케이스는 검증되지 않았다 — DB 상태 의존(fixture DB로 대체 예정)" >&2
fi

# ⑤ QUIET=1: stderr 경고 없음 + SHIM_LOG 카운터는 유지 (§14-⑤ 정책)
: > "$SHIM_TMP"
err=$(DISCORD_SEND_DRY_RUN=1 "$SEND" -c "$CH" "quiet" 2>&1 >/dev/null)
lines=$(wc -l < "$SHIM_TMP")
if [[ "$err" != *deprecated* && "$lines" -ge 1 ]]; then
  ok "⑤ QUIET=1 → 경고 없음 + 카운터 기록 유지"
else
  bad "⑤ QUIET=1 → 경고 없음 + 카운터 기록 유지" "경고없음 + 기록≥1" "err=[$err] lines=$lines"
fi

# ⑥ QUIET 빈값 = "억제 해제" → 경고 다시 보임 (플래그성 env는 `${VAR-기본}`이라야 성립)
# 왜: `${VAR:-1}`은 빈 문자열도 미설정으로 취급해 1로 채워버려, 빈값으로 억제를 풀 수 없었다
# (룬드 M:s7e9가 CALLER_EXCLUDE에서 같은 함정을 밟고 발견). 값이 의미인 env는 `:-`, 플래그는 `-`.
: > "$SHIM_TMP"
err=$(DISCORD_SEND_DRY_RUN=1 DISCORD_SEND_QUIET_SHIM= "$SEND" -c "$CH" "unquiet" 2>&1 >/dev/null)
lines=$(wc -l < "$SHIM_TMP")
if [[ "$err" == *deprecated* && "$lines" -ge 1 ]]; then
  ok "⑥ QUIET 빈값 → 경고 복원 + 카운터 유지"
else
  bad "⑥ QUIET 빈값 → 경고 복원 + 카운터 유지" "경고있음 + 기록≥1" "err=[$err] lines=$lines"
fi

echo ""
if [[ $skipped -gt 0 ]]; then
  echo "결과: $pass pass, $fail fail, ⚠️ $skipped skipped (미검증 — 위 stderr 참고)"
else
  echo "결과: $pass pass, $fail fail"
fi
[[ $fail -eq 0 ]]
