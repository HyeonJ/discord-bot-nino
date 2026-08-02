#!/usr/bin/env python3
"""변수 참조 뒤에 비ASCII 가 바로 붙는 자리를 센다 — bash 3.2 이름 경계 버그.

왜 파일로 뺐나 (2026-08-02):
  이 검사기는 `repo-hygiene.test.sh` 의 heredoc 안에 인라인으로 살았다. 그러면
  **다른 뿌리로 못 돌려서 대조군을 세울 수 없다** — 대조군을 만들려면 같은 파이썬을
  한 벌 더 써야 하고, 그 순간 「사본 두 벌」이 된다. 그게 이 PR 이 고치는 바로 그 병이다.
  ⇒ 길목을 하나로 두고 **뿌리를 인자로** 받는다. 운영 호출은 레포를, 대조군은 임시 디렉터리를 준다.

무엇을 세지 «않는가» — 세 층은 이 버그와 무관하다:
  ⓐ 주석      형태를 «말하는 줄»이지 그 형태가 아니다
  ⓑ `\\$VAR`  이스케이프는 확장되지 않으므로 이름 경계가 생기지 않는다
  ⓒ 면제 표식 `hygiene:allow-nonascii` — 일부러 그 형태를 만드는 픽스처·미끼용.
              **주석 위치에서만** 먹고 **그 줄에만** 먹는다. 파일 전체를 끄는 표식이면
              다음 사람이 파일 머리에 붙이고 규칙이 통째로 사라진다.

사용법:  python3 tests/lib/nonascii-scan.py <뿌리 디렉터리>
출력:    위반 자리를 공백으로 이어 한 줄 (`경로:행`). 없으면 빈 줄.
"""
import os
import re
import sys

PAT = re.compile(r'\$[A-Za-z_][A-Za-z0-9_]*[^\x00-\x7f]')
ESC = re.compile(r'\\\$')
ALLOW = re.compile(r'#.*hygiene:allow-nonascii')
SKIP_DIRS = (".git", "node_modules", "backups")
# 🔴 검사기를 검사 대상에서 뺀다 — 이 파일 안에 패턴 문자열 자체가 산다.
#   (오늘 세 번 밟은 형태: grep 가드 자기 줄 · 안전형 안의 부분문자열 · 파이썬 가드의 패턴)
SELF = os.path.basename(__file__)


def scan(root):
    hits = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for fn in sorted(filenames):
            if not fn.endswith(".sh") or fn == SELF:
                continue
            fp = os.path.join(dirpath, fn)
            try:
                src = open(fp, encoding="utf-8", errors="replace").read()
            except OSError:
                continue
            for i, line in enumerate(src.splitlines(), 1):
                if line.lstrip().startswith("#"):
                    continue
                if ALLOW.search(line):
                    continue
                if PAT.search(ESC.sub("", line)):
                    hits.append("%s:%d" % (os.path.relpath(fp, root), i))
    return hits


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.stderr.write("usage: nonascii-scan.py <뿌리 디렉터리>\n")
        sys.exit(2)
    print(" ".join(scan(sys.argv[1])))
