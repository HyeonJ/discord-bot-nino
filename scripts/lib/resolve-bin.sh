#!/usr/bin/env bash
# resolve-bin.sh — **cron 에서 안 보이는 도구**의 경로를 찾는다. (source 해서 쓴다)
#
# 왜: cron 의 PATH 는 `/usr/bin:/bin` 뿐이라 nvm·`~/.local/bin`·bun 에 설치된 것이
#   전부 안 보인다. 실측(2026-07-28): `node` `npm` `npx` `bun` `uv` `age` 6개가 cron 에서
#   해석 실패 — `check-core-drift.sh` 가 매 실행 `node: command not found`(rc=127) 로
#   **판정 불가**를 내고 있었다. 문구는 정직했지만 **그 검사가 cron 에서 한 번도 안 돌았다.**
#   ⚠️ 발견자는 **그 검사 자신**이다 — 드리프트 알림(check-core-drift.sh)이 20:15 에 스스로
#      rc=127 을 리포트했다. 사람도 다른 봇도 아니다. 도구가 자기 무능을 말하게 해둔 값이
#      여기서 나왔다(귀속을 사람 쪽으로 적으면 그 값이 기록에서 사라진다).
#   *정직한 무능도 무능이다* — 못 쟀다고 말하는 것과 잴 수 있게 만드는 것은 다른 일이다.
#
# 🔑 자리마다 절대경로를 박지 않는다. 박으면 nvm 버전이 바뀔 때 자리 수만큼 깨진다
#   — 오늘 여러 번 본 *인스턴스가 아니라 클래스로* 그대로다. 해석은 여기 한 곳을 지난다.
#
# 계약: 찾으면 경로를 stdout 으로 내고 rc=0. 못 찾으면 **아무것도 안 내고 rc=1**.
#   ⚠️ 못 찾은 것을 빈 문자열로 돌려주면 호출부가 `""` 를 실행해 **다른 에러**로 죽는다
#   — 원인이 "도구 부재" 인데 "구문 오류" 로 보이는 자리가 된다.

resolve_bin() {  # <이름> [주어진 경로]
    local name="${1:-}" given="${2:-}" c
    [ -n "$name" ] || return 1

    # ① 명시적으로 준 것이 이긴다(검증 가능성 — 시험이 실패 경로를 태울 수 있어야 한다)
    if [ -n "$given" ]; then
        if [ -x "$given" ] || command -v "$given" >/dev/null 2>&1; then
            printf '%s' "$given"; return 0
        fi
        return 1
    fi

    # ② PATH 에 있으면 그것(대화형 셸·systemd 유닛에서는 여기서 끝난다)
    if command -v "$name" >/dev/null 2>&1; then
        printf '%s' "$name"; return 0
    fi

    # ③ cron 에서 안 보이는 설치 위치들. glob 이 안 맞으면 리터럴로 남으므로 -x 가 걸러낸다
    for c in "$HOME/.local/bin/$name" \
             "$HOME/.bun/bin/$name" \
             /usr/local/bin/"$name" \
             /opt/homebrew/bin/"$name"; do
        [ -x "$c" ] && { printf '%s' "$c"; return 0; }
    done

    # ④ nvm 은 **버전 디렉터리가 여럿**이라 마지막에 본다.
    # ⚠️ glob 확장은 **문자열 순**이라 그냥 첫 값을 쓰면 최신을 안 고른다
    #    (룬드 실측 2026-07-28: `v18.19.0 · v20.11.0 · v8.17.0` → **v18 을 고른다**.
    #     `v8` 이 문자열 순으로 맨 뒤라 최악은 피했지만, 고른 값이 `nvm use` 로 정한 것과 다르다).
    #    ⇒ 버전을 **숫자로** 비교해 가장 높은 것을 쓴다. `sort -V` 는 BSD 에 없을 수 있어
    #      `-t. -k1,1n -k2,2n -k3,3n` 로 맞춘다(POSIX 범위).
    local best="" ver
    for c in "$HOME/.nvm/versions/node"/*/bin/"$name"; do
        [ -x "$c" ] || continue
        ver="${c#"$HOME/.nvm/versions/node/"}"; ver="${ver%%/*}"; ver="${ver#v}"
        best="$best$ver	$c
"
    done
    if [ -n "$best" ]; then
        printf '%s' "$best" | sort -t. -k1,1nr -k2,2nr -k3,3nr | head -1 | cut -f2 | tr -d '\n'
        return 0
    fi
    return 1
}
