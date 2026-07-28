#!/usr/bin/env bash
# 시험용 시각 조작 — GNU/BSD 공용. **여기가 정본이다.**
#
# 왜: `touch -d '30 days ago'` 는 GNU 전용이다. macOS(BSD)에서는
#   `touch: out of range or illegal time specification` 으로 죽고, 그 죽음이
#   **무관한 단언을 빨갛게 만든다**(룬드 맥 실측 2026-07-28: retention 시험 1 fail).
#   시험 파일 주석에 "macOS 로 옮기면 바꿔야 한다" 고 적어두고도 안 지킨 자리였다.
#
# 🔑 클래스로 읽는다: 이건 `touch` 하나의 문제가 아니라 **"GNU 전용 시각 도구가
#   시험에 섞여 있다"** 는 형태다. 개별로 고치면 다음 자리(`date -d`)가 남는다 —
#   같은 날 age→crontab 에서 이미 한 번 밟았다. 그래서 시각 조작은 전부 여기를 지난다.
#
# 사본 금지: 두 시험이 각자 헬퍼를 가지면 한쪽만 고쳐진다. 정본은 이 파일 하나다.
#
# 계약: 상대 시각을 **초로 계산**한 뒤 POSIX `touch -t` 로만 찍는다.
#   `date` 의 epoch 포맷만 갈리므로(GNU `-d @N` / BSD `-r N`) 그 한 줄만 분기한다.

# <epoch> <+포맷> → 문자열. 어느 쪽 date 로도 못 찍으면 rc=2(판정 불가)로 올린다.
ts_fmt() {
    local epoch="$1" fmt="$2" out
    out="$(date -d "@$epoch" "$fmt" 2>/dev/null)" && { printf '%s' "$out"; return 0; }
    out="$(date -r "$epoch" "$fmt" 2>/dev/null)" && { printf '%s' "$out"; return 0; }
    echo "ts_fmt: date 가 -d @N 도 -r N 도 안 받는다 — 시각을 만들 수 없다" >&2
    return 2
}

# <초 전> <+포맷> → 문자열 (파일 내용에 과거 시각을 심을 때)
fmt_ago() {
    local ago="$1" fmt="$2"
    ts_fmt "$(( $(date +%s) - ago ))" "$fmt"
}

# <초 전> <파일...> → 그 파일들의 mtime 을 과거로
touch_ago() {
    local ago="$1"; shift
    local stamp
    stamp="$(fmt_ago "$ago" '+%Y%m%d%H%M.%S')" || return 2
    touch -t "$stamp" "$@"
}

# 자주 쓰는 단위 — 호출부에서 86400 곱셈이 반복되지 않게
DAY=86400
HOUR=3600
