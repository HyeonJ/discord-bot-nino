#!/usr/bin/env python3
"""재조직 PR 이 «규범»을 흘렸나 — 조각 층 전수 + 인과형 체.

왜 있나
  큰 재조직 PR(문서를 쪼개고 다시 쓰는 것)에서 「규칙 하나가 사라졌나」는
  텍스트 대조로 «원리적으로» 안 갈린다 — 옮기면서 다시 쓰기 때문에
  정확 대조는 거짓 양성을, 느슨한 대조는 거짓 음성을 낸다.
  ⇒ 이 도구는 «증명»이 아니라 «체»다. 509 를 43 으로, 43 을 2 로 줄여
     사람이 읽을 수 있는 크기로 만드는 것까지가 이 도구의 몫이다.

왜 인과형인가
  규범이 「~한다 / ~말 것」이 아니라 「~하면 ~가 된다」로 적히면
  «어떤» 명령형 좌변으로도 안 잡힌다. 두 좌변은 배타적이라 둘 다 돌려야 한다
  (--selftest 가 그 배타성을 대조군으로 지킨다).

층
  조항 층 초록은 「그 조항이 있다」에 답하지 「같은 것을 시키나」엔 답하지 않는다.
  그래서 분모는 «조각 층»(볼드 조각)으로 내려서 센다.

쓰기
  clause-landing-census.py --old <옛 문서> --corpus <새 트리 디렉터리>
  clause-landing-census.py --old old.md --corpus head/ --marker 🤝   # 특정 조항군만
  clause-landing-census.py --selftest
경위: memory/inbox-2026-07-31.md #0811-117
"""

import argparse
import collections
import json
import pathlib
import re
import sys

# 인과형 = «조건 표지» + 40자 이내 «결과 동사». 둘 다 꼴의 열거라 열거 밖은 샌다.
COND = r"(면|니까|라서|므로|때문에|이라|어서|아서|자마자|는 순간|하면)"
RES = (
    r"(샌다|샌|갈린다|갈려|죽는다|죽어|낡는다|낡아|먹는다|먹어|가린다|가려"
    r"|숨는다|숨어|된다|돼|난다|나온다|생긴다|남는다|남아|보인다|읽힌다"
    r"|잡힌다|안 |못 |거짓|무효|틀린|틀리|깨진|깨져|사라)"
)
CAUSAL = re.compile(COND + r".{0,40}?" + RES)
IMPERATIVE = re.compile(
    r"(한다|않는다|말 것|하지 마|금지|해야|안 된다|둔다|적는다|쓴다|⛔|필수|할 것|하자|지켜)"
)

BOLD = re.compile(r"\*\*(.+?)\*\*", re.S)
TOKEN = re.compile(r"[가-힣]{2,}")

# 희귀 토큰 기준 — 이보다 흔한 낱말은 어디서나 맞아 키워드가 못 된다
RARE_MAX_FREQ = 60
COOCCUR_MIN = 2  # 한 파일 안에서 이만큼 공존하면 «재서술로 있다»


def bold_fragments(text, marker=None):
    """볼드 조각을 중복 제거해 돌려준다. marker 를 주면 그 표지가 있는 «줄»의 것만 남긴다.

    🔴 «거르고 추출»하지 않고 «추출하고 라벨»한다 — `**` 짝은 줄을 넘어 맞을 수 있어
    먼저 거르면 조각 «경계»가 달라진다. 그러면 좁힌 집합이 넓은 집합의 부분집합이
    아니게 되어 교집합·잔여 계산이 조용히 틀린다(2026-08-11 실측: 285/81/13 → 281/166/22).
    """
    out, seen = [], set()
    for m in BOLD.finditer(text):
        frag = m.group(1).strip()
        if not frag or frag in seen:
            continue
        seen.add(frag)  # 🔴 «거르기 전»에 등록한다 — 안 그러면 첫 등장이 표지 밖인 조각이
        #                    좁힌 집합에만 살아남아 부분집합 관계가 깨진다
        if marker is not None:
            start = text.rfind("\n", 0, m.start()) + 1
            end = text.find("\n", m.end())
            if marker not in text[start : len(text) if end < 0 else end]:
                continue
        out.append(frag)
    return out


def load_corpus(root):
    paths = sorted(pathlib.Path(root).rglob("*.md"))
    return {str(p): p.read_text(encoding="utf-8", errors="replace") for p in paths}


def keywords(frag, freq, n=4):
    """그 조각에서 «희귀한» 토큰만 골라 키워드로 쓴다 (흔한 낱말은 어디서나 맞는다)."""
    toks = [t for t in dict.fromkeys(TOKEN.findall(frag)) if freq[t] <= RARE_MAX_FREQ]
    toks.sort(key=lambda t: freq[t])
    return toks[:n]


