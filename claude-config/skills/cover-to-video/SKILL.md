---
name: cover-to-video
description: AI 커버 음원 + 이미지 → mp4 영상 생성 (유튜브 업로드용)
user_invocable: true
---

AI 커버 음원에 이미지를 합쳐서 유튜브 업로드 가능한 mp4 영상을 만드는 스킬.

## 사용법

사용자가 음원 파일 경로 + (선택) 이미지를 제공하면 영상을 생성한다.

## 파이프라인

### 1. 이미지 준비
```bash
WORK_DIR=/tmp/voice-cover
SONG_NAME="곡이름"
AUDIO_FILE="$WORK_DIR/${SONG_NAME}_cover.wav"

# 방법 A: 사용자가 이미지 제공
IMAGE_FILE="/path/to/image.jpg"

# 방법 B: 이미지 없으면 검정 배경 + 텍스트 생성
ffmpeg -y -f lavfi -i "color=c=black:s=1920x1080:d=1" -vframes 1 "$WORK_DIR/cover_bg.png"
IMAGE_FILE="$WORK_DIR/cover_bg.png"
```

### 2. 영상 생성
```bash
# 정지 이미지 + 음원 → mp4 (H.264 + AAC, 유튜브 최적)
ffmpeg -y \
  -loop 1 -framerate 1 -i "$IMAGE_FILE" \
  -i "$AUDIO_FILE" \
  -c:v libx264 -preset slow -crf 18 -tune stillimage \
  -c:a aac -b:a 320k -ar 48000 \
  -pix_fmt yuv420p \
  -shortest \
  -movflags +faststart \
  "$WORK_DIR/${SONG_NAME}_cover.mp4"
```

### 3. 결과 파일
- 영상: `$WORK_DIR/${SONG_NAME}_cover.mp4`

## 옵션
- `-crf 18`: 높은 화질 (유튜브 업로드용으로 충분)
- `-b:a 320k`: 고음질 오디오
- `-tune stillimage`: 정지 이미지 최적화 (파일 크기 절약)
- `-movflags +faststart`: 유튜브 업로드 최적화

## 참고
- ffmpeg만 사용하므로 추가 설치 불필요
- 이미지 해상도: 1920x1080 권장 (유튜브 HD)
- 이미지가 없으면 검정 배경으로 생성
