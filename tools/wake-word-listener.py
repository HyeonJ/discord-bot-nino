#!/usr/bin/env python3
"""니노야 웨이크워드 감지 스크립트

Windows ffmpeg으로 마이크 녹음 → Google Speech Recognition으로 "니노야" 감지
실행: uv run --with SpeechRecognition python3 wake-word-listener.py
"""

import subprocess
import os
import sys
import time
import speech_recognition as sr

POWERSHELL = "/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
RECORD_SECONDS = 3
WIN_WAV = r"C:\Users\bpx27\nino-wake-listen.wav"
WSL_WAV = "/mnt/c/Users/bpx27/nino-wake-listen.wav"
BOOST_WAV = "/tmp/nino-wake-boosted.wav"
WAKE_FILE = "/tmp/nino-wake-detected"
WAKE_WORDS = ["니노", "니노야", "리노야", "니노아", "미노야", "이노야", "민호야", "민호", "nino"]


def get_mic_device():
    """현재 ffmpeg dshow 마이크 디바이스 자동 탐지"""
    try:
        result = subprocess.run(
            [POWERSHELL, "-Command",
             "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; "
             "ffmpeg -list_devices true -f dshow -i dummy 2>&1"],
            capture_output=True, text=True, timeout=10
        )
        output = result.stdout + result.stderr
        for line in output.split('\n'):
            if '(audio)' in line:
                parts = line.split('"')
                if len(parts) >= 2:
                    return parts[1]
    except Exception as e:
        print(f"[WARN] 디바이스 탐지 실패: {e}", file=sys.stderr, flush=True)
    return "헤드셋 마이크(CORSAIR HS80 RGB Wireless Gaming Receiver)"


def record_chunk(mic_device):
    """Windows ffmpeg으로 마이크 녹음"""
    cmd = (
        f"[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; "
        f"ffmpeg -y -f dshow -i 'audio={mic_device}' -t {RECORD_SECONDS} "
        f"-ar 16000 -ac 1 -acodec pcm_s16le '{WIN_WAV}' 2>&1 | Out-Null"
    )
    try:
        subprocess.run(
            [POWERSHELL, "-Command", cmd],
            timeout=RECORD_SECONDS + 10,
            capture_output=True,
        )
        return os.path.exists(WSL_WAV) and os.path.getsize(WSL_WAV) > 1000
    except subprocess.TimeoutExpired:
        print("[WARN] 녹음 타임아웃", file=sys.stderr, flush=True)
        return False


def boost_audio():
    """볼륨 증폭"""
    try:
        subprocess.run(
            ["ffmpeg", "-y", "-i", WSL_WAV, "-af", "volume=15dB", BOOST_WAV],
            capture_output=True, timeout=5,
        )
        return os.path.exists(BOOST_WAV)
    except Exception:
        return False


def recognize_google(audio_path):
    """Google Speech Recognition으로 한국어 인식"""
    recognizer = sr.Recognizer()
    try:
        with sr.AudioFile(audio_path) as source:
            audio = recognizer.record(source)
        text = recognizer.recognize_google(audio, language="ko-KR")
        return text.strip()
    except sr.UnknownValueError:
        return ""
    except sr.RequestError as e:
        print(f"[WARN] Google API 에러: {e}", file=sys.stderr, flush=True)
        return ""
    except Exception as e:
        print(f"[ERROR] 인식 실패: {e}", file=sys.stderr, flush=True)
        return ""


def main():
    mic_device = get_mic_device()
    print(f"[마이크] {mic_device}", file=sys.stderr, flush=True)
    print(f"[감지어] {', '.join(WAKE_WORDS)}", file=sys.stderr, flush=True)
    print(f"[{RECORD_SECONDS}초 간격으로 녹음 시작]", file=sys.stderr, flush=True)
    print(f"[Google Speech Recognition 사용]", file=sys.stderr, flush=True)

    cooldown = 0
    while True:
        try:
            if cooldown > 0:
                cooldown -= 1
                time.sleep(1)
                continue

            if not record_chunk(mic_device):
                continue

            if not boost_audio():
                continue

            # Google Speech Recognition (빠름!)
            transcript = recognize_google(BOOST_WAV)

            if transcript:
                print(f"  [HEARD] {transcript}", file=sys.stderr, flush=True)
                for wake in WAKE_WORDS:
                    if wake in transcript:
                        print(f"[WAKE] '{wake}' 감지!", file=sys.stderr, flush=True)
                        with open(WAKE_FILE, "w") as f:
                            f.write(transcript)
                        print(f"WAKE:{transcript}", flush=True)
                        cooldown = 30
                        break

        except KeyboardInterrupt:
            print("\n[종료]", file=sys.stderr, flush=True)
            break
        except Exception as e:
            print(f"[ERROR] {e}", file=sys.stderr, flush=True)
            time.sleep(2)


if __name__ == "__main__":
    main()
