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

# <"YYYY-MM-DD HH:MM(:SS)"> → epoch. `ts_fmt` 의 **역방향**이다.
#   🔑 `date -d "<사람이 읽는 시각>"` 은 GNU 전용이고 BSD 는 `date -j -f <포맷>` 이다.
#   `ts_fmt` 와 같은 병이라 여기(정본)에 둔다 — 시험이 «어제 밤 23:30» 같은 시각을 고정할 때 쓴다.
#   ⚠️ BSD 가지는 이 기계(GNU)에서 안 돈다. **룬드 맥 실행이 그 가지의 유일한 관측이다** —
#      ts_fmt 의 `date -r` 가지와 같은 처지이고, 이 파일이 존재하는 이유가 그것이다.
ts_epoch() {
    local s="$1" out
    out="$(date -d "$s" +%s 2>/dev/null)" && { printf '%s' "$out"; return 0; }
    out="$(date -j -f '%Y-%m-%d %H:%M:%S' "$s" +%s 2>/dev/null)" && { printf '%s' "$out"; return 0; }
    out="$(date -j -f '%Y-%m-%d %H:%M' "$s" +%s 2>/dev/null)" && { printf '%s' "$out"; return 0; }
    echo "ts_epoch: date 가 -d 도 -j -f 도 안 받는다 — '$s' 를 epoch 으로 못 바꾼다" >&2
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

# <파일> → mtime(epoch). `stat -c %Y` 는 GNU 전용이고 BSD 는 `-f %m` 이다.
#   🔑 `touch -d` 와 **같은 병이다** — 시각 도구가 GNU/BSD 로 갈리는 자리.
#   개별로 고치면 다음 자리가 남으므로 여기(정본)에 둔다. 못 읽으면 rc=2(판정 불가).
mtime_of() {
    local f="$1" out
    out="$(stat -c %Y "$f" 2>/dev/null)" && { printf '%s' "$out"; return 0; }
    out="$(stat -f %m "$f" 2>/dev/null)" && { printf '%s' "$out"; return 0; }
    echo "mtime_of: stat 이 -c %Y 도 -f %m 도 안 받는다 — mtime 을 읽을 수 없다" >&2
    return 2
}

# <epoch> <파일...> → 그 파일들의 mtime 을 **절대 시각**으로
#   🔸 `touch_ago` 는 상대(초 전)고 이건 절대다. `touch -d '@N'` 이 GNU 전용이라 여기로 온다.
touch_at() {
    local epoch="$1"; shift
    local stamp
    stamp="$(ts_fmt "$epoch" '+%Y%m%d%H%M.%S')" || return 2
    touch -t "$stamp" "$@"
}
