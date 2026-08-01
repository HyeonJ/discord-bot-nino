#!/bin/bash
# rc-pipe-guard.sh — PreToolUse(Bash) hook
# 「rc 를 볼 자리에 파이프를 붙이지 않는다」(skill shell-git-procedure 1번)를 **도구로 박는다**.
#
# 🔴 실사고: `git commit -F msg.txt file.sh | tail -2 && git push`
#    파이프라인의 rc 는 **마지막 명령(tail)의 것**이라, commit 이 pathspec 오류로 실패했는데도
#    `&&` 가 통과시켜 **빈 브랜치를 push** 했다. 규칙은 그 전부터 있었고 그 뒤로도 밟았다
#    ⇒ 대전제 Ⅳ: 매번 같은 검사가 가능하면 문장이 아니라 **도구**에 넣는다.
#
# 🔑 넷이 **다 참일 때만** 막는다 (하나라도 빠지면 정상 관용구다):
#    ① 파이프 끝이 관찰·자름 도구       ② 그 파이프라인의 rc 가 `&&`/`||` 로 소비된다
#    ③ 파이프 앞머리가 부작용 명령      ④ `pipefail` 이 안 켜져 있다
#    좁게 잡는 이유: **고칠 수 없는 오탐은 가드를 죽인다**(사람은 파일이 아니라 가드를 끈다).
#
# 🔑 분석 전에 **실행되지 않는 글자**를 지운다 — heredoc 본문·따옴표 안·주석.
#    나는 이 사고 예시를 코드블록으로 자주 보낸다. 안 지우면 가드가 **자기 설명을 막는다.**
#    ⚠️ 지우기는 **문자열 전체 상태기계**로 한다. 줄 단위로 훑으면 여러 줄에 걸친 따옴표에서
#       열린 상태를 다음 줄로 못 가져간다(룬드가 코어 lint 백틱 사각에서 실측한 것과 같은 기전).
#
# 실패 방향: 파싱 불가·비Bash 는 **통과**(exit 0). 가드가 도구를 못 쓰게 만들면 안 된다.
#    ⇒ 거짓 음성(조용) 쪽으로 실패한다. 시끄러운 쪽이 낫다는 기준과 어긋나 보이지만,
#      여기선 **차단 자체가 시끄러운 행위**라 오탐의 대가가 더 크다(가드 폐기 = 축 전체 상실).

input=$(cat)

