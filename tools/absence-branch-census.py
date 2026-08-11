#!/usr/bin/env python3
"""absence-branch-census — 「도구가 «없을» 때 어느 가지로 떨어지나」를 센다.

좌변: **부재가 떨어지는 가지에 `ok`(=통과)가 있나.**
      🔴 «조건의 부호»가 아니다 — 첫 시도를 「부정 조건」으로 뒀더니 0건이 나왔는데
      정작 찾던 실물(`#187` ④)이 `elif` + 말단 `else→ok` 라 안 부정이었다.
      좌변이 틀리면 0 은 「없다」가 아니라 「안 봤다」다.

왜: 한 부재가 «양방향»으로 틀릴 수 있다 — 같은 `grep` rc=127 이
    한 축은 `else` 로 흘려 «거짓 초록», 다른 축은 «거짓 빨강»을 냈다(2026-08-11 실측).
    ⇒ 「빨강이면 안전」은 그 자리의 `if/elif/else` 배치에 매여 있다.

⚠️ **알려진 한계 — 감싸는 가드를 못 본다.** `if command -v sed …; then note; else <본체> fi`
    로 고쳐도 본체를 그대로 짚는다(과대보고). ⇒ **「이 모양이 있다」는 말할 수 있고
    「고쳤다」는 이 도구로 «증명 못 한다».**

    🔑 이건 **「수렴 실증」**(feedback_verify_mutation.md:125)이 안 떨어지는 갈래인데,
    알려진 갈래(*검사가 자기 수정 행위를 관측 대상에 포함 → 영구 빨강*)와 **겉은 같고**
    (수렴이 안 떨어진다) **갈리는 축은 「고칠 수 있나」**다 — 저건 검사 정의를 고치면 되고
    이건 **능력 밖**이라 고칠 게 없다.

    🔴 **그래서 이 도구에 「고쳤나」를 «묻지 않는다».** 「능력 밖」을 「아직 안 고침」으로
    적으면 이 도구는 영영 «수리 대기»로 살고 **그 사이 그 축은 «감시되는 것처럼» 보인다**
    (룬드 2026-08-11). 고침의 확인은 **그 파일을 직접 읽어서** 한다.

⚠️ **알려진 한계 2 — 블록 파서가 «한 줄 꼴»을 놓친다.** `else X; fi` 처럼 `fi` 가 자기 줄에
    없으면 스택이 안 닫혀 **그 블록이 통째로 분모 밖**으로 떨어진다. 실측: `runner-glob-coverage.
    test.sh:115`(`elif python3 -c 'pass' …`)가 그래서 안 세어졌다 — 생 grep 3건 vs 분모 2개.
    🔑 **이 한계는 «위험 0건»과 구별이 안 된다** — 안 본 것도 0, 봐서 통과한 것도 0이다.
    ⇒ **`--list-denominator` 로 이름을 찍고 생 grep 과 «맞춰본다».** 대조값이 있어도
      맞추는 «동작»이 없으면 없는 것이다(2026-08-11: 3건을 손으로 세어두고도 안 맞춰봤다).

쓰기:
    python3 tools/absence-branch-census.py '(gh|jq|flock|python3|node|pgrep|curl)' tests/*.test.sh
    # ✅ 분모를 «이름»으로 찍는다 — 「N개 봤다」는 「이 파일을 봤나」에 답 못 한다(룬드)
    python3 tools/absence-branch-census.py '(python3|node)' tests/*.test.sh --list-denominator
    # 좌변을 「모든 외부 명령」으로 넓히면 못 고칠 목록이 나온다(grep|sed 로 56건/20파일).
    #   «호스트마다 진짜 갈리는 것»으로 두면 닫힌다(44 시험에 3건, 전부 이미 가드).
"""

import re, sys, pathlib
# 🔴 «분모를 열거하는 모드» — 수로는 「이 파일을 봤나」에 답 못 한다(룬드 2026-08-11).
#   「N개 봤다」는 픽스처 한 장이 분모 «밖»으로 떨어져도 **N 이 하나 줄 뿐**이라 아무도 안 본다.
#   ⇒ 이름을 찍어야 ①「걸리면 «안» 되는 것이 분모 «안»에 있나」가 «조회»가 된다. 없으면 ①도 판단이라 샌다.
LIST_DENOM = '--list-denominator' in sys.argv
argv = [a for a in sys.argv[1:] if a != '--list-denominator']
TOOLS = argv[0]
paths = [pathlib.Path(p) for p in argv[1:]]
def blocks(lines):
    """if…fi 블록을 대충 뜬다 — 들여쓰기 기준 없이 if/fi 깊이로"""
    out=[]; stack=[]
    for i,l in enumerate(lines):
        s=l.strip()
        if re.match(r'^(if|elif)\b', s) and re.match(r'^if\b', s): stack.append(i)
        elif s=='fi' and stack: out.append((stack.pop(), i))
    return out
