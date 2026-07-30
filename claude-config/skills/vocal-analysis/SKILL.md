---
name: vocal-analysis
description: 유튜브 노래 영상의 특정 구간 보컬 발성 분석 — 피치, 포먼트, 음질, 스펙트로그램
user_invocable: true
---

유튜브 영상에서 특정 구간의 보컬을 분석하는 스킬.

## 사용법

사용자가 유튜브 링크 + 분석할 구간(시작~끝)을 제공하면 아래 파이프라인을 실행한다.

## 파이프라인

### 1. 환경 준비
```bash
WORK_DIR=/tmp/vocal-analysis
mkdir -p $WORK_DIR
cd $WORK_DIR

# venv가 없으면 생성 + 패키지 설치
if [ ! -d .venv ]; then
  uv venv .venv
  source .venv/bin/activate
  uv pip install setuptools
  uv pip install "torch==2.5.1" "torchaudio==2.5.1" demucs praat-parselmouth matplotlib numpy scipy
else
  source .venv/bin/activate
fi
```

### 2. 오디오 다운로드 + 구간 추출
```bash
# 다운로드
yt-dlp -x --audio-format wav -o "original.%(ext)s" "유튜브URL"

# 구간 추출 (여유있게 전후 5초씩)
ffmpeg -y -i original.wav -ss 시작초 -to 끝초 -ar 44100 -ac 1 section.wav
```

### 3. 보컬 분리 (Demucs)
```bash
python3 -m demucs --two-stems vocals -n htdemucs section.wav -o separated
# 결과: separated/htdemucs/section/vocals.wav
```

### 4. 분석 스크립트 실행
`analyze.py` 스크립트를 사용하여 분석. 스크립트 위치: `/home/bpx27/.claude/skills/vocal-analysis/analyze.py`

분석 항목:
- **피치(음높이)**: 최저~최고음, 음이름 변환, 피치 변화율
- **포먼트(F1/F2)**: 고음 vs 저음에서 입 열림/혀 위치 차이
- **HNR**: 발성의 깨끗함 (높을수록 좋음)
- **스펙트로그램**: 주파수 분포 시각화
- **음량 변화**: 다이나믹스

```bash
python3 /home/bpx27/.claude/skills/vocal-analysis/analyze.py \
  --vocal separated/htdemucs/section/vocals.wav \
  --start 구간시작초(section.wav기준) \
  --end 구간끝초(section.wav기준) \
  --offset 원곡시작시간초 \
  --title "가사 내용" \
  --output analysis_result.png
```

### 5. 결과 전달
- 차트 이미지 (`analysis_result.png`)를 Discord로 전송
- 핵심 수치 + 발성 해석 + 연습 팁 함께 전달

## 해석 가이드

### 포먼트 해석
- **F1 (입 열림)**: 높을수록 입을 크게 벌림. 고음에서 F1이 올라가면 '오픈 마우스' 테크닉
- **F2 (혀 위치)**: 높을수록 혀가 앞쪽. 낮으면 혀가 뒤로

### HNR 해석
- **20dB 이상**: 매우 깨끗한 발성
- **10~20dB**: 보통
- **10dB 미만**: 기식성(breathy) 발성

### 피치 변화율
- **200 Hz/sec 이하**: 부드러운 음 이동
- **200~500 Hz/sec**: 빠른 음 이동
- **500 Hz/sec 이상**: 매우 급격한 점프

## 주의사항
- GPU 없으면 Demucs 분리에 15~30초 소요
- torch 2.5.1 고정 (최신 버전은 torchcodec 의존성 문제)
- 한글 폰트: NanumGothic 또는 NotoSansCJK 필요
