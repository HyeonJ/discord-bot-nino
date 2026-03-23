---
name: yaksu-history
description: Discord 메시지 히스토리를 조회한다. 스레드 대화, reply chain, 특정 메시지/시간 전후 맥락, 키워드 검색. 기본 출력 JSONL (jq 체이닝 가능), --pretty로 사람용 포맷. Use when "대화 찾아줘", "스레드 보여줘", "뭐라고 했었지", "reply chain", or looking up past Discord conversations.
---

Discord 메시지 히스토리 CLI — SQLite 기반.

## 명령어

```bash
# 스레드 전체 대화
yaksu-history thread <스레드명> [--pretty]

# reply chain 추적
yaksu-history reply-chain <메시지ID> [--pretty]

# 특정 메시지 전후 맥락
yaksu-history around --id <메시지ID> [-B N] [-A N] [--pretty]

# 특정 채널+시간 전후
yaksu-history around --channel <채널명> --at <시간> [-B N] [-A N] [--pretty]

# 키워드 검색
yaksu-history search <키워드> [--channel <채널명>] [--author <이름>] [--pretty]

# JSONL 마이그레이션
yaksu-history migrate <JSONL 디렉토리>
```

## 출력 형식
- 기본: JSONL (jq 체이닝 가능)
- `--pretty`: 사람이 읽기 좋은 포맷

## 체이닝 예시
```bash
yaksu-history search '파일' | jq -r '.content'
yaksu-history search '저울' --channel 충재-다용도 | jq '.author_name'
```

## DB 위치
- 환경변수 `YAKSU_HISTORY_DB` 또는 기본값 `~/.local/share/yaksu-history/messages.db`
- relay에서 JSONL + SQLite 동시 저장 중
