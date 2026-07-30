#!/usr/bin/env python3
"""mdweb-link-check.py — stdin 텍스트에서 md-web 링크를 찾아 문제를 stdout 으로 낸다.

mdweb-link-guard.sh 의 판정부. **셸 -c 인라인이 아니라 파일**인 이유:
정규식에 `'`·백틱이 들어가서 `python3 -c '...'` 의 인용을 끊었고, 그때 bash 문법오류 rc=2 가
훅의 차단 코드(2)와 **같아서** 깨진 훅이 "전부 잘 막는 훅"처럼 보였다(2026-07-30).

출력이 비면 문제 없음. 종료코드는 판정에 쓰지 않는다(호출부가 stdout 으로만 판단).
"""
import json
import os
import re
import subprocess
import sys
from urllib.parse import quote, unquote

API = os.environ.get("MDWEB_API", "http://localhost:58082/api/file")
TREE = os.environ.get("MDWEB_TREE", "http://localhost:58082/api/tree")

END = r"""[^\s"'`)<>\]]"""          # URL 끝을 끊는 문자들 (따옴표·백틱·괄호·꺾쇠)
PROXY = re.compile(r"https?://" + END + r"*?/md-web/(" + END + r"*)")
PORT = re.compile(r"https?://" + END + r"*?:58082/#/(" + END + r"*)")
# base path 가 빠진 것 — 첫 세그먼트가 md-web root 일 때만 md-web 링크로 본다
BARE = re.compile(r"https?://(?:darren|localhost)(?::\d+)?/(?!md-web/)(" + END + r"+)")


def curl(url):
    """(http_code, body) — 못 붙으면 code='0'"""
    try:
        p = subprocess.run(
            ["curl", "-s", "--max-time", "5", "-w", "\n%{http_code}", url],
            capture_output=True, text=True, timeout=8,
        )
        out = p.stdout.rsplit("\n", 1)
        return (out[1].strip() if len(out) == 2 else "0"), out[0]
    except Exception:
        return "0", ""


def unreachable(code):
    """붙지 못한 것 — curl 은 연결 실패를 `000` 으로 준다(`0` 이 아니다).
    이걸 몰라서 md-web 이 죽었을 때 '그 파일이 없다 (rc=000)' 로 잘못 안내했다(2026-07-30 시험이 잡음)."""
    return code in ("0", "000")


_roots = None


def roots():
    """md-web rootId 집합. None = 판정 불가(서버 죽음) — 그 경우 BARE 는 안 건드린다."""
    global _roots
    if _roots is None:
        code, body = curl(TREE)
        if code != "200":
            _roots = None if unreachable(code) else set()
        else:
            try:
                _roots = {n.get("rootId") for n in json.loads(body) if n.get("rootId")}
            except Exception:
                _roots = set()
    return _roots


problems = []
seen = set()


def judge(url, ref, bare=False):
    """ref = '{rootId}/{path...}'"""
    if url in seen:
        return
    seen.add(url)
    parts = [p for p in ref.split("/") if p]
    if not parts:
        return
    root, rel = parts[0], "/".join(parts[1:])

    if bare:
        r = roots()
        if r is None or root not in r:
            return                      # md-web 링크가 아니거나 판정 불가
        problems.append(
            f"{url}\n     → base path 가 빠졌다. `http://darren/md-web/{ref}` 여야 한다 "
            "(프리픽스 없으면 폴백 안내문이 200 으로 와서 코드로는 안 보인다)"
        )
        return

    if rel.endswith(".md"):
        problems.append(
            f"{url}\n     → `.md` 를 떼고 보낼 것 (Darren 지시 2026-07-30). "
            f"붙이면 렌더링본이 아니라 text/plain raw 가 온다: {url[:-3]}"
        )
        return
    if not rel:
        return                          # 루트만 가리키는 링크는 파일 판정 대상이 아니다

    code, _ = curl(f"{API}?rootId={quote(root)}&path={quote(unquote(rel) + '.md')}")
    if code == "200":
        return
    if unreachable(code):
        problems.append(
            f"{url}\n     → md-web(58082) 이 응답하지 않아 링크를 확인할 수 없다. "
            "`bash scripts/start-md-web.sh` 후 재시도 (지금 보내면 Darren 도 못 연다)"
        )
        return
    problems.append(
        f"{url}\n     → 그 파일이 없다 (api/file rc={code}). "
        f"rootId={root} path={rel}.md — 파일을 먼저 두거나 경로를 고칠 것"
    )


def main():
    text = sys.stdin.read()
    for m in PROXY.finditer(text):
        judge(m.group(0), m.group(1))
    for m in PORT.finditer(text):
        judge(m.group(0), m.group(1))
    for m in BARE.finditer(text):
        judge(m.group(0), m.group(1), bare=True)
    if problems:
        print("\n".join(f"  - {p}" for p in problems))


if __name__ == "__main__":
    main()
