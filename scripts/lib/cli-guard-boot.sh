#!/usr/bin/env bash
# cli-guard-boot.sh — 코어 cli-guard 를 **찾아서 물리는** 니노 쪽 배선 한 벌. (source 해서 쓴다)
#
# 🔴 왜 있나 (2026-07-31):
#   `#102` 에서 `check-usage-alert.sh` 에 코어 경로 해석 + 부재 처리 + usage 정의를
#   직접 써 넣었다. 채택 대상이 5개 더 있어서, 그대로 가면 **같은 배선이 6벌**이 된다.
#   🔑 오늘 이미 그 값을 치렀다 — 종료코드 계약 사본이 두 벌이라 갈렸고(`#95` 자리),
#     룬드의 `TOKEN_SRC` 도, 내 시험의 호출부 5곳도 전부 *"세어서 붙이면 다음 것이 샌다"* 였다.
#   ⇒ 배선은 **여기 한 곳**. 소비자는 usage 문구만 자기 것으로 준다.
#
# 🔴 코어 위치는 기계마다 다르다 — 니노 `~/yaksu-bot-core-live`, 룬드 맥 `~/yaksu-bot-core`.
#   운영 기본값은 니노 것이 맞지만 **후보를 훑어서** 상대 기계에서도 돌게 한다.
#   (룬드 맥에서 `#102` 시험이 28 fail 났던 자리. 원인이 *내가 가진 것*이라 내 기계에선
#    원리적으로 안 보였다 — 상대 기계가 유일한 관찰자였다.)
#
# 쓰는 법
#   cli_guard_usage() { echo "usage: ..."; }        # **먼저** 정의한다 (안 주면 최소 형태)
#   CLI_GUARD_ON_REJECT=my_log_fn                   # (선택) 거절 시 부를 함수 — 흔적을 남긴다
#   . "$BOT_DIR/scripts/lib/cli-guard-boot.sh"
#   cli_guard_boot "$@"                             # 거절이면 여기서 exit 2 한다
#
# 노출하는 것: `cli_guard_boot` · 그리고 코어가 노출하는 `CLI_DRY_RUN`·`cli_guard_send`

# 🔸 source 자체는 부작용이 없다(코어 계약 ⑦과 같은 규약). 실제 판정은 `cli_guard_boot` 에서.
cli_guard_boot() {
    local core found=""
    for core in "${CORE_REPO:-}" "$HOME/yaksu-bot-core-live" "$HOME/yaksu-bot-core"; do
        [ -n "$core" ] && [ -r "$core/scripts/cli-guard.sh" ] && { found="$core"; break; }
    done

    if [ -z "$found" ]; then
        # 🔴 **가드 없이 돌지 않는다.** 붙였다고 믿는 채로 안 붙은 상태는 붙이기 전보다 나쁘다 —
        #   믿음이 생기면 아무도 다시 안 본다. 조용히 넘기는 것이 여기서 제일 나쁜 선택이다.
        CLI_GUARD_VERDICT=no_cli_guard
        printf '⛔ 판정 불가 — cli-guard 정본을 못 찾았다.\n' >&2
        printf '   찾아본 곳: $CORE_REPO · ~/yaksu-bot-core-live · ~/yaksu-bot-core\n' >&2
        printf '   코어 클론이 없거나 낡았다 — 클론하거나 CORE_REPO=<경로> 로 지정할 것.\n' >&2
        [ -n "${CLI_GUARD_ON_REJECT:-}" ] && "$CLI_GUARD_ON_REJECT" no_cli_guard
        exit 2
    fi

    CLI_GUARD_CORE="$found"
    # shellcheck disable=SC1090
    . "$found/scripts/cli-guard.sh"

    if ! cli_guard_parse "$@"; then
        # 🔑 **거절도 흔적을 남긴다.** cron 은 stderr 를 버리므로, 안 남기면 crontab 오타
        #   하나로 이 감시기가 *아무 표시 없이* 멈춘다 — 감시기가 조용히 죽는 그 형태다.
        # 🔸 `bad_args`(모르는 인자)와 `bad_env`(CLI_DRY_RUN 상속)를 갈라 센다.
        #   둘 다 *못 쟀다*지만 **고칠 곳이 다르다** — 부르는 줄 vs 환경.
        if [ "${CLI_GUARD_ENV_DRY:-0}" = "1" ]; then
            CLI_GUARD_VERDICT=bad_env
        else
            CLI_GUARD_VERDICT=bad_args
        fi
        [ -n "${CLI_GUARD_ON_REJECT:-}" ] && "$CLI_GUARD_ON_REJECT" "$CLI_GUARD_VERDICT"
        exit 2
    fi
    return 0
}
