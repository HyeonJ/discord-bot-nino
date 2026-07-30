---
name: subtitle
description: 외국어 영상에서 한글 자막(SRT) 생성 — Whisper 음성인식 + 번역, 하드섭 OCR 지원
---

외국어 영상을 받아 한글 자막 파일(SRT)을 생성한다.

## 모드

### 1. 음성 인식 모드 (기본)
Whisper로 음성을 인식해서 자막 생성 후 한국어로 번역.

### 2. 하드섭 OCR 모드
영상에 직접 렌더링된 외국어 자막을 프레임 캡처 + Vision OCR로 읽어서 번역.

## 사용법

인자(ARGUMENTS)로 파일 경로, URL, 옵션이 전달된다.

### 옵션 파싱
- `--model <tiny|small|medium>` — Whisper 모델 (기본: small)
- `--lang <code>` — 소스 언어 코드 (기본: 자동감지)
- `--no-translate` — 번역 없이 원문 자막만
- `--target <code>` — 번역 대상 언어 (기본: ko)
- `--ocr` — 하드섭 OCR 모드 강제
- 나머지 인자 = 파일 경로 또는 URL

## 처리 흐름 A: 음성 인식

```bash
# 1. 입력 확보
#    - YouTube URL이면 yt-dlp로 다운로드
#    - Discord 첨부 파일 경로면 그대로 사용
#    - 로컬 경로면 그대로 사용
INPUT="$1"

# YouTube URL 감지
if echo "$INPUT" | grep -qE 'youtube\.com|youtu\.be'; then
    yt-dlp -f 'bestaudio[ext=m4a]/best' -o '/tmp/subtitles/%(title)s.%(ext)s' "$INPUT"
    INPUT=$(ls -t /tmp/subtitles/*.m4a | head -1)
fi

# 2. 오디오 추출 (영상이면)
ffmpeg -i "$INPUT" -vn -acodec pcm_s16le -ar 16000 -ac 1 /tmp/subtitles/audio.wav -y

# 3. Whisper 음성 인식
whisper /tmp/subtitles/audio.wav \
    --model small \
    --output_format srt \
    --output_dir /tmp/subtitles/ \
    --word_timestamps True

# 4. 원문 SRT 파일 확인
# /tmp/subtitles/audio.srt 에 생성됨
```

**번역 단계:**
- 원문 SRT 파일을 읽어서 Claude가 직접 한국어로 번역
- SRT 포맷(번호, 타임스탬프) 유지하고 텍스트만 번역
- 기술 용어는 원문 유지, 자연스러운 의역

**번역 규칙:**
- 타임스탬프 절대 변경 금지
- 자막 번호 유지
- 기술 용어(React, API 등)는 원문 그대로
- 자연스러운 한국어로 의역 (직역 금지)
- 번역 결과를 `{원본파일명}.ko.srt`로 저장

## 처리 흐름 B: 하드섭 OCR

```bash
# 1. 프레임 캡처 (1초 간격)
mkdir -p /tmp/subtitles/frames
ffmpeg -i "$INPUT" -vf "fps=1" /tmp/subtitles/frames/frame_%04d.png -y

# 2. 하단 자막 영역만 크롭 (하단 20%)
for f in /tmp/subtitles/frames/frame_*.png; do
    # ffmpeg로 하단 크롭 (자막이 보통 하단에 위치)
    ffmpeg -i "$f" -vf "crop=iw:ih*0.2:0:ih*0.8" "${f%.png}_crop.png" -y
done
```

**OCR + 번역 단계:**
- 크롭된 프레임 이미지들을 Claude Vision(Read 도구)으로 읽어서 자막 텍스트 추출
- 연속 동일 자막은 병합하고 시작/끝 타임스탬프 계산
- 추출된 텍스트를 한국어로 번역
- SRT 포맷으로 출력

## 출력

- 원문 자막: `/tmp/subtitles/{파일명}.srt`
- 한글 자막: `/tmp/subtitles/{파일명}.ko.srt`
- Discord 전달: `discord-send -f /tmp/subtitles/{파일명}.ko.srt DM-Darren "한글 자막 완성!"`

## Whisper 모델 정보

| 모델 | 크기 | 속도 (5분 영상) | 정확도 |
|------|------|----------------|--------|
| tiny | 73MB | ~10초 | 낮음 |
| small | 462MB | ~30초 | 양호 (기본) |
| medium | ~1.5GB | ~2분 | 높음 |

*집컴 CPU(i5-14600K) 기준. 첫 실행 시 모델 다운로드 필요.*

## 예시

```
# 로컬 파일
/subtitle /tmp/video.mp4

# YouTube
/subtitle https://www.youtube.com/watch?v=xxxxx

# medium 모델로 정확하게
/subtitle /tmp/video.mp4 --model medium

# 원문만 (번역 없이)
/subtitle /tmp/video.mp4 --no-translate

# 하드섭 OCR
/subtitle /tmp/video.mp4 --ocr

# 일본어→한국어
/subtitle /tmp/video.mp4 --lang ja
```
