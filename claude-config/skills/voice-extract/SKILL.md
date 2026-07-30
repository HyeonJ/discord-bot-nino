---
name: voice-extract
description: 유튜브 영상에서 보컬/반주 분리 추출 — demucs htdemucs_ft 모델 사용
user_invocable: true
---

유튜브 영상에서 보컬과 반주를 분리 추출하는 스킬.

## 사용법

사용자가 유튜브 링크를 제공하면 아래 파이프라인을 실행한다.

## 파이프라인

### 1. 환경 준비
```bash
WORK_DIR=/tmp/voice-cover
mkdir -p $WORK_DIR
cd $WORK_DIR

# venv가 없으면 생성 + 패키지 설치
if [ ! -d .venv ]; then
  uv venv .venv --python 3.10
  source .venv/bin/activate
  uv pip install "torch==2.5.1" "torchaudio==2.5.1" --index-url https://download.pytorch.org/whl/cpu
  uv pip install demucs
else
  source .venv/bin/activate
fi
```

### 2. 유튜브 다운로드
```bash
# WAV로 다운로드 (최고 품질)
yt-dlp -x --audio-format wav --audio-quality 0 -o "$WORK_DIR/source.%(ext)s" "유튜브URL"
```

### 3. 보컬/반주 분리
```bash
# htdemucs_ft = 최고 품질 모델 (Fine-tuned Hybrid Transformer Demucs)
# --two-stems=vocals → 보컬 + 반주 2트랙으로 분리
demucs --two-stems=vocals -n htdemucs_ft -o "$WORK_DIR/separated" "$WORK_DIR/source.wav"
```

### 4. 결과 파일
분리 완료 후 아래 경로에 파일 생성:
- 보컬: `$WORK_DIR/separated/htdemucs_ft/source/vocals.wav`
- 반주: `$WORK_DIR/separated/htdemucs_ft/source/no_vocals.wav`

## 출력

결과 파일 경로를 사용자에게 안내한다.
보컬 파일은 voice-train(모델 학습)이나 voice-cover(AI 커버)에 사용 가능.

## 참고
- CPU 전용 환경 (AMD GPU). 4분 곡 기준 약 5~10분 소요.
- htdemucs_ft 모델은 첫 실행 시 자동 다운로드됨 (~80MB)
- 여러 곡을 분리할 때는 반복 실행하면 됨
