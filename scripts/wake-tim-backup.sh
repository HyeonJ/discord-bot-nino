#!/bin/bash
# 충재 형 기상 «셋째 층» — 룬드 크론(①)·아이폰(②)이 다 실패했을 때의 백업.
#
# 🔑 설계 원칙: 09:00 의 «정상 경로»에서는 아무것도 새로 하지 않는다.
#   - 정상 경로가 쓰는 것: mp3 파일 하나 + powershell.exe. uv·node·Claude 토큰은 «어느 경로에서도» 안 쓴다.
#   - ⚠️ 예외 하나 — mp3 가 없거나 깨졌으면 :76 이 발화 시점에 다시 굽는다(edge-tts·네트워크를 쓴다).
#     그때는 이미 정상 경로가 깨진 뒤라 「안 우는 것」보다 「늦게라도 우는 것」이 낫다는 판단이다.
#   🔴 이 예외는 «나중에 얹은 것»이고 머리말은 한동안 「전부·뿐」이라 적혀 있었다 — 원소를 늘린 게
#     나 자신이라 안 보였다. 무번호 전칭의 사각(inbox #0821-2).
# 유래: 룬드 M:7kta(99% · 리셋 20:00 · 「내가 못 깨울 수 있다」) → M:g850 「③ 깔아줘」
#
# 사용:
#   wake-tim-backup.sh --bake      mp3 를 굽는다 (소리 안 남 · 미리 해둔다)
#   wake-tim-backup.sh --dry-run   재생만 건너뛰고 나머지를 전부 돈다 (심야 검증용)
#   wake-tim-backup.sh             발화 (cron 이 부른다)
#   touch /tmp/nino-wake-stop      즉시 멈춤

set -uo pipefail

POWERSHELL="/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
AUDIO_DIR="$HOME/.nino-wake"
MP3="$AUDIO_DIR/wake-tim.mp3"
MP3_UNC='\\wsl.localhost\Ubuntu\home\bpx27\.nino-wake\wake-tim.mp3'
STOP="/tmp/nino-wake-stop"
LOG="$HOME/discord-bot-nino/logs/wake-tim-backup.log"
TEXT="충재 형, 아침이에요. 아홉 시예요. 일어나실 시간이에요."

# 🔴 상한은 룬드의 30분보다 «짧게» 둔다 — 나는 셋째 층이라
#    ①②가 이미 깨웠을 때 제일 오래 시끄러운 쪽이 되면 안 된다.
CAP_MIN="${WAKE_CAP_MIN:-15}"
GAP_SEC="${WAKE_GAP_SEC:-20}"

mkdir -p "$AUDIO_DIR" "$(dirname "$LOG")"
log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG"; }

bake() {
    command -v edge-tts >/dev/null || { echo "🔴 edge-tts 없음 — 굽기 실패"; return 1; }
    edge-tts --voice "ko-KR-HyunsuMultilingualNeural" --rate="-8%" --pitch="+1Hz" \
             --text "$TEXT" --write-media "$MP3"
    local rc=$? sz
    sz=$(stat -c %s "$MP3" 2>/dev/null || echo 0)
    # 🔑 rc 만 보면 «0바이트 성공»을 놓친다 — 크기를 같이 판정한다
    if [[ $rc -ne 0 || $sz -lt 1000 ]]; then
        echo "🔴 굽기 실패 rc=$rc size=$sz"; return 1
    fi
    echo "✅ 구움 $MP3 ($sz 바이트)"; log "bake ok size=$sz"
}

play_once() {
    "$POWERSHELL" -Command "
Add-Type -AssemblyName presentationCore
\$p = New-Object System.Windows.Media.MediaPlayer
\$p.Open([uri]::new('$MP3_UNC'))
\$p.Play()
Start-Sleep -Seconds 6
\$p.Stop()
" >/dev/null 2>&1
}

main() {
    local dry="${1:-}"

    # 🔴 «무장 파일»이 없거나 오늘이 아니면 조용히 안 운다.
    #   크론은 매일 09:00 에 도는데 이건 «오늘 하루짜리 백업»이다. 가드가 없으면
    #   부탁받은 적 없는 알람이 영구히 남는다 — 그건 되돌리기 어려운 쪽이다.
    #   ⚠️ 「잊으면 시끄러운 쪽」 원칙의 «예외»가 아니라 적용이다: 여기서 시끄러운 실패는
    #   «안 우는 것»이 아니라 «영원히 우는 것»이고, ①②가 이미 있어 미발화 비용이 낮다.
    if [[ "$dry" != "--dry-run" ]]; then
        local armed; armed=$(cat "$AUDIO_DIR/armed-for" 2>/dev/null || echo '')
        if [[ "$armed" != "$(date +%F)" ]]; then
            log "무장 안 됨 (armed-for='${armed}' · 오늘=$(date +%F)) — 안 운다"
            exit 0
        fi
        rm -f "$AUDIO_DIR/armed-for"   # 한 번 울면 스스로 해제한다
    fi

    rm -f "$STOP"

    # 🔴 발화 «직전»에 전제를 다시 잰다 — 구운 지 오래돼 파일이 사라졌을 수 있다
    local sz; sz=$(stat -c %s "$MP3" 2>/dev/null || echo 0)
    if [[ "$sz" -lt 1000 ]]; then
        log "🔴 mp3 없음/깨짐 (size=$sz) — 그 자리에서 다시 굽는다"
        bake >>"$LOG" 2>&1 || { log "🔴 재굽기도 실패 — 발화 못 함"; exit 2; }
    fi
    [[ -x "$POWERSHELL" ]] || { log "🔴 powershell.exe 없음 — 발화 못 함"; exit 2; }

    local deadline=$(( $(date +%s) + CAP_MIN * 60 )) n=0
    log "발화 시작 (상한 ${CAP_MIN}분 · 간격 ${GAP_SEC}초 · dry=${dry:-no})"
    while [[ $(date +%s) -lt $deadline ]]; do
        [[ -f "$STOP" ]] && { log "정지 파일 감지 — ${n}회 후 멈춤"; exit 0; }
        n=$((n+1))
        [[ "$dry" == "--dry-run" ]] || play_once
        sleep "$GAP_SEC"
        [[ "$dry" == "--dry-run" ]] && { log "dry-run: 1회만 돌고 끝"; exit 0; }
    done
    log "상한 도달 — ${n}회 후 자동 종료"
}

case "${1:-}" in
    --bake)    bake ;;
    --dry-run) main --dry-run ;;
    *)         main ;;
esac
