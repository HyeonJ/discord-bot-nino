#!/usr/bin/env bash
# 판정기 원장 자체검사 — 「없는 행 · 낡은 행 · 복붙」 세 축
#
# 🔴 왜 생겼나 (2026-08-10, 룬드 전수): 내 `#168` 이 「빠진 다섯을 채웠다」고 주장했는데
#    **실제로는 열이었다.** 좌변을 「최근」으로 잡아서 «시간 창»을 셌고, 분모(차집합)를 안 셌다.
#    그가 손으로 전수해서 찾은 것이 **없는 행 5 · 끊긴 체인 2곳 · 인접 중복 0** 이었다.
# 🔑 **트리거와 검사는 다른 것을 막는다** — 「머지하면 행을 적는다」는 «앞으로»를 막고,
#    이 시험은 «이미 있는 것»을 막는다. 트리거만 두면 이미 빠진 행은 영영 안 보인다.
#
# 🔑 **꼬리(마지막 행 이후의 머지)는 분모 밖이다** — 행은 머지 «뒤»에 적히므로 그 구간이
#    비어 있는 것은 정상이다. 병은 그 꼬리가 «안 채워진 채 묻히는 것»이고, 그 순간
#    (다음 원장 PR 이 더 뒤의 행을 넣는 순간) 그것들은 **안쪽**이 되어 축①에 걸린다.
#    ⇒ 늦게 잡지만 **조용히 놓치지는 않는다.**
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LEDGER="${MERGE_LEDGER:-$BOT_DIR/.github/merge-ledger.md}"
CI_YML="$BOT_DIR/.github/workflows/ci.yml"

pass=0; fail=0; skip=0
ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; fail=$((fail + 1)); [ -n "${2:-}" ] && echo "     want: $2"; [ -n "${3:-}" ] && echo "     got:  $3"; }

# 🔴 축을 «파이썬 한 곳»에 둔다 — 본 검사와 아래 🧪 역사 대조군이 **같은 코드**를 써야
#   대조군이 「이 검사가 그때 잡았을까」를 실제로 답한다. 사본이 둘이면 그 답이 흐려진다.
AXES="$(mktemp)"; trap 'rm -f "$AXES"' EXIT INT TERM
cat > "$AXES" <<'PYEOF'
import json, os, re, subprocess, sys

src = sys.argv[1]          # "<ref>:<path>" 또는 파일 경로
if ":" in src and not os.path.exists(src):
    r = subprocess.run(["git", "show", src], capture_output=True, text=True)
    if r.returncode != 0:
        print(json.dumps({"err": f"git show 실패: {r.stderr.strip()[:120]}"})); sys.exit(0)
    txt = r.stdout
else:
    txt = open(src, encoding="utf-8").read()

rows, malformed = [], []
for ln in txt.splitlines():
    if not ln.startswith("| "):
        continue
    c = [x.strip() for x in ln.strip().strip("|").split("|")]
    if len(c) < 3 or c[0] != "니노":
        continue                                  # 머리글·구분선·다른 레포 행
    m = re.match(r"`?#(\d+)`?\s+`?([0-9a-f]{7,40})`?", c[1])
    if not m:
        malformed.append(c[1][:40]); continue     # 🔴 조용히 버리지 않는다 — 세서 낸다
    lm = re.search(r"`([0-9a-f]{7,40})`", c[2])
    rows.append({"pr": int(m.group(1)), "sha": m.group(2), "prev": lm.group(1) if lm else None})

if len(rows) < 2:
    print(json.dumps({"err": f"행이 {len(rows)}개라 «인접 쌍»이 안 생긴다"})); sys.exit(0)

def linked(a, b):
    """b.prev 가 a.sha 를 가리키나 — 길이가 달라 양방향 prefix 로 본다."""
    return bool(b["prev"]) and (a["sha"].startswith(b["prev"]) or b["prev"].startswith(a["sha"]))

pairs = len(rows) - 1
broken   = [[rows[i-1]["pr"], rows[i]["pr"]] for i in range(1, len(rows)) if not linked(rows[i-1], rows[i])]
noprev   = sum(1 for r in rows[1:] if not r["prev"])          # 축② 가 «못 잰» 쌍
dups     = [rows[i]["pr"] for i in range(1, len(rows))
            if (rows[i]["pr"], rows[i]["sha"]) == (rows[i-1]["pr"], rows[i-1]["sha"])]

# 축① — 구간은 [첫 행 머지 .. 마지막 행 머지]. 꼬리는 분모 밖(머리말 참조).
first, last = rows[0]["sha"], rows[-1]["sha"]
out = {"rows": len(rows), "pairs": pairs, "broken": broken, "noprev": noprev,
       "dups": dups, "malformed": malformed, "span": [rows[0]["pr"], rows[-1]["pr"]]}
