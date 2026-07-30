#!/usr/bin/env bash
# portability-guard.sh — GNU/BSD 로 갈리는 **시각 도구**가 정본 밖에 있는지 잰다. **여기가 정본이다.**
#
# 🔴 왜 공용인가 (2026-07-31):
#   같은 가드를 `nino-watchdog.test.sh` 안에 두고 있었는데, **가드가 파일마다 사본**이면
#   새 시험 파일은 그냥 **안 쓰는 것으로 통과**한다. 실제로 그렇게 됐다 —
#   `tests/lib/timeshift.sh` 머리말에 *"사본 금지, 정본은 이 파일 하나"* 가 적혀 있는데도
#   `nino-watchdog.test.sh` 가 source 를 안 해 룬드 맥에서 4 fail 이 났다.
#   🔑 **안 쓰는 것이 조용한 한, 정본은 권고일 뿐이다.** 시끄럽게 만드는 게 이 파일이다.
#
# 🔑 무엇을 보나 — 명령 **목록**이 아니라 **성질**:
#   "GNU/BSD 로 갈리는 시각 도구가, 폴백도 정본 헬퍼도 없이 명령 위치에 있다"
#
# 🔸 세 가지를 면제한다. 면제 이유가 전부 *측정된 오탐*이다:
#   ① 주석 줄                    — 호출이 아니다
#   ② **가까이 있는** BSD 폴백     — `stat -c … || stat -f …`. 같은 줄만 보면 안 된다:
#                                  `morning-briefing.sh` 의 `file_mtime()` 은 `date -r` 과
#                                  `stat -f` 가 **두 줄로 갈려** 있어 오탐이 났다(실측).
#                                  ⇒ ±4행 창으로 본다.
#   ③ **문자열 속** 등장          — `ok "GNU date -d 는 …"` 같은 *설명 문구*와
#                                  가드 자신의 패턴 리터럴이 여기 걸린다.
#                                  ⇒ **명령 위치**(줄머리·`;`·`|`·`&&`·`(`·`$(`·`{` 뒤)만 본다.
#   ⚠️ ③ 없이 재보면 오탐 6곳이 나온다(실측). 그중 둘은 **이 가드가 자기 패턴을 세는 것**이라,
#     면제가 없으면 *검사기가 자기를 센다* 형태가 된다.
#
# 사용:  . tests/lib/portability-guard.sh ;  portability_scan <파일...>
#        stdout 에 "<파일>:<행> <구문>" 한 줄씩. 없으면 아무것도 안 낸다. rc 는 항상 0 —
#        🔴 **판정은 부르는 쪽이 한다**(rc 로 접으면 `|| true` 한 번에 조용해진다).

portability_scan() {
    python3 - "$@" <<'PYEOF'
import re, sys, os

LEAD = r'(?:^|[;&|(`{]|&&|\|\|)\s*'
RULES = [
    (LEAD + r'date\s+(?:-u\s+)?-d\b',  'date -d',  r'\bdate\s+-[vr]\b'),
    (LEAD + r'touch\s+-d\b',           'touch -d', r'\btouch\s+-t\b'),
    # 🔸 mtime 을 읽는 방법이 셋(`stat -c` GNU · `stat -f` BSD · `date -r <파일>` 양쪽)이라,
    #   짝은 **같은 명령**이 아니라 *"다른 방법이 곁에 있나"* 로 본다.
    (LEAD + r'stat\s+-c\b',            'stat -c',  r'\bstat\s+-f\b|\bdate\s+-r\b'),
    (LEAD + r'stat\s+-f\b',            'stat -f',  r'\bstat\s+-c\b|\bdate\s+-r\b'),
    # 🔴 `date -r` 규칙은 **뺐다**(실측으로 오탐): `date -r <파일>` 은 GNU/BSD 둘 다 된다.
    #   갈리는 건 `date -r <epoch>` 뿐이고 그건 정본(timeshift.sh)에만 있다.
    #   ⇒ 규칙을 늘리기 전에 **양쪽에서 실제로 갈리는지** 먼저 확인한다.
]
# 정본 헬퍼 자신은 GNU/BSD 를 **둘 다** 써야 한다 — 그게 그 파일의 일이다.
# 🔴 정본 자신과 **이 가드의 시험**은 뺀다.
#   정본은 GNU/BSD 를 둘 다 써야 하고(그게 그 파일의 일이다),
#   `portability.test.sh` 는 **일부러 위반을 심은 픽스처**를 갖고 있다.
#   ⚠️ 이걸 안 빼면 *검사기가 자기를 센다* — 이 레포에서 네 번째로 세는 형태다.
CANON = ('timeshift.sh', 'portability-guard.sh', 'portability.test.sh')

for path in sys.argv[1:]:
    if os.path.basename(path) in CANON:
        continue
    try:
        src = open(path, errors='replace').read()
    except OSError as e:
        print(f"{path}:0 못 읽었다({e.__class__.__name__})")
        continue
    # 파일 안에 남아 있는 옛 정본 헬퍼(iso_off) 본문도 면제 — 그 안은 분기가 의도다
    m = re.search(r'^iso_off\(\)\s*\{.*?^\}', src, re.S | re.M)
    exempt = set(m.group(0).splitlines()) if m else set()
    lines = src.splitlines()
    for i, line in enumerate(lines, 1):
        if line.lstrip().startswith('#') or line in exempt:
            continue
        # 🔴 **가까움은 폴백이 아니다.** 처음엔 ±4행 창으로 봤는데, 서로 무관한 두 사용이
        #   **서로를 면제**해버렸다(실측: 픽스처 4건 중 `stat -c`·`stat -f` 2건이 조용해졌다).
        #   ⇒ 같은 줄이거나, **바로 옆 줄이면서 둘 중 하나에 `||` 가 있을 때**만 폴백으로 본다.
        #     `m=$(date -r …) || m=""` / `[[ … ]] || m=$(stat -f …)` 형태가 그것이다.
        adj = lines[max(0, i - 2):i + 1]
        near = line if '||' not in "\n".join(adj) else "\n".join(adj)
        for pat, name, bsd in RULES:
            if re.search(pat, line) and not re.search(bsd, near):
                print(f"{path}:{i} {name}")
PYEOF
}
