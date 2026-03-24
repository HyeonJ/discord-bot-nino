#!/bin/bash
# 니노 음성 비서 루프
# 니노야 감지 → "응!" → 녹음 → STT → Claude 처리 → TTS 응답
# 사용: ./voice-assistant.sh

set -e
cd "$(dirname "$0")"
source ~/.nvm/nvm.sh

POWERSHELL="/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
WAKE_LISTENER="wake-word-listener.py"
WAKE_FILE="/tmp/nino-wake-detected"
LOG="/tmp/nino-voice-assistant.log"

# 현재 마이크 디바이스 탐지
get_mic_device() {
    $POWERSHELL -Command "
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
ffmpeg -list_devices true -f dshow -i dummy 2>&1
" 2>&1 | grep '(audio)' | head -1 | sed 's/.*"\(.*\)".*/\1/'
}

# TTS 재생
say() {
    local text="$1"
    local duration="${2:-3}"
    edge-tts --voice "ko-KR-HyunsuMultilingualNeural" --rate="-8%" --pitch="+1Hz" --text "$text" --write-media /tmp/nino-reply.mp3 2>/dev/null
    $POWERSHELL -Command "
Add-Type -AssemblyName presentationCore
\$player = New-Object System.Windows.Media.MediaPlayer
\$player.Open([uri]::new('\\\\wsl.localhost\\Ubuntu\\tmp\\nino-reply.mp3'))
\$player.Play()
Start-Sleep -Seconds $duration
" 2>/dev/null
}

# 녹음
record() {
    local mic="$1"
    local seconds="${2:-5}"
    $POWERSHELL -Command "
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
ffmpeg -y -f dshow -i 'audio=$mic' -t $seconds -ar 16000 -ac 1 -acodec pcm_s16le C:\Users\bpx27\nino-mic-input.wav 2>&1 | Out-Null
" 2>/dev/null
}

# STT (Google Speech Recognition)
stt() {
    ffmpeg -y -i /mnt/c/Users/bpx27/nino-mic-input.wav -af "volume=15dB" /tmp/nino-mic-boosted.wav 2>/dev/null
    uv run --with SpeechRecognition python3 -c "
import speech_recognition as sr
r = sr.Recognizer()
with sr.AudioFile('/tmp/nino-mic-boosted.wav') as s:
    audio = r.record(s)
try:
    text = r.recognize_google(audio, language='ko-KR')
    print(text)
except sr.UnknownValueError:
    pass
" 2>/dev/null
}

# 리스너 시작
start_listener() {
    rm -f "$WAKE_FILE"
    kill "$(cat /tmp/nino-wake-listener.pid 2>/dev/null)" 2>/dev/null || true
    uv run --with SpeechRecognition python3 "$WAKE_LISTENER" 2>>"$LOG" &
    echo $! > /tmp/nino-wake-listener.pid
    echo "[voice-assistant] 리스너 시작 PID: $!" >> "$LOG"
}

# 메인 루프
main() {
    MIC=$(get_mic_device)
    echo "[voice-assistant] 마이크: $MIC" | tee -a "$LOG"
    echo "[voice-assistant] 음성 비서 시작" | tee -a "$LOG"

    start_listener

    while true; do
        # 1. 웨이크워드 대기
        DETECTED=false
        for i in $(seq 1 600); do  # 최대 10분 대기
            if [ -f "$WAKE_FILE" ]; then
                TRANSCRIPT=$(cat "$WAKE_FILE")
                rm -f "$WAKE_FILE"
                echo "[voice-assistant] WAKE: $TRANSCRIPT" >> "$LOG"
                DETECTED=true
                break
            fi
            sleep 1
            # 리스너가 죽었으면 재시작
            if ! kill -0 "$(cat /tmp/nino-wake-listener.pid 2>/dev/null)" 2>/dev/null; then
                echo "[voice-assistant] 리스너 재시작" >> "$LOG"
                start_listener
                sleep 10
            fi
        done

        if [ "$DETECTED" = false ]; then
            continue
        fi

        # 2. 리스너 중지 (마이크 해제)
        kill "$(cat /tmp/nino-wake-listener.pid 2>/dev/null)" 2>/dev/null || true
        sleep 0.5

        # 3. "응!" TTS
        say "응 말해봐" 2

        # 4. 녹음 (8초)
        record "$MIC" 8

        # 5. STT
        SAID=$(stt)
        echo "[voice-assistant] Darren said: '$SAID'" >> "$LOG"

        if [ -z "$SAID" ]; then
            say "미안 잘 안 들렸어. 다시 불러줘" 3
            start_listener
            continue
        fi

        # 6. Claude 처리 + TTS 응답
        # stdout으로 출력하면 Claude Code가 처리
        echo "VOICE_INPUT:$SAID"

        # 7. 리스너 재시작
        start_listener

        # Claude Code 처리를 위해 잠시 대기
        sleep 30
    done
}

main "$@"