for sha in (first, last):
    if subprocess.run(["git", "cat-file", "-e", sha + "^{commit}"],
                      capture_output=True).returncode != 0:
        out["missing_axis1"] = f"히스토리가 {sha} 에 안 닿는다"
        print(json.dumps(out, ensure_ascii=False)); sys.exit(0)
log = subprocess.run(["git", "log", "--first-parent", "--format=%s", f"{first}..{last}"],
                     capture_output=True, text=True)
if log.returncode != 0:
    out["missing_axis1"] = "git log 실패"
    print(json.dumps(out, ensure_ascii=False)); sys.exit(0)
seen = {int(m.group(1)) for l in log.stdout.splitlines() if (m := re.search(r"\(#(\d+)\)\s*$", l))}
seen.add(rows[0]["pr"])                            # 구간의 왼쪽 끝은 로그에 안 나온다
rec = {r["pr"] for r in rows}
out["commits"]  = len(log.stdout.splitlines())
out["missing"]  = sorted(seen - rec)               # 머지됐는데 행이 없다
out["phantom"]  = sorted(rec - seen)               # 행은 있는데 그 구간의 머지가 아니다
print(json.dumps(out, ensure_ascii=False))
PYEOF

axes() { python3 "$AXES" "$1"; }
jq_() { printf '%s' "$1" | python3 -c "import json,sys;print(json.load(sys.stdin).get(sys.argv[1],''))" "$2"; }

echo "── ⓪ 전제 — 이 검사가 «돌 수 있는» 조건 ──"
# 🔴 히스토리 부재를 «판정 불가»로 접지 않는다. 부재가 아무것도 안 말하는데(어느 PR 이
#   머지됐는지는 얕은 클론이 모른다) **우리가 고칠 수 있는 것**이라 실패로 낸다.
#   부재를 판불로 두면 파일 rc=0 이라 원장엔 «통과»로만 보인다(`#171` 에서 밟은 자리).
if LC_ALL=C grep -qE '^[[:space:]]*fetch-depth:[[:space:]]*0[[:space:]]*$' "$CI_YML"; then
    ok "ci.yml 이 fetch-depth: 0 이다 — 축①이 CI 에서 «실제로» 돈다"
else
    bad "ci.yml 에 fetch-depth: 0 이 없다 — 축①이 CI 에선 못 돈다(얕은 클론)" \
        "checkout@v4 with: fetch-depth: 0" "$(LC_ALL=C grep -n -A3 'actions/checkout' "$CI_YML" | head -5)"
fi

echo
echo "── ① 없는 행 · ② 낡은 행 · ③ 복붙 ──"
J="$(axes "$LEDGER")"
ERR="$(jq_ "$J" err)"
if [ -n "$ERR" ]; then
    bad "원장을 못 읽었다 — 「행이 없다」와 「형식이 바뀌었다」를 «실패»로 낸다" "행 ≥ 2" "$ERR"
else
    ROWS="$(jq_ "$J" rows)"; PAIRS="$(jq_ "$J" pairs)"; SPAN="$(jq_ "$J" span)"
    echo "  분모: 행 $ROWS · 인접 쌍 $PAIRS · 구간 $SPAN"

    MAL="$(jq_ "$J" malformed)"
    [ "$MAL" = "[]" ] && ok "머지 칸이 «전부» 파싱됐다 (버린 행 0)" \
                      || bad "파싱 못 한 머지 칸이 있다 — 조용히 분모에서 빠진다" "[]" "$MAL"

    MISS_A1="$(jq_ "$J" missing_axis1)"
    if [ -n "$MISS_A1" ]; then
        bad "축① 을 못 쟀다 — $MISS_A1" "원장 첫·끝 sha 가 히스토리에 있어야 한다" \
            "얕은 클론이면 ⓪ 을 먼저 고칠 것"
    else
        COMMITS="$(jq_ "$J" commits)"; MISSING="$(jq_ "$J" missing)"; PHANTOM="$(jq_ "$J" phantom)"
        echo "  축① 분모: 구간 머지 커밋 $COMMITS 개"
        [ "$MISSING" = "[]" ] && ok "축① 없는 행 0 — 구간 안 머지가 «전부» 원장에 있다" \
                              || bad "축① 머지됐는데 행이 없다" "[]" "$MISSING"
        # 🔸 반대 방향도 본다 — 번호 오타·다른 레포 행이 섞이면 여기 걸린다.
        [ "$PHANTOM" = "[]" ] && ok "  → 반대 방향도 0 — 구간 밖 PR 번호가 섞이지 않았다" \
                              || bad "축① 행은 있는데 그 구간의 머지가 아니다" "[]" "$PHANTOM"
    fi

    BROKEN="$(jq_ "$J" broken)"; NOPREV="$(jq_ "$J" noprev)"
    [ "$BROKEN" = "[]" ] && ok "축② 체인 연결 — 각 행의 좌변이 «직전 행의 머지 sha»다 ($PAIRS 쌍)" \
                         || bad "축② 체인이 끊겼다 (인접 PR 쌍)" "[]" "$BROKEN"
    # 🔴 «못 잰 쌍»을 따로 센다 — 좌변 칸이 비면 `linked()` 가 거짓을 내는데,
    #   그건 「끊겼다」가 아니라 「안 적혔다」다. 수를 안 내면 둘이 뭉개진다.
    [ "$NOPREV" -eq 0 ] && ok "  → 좌변 칸이 빈 행 0 (축②가 «못 잰» 쌍 없음)" \
                        || bad "  → 좌변 칸이 빈 행 $NOPREV 개 — 축②가 그만큼 못 쟀다" "0" "$NOPREV"

    DUPS="$(jq_ "$J" dups)"
    [ "$DUPS" = "[]" ] && ok "축③ 인접 중복 0 — 복붙한 행이 없다" \
                       || bad "축③ 인접한 두 행이 같은 (PR, sha) 다" "[]" "$DUPS"
