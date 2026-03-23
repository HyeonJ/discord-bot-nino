# PCB-VOX Admin Notion 관리 스킬

pcb-vox-admin QR 관리자 프로젝트의 Notion 문서를 생성/수정/조회하고, Notion 기반으로 개발 작업을 수행하는 스킬 모음.

## 접근 방법

Notion MCP는 회사컴(bpx27@100.111.194.120)의 WSL Ubuntu에서만 사용 가능.
SSH 경유로 Claude CLI를 실행해서 Notion 작업 수행.

### SSH 실행 패턴
```bash
# 1. 프롬프트를 파일로 저장
cat > /tmp/notion-prompt.txt << 'EOF'
프롬프트 내용
EOF

# 2. 래퍼 스크립트 생성 (unix 줄바꿈 필수)
printf '#!/bin/bash\nexport PATH="/home/bpx27/.nvm/versions/node/v24.14.0/bin:$PATH"\nexport HOME="/home/bpx27"\nPROMPT=$(cat /mnt/c/Users/bpx27/notion-prompt.txt)\nclaude -p "$PROMPT" --model claude-haiku-4-5-20251001 --dangerously-skip-permissions\n' > /tmp/run-notion.sh

# 3. SCP로 파일 전송 후 WSL에서 실행
scp /tmp/notion-prompt.txt bpx27@100.111.194.120:C:/Users/bpx27/notion-prompt.txt
scp /tmp/run-notion.sh bpx27@100.111.194.120:C:/Users/bpx27/run-notion.sh
ssh bpx27@100.111.194.120 "wsl -d Ubuntu bash /mnt/c/Users/bpx27/run-notion.sh"
```
**주의**: base64 인라인 방식은 Windows SSH 명령줄 길이 제한에 걸림. 반드시 SCP+래퍼 스크립트 방식 사용.

## Notion 페이지 구조 (QR 관리자)

```
QR 관리자 (325d10f5-faac-81c7-8180-f170e9d7ef71)
├── Overview (325d10f5faac81f2a31ee4771993fe78)
├── 기능별 개발 (325d10f5faac81a48aa8d2ef89d7358b)
│   ├── QR 생성 (325d10f5faac8175a89bf5cc5f5c83d6)
│   │   ├── 개발 진행상황 (325d10f5faac812ab5bdc43525280f16)
│   │   └── 테스트 진행상황 (325d10f5faac819ca2cbe59e6469f443)
│   ├── QR 조회 (325d10f5faac816684d2f798a22f481d)
│   │   ├── 개발 진행상황 (325d10f5faac81f994f5d96d0b0fedb2)
│   │   └── 테스트 진행상황 (325d10f5faac81fca805d42db2b104fe)
│   ├── QR 상세 (325d10f5faac8147aca0e342f04f4094)
│   └── QR 통계(대시보드) (325d10f5faac81008acbdeaf42365a1c)
├── 프로젝트 진행/운영 (325d10f5faac8172a7f3d1469b1b0ad8)
│   ├── Daily 진행상황 (325d10f5faac814ea6b2f1d4da9134ce)
│   └── 버그/이슈 로그 (325d10f5faac8130b9aee0fadc4ba965)
├── 기획/설계 (32cd10f5-faac-8137-8adb-ded536eca9c8)
│   ├── API 명세 (32cd10f5-faac-8133-83a0-c887ed07cec5)
│   ├── DB 스키마 (32cd10f5-faac-81b7-93dd-cafa4f894142)
│   └── 릴리스 로그 (32cd10f5-faac-81a1-8da8-dd89d3ec95b3)
└── 클로드 Skill (32cd10f5-faac-819c-9597-f5d2a4b2a17b)
```

## Notion 페이지 구조 (QR 사용자)

