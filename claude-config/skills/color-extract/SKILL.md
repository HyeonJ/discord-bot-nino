---
name: color-extract
description: 이미지에서 색상 추출 + 퍼블 매칭용 시각 분석. 색상 코드, 크기, 간격 등 정확한 수치 추출
user-invocable: true
---

# 이미지 색상 추출 & 시각 분석

이미지에서 정확한 색상(HEX/RGB)을 추출하고, UI 요소의 크기/간격을 분석하는 도구.

## 색상 추출 CLI

```bash
# 전체 이미지에서 상위 10개 색상 (흰색/회색 제외)
/home/bpx27/.local/share/color-extract/.venv/bin/python /home/bpx27/discord-bot-nino/tools/color-extract.py <이미지경로> --exclude-white --exclude-gray

# 특정 영역만 추출 (x, y, width, height)
/home/bpx27/.local/share/color-extract/.venv/bin/python /home/bpx27/discord-bot-nino/tools/color-extract.py <이미지경로> --region 100,50,200,100 --exclude-white --exclude-gray --top 5
```

## 사용 시나리오

### 퍼블 매칭 작업
1. 퍼블 스크린샷과 현재 구현 스크린샷 2장을 받음
2. 색상 추출 CLI로 정확한 색상 코드 확인
3. Read 도구로 이미지 열어서 시각적 차이 비교
4. 차이점을 정리해서 수정 지시 생성

### 색상 추출 팁
- `--exclude-white --exclude-gray`: 배경색 제거 후 의미 있는 색상만 추출
- `--region`: 특정 UI 요소(버튼, 차트, 아이콘 등) 영역만 집중 분석
- 차트 색상: 차트 영역을 --region으로 지정하면 정확도 높아짐

### 크기/간격 분석
이미지에서 직접 크기를 재야 할 때:
```bash
# 이미지 크기 확인
/home/bpx27/.local/share/color-extract/.venv/bin/python -c "
from PIL import Image
img = Image.open('이미지경로')
print(f'크기: {img.size[0]}x{img.size[1]}')
"
```

## 설치 경로
- venv: `/home/bpx27/.local/share/color-extract/.venv`
- CLI: `/home/bpx27/discord-bot-nino/tools/color-extract.py`
