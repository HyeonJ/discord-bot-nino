#!/usr/bin/env bash
# heredoc-form-guard.sh — 명령치환 **안**의 heredoc(`$( … <<TAG … )`)을 잰다. **여기가 정본이다.**
#
# 🔴 왜 이 형태인가:
#   bash 3.2 는 `$( … << 'X' … )` 본문의 **백틱이 홀수**면 파싱에서 죽는다. bash 5 는 둘 다 통과.
#   ⇒ 내 기계에서는 영원히 조용하고 룬드 맥에서만 터진다. 지금 남은 자리는 전부 짝수라
#     **버그가 아니라 뇌관**이고, 방아쇠는 «본문 편집»이다(백틱 하나면 홀수가 된다).
#
# 🔸 면제 네 가지. ①②③은 `portability-guard.sh` 와 같은 축인데 **④는 새 종류다** —
#   같은 인벤토리를 스캐너 두 판본으로 재봤더니 셋 다 **실물로** 나왔다(2026-08-02 실측):
#     ① 주석 줄            — `shared-contract-drift.test.sh:253` 의 `<<'PY'` 언급
#     ② `<<<` 히어스트링    — `check-usage-alert.test.sh:460` 의 printf 문자열
#     ③ 표식 `hygiene:allow-heredoc-subst` — 근거를 그 줄에 적고 넘어간다
#     ④ **다른 heredoc 본문 안**에 있는 opener 모양 — `catchup-hint.test.sh:425` 의
#        파이썬 정규식 `r"<<'PYEOF'.*?^PYEOF"`. 이건 **열림이 아니라 데이터**다.
#   🔑 ④ 가 없으면 검사기가 «자기 시험의 픽스처»를 센다 — 이 레포에서 다섯 번째로 세는 형태다.
#
# 🔸 **이 가드가 못 보는 것** — 값싼 수이지 완전한 수가 아니다:
#   · 여는 `$(` 와 `<<` 가 **다른 줄**로 갈리면 못 잡는다(같은 줄의 괄호 균형만 본다)
#   · 백틱 형태 `` `cmd <<X` `` 는 안 본다 — 3.2 사망이 확인된 건 `$()` 형태다
#   · 한 줄에 heredoc 이 둘이면 첫 것만 본다
#   적어두는 이유는 다음 사람이 *잡히니까 없다* 로 읽지 않게 하기 위해서다.
#
# 사용:  . tests/lib/heredoc-form-guard.sh ;  heredoc_subst_scan <파일|디렉터리...>
#        stdout 에 "<파일>:<행> $( … <<TAG ) 백틱 N(짝/홀)" 한 줄씩. 없으면 아무것도 안 낸다.
#        rc 는 항상 0 — 🔴 **판정은 부르는 쪽이 한다**(rc 로 접으면 `|| true` 한 번에 조용해진다).

heredoc_subst_scan() {
    python3 - "$@" <<'PYEOF'
import os, re, sys

OPEN  = re.compile(r"<<(?!<)-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")
ALLOW = re.compile(r'hygiene:allow-heredoc-subst')
# 정본 자신과 그 시험(일부러 위반을 심은 픽스처를 갖는다)은 뺀다.
CANON = ('heredoc-form-guard.sh',)


def scan(path):
    try:
        lines = open(path, errors='replace').read().split("\n")
    except OSError as e:
        print(f"{path}:0 못 읽었다({e.__class__.__name__})")
        return

    i, n = 0, len(lines)
    while i < n:
        line = lines[i]
        m = None if line.lstrip().startswith('#') else OPEN.search(line)
        if not m:
            i += 1
            continue

        tag = m.group(2)
        # 본문을 먼저 걷는다 — 열림이든 아니든 **본문 안은 데이터**다(면제 ④).
        body, j = [], i + 1
        while j < n and lines[j].strip() != tag:
            body.append(lines[j])
            j += 1

        # 같은 줄에서 `<<` 앞의 괄호 균형 — 안 닫힌 `$(` 가 있으면 명령치환 안이다.
        head = line[:m.start()]
        depth = head.count('$(') - head.count(')')
        if depth > 0 and not ALLOW.search(line):
            ticks = sum(x.count('`') for x in body)
            par = '홀' if ticks % 2 else '짝'
            print(f"{path}:{i + 1} $( … <<{tag} ) 백틱 {ticks}({par})")

        i = j + 1


targets = []
for arg in sys.argv[1:]:
    if os.path.isdir(arg):
        for dp, _, fn in os.walk(arg):
            if 'node_modules' in dp:
                continue
            targets += [os.path.join(dp, f) for f in sorted(fn) if f.endswith('.sh')]
    else:
        targets.append(arg)

for path in targets:
    if os.path.basename(path) not in CANON:
        scan(path)
PYEOF
}