```
QR 사용자 (326d10f5-faac-81ff-9adf-faf19679b5d0)
├── Overview (32cd10f5-faac-811c-9c67-e4b3d8740d41)
├── 사용자 화면 흐름 (32cd10f5-faac-81e4-b0c1-f20f5bf5f423)
│   ├── 시작 화면 (32cd10f5-faac-8102-8067-e4a1e4e5dcf9)
│   ├── 카카오 인증 (32cd10f5-faac-8126-ba58-fd2d26b09a32)
│   ├── 추가정보 입력 (32cd10f5-faac-816a-923c-e7825fa8db14)
│   ├── 가입 완료 (32cd10f5-faac-818a-a46c-c4cd012589bd)
│   └── 예외/에러 플로우 (32cd10f5-faac-8191-bd4a-dee522a49427)
├── 기능별 개발 (32cd10f5-faac-8131-b4e2-f9dfdf1b04a9)
│   ├── 세션/인증 처리 (32cd10f5-faac-812d-b4ca-db70623ca874)
│   ├── 회원가입 API (32cd10f5-faac-8197-9b9d-caf50e80b870)
│   ├── 자녀 정보 저장 (32cd10f5-faac-81a0-8654-ebc5be365af2)
│   ├── 공통 UX/컴포넌트 (32cd10f5-faac-81e4-95d9-fb439d392028)
│   └── 기업/프로그램 분기 (32cd10f5-faac-815c-9dd2-f85c0c24af18)
├── 프로젝트 진행/운영 (32cd10f5-faac-81e8-a957-f05c7fcc1226)
│   ├── 전체 개발 진행상황 (32cd10f5-faac-8143-81de-c26d1acdcdd3)
│   ├── Daily 진행상황 (32cd10f5-faac-81ac-abde-ffe7683d0bd3)
│   └── 운영 이슈 (32cd10f5-faac-8195-8219-edda789bab8e)
├── 품질이슈/릴리스 (32cd10f5-faac-8119-8fd9-cff9de79fbf0)
│   ├── 디펙/버그 로그 (32cd10f5-faac-811d-a555-cd043424878a)
│   ├── 주간 리뷰 (32cd10f5-faac-8183-902d-e4958ccee02d)
│   ├── 릴리스 마일스톤 (32cd10f5-faac-81c6-a458-fda7f859cb1e)
│   └── 회귀 테스트 체크리스트 (32cd10f5-faac-8196-91e7-fe2a7c0af636)
├── 기업/프로그램 확장 (32cd10f5-faac-8150-b147-e1baa6219eaa)
│   ├── 기업/프로그램 목록 (32cd10f5-faac-81d6-9969-d1f8fb87647b)
│   ├── 신규 추가 온보딩 체크리스트 (32cd10f5-faac-817a-9415-dd7195841215)
│   └── 설정 템플릿 (32cd10f5-faac-8109-a8a9-c1a9d65e0365)
└── 기획/설계 (32cd10f5-faac-8119-8461-f95bc9b5efef)
    ├── 화면설계 (32cd10f5-faac-81e4-93ed-d8101b53802e)
    ├── API 명세 (32cd10f5-faac-8185-af01-e79e9cdcb0d3)
    ├── DB 스키마 (32cd10f5-faac-8148-834c-dddd70fed756)
    └── 보안/세션 정책 (32cd10f5-faac-817c-87ed-fb4242069c72)
```

---

## Skill 목록 (15개)

### 1. notion.ctx_bootstrap — 작업 컨텍스트 초기화
- **트리거**: "오늘 할 일 정리해줘", "작업 시작", "컨텍스트 로드"
- **기능**: Overview + 전체 진행상황 + Daily 최신 + 버그/이슈 페이지를 한번에 읽어서 현재 프로젝트 상태 요약. 착수 순서 제안
- **입력**: 없음 (자동으로 주요 페이지 fetch)
- **출력**: 프로젝트 현황 요약 + 오늘 우선 작업 추천

### 2. notion.resolve_page — Notion 페이지 찾기
- **트리거**: "이 페이지 찾아줘", "QR 조회 문서 어디야", "노션에서 찾아줘"
- **기능**: 제목/키워드로 Notion 페이지를 검색하고 ID, 위치, 타입 반환
- **입력**: 페이지 제목 또는 키워드
- **출력**: 페이지 ID + 경로 + 타입(기획/개발/테스트 등)

