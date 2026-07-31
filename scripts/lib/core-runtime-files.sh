#!/usr/bin/env bash
# 코어 레포 경로가 **런타임 파일인가** — 제외 목록으로 판정한다.
#
# 🔴 왜 제외 목록인가 (2026-07-31, 라이브 거짓 초록에서 나옴)
#   이 판정은 원래 check-core-drift.sh 안에 한 줄로 있었고 **포함 목록**이었다:
#       grep -cE '^(relay|discord-send)/'
#   두 가지가 동시에 틀려 있었다.
#     ① `tmux-send.sh`(레포 루트)가 목록에 없어서 **매 전송마다 도는 파일이 0건**으로 나갔다.
#        하필 셸 스크립트라 재시작 없이 pull 즉시 동작이 바뀌는 — 가장 즉각적인 파일이다.
#     ② `^discord-send/` 는 **아무것도 안 잡는다.** `discord-send` 는 루트의 *파일*이지
#        디렉터리가 아니다. 목록에 이름이 적혀 있어 덮인 줄 알았는데 태어나서 한 번도 안 걸렸다.
#   ⇒ 손목록은 낡기만 하는 게 아니라 **처음부터 틀려 있어도 조용하다.**
#
# 🔑 실패 방향을 뒤집는 게 이 파일의 전부다.
#     포함 목록  새 파일 → 0건 (과소보고·조용함)   ← 사람이 "받아도 된다"고 읽는다
#     제외 목록  새 파일 → 1건 (과대보고·시끄러움) ← 사람이 한 번 더 본다
#   감지되는 단점을 감지되지 않는 단점보다 택한다.
#
# ⚠️ 이 제외 목록도 손으로 적은 목록이다. 낡지 않는다고 주장하지 않는다 —
#    **낡았을 때 어느 쪽으로 틀리는가**만 보장한다.
# ⚠️ 이 값은 억제 로직이 아니라 **사람이 읽고 pull/재시작을 정하는 근거**다.
#    (core-drift-cron.sh 의 FORCE 는 `process_behind` 를 읽지 이 값을 읽지 않는다.)

# 경로 하나가 런타임 파일이면 0(참), 아니면 1(거짓).
core_is_runtime_path() {
    case "$1" in
        docs/*|tests/*|.github/*) return 1 ;;   # 문서·시험·CI — 받아도 relay 동작이 안 바뀐다
        *.md)                     return 1 ;;
        .gitignore|.env.example|eslint.config.js) return 1 ;;
        '')                       return 1 ;;   # 빈 줄
        *)                        return 0 ;;   # 🔑 모르는 경로는 런타임이다
    esac
}

# stdin 의 경로 목록에서 런타임 건수를 센다. 비어 있으면 0.
# 🔸 `grep -c` 를 쓰지 않는다 — 매치 0이면 rc=1 이라 호출부가 `set -e` 를 쓰는 순간
#    "런타임 변경 없음"이 스크립트를 죽인다. 세는 일이 실패로 보이면 안 된다.
count_runtime_paths() {
    local path n=0
    while IFS= read -r path; do
        core_is_runtime_path "$path" && n=$((n + 1))
    done
    printf '%s' "$n"
}
