---
name: voice-cover
description: AI 커버 생성 — 원곡에 다른 가수 목소리를 입혀서 커버 음원 생성 (RVC v2)
user_invocable: true
---

원곡에 다른 가수의 목소리를 입혀서 AI 커버 음원을 생성하는 스킬.

## 사용법

사용자가 원곡 유튜브 링크 + 목소리 모델(가수이름)을 제공하면 아래 파이프라인을 실행한다.

## 사전 조건
- voice-train으로 학습한 모델이 `/home/bpx27/voice-models/가수이름/` 에 있어야 함
- 또는 다운받은 .pth 모델 파일 경로를 직접 지정

## 파이프라인

### 1. 환경 준비
```bash
WORK_DIR=/tmp/voice-cover
MODELS_DIR=/home/bpx27/voice-models
mkdir -p $WORK_DIR
cd $WORK_DIR

# rvc-python venv (추론 전용)
RVC_VENV=$WORK_DIR/rvc-venv
if [ ! -d "$RVC_VENV" ]; then
  uv venv "$RVC_VENV" --python 3.10
  source "$RVC_VENV/bin/activate"
  uv pip install "torch==2.5.1" "torchaudio==2.5.1" --index-url https://download.pytorch.org/whl/cpu
  uv pip install rvc-python
else
  source "$RVC_VENV/bin/activate"
fi
```

### 2. 원곡 다운로드 + 보컬/반주 분리
```bash
SONG_NAME="곡이름"  # 출력 파일명에 사용
SINGER="가수이름"    # 모델 폴더명

# 다운로드
yt-dlp -x --audio-format wav --audio-quality 0 -o "$WORK_DIR/${SONG_NAME}_original.%(ext)s" "유튜브URL"

# 보컬/반주 분리 (demucs venv 사용)
source $WORK_DIR/.venv/bin/activate  # demucs venv
demucs --two-stems=vocals -n htdemucs_ft -o "$WORK_DIR/separated" "$WORK_DIR/${SONG_NAME}_original.wav"

VOCALS="$WORK_DIR/separated/htdemucs_ft/${SONG_NAME}_original/vocals.wav"
INSTRUMENTAL="$WORK_DIR/separated/htdemucs_ft/${SONG_NAME}_original/no_vocals.wav"
```

### 3. RVC 음성 변환 (최고 퀄리티 설정)
```bash
source "$RVC_VENV/bin/activate"

# 모델 파일 찾기
MODEL_PTH=$(ls $MODELS_DIR/$SINGER/*.pth | head -1)
MODEL_INDEX=$(ls $MODELS_DIR/$SINGER/*.index 2>/dev/null | head -1)

# RVC 변환 (최고 품질 파라미터)
python -m rvc_python cli \
  -i "$VOCALS" \
  -o "$WORK_DIR/${SONG_NAME}_converted_vocals.wav" \
  -mp "$MODEL_PTH" \
  -ip "$MODEL_INDEX" \
  -de cpu \
  -me rmvpe \
  -pi 0 \
  -ir 0.4 \
  -fr 3 \
  -rsr 0 \
  -rmr 0.25 \
  -pr 0.33 \
  -v v2
```

### 4. 변환된 보컬 + 반주 합성
```bash
# 보컬과 반주 믹싱 (보컬 볼륨 약간 높게)
ffmpeg -y \
  -i "$WORK_DIR/${SONG_NAME}_converted_vocals.wav" \
  -i "$INSTRUMENTAL" \
  -filter_complex "[0:a]volume=1.1[v];[1:a]volume=0.9[i];[v][i]amix=inputs=2:duration=longest:dropout_transition=0" \
  "$WORK_DIR/${SONG_NAME}_cover.wav"
```

### 5. 결과 파일
- 최종 커버: `$WORK_DIR/${SONG_NAME}_cover.wav`
- 변환된 보컬만: `$WORK_DIR/${SONG_NAME}_converted_vocals.wav`

## 피치 조정
남자→여자 또는 반대 변환 시 피치 조정 필요:
- 남→여: `-pi 12` (1옥타브 업)
- 여→남: `-pi -12` (1옥타브 다운)
- 미세 조정: `-pi 3` ~ `-pi 5` 정도로 실험

## 품질 파라미터 설명
- `rmvpe`: 가장 정확한 피치 추출 알고리즘
- `index_rate 0.4`: 목소리 유사도 (높으면 원본에 가까움, 너무 높으면 아티팩트)
- `filter_radius 3`: 피치 중앙값 필터 (노이즈 감소)
- `rms_mix_rate 0.25`: 볼륨 엔벨로프 혼합 비율
- `protect 0.33`: 무성자음 보호 (한국어에 중요)

## 대안: Seed-VC (모델 없이 제로샷 변환)
학습된 RVC 모델이 없을 때 Seed-VC로 제로샷 변환 가능.
```bash
# Seed-VC 설치
git clone https://github.com/Plachtaa/seed-vc.git /home/bpx27/seed-vc
cd /home/bpx27/seed-vc
uv venv .venv --python 3.10
source .venv/bin/activate
uv pip install -r requirements.txt

# 변환 (참조 오디오 = 타겟 가수의 보컬 클립)
python inference.py \
  --source "$VOCALS" \
  --target "참조보컬.wav" \
  --output "$WORK_DIR/${SONG_NAME}_seedvc_vocals.wav" \
  --diffusion_steps 100
```
- 모델 학습 불필요, 참조 오디오만 있으면 됨
- RVC보다 퀄리티가 약간 떨어질 수 있음
- CPU에서도 동작 (느리지만 가능)

## 참고
- CPU 전용 환경. 4분 곡 기준 RVC 변환에 약 5~15분 소요.
- 전체 파이프라인 (다운로드 + 분리 + 변환 + 합성): 약 15~30분