### 3. notion.spec_reader — 기획/설계 문서 읽기
- **트리거**: "API 스펙 읽어줘", "화면설계서 확인해줘", "DB 스키마 보여줘"
- **기능**: 기획/설계 페이지에서 구현 범위, 제약 조건, 완료 기준 추출
- **입력**: 페이지 이름 또는 ID
- **출력**: 구현 체크리스트 + 제약 조건 + 모호성 리스크

### 4. notion.task_planner — 작업 분해
- **트리거**: "이 기능 작업 분해해줘", "작업 계획 세워줘"
- **기능**: Notion 문서 기준으로 하위 작업을 분해하고 우선순위 매기기
- **입력**: 기능명 또는 페이지 ID
- **출력**: 하위 작업 목록 + 우선순위 + 예상 시간

### 5. notion.task_pickup — 다음 작업 추천
- **트리거**: "지금 뭐 하면 돼?", "다음 할 일 추천해줘"
- **기능**: 현재 상태/의존관계 기반으로 바로 시작할 수 있는 작업 추천
- **입력**: 없음 (현재 진행상황 자동 확인)
- **출력**: 추천 작업 3개 + 근거

### 6. notion.implement_from_spec — 스펙 기반 코드 작성
- **트리거**: "스펙대로 코드 짜줘", "이 명세 구현해줘", "API 명세 보고 코드 작성"
- **기능**: Notion 명세를 읽고 코드 수정/생성 범위를 제안한 뒤 실행
- **입력**: 기능명 또는 페이지 ID + 코드 경로
- **출력**: 변경 파일 목록 + 코드 작성 + 영향 범위
- **필수 절차**: 코드 작성 전 반드시 **릴리스 로그**(325d10f5faac8152803ec2683343667e)에서 가장 최근 버전의 화면설계서 PDF를 확인하고 참조할 것. 릴리스 로그의 버전 이력(Revision History) 하단에 첨부된 PDF가 최신 스펙임.

### 7. notion.api_contract_sync — API 명세 vs 코드 비교
- **트리거**: "API 명세 기준으로 미구현 체크", "API 불일치 확인"
- **기능**: API 명세 페이지와 실제 코드를 비교해서 누락/불일치 검출
- **입력**: API 명세 페이지 ID (기본: 325d10f5faac8158834cc3602470d8c7)
- **출력**: 일치/불일치 목록 + 누락된 endpoint

### 8. notion.ui_spec_sync — UI 문서 기반 구현 체크
- **트리거**: "화면 문서 기준으로 누락 확인", "UI 구현 체크"
- **기능**: 화면설계 문서 기준으로 컴포넌트/상태/이벤트 구현 체크리스트 생성
- **입력**: 화면명 또는 페이지 ID
- **출력**: UI 체크리스트 + 누락 항목

### 9. notion.test_scenario_sync — 테스트 시나리오 → 코드
- **트리거**: "테스트 시나리오로 테스트 코드 만들어줘", "테스트 골격 생성"
- **기능**: 테스트 진행상황 페이지에서 시나리오를 읽고 테스트 코드 골격 생성
- **입력**: 기능명 (QR 생성/조회/상세/통계)
- **출력**: 테스트 코드 파일 + 시나리오 매핑

### 10. notion.qa_update_sync — 테스트 결과 → Notion 반영
- **트리거**: "테스트 결과 노션에 반영해줘", "QA 결과 업데이트"
- **기능**: 테스트 실행 결과를 해당 기능의 테스트 진행상황 + 품질이슈 페이지에 반영
- **입력**: 테스트 결과 (pass/fail 목록)
- **출력**: Notion 업데이트 결과

### 11. notion.task_complete_update — 작업 완료 처리
- **트리거**: "이 작업 완료 처리해줘", "작업 끝났어 노션 업데이트"
- **기능**: 상태를 Done으로 변경, 체크리스트 체크, PR 링크 추가, Daily에 기록
- **입력**: 작업명 + PR 링크 (선택)
- **출력**: 업데이트 결과 + 다음 단계 제안

### 12. notion.blocker_watchdog — 지연/블로커 감지
- **트리거**: "지연된 작업 확인", "블로커 체크", "막힌 거 있어?"
- **기능**: 진행상황 페이지에서 blocked/지연 이슈를 감지하고 우선순위 재조정 제안
- **입력**: 없음 (전체 스캔)
- **출력**: 지연 작업 목록 + 원인 분석 + 해결 제안