def reworded_hit(frag, docs, freq):
    """정확 대조로는 「없음」인데 키워드가 한 파일에 공존하면 «재서술로 있다»의 하한."""
    kws = keywords(frag, freq)
    if not kws:
        return 0, None, kws
    count, path = max((sum(k in d for k in kws), p) for p, d in docs.items())
    return count, path, kws


def census(old_text, docs, marker=None):
    frags = bold_fragments(old_text, marker)
    corpus = "\n".join(docs.values())
    freq = collections.Counter(TOKEN.findall(corpus))

    absent = [f for f in frags if f not in corpus]
    imperative = [f for f in absent if IMPERATIVE.search(f)]
    rest = [f for f in absent if not IMPERATIVE.search(f)]
    causal = [f for f in rest if CAUSAL.search(f)]

    probed = []
    for f in causal:
        count, path, kws = reworded_hit(f, docs, freq)
        probed.append({"조각": f, "공존": count, "파일": path, "키워드": kws})
    unfound = [r for r in probed if r["공존"] < COOCCUR_MIN]

    return {
        "분모_조각": len(frags),
        "있음": len(frags) - len(absent),
        "없음": len(absent),
        "없음_지시어미": len(imperative),
        "없음_나머지": len(rest),
        "인과형_후보": len(causal),
        "인과형_재서술로있음": len(causal) - len(unfound),
        "읽을것": unfound,
    }


# --selftest — 두 좌변이 «배타적»이라는 것이 이 도구의 전제다. 깨지면 체가 무의미해진다.
CONTROLS = [
    ("인과형 원형 ①", "정정을 새 줄로만 얹으면 원 조항이 남아 사본이 갈린다", True, False),
    ("인과형 원형 ②", "채팅으로만 고치면 본문이 낡은 채로 남는다", True, False),
    ("인과형 원형 ③", "분모를 안 적으면 「전부」가 거짓이 된다", True, False),
    ("명령형 대조군", "커밋 메시지는 heredoc 으로 적는다", False, True),
    ("서사 대조군", "그날 18:43 에 철회했고 본문은 그대로였다", False, False),
]


def selftest():
    bad = 0
    for label, text, want_causal, want_imp in CONTROLS:
        got_c, got_i = bool(CAUSAL.search(text)), bool(IMPERATIVE.search(text))
        ok = got_c == want_causal and got_i == want_imp
        bad += not ok
        print(f"{'ok  ' if ok else 'FAIL'} {label}: 인과형={got_c} 지시어미={got_i}")
    print(f"\n{len(CONTROLS) - bad}/{len(CONTROLS)} 통과")
    return 1 if bad else 0


def main():
    ap = argparse.ArgumentParser(
        description="재조직 PR 의 «규범 착지»를 조각 층에서 세고 인과형으로 거른다",
        epilog="이것은 증명이 아니라 «체»다 — 남은 것은 사람이 읽어야 한다",
    )
    ap.add_argument("--old", help="옛 문서 (재조직 «전» 파일)")
    ap.add_argument("--corpus", help="새 트리 디렉터리 (*.md 전부를 분모로 쓴다)")
    ap.add_argument("--marker", help="이 표지가 있는 줄로 분모를 좁힌다 (예: 🤝)")
    ap.add_argument("--json", action="store_true", help="결과를 JSON 으로")
    ap.add_argument("--selftest", action="store_true", help="좌변 배타성 대조군만 돌린다")
    args = ap.parse_args()

    if args.selftest:
        return selftest()
    if not args.old or not args.corpus:
        ap.error("--old 와 --corpus 가 필요하다 (또는 --selftest)")

    old_text = pathlib.Path(args.old).read_text(encoding="utf-8", errors="replace")
    docs = load_corpus(args.corpus)
    if not docs:
        print(f"🔴 코퍼스가 비었다: {args.corpus} 에 *.md 가 없다", file=sys.stderr)
        return 2
    r = census(old_text, docs, args.marker)

    if args.json:
        print(json.dumps(r, ensure_ascii=False, indent=2))
        return 0

    scope = f" (표지 {args.marker!r} 줄만)" if args.marker else ""
    print(f"코퍼스: {len(docs)}파일{scope}")
    print(f"볼드 조각 {r['분모_조각']}(중복제거)")
    print(f"  ├ 있음 {r['있음']}")
    print(f"  └ 없음 {r['없음']}")
    print(f"      ├ 지시어미 {r['없음_지시어미']}")
    print(f"      └ 나머지   {r['없음_나머지']}")
    print(f"          └ 인과형 {r['인과형_후보']}")
    print(f"              ├ 재서술로 있음 {r['인과형_재서술로있음']}")
    print(f"              └ 못 찾음      {len(r['읽을것'])}")
    if r["읽을것"]:
        print("\n=== 사람이 읽을 자리 ===")
        for row in r["읽을것"]:
            print(f"  · 공존{row['공존']} kw={row['키워드']}")
            print(f"    {' '.join(row['조각'].split())[:140]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