verdict=$(printf '%s' "$input" | python3 -c '
import json, re, sys

RAW = sys.stdin.read()
try:
    payload = json.loads(RAW)
except Exception:
    sys.exit(0)                      # 페이로드가 아니면 관여하지 않는다
if payload.get("tool_name") not in (None, "Bash"):
    sys.exit(0)
cmd = payload.get("tool_input", {}).get("command", "")
if not cmd:
    sys.exit(0)

# ── 1) heredoc 본문 제거 (본문 안엔 따옴표·파이프가 마음대로 산다) ──
def strip_heredocs(text):
    lines, out, i = text.split("\n"), [], 0
    while i < len(lines):
        line = lines[i]
        out.append(line)
        m = re.search(r"<<-?\s*([\"\x27]?)([A-Za-z_][A-Za-z0-9_]*)\1", line)
        i += 1
        if m:
            delim = m.group(2)
            while i < len(lines) and lines[i].strip() != delim:
                i += 1
            if i < len(lines):
                out.append("")       # 종료 구분자 줄은 빈 줄로 (문장 경계 보존)
                i += 1
    return "\n".join(out)

# ── 2) 따옴표 안 + 주석 제거 (상태기계 — 줄 경계를 넘어 상태를 가져간다) ──
def mask(text):
    out, st, i, n = [], "N", 0, len(text)
    while i < n:
        c = text[i]
        if st == "N":
            if c == "\\" and i + 1 < n:
                out.append(" "); i += 2; continue
            if c == "\x27": st = "S"; out.append(" "); i += 1; continue
            if c == "\"":   st = "D"; out.append(" "); i += 1; continue
            if c == "#" and (not out or out[-1].isspace()):
                while i < n and text[i] != "\n":
                    i += 1
                continue
            out.append(c); i += 1; continue
        if st == "S":
            if c == "\x27": st = "N"
            out.append("\n" if c == "\n" else " ")   # 줄 수는 보존, 내용은 지운다
            i += 1; continue
        # st == "D"
        if c == "\\" and i + 1 < n:
            out.append("  "); i += 2; continue
        if c == "\"": st = "N"
        out.append("\n" if c == "\n" else " ")
        i += 1
    return "".join(out)

code = mask(strip_heredocs(cmd))

if re.search(r"\bpipefail\b", code):
    sys.exit(0)                      # ④ 켜져 있으면 파이프가 rc 를 안 먹는다

OBSERVE = {"head","tail","wc","less","more","cat","tee","column","nl"}
# rc 가 의미 있는(부작용) 명령. git 은 하위명령까지 봐야 한다 — status/log/diff 는 읽기다.
EFFECT = {"npm","pnpm","yarn","bun","pip","uv","make","cp","mv","rm","mkdir","chmod","chown",
          "ln","tar","rsync","install","systemctl","docker","terraform","ansible","gradlew",
          "./gradlew","mvn","cargo","go","pytest","jest"}
GIT_EFFECT = {"commit","push","pull","merge","rebase","reset","checkout","switch","tag",
              "cherry-pick","revert","clean","stash","fetch","am","apply","mv","rm","add"}

def first_word(seg):
    for w in seg.split():
        if "=" in w and not w.startswith("-"):   # VAR=v cmd 형태의 앞부분은 건너뛴다
            continue
        return w
    return ""

def is_effect(seg):
    w = first_word(seg)
    base = w.rsplit("/", 1)[-1]
    if base == "git":
        parts = [p for p in seg.split() if not p.startswith("-")]
        return len(parts) > 1 and parts[1] in GIT_EFFECT
    return base in EFFECT

def is_observe(seg):
    return first_word(seg).rsplit("/", 1)[-1] in OBSERVE

# ── 3) 문장으로 가른다. 한 호출에 여러 문장이 산다 ──
for sentence in re.split(r"[\n;]+", code):
    if not sentence.strip():
        continue
    # rc 소비 경계(&&, ||)로 나눈다. **마지막 조각의 rc 는 아무도 안 본다** → segs[:-1].
    # 🔑 여기 원래 `if len(segs) < 2: continue` 가 있었는데 **동치 변이**로 드러나 지웠다 —
    #    조각이 하나면 segs[:-1] 이 이미 빈 목록이라 그 줄은 하중이 0이었다.
    #    조건이 「있다」와 「무언가를 지킨다」는 다르다(변이로만 갈린다).
    segs = re.split(r"\|\||&&", sentence)
    for seg in segs[:-1]:
        stages = [s for s in seg.split("|") if s.strip()]
        if len(stages) < 2:
            continue
        if is_observe(stages[-1]) and is_effect(stages[0]):
            print(stages[0].strip()[:60] + " | ... | " + stages[-1].strip()[:20])
            sys.exit(7)
sys.exit(0)
' 2>/dev/null)
rc=$?

[ "$rc" -eq 7 ] || exit 0

cat >&2 <<EOF
🚫 rc 를 볼 자리에 파이프가 붙었습니다 — 파이프라인의 rc 는 **마지막 명령의 것**이라
   앞의 실패를 \`&&\`/\`||\` 가 못 봅니다. (실사고: commit 실패 → 빈 브랜치 push)

   걸린 자리: $verdict

   ✅ rc 를 먼저 받으세요:
        <명령>
        rc=\$?; echo "rc=\$rc"
        [ \$rc -eq 0 ] || exit 1
        <다음 명령>
   ✅ 또는 같은 호출 안에서 \`set -o pipefail\` 을 켜세요.
   (근거: skill shell-git-procedure 1번 · 관찰만 할 거면 \`&&\` 를 떼면 통과합니다)
EOF
exit 2