danger=[]; safe=[]; denom=[]; skipped=[]
for f in paths:
    lines=f.read_text(encoding='utf-8',errors='replace').splitlines()
    for a,b in blocks(lines):
        blk=lines[a:b+1]
        cond_lines=[(a+j+1,x) for j,x in enumerate(blk) if re.match(r'^\s*(if|elif)\b',x)]
        uses=[(ln,x) for ln,x in cond_lines if re.search(r'(^|[\s|(!])(command\s+)?'+TOOLS+r'\b', x)]
        if not uses:
            skipped.append((f.name, a+1, (blk[0].strip()[:60] if blk else '')))
            continue
        denom.append((f.name, uses[0][0], uses[0][1].strip()[:70]))
        # 부재가 떨어지는 곳: 조건이 «부정»이면 그 then, 아니면 마지막 else
        neg = any(re.search(r'!\s*(command\s+)?'+TOOLS, x) for _,x in uses)
        # 마지막 else 다음 8줄
        eidx=[j for j,x in enumerate(blk) if re.match(r'^\s*else\s*$',x)]
        target = blk[eidx[-1]:eidx[-1]+8] if eidx else []
        if neg:
            j=[j for j,x in enumerate(blk) if re.search(r'!\s*(command\s+)?'+TOOLS, x)][0]
            target = blk[j:j+8]
        has_ok = any(re.match(r'\s*ok\s', x) for x in target)
        rec=(f.name, uses[0][0], uses[0][1].strip()[:78], '부정' if neg else '말단else')
        (danger if has_ok else safe).append(rec)
# 🔴 **「옆에 둔다」로는 부족하고 «같은 출력에 나란히» 찍어야 한다**(룬드 2026-08-11).
#   블록 파서를 안 거친 «생 조건 줄» 을 여기서 직접 세어 분모와 **한 줄에** 낸다.
#   ⇒ 파서가 블록을 놓치면(한 줄 꼴 `else X; fi` 등) 두 수가 갈려 **그냥 보인다.**
#   ⚠️ 이걸 「따로 돌려서 맞춰봐라」로 두면 그건 판단이라 샌다 — 2026-08-11 에 내가
#     3 과 2 를 같은 날 손에 쥐고도 안 맞춰봤다.
raw = 0
for f in paths:
    for l in f.read_text(encoding='utf-8', errors='replace').splitlines():
        if re.match(r'^\s*(if|elif)\b', l) and re.search(r'(^|[\s|(!])(command\s+)?'+TOOLS+r'\b', l):
            raw += 1
mark = "✅" if raw == len(denom) else "🔴"
print(f"{mark} 분모 {len(denom)}개  ·  생 조건줄 {raw}건" +
      ("" if raw == len(denom) else f"  ← 갈렸다: 파서가 {raw-len(denom)}개를 «안 봤다»(한 줄 꼴 `else X; fi` 등)"))
if LIST_DENOM:
    print(f"📋 분모 — 이 도구를 «조건에서» 쓰는 if 블록 {len(denom)}개 (파일 {len(paths)}개)")
    for r in denom: print(f"   · {r[0]}:{r[1]}  {r[2]}")
    print(f"📋 분모 «밖» — 조건에 그 도구가 없어 안 본 if 블록 {len(skipped)}개")
    for r in skipped[:10]: print(f"   ⌀ {r[0]}:{r[1]}  {r[2]}")
    if len(skipped) > 10: print(f"   … 외 {len(skipped)-10}개 (전부 보려면 이 목록을 파일로 받을 것)")
    print()
print(f"🔴 위험(부재 → ok 가지): {len(danger)}건")
for r in danger: print(f"   {r[0]}:{r[1]}  [{r[3]}]\n      {r[2]}")
print(f"🔸 안전(부재 → bad/note 가지): {len(safe)}건")