fi

echo
echo "── ④ 🧪 역사 대조군 — 「그때 이 검사가 잡았을까」를 «답한다» ──"
# 🔑 합성 변이보다 세다: 룬드가 **손으로** 전수해서 찾은 값이 있고(2026-08-10),
#   그 직전 커밋의 원장이 레포에 그대로 남아 있다. 위와 **같은 코드**로 돌려 수를 맞춘다.
#   ⚠️ 이 좌변은 고정 커밋이라 «낡지 않는다» — 원장이 앞으로 어떻게 바뀌든 그대로 참이다.
BEFORE_168="605c882^:.github/merge-ledger.md"
JB="$(axes "$BEFORE_168")"
if [ -n "$(jq_ "$JB" err)" ] || [ -n "$(jq_ "$JB" missing_axis1)" ]; then
    bad "역사 대조군을 못 돌렸다 — 이 시험이 «무엇을 잡는지» 증명이 없다" \
        "605c882^ 의 원장을 읽고 축①까지" "$(jq_ "$JB" err)$(jq_ "$JB" missing_axis1)"
else
    HM="$(jq_ "$JB" missing)"; HB="$(jq_ "$JB" broken)"; HD="$(jq_ "$JB" dups)"
    [ "$HM" = "[136, 138, 139, 140, 147]" ] \
      && ok "🧪 축① 이 그때의 «없는 행 다섯»을 정확히 집는다 — 룬드 손 전수와 일치" \
      || bad "🧪 축① 역사 대조군 불일치" "[136, 138, 139, 140, 147]" "$HM"
    [ "$HB" = "[[137, 141], [143, 148]]" ] \
      && ok "🧪 축② 가 그때의 «끊긴 2곳»을 정확히 집는다" \
      || bad "🧪 축② 역사 대조군 불일치" "[[137, 141], [143, 148]]" "$HB"
    # 🔸 음성도 대조군이다 — 그때 인접 중복은 «실제로 0» 이었다(그가 따로 확인했다).
    #   양성만 맞추면 「축③ 이 늘 0 을 낸다」와 구별이 안 되므로, 축③ 의 양성은 ⑤ 가 만든다.
    [ "$HD" = "[]" ] \
      && ok "🧪 축③ 은 그때 «0» 이었다 — 음성도 맞는다(오탐 아님)" \
      || bad "🧪 축③ 역사 대조군 불일치" "[]" "$HD"
fi

echo
echo "── ⑤ 🧪 변이 — 축③ 의 «양성»은 여기서 만든다(역사에 표본이 없다) ──"
MUT="$(mktemp)"; MUT2="$(mktemp)"
trap 'rm -f "$AXES" "$MUT" "$MUT2"' EXIT INT TERM
LAST_ROW="$(LC_ALL=C grep '^| 니노 ' "$LEDGER" | tail -1)"
if [ -n "$LAST_ROW" ]; then
    { cat "$LEDGER"; printf '%s\n' "$LAST_ROW"; } > "$MUT"
    JM="$(axes "$MUT")"
    [ "$(jq_ "$JM" dups)" != "[]" ] \
      && ok "🧪 마지막 행을 복붙하니 축③ 이 문다 ($(jq_ "$JM" dups))" \
      || bad "🧪 축③ 이 복붙을 못 잡는다 — 늘 0 을 내고 있었다" "빈 배열이 아님" "$(jq_ "$JM" dups)"
    # 🔸 그 변이가 «축③만» 흔드는지 — 다른 축까지 빨개지면 무엇이 물었는지 안 갈린다.
    [ "$(jq_ "$JM" missing)" = "[]" ] \
      && ok "  → 그 변이가 축①은 안 흔든다 (어느 축이 물었는지 갈린다)" \
      || bad "  → 변이가 축①까지 흔든다" "[]" "$(jq_ "$JM" missing)"
else
    echo "  🔸 판정 불가: 원장에서 마지막 「니노」 행을 못 뽑았다"; skip=$((skip + 1))
fi

echo
echo "  통과 $pass · 실패 $fail · 판정 불가 $skip"
[ "$fail" -eq 0 ]
