유튜브 악보 영상에서 악보 이미지를 추출하여 PDF로 만드는 스킬.

## 사용법

```bash
cd ~/discord-bot-nino/tools/sheet-music-extractor

# 기본 (이미지만)
uv run python extract.py "유튜브URL" --output output.pdf

# 양식 적용 (제목/아티스트 포함 A4 PDF)
uv run python extract.py "유튜브URL" --output output.pdf --format formatted --title "곡명" --artist "아티스트"

# 흑백 변환 (컬러 음표 → 검정)
uv run python extract.py "유튜브URL" --output output.pdf --bw

# 교대 갱신 영상 (위/아래 반씩 바뀌는 영상)
uv run python extract.py "유튜브URL" --output output.pdf --split-mode half

# 풀 옵션
uv run python extract.py "유튜브URL" --output output.pdf --split-mode half --format formatted --title "곡명" --artist "아티스트" --bw
```

## 옵션

| 옵션 | 기본값 | 설명 |
|------|--------|------|
| --output, -o | output.pdf | 출력 PDF 경로 |
| --fps | 1 | 프레임 추출 속도 (fps) |
| --split-mode | auto | auto/half/none — 교대 갱신 감지 |
| --format | simple | simple/formatted — PDF 양식 |
| --title | "" | 곡 제목 (formatted용) |
| --artist | "" | 아티스트 (formatted용) |
| --bw | false | 흑백 변환 |
| --hash-threshold | 8 | 중복 제거 해시 거리 |

## 파이프라인

1. yt-dlp로 영상 다운로드
2. ffmpeg로 프레임 추출 (1fps)
3. 흰 배경 비율로 악보 프레임 필터링
4. Perceptual Hash로 중복 제거 (split-mode 적용)
5. 컬러 UI 바 자동 크롭 (흰 픽셀 비율 기반)
6. (선택) 흑백 변환
7. PDF 생성

## 필요 도구
- ffmpeg (`sudo apt install ffmpeg`)
- Python 패키지: uv가 자동 설치 (yt-dlp, Pillow, imagehash, numpy)

## Discord에서 사용
유저가 유튜브 악보 링크를 주면 이 스킬로 추출 후 discord-send -f로 PDF 전송.
