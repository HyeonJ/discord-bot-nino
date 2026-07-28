#!/usr/bin/env bash
# resolve-bin.sh — **cron 에서 안 보이는 도구**의 경로를 찾는다. (source 해서 쓴다)
#
# 왜: cron 의 PATH 는 `/usr/bin:/bin` 뿐이라 nvm·`~/.local/bin`·bun 에 설치된 것이
#   전부 안 보인다. 실측(2026-07-28): `node` `npm` `npx` `bun` `uv` `age` 6개가 cron 에서
#   해석 실패 — `check-core-drift.sh` 가 매 실행 `node: command not found`(rc=127) 로
#   **판정 불가**를 내고 있었다. 문구는 정직했지만 **그 검사가 cron 에서 한 번도 안 돌았다.**
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
             "$HOME/.nvm/versions/node"/*/bin/"$name" \
             /usr/local/bin/"$name" \
             /opt/homebrew/bin/"$name"; do
        [ -x "$c" ] && { printf '%s' "$c"; return 0; }
    done
    return 1
}