### 13. notion.daily_report — Daily 리포트 작성
- **트리거**: "오늘 한 거 정리해줘", "Daily 써줘", "퇴근 전 정리"
- **기능**: 오늘 작업 내역을 Daily 진행상황 페이지에 날짜별로 기록
- **입력**: 없음 (git log + 대화 내역에서 자동 추출) 또는 수동 입력
- **출력**: Daily 페이지 생성/업데이트

### 14. notion.release_note_sync — 릴리스 노트 작성
- **트리거**: "릴리스 노트 써줘", "이번 배포 정리"
- **기능**: 릴리스 마일스톤 페이지에 배포 내역, 변경사항, 알려진 이슈 정리
- **입력**: 버전명 (선택)
- **출력**: 릴리스 노트 페이지 생성

### 15. notion.postmortem_capture — 장애 사후보고서
- **트리거**: "장애 보고서 써줘", "사후 분석 정리"
- **기능**: 장애 발생 시 타임라인, 원인, 영향, 대응, 재발 방지 정리
- **입력**: 장애 내용 설명
- **출력**: 사후보고서 페이지 생성

---

## Skill 의존 관계

```
ctx_bootstrap ─→ resolve_page, task_pickup, daily_report
resolve_page ─→ spec_reader, api_contract_sync, ui_spec_sync, test_scenario_sync
spec_reader ─→ task_planner, implement_from_spec
task_planner ─→ implement_from_spec, task_pickup
implement_from_spec ─→ task_complete_update, qa_update_sync
test_scenario_sync ─→ qa_update_sync
qa_update_sync ─→ release_note_sync, blocker_watchdog
postmortem_capture ─→ 독립 실행 가능
```

## 실행 흐름 예시

### 일반적인 개발 사이클
1. `ctx_bootstrap` → 오늘 상태 파악
2. `task_pickup` → 다음 작업 선택
3. `spec_reader` → 명세 확인
4. `implement_from_spec` → 코드 작성
5. `test_scenario_sync` → 테스트 작성
6. `qa_update_sync` → 테스트 결과 반영
7. `task_complete_update` → 완료 처리
8. `daily_report` → 퇴근 전 정리

---

## 페이지 용도 가이드

| 섹션 | 용도 | 언제 업데이트 |
|------|------|--------------|
| Overview | 기술 스택, 프로젝트 개요 | 스택 변경 시 |
| 기능별 개발 | 각 기능의 개발/테스트 진행상황 | 개발 진행 시 매번 |
| Daily 진행상황 | 매일 작업한 내용 기록 | 퇴근 전 or 작업 마무리 시 |
| 버그/이슈 로그 | 발견된 버그, 이슈 기록 | 버그 발견 시 |
| 주간 리뷰 | 주간 진행 요약 | 매주 금요일 |
| 릴리스 마일스톤 | 릴리스 일정, 목표 | 마일스톤 설정/변경 시 |
| 기획/설계 | 화면설계서, API, DB 등 설계 문서 | 설계 변경 시 |
| 디자인/UI | 퍼블리싱 결과물 정리 | 디자인 완료 시 |
| 페이지 구조 카탈로그 | 전체 구조 맵 | 페이지 추가/삭제 시 |
| 클로드 Skill | Skill 트리거 + 기능 설명 | Skill 변경 시 |

## 아이콘 규칙

- **아이콘 사용 안 함** (Darren 요청 2026-03-23). 모든 페이지 기본 아이콘으로.
- 새 페이지 생성 시 아이콘 설정하지 말 것.

## 주의사항
- Notion 작업은 반드시 SSH 경유 (로컬에서 Notion MCP 직접 사용 불가)
- 한글 프롬프트는 base64 인코딩으로 전달
- 페이지 생성 후 이 skill 파일의 트리 구조도 함께 업데이트할 것
- 긴 작업은 백그라운드 에이전트로 실행
- **페이지 삭제/아카이브 불가**: MCP에 archived 기능 없고, OAuth 토큰은 REST API 직접 호출 시 401. 삭제는 Darren에게 요청할 것
