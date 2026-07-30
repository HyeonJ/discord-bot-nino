---
name: gemini
description: Gemini에게 질문하기 — gemini CLI + API key 사용. 세컨드 오피니언, 검색, 번역 등에 활용
user_invocable: true
---

Gemini CLI를 사용해 Google Gemini 모델에게 질문하는 스킬.

## 사용법

```bash
# 기본 질문 (gemini-2.5-flash)
source ~/.nvm/nvm.sh && source /home/bpx27/discord-bot-nino/.env && echo "질문 내용" | GEMINI_API_KEY=$GEMINI_API_KEY gemini -p "" -m gemini-2.5-flash

# 고급 모델 (gemini-2.5-pro)
source ~/.nvm/nvm.sh && source /home/bpx27/discord-bot-nino/.env && echo "질문 내용" | GEMINI_API_KEY=$GEMINI_API_KEY gemini -p "" -m gemini-2.5-pro
```

## 모델 선택
- **gemini-2.5-flash**: 빠르고 가벼운 기본 모델. 일상 질문, 번역, 간단한 검색에 적합
- **gemini-2.5-pro**: 복잡한 추론, 코드 분석, 심층 답변에 적합

## 활용 예시
- 세컨드 오피니언: Claude와 다른 관점이 필요할 때
- 실시간 정보: 최신 뉴스, 날씨, 검색 결과
- 번역/언어: 자연스러운 번역이나 언어 관련 질문
- 코드 리뷰: 다른 AI의 시각으로 코드 검토

## 주의사항
- API key는 `.env`에서 로드 (GEMINI_API_KEY)
- 무료 티어: Flash 30회/분, 1,500회/일 | Pro 15회/분, 150회/일
- 무료 한도 초과 시 429 에러 (자동 결제 안 됨)
- nvm 로드 필수: `source ~/.nvm/nvm.sh`
