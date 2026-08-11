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
        # ⚠️ `<<<` 는 herestring 이지 heredoc 이 아니다. 오인하면 델리미터가 영영 안 와서
        #    **그 뒤 문장 전부가 사각**이 된다(룬드 실측, 그도 코어 ⑯-g 로 같은 축을 잠갔다).
        #    ⇒ `<<` 앞뒤에 `<` 가 없어야 heredoc.
        m = re.search(r"(?<!<)<<(?!<)-?\s*([\"\x27]?)([A-Za-z_][A-Za-z0-9_]*)\1", line)
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

# 🔴 **rc 를 «가로채지 않고» 남의 rc 를 그대로 돌려주는 것들.** 이걸 안 벗기면 좌변이
#    `command`·`timeout` 에서 멈춰 EFFECT/OBSERVE 열거에 안 걸린다 — 조용한 미탐.
#    실측 2026-08-11: 다섯 꼴(`| command tail` · `| timeout 5 tail` · `| env LC_ALL=C grep`
#    · `timeout 60 git push |` · `nohup git push |`)이 **전부 통과**했고 맨몸만 막혔다.
#    🔑 이 미탐은 **우리 계약이 만든다** — 계약이 `command grep` 을 쓰라고 시키므로(Bash 도구의
#      `grep` 이 셸 함수라 ignore 트리를 건너뛴다) 손버릇이 정확히 열거 «밖»으로 간다. 룬드 #155 동형.
#    🔸 `xargs` 는 **일부러 안 넣는다** — 자체 실행기라 그 rc 가 xargs 것이고, 벗기면 뜻이 달라진다.
#      열거는 여전히 남지만 **틀릴 거면 «안 벗기는»(=미탐) 쪽으로** 틀린다.
WRAPPERS = {"command", "builtin", "exec", "env", "nice", "nohup", "stdbuf",
            "time", "timeout", "sudo", "setsid", "ionice", "chrt"}
# 🔴 `timeout`·`time` 의 시간 인자는 **옵션도 `VAR=` 도 아닌 맨 낱말**이라 옵션 건너뛰기로는
#    안 넘어간다 — 여기서 멈추면 좌변이 `5` 가 돼 다시 미탐이다(룬드 판에 이 갈래가 없다).
DURATION = re.compile(r"^[0-9]+(\.[0-9]+)?[smhd]?$")

def effective_tokens(seg):
    """래퍼를 벗기고 **실제로 도는 명령**의 낱말들을 돌려준다.

    🔑 좌변을 «꼴의 열거»가 아니라 «뜻»으로 적는다 — 뜻은 「이 낱말의 rc 가 제 것인가」다.
       `git_subcommand()` 가 이미 같은 생각(옵션과 그 값을 건너뛰고 진짜 낱말을 찾는다)을
       하고 있었는데 **`git` 축에만 걸려 있어서** 이 래퍼 축으로 안 왔다. 같은 파일 안에서
       한 함수 옆에 있던 기법이 안 건너온 것 — 「근거를 조항 «안»에 적으면 그 범위로 닫힌다」.
    """
    toks = seg.split()
    i = 0
    while i < len(toks):
        t = toks[i]
        if t.startswith("-"):                       # 래퍼의 옵션
            i += 1
            continue
        if "=" in t:                                # VAR=v cmd 형태의 앞부분
            i += 1
            continue
        base = t.rsplit("/", 1)[-1]
        if base not in WRAPPERS:
            return toks[i:]
        i += 1
        if base in ("timeout", "time") and i < len(toks) and DURATION.match(toks[i]):
            i += 1
    return []

def first_word(seg):
    toks = effective_tokens(seg)
    return toks[0] if toks else ""

# git 의 **전역 옵션 중 값을 따로 받는 것**. 이걸 모르면 그 «값»이 하위명령 자리에 남는다.
# 🔴 룬드 실측: `git -C /path commit … | tail && push` 가 rc=0 이었다 — `-C` 는 옵션이라 걸러지고
#    `/path` 가 parts[1] 이 돼 GIT_EFFECT 불매치. 우리 둘 다 cwd 함정 때문에 `git -C` 를 표준으로
#    쓰므로, **막으려는 사고가 가장 자주 나타나는 표기로 오면 통과**하고 있었다.
GIT_VALUE_GLOBALS = {"-C", "-c", "--git-dir", "--work-tree", "--namespace",
                     "--exec-path", "--super-prefix", "--config-env"}

def git_subcommand(seg):
    """옵션(과 그 값)을 건너뛰고 **첫 비옵션 낱말**을 하위명령으로 본다.

    🔑 좌변이 `seg.split()` 이면 `timeout 60 git … ` 에서 i=1 이 `60` 을 가리킨다 —
       래퍼를 벗긴 낱말 목록 위에서 세야 두 수리가 «겹쳐서» 산다(`timeout 60 git -C /r push`).
    """
    toks = effective_tokens(seg)
    if not toks:
        return ""
    i = 1
    while i < len(toks):
        t = toks[i]
        if not t.startswith("-"):
            return t
        i += 2 if (t in GIT_VALUE_GLOBALS and "=" not in t) else 1
    return ""

def is_effect(seg):
    w = first_word(seg)
    base = w.rsplit("/", 1)[-1]
    if base == "git":
        return git_subcommand(seg) in GIT_EFFECT
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

# ── 차단을 «센다». 이게 없으면 이 가드의 효과가 영원히 «일화»로만 남는다.
#   🔴 실물(2026-08-10): 룬드의 Tim 보고에 「오늘 세 번 막혔다」를 보태놓고 «세지 않고» 말했다.
#      재셀 유일 경로가 내 세션 jsonl 이었고, 그건 압축되면 사라지고 남이 검산할 수도 없다.
#   🔑 ⏱️ 「칸의 효과는 채택 시각 이후 사례로만 센다」는 «셀 수단»이 있어야 실행된다.
#   ⚠️ 실패 방향은 이 파일의 나머지와 같다 — 로그를 못 써도 **차단은 그대로 한다**(조용히 통과 X).
_log="${RC_PIPE_GUARD_LOG:-$HOME/discord-bot-nino/logs/rc-pipe-guard.log}"
if mkdir -p "$(dirname "$_log")" 2>/dev/null; then
    # 한 줄로 접는다 — 여러 줄이면 `wc -l` 이 건수가 아니게 된다.
    printf '%s\tBLOCK\t%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" \
        "$(printf '%s' "$verdict" | tr '\n\t' '  ')" >> "$_log" 2>/dev/null || true
fi
exit 2
