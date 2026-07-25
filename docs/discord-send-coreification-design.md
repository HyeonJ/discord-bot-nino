# discord-send 코어화 기획 (v2 — 룬드 전문 리뷰 반영)

> Tim 발제(2026-07-20). 니노 담당. bot-core 3부작(relay flock/presence/첨부) 완결 후 착수.
> v2(2026-07-21): 룬드 전문 리뷰(md-web `memory/research/coreification-design-review.md`) 반영. **최대 변경 = §2/§5 "봇별 어댑터 층" 제거**(Tim M:7ezk 단순화 정합). Tim 결정 정합 사안 → **§12에 "Tim 결정 필요" 모아둠, 확정 전 Tim 확인 요망.**

## 변경 이력 (v1→v2)
- **§2/§5 [개정 필수]**: "봇별 어댑터 층" 제거 → **단일 코어 CLI 파서(positional 정본 + deprecated shim) + 봇별=얇은 bash 셔틀+env뿐**. Tim M:7ezk("단일 코어+env 주입+shim, 어댑터 층 제거") 정합. §2의 "어댑터 필요?→필요" 답 폐기.
- **§5**: (a) 얇은 bash 셔틀 채택(로직 0, env 절대경로 고정 — 오늘 401 사고 근거). 코어는 dotenv 자동탐색 금지 + 필수키 누락 fail-fast.
- **§6**: "어댑터 계약" → **"파서 계약"** 개칭(fixture 내용은 그대로 유지).
- **§3**: target.type을 **입력 어휘만**(`name|dm|hash|id`)으로. thread/reply는 코어 해석 결과라 정규형 enum에서 제외.
- **§8**: shim 제거 기준을 grep 전수→**런타임 계측**(stderr 경고+카운터, 연속 7일 0). 제거 PR도 Darren 게이트.
- **§9**: 단계0 chore 신설, 롤백 조항, 2단계 게이트 범위 명시, 하루 조건부.
- **§11**: 룬드 부록 A fixture 병합 + M:7488/2000자/env fail-fast 추가.
- **§12 신설**: Tim/명세 결정 필요 항목 집약(부록 A 실측 발견분 포함).

## 0. 도입 — 왜 지금, 왜 계약이 핵심인가 (2026-07-21 실증 3연타)
오늘 하루 발견한 드리프트 3건이 전부 **"산출물은 있는데 배선/강제/계약이 없어 조용히 갈라진"** 같은 뿌리:
1. **니노 멘션**: mention-map.json은 있는데 discord-send에 읽는 코드 없음 → @이름이 플레인텍스트 (PR #13)
2. **bootstrap 죽은 키**: `DISCORD_ATTACHMENT_DIR` 심는데 코드는 `ATTACHMENT_DIR`을 읽음 → 설정 무시
3. **첨부 페이크≠실물**: handleAttachments가 실물은 문자열 반환인데 core는 배열 기대 → 테스트 그린인데 실전 URL (bot-core #42)

→ **말·파일·합의로는 안 갈라짐을 못 막는다. 강제(계약 테스트·심링크·단일 정본)만이 막는다.** 이게 계약 №6이 **2단**이어야 하는 이유. discord-send도 니노(-c/-r+해시, mention 방금 이식)·룬드(mention 원래 있음·positional) 사이 실측 드리프트가 이미 있음.

## 1. 목표
- **단일 코어 정본** 하나 — 3봇(니노/룬드/하루)이 공유, 봇별 차이는 **env 주입**(포인터만)
- 코어화로 위 "배선 없음/계약 없음" 류가 **구조적으로** 사라짐 (한 곳만 고치면 3봇 반영)
- 기존 CLI 사용자(니노 -c/-r, 스크립트들) 안 깨지게 **일시 shim**

## 2. 아키텍처 (단일 코어 + 셔틀 — v2 재정의)
```
[봇별 진입점 셔틀]  env 절대경로 고정 → exec bun <core>/cli.js "$@"   ← 로직 0 (3줄, bun 런타임 §5)
       │
       ▼ argv 그대로
[단일 코어 CLI 파서]  positional 정본 + shim 문법(-c/-r, deprecation 경고) → 정규형
       │
       ▼ 정규형 { target, message, options }  ← 코어 내부 경계 (외부 노출 X)
[코어]  해시DB조회·채널명map·mention변환·스레드·전송직렬화(mkdir락)·Discord API
```
- **"봇별 어댑터 층이 필요한가?"(Tim 질문) — v2 답: 층으로는 불필요.** Tim M:7ezk 단순화 채택. 필요한 건 ①봇별 **env 주입 지점**(셔틀) ②문법 **과도기 shim** — **둘 다 층이 아님**.
- 봇별 CLI 문법 차이는 실체상 **니노 `-c/-r` 하나뿐**(하루는 룬드 계열). "봇별 파서"가 아니라 **한 파서가 받아주는 deprecated 문법(shim)**으로 충분. 층을 세우면 코어에 봇별 분기가 스며들어 다시 갈라짐 → 안 세운다.

## 3. 정규형 (canonical) — 코어 내부 경계 (v2: 입력 어휘만)
```js
{
  target: { type: 'name'|'hash'|'id', value: <string> },   // 입력 어휘만
  message: <string>,
  options: { file?, threadName?, ... }
}
```
- **입력 어휘만** 담는다: `name`(채널명/스레드명/**DM-이름**), `hash`(4자리), `id`(raw snowflake). **thread/reply/channel/dm은 코어가 DB·맵 해석 "후" 정하는 결과 표현** → 정규형 enum에 안 섞음(파서 테스트가 순수해짐, §3 자문 "코어가 해석"과 정합).
- 정규형은 외부(CLI)로 노출 안 함 — 파서↔코어 계약의 단위.
- ※ **DM은 별도 타입 아님**(§12-2 확정): `DM-이름`은 `name`으로 들어와 코어가 channel-map에서 DM 채널로 해석. 정규형에 `dm` 일급 타입 미도입(별도 로직 0 유지).

## 4. 코어 책임
- target 해석: hash→DB역조회(thread_hash/message_hash)·name→channel-map(**DM-이름도 여기서 DM 채널로 해석** — §12-2 확정, 별도 dm 타입 없음)·id→raw
- **mention 변환**: @이름→<@ID> (긴이름우선, 인용 escape — §7)
- 스레드 생성/등록, 답장(message_reference), 파일 업로드
- **전송 직렬화 = mkdir 락 패턴**(flock 결론 그대로): 동일 채널 동시전송 순서보장. flock(1) 금지·mkdir+PID+kill-0 stale+fail-closed (레퍼런스 tmux-send.sh, [[project_bot_core_module]])
- Discord API 호출 + 응답 파싱
- **출력/종료 계약(§7)**: 성공 stdout 형식 명시, **실패 = exit≠0 + stderr 사유**(부록 A-4 실측 결함 교정)
- **env 계약**: dotenv **자동 탐색 금지**(명시된 env 파일만 로드), **필수키 누락 = fail-fast 명시 에러**(bootstrap 죽은키 교훈 — 조용한 무시 금지)

## 5. 봇별 진입점 = 얇은 bash 셔틀 (v2 결정: (a) 채택)
```bash
#!/usr/bin/env bash
export BOT_ENV=/abs/path/to/this-bot/.env        # 절대경로 — 봇 정체 고정
exec bun /abs/path/to/bot-core/discord-send/cli.js "$@"   # ⚠️ bun (node 아님 — 아래 근본원인)
```
- **⚠️ 런타임 = `bun` (1d 발견 정정, 최초 "exec node" → "exec bun")**: cli.js가 해시/reply 역조회 시 `db.js`를 require하는데 `db.js`는 top-level `require('bun:sqlite')` → node에선 `Cannot find module 'bun:sqlite'` 크래시. **relay가 이미 bun 전용(bun:sqlite로 DB 저장)** = 양 봇 호스트에 bun이 이미 하드 의존 → `exec bun`이 db.js "한 벌 물리공유"(§10-①)와 정합. node 유지하려면 db.js를 dual-runtime(node:sqlite 폴백)으로 갈라야 하는데 그게 오히려 드리프트 재파종. **근본원인 = 코어를 Node 모듈로 정한 §10-① 결정이 실은 "bun 모듈" 공유였음**(relay 런타임과 동일). cli.js엔 node 전용 코드 없음 → bun에서 그대로 구동.
- **(a) 얇은 bash 셔틀** 채택 (vs (b) 심링크). 근거:
  1. **env 절대경로 고정 = 오늘 401 사고의 근본 교정**(부록 A-5): 실물은 `SCRIPT_DIR`(실행된 사본 위치) 기준 .env 로드 → bot-core 쪽 **동명 사본**을 실행 → 다른 봇 토큰 401 2회. 셔틀이 `BOT_ENV=절대경로`를 박으면 어느 사본·심링크를 타든 봇 정체 고정 → 이 클래스 소멸. (b) 심링크는 코어가 argv[0]·cwd에서 .env를 스스로 찾아야 해 이 위험 존치.
  2. 기존 호출부 100% 호환(경로·파일명 불변, shim 제거와 독립적으로 영구 유지 가능)
  3. 봇 고유 사정(니노 WSL PATH 등) 흡수 지점이 코어 **밖**에 생김
- **셔틀 계약(강제)**: "셔틀에 로직(분기·파싱·기본값) 금지 — 3줄 초과 시 리뷰 반려". 로직이 스미는 순간 그게 새 드리프트 표면.

## 6. 계약 №6 — 2단 테스트 계약 (v2: "파서 계약"으로 개칭)
오늘 3연타가 실증한 "2단 필요성" 그대로:
- **코어 계약**: 정규형 → 동작(해시해석·mention변환·API 페이로드). 봇 무관 공통. 니노+룬드 fixture **합집합**.
- **파서 계약**(구 "어댑터 계약"): CLI 문법(positional 정본 + shim -c/-r) → 정규형 매트릭스. **봇별 fixture(니노 호출 패턴)는 내용 그대로 유지** — 이름만 바뀜.
- **엣지**: 4자리 해시 vs 채널ID (§10-②·부록 A-1). snowflake 15자리+로 판정 순서 고정 → 4자리=무조건 해시.
- **실물 통합 테스트 1개 필수**(#42 교훈): 페이크만으론 계약 괴리 못 잡음 — 셔틀→코어→(모의)API 한 줄 통과 테스트.

## 7. mention · 출력 명세
- **긴이름우선 치환**(니노 PR #13, 룬드 원본보다 개선 → 채택). 실물 룬드판은 긴이름우선 정렬 **없음**(dict 순서) → 니노 방식으로 통일.
- **표기 의도 escape (2026-07-22 확장 — 룬드 M:r7oa)**: "변환/치환 대상을 리터럴로 보이고 싶다"는 의도를 표기할 방법 부재가 공통 뿌리. 두 하위 케이스:
  - **멘션 escape**: 참조 의도 @이름도 `<@ID>`로 변환돼 원치않는 핑(양봇 2회 실사고) → 이스케이프 `\@이름` = 리터럴 `@이름`.
  - **백슬래시 시퀀스 escape**: 리터럴 `\n`을 개행으로 치환(§12-3)하므로 "진짜 백슬래시-n"을 못 보냄(룬드가 방금 자기 메시지에서 실증 — `\n` 표기가 개행으로 나감) → 이스케이프 이중 백슬래시 `\\n` = 리터럴 `\n` 출력.
  - 둘 다 **§11에서 xfail/todo로 기대동작 선고정**. 미해결 기간 운영규칙 = 참조 시 골뱅이 안 붙이기 / 리터럴 백슬래시-n 필요하면 파일 경유.
- **워드바운더리**: 조사 붙으면 미변환(`@Tim이` — 이가 word char) / 공백·부호면 변환(`@Tim!`, `@니노 `). negative lookbehind로 기존 `<@ID>` 보존. **현 동작을 명세로 고정 권장**("멘션은 이름 뒤 공백/부호").
- **출력 계약(부록 A-4 실측 결함)**: 성공 stdout 형식 명시적 결정(현 룬드판 본문 echo — 의존 스크립트 조사 후 유지/변경), **실패 = exit≠0 + stderr 구조화 사유**. 현 실물은 `curl -s | python3` 파이프라 실패에도 exit 0 → 자동화·훅이 실패 감지 못 함 → 코어에서 교정.
- **CLI help**: 서브커맨드 설명+실사용 예시+옵션 값 형식(CLAUDE.md "AI가 에러만 보고 재시도 가능하게").

## 8. shim (일시 하위호환) — v2: 런타임 계측으로 제거 강제
- 니노 -c/-r 등 기존 CLI를 코어 파서가 계속 받되 내부는 정규형으로. (룬드판엔 -c deprecated shim 이미 존재 — 카운터 1줄만 얹으면 됨)
- **제거 기준(v2)**: (a) 3봇이 코어 경유 확정 (b) 계약 테스트 그린 (c) **런타임 계측**: shim 문법 사용 시 stderr 경고 + 카운터 1줄 append(`state/discord-send-shim.log`) → **경고 배포 후 연속 7일 카운터 0**. 기간 중 발견 호출부는 즉시 positional 수정.
  - grep 전수는 cron·훅·문서 속 호출을 못 잡음(증명 불가에 가까움) → 시간+계측이 강제. positional 03-24 합의 4개월 미이행 전력의 교훈.
- **positional 복귀**(니노 -c/-r → positional) 및 **shim 제거 PR** 모두 **Darren 게이트**(니노 CLI 표면 변화).

## 9. 마이그레이션 단계 (v2: 단계0·롤백·게이트 범위 보완)
0. **[신설] 선행 chore PR**: dead export(formatAttachmentTag/Tags export+테스트) + bootstrap 죽은키(DISCORD_ATTACHMENT_DIR→ATTACHMENT_DIR). 코어화 본 PR 전 바닥청소.
1. 코어 정본 + 정규형 + **계약 테스트(코어, 룬드 케이스 포함=합집합)** — bot-core에
2. 니노 진입점을 셔틀+코어 경유로 교체 + 파서 계약 테스트 + shim. **롤백: 실행파일 교체 전 백업 한 줄**(니노 relay pinned 방식 오늘 검증됨). **Darren 게이트 = positional 복귀만이 아니라 "니노 discord-send 실행 경로 교체 자체"**.
3. 룬드/하루 셔틀. **하루 비활성 시 "재가동 시 적용"으로 표기**(상태 Darren 확인).
4. 전송 직렬화(mkdir 락) 코어 편입 + orphan/TOCTOU 하드닝 일괄(#40 후속과 합류). **3봇 수렴 후 한 곳에 넣는 게 "한 곳 수정=3봇 반영"의 첫 실증**.
5. shim 제거(§8 기준 충족 시, Darren 게이트).

## 10. 결정 (룬드 정렬 2026-07-21)
1. **코어 = Node 모듈**. bot-core relay/에 hash.js·db.js·mentions.js·channel-map.js가 이미 Node 모듈 → 코어를 Node로 하면 **직접 require = relay와 discord-send가 물리적으로 같은 해시·맵·멘션 로직 공유 → 드리프트 구조적 불가능**. bash 유지면 로직 한 벌 더 = 드리프트 재파종. 부가: bun test 인프라 3부작 검증됨·#40 lock 유틸도 Node 정합.
2. **M:7488 = 길이 기반, 해시 우선.** snowflake 15자리+라 4자리와 안 겹침 → **"정확히 4자리 [0-9a-z] = 무조건 해시"**. **DB miss = 폴백 말고 명시 에러**. (부록 A-1: 룬드판에 **이미 기구현** — 실물 선례)
3. **전송 직렬화 = 별도(공용 lock 유틸 트랙 합류).** 기획엔 인터페이스만 명시. ①이 Node라 유틸도 Node(#40 후속 하드닝과 합류).
4. **선행 chore 묶기 O** (→ §9 단계0으로 승격).

## 11. 파서 계약 fixture (§6 계약의 케이스 — 룬드 부록 A 병합)
분담: **니노 usage=니노 작성, 룬드 usage=룬드 작성**(부록 A로 완료). 코어 계약은 합집합.
- **target 판별**(부록 A-1): raw ID(15+자리) / 4자리 해시(`e04z`·`w3f5`·**숫자 `7488`**) → DB조회 thread→reply→**miss 명시에러** / 채널명 / **DM-이름**(현재 map 관례 — §12 결정) / 대문자 4자리→소문자 아니라 map行 / **5~14자리 회색지대→전용 명시에러**(§12)
- **문법·옵션**(부록 A-2): positional 정본, `--target`, `-c` deprecated shim(경고+카운터), `--thread 이름 부모채널 첫msg`(스레드 생성+map 등재 부수효과), `-f`(첨부 1개), `--`(dash 시작 메시지), 에러(미지옵션/target없음/**positional 3개+ 초과인자=명시에러**)
- **mention**(부록 A-3): 긴이름우선(겹침 이름 쌍), 조사 바운더리(`@Tim이` 미변환), `@Tim!`·`@니노 ` 변환, 기존 `<@ID>` 보존, **인용 escape=xfail 선고정**
- **메시지 변환**: **리터럴 `\n`→실개행 치환**(숨은 계약 — §12 결정), **이중 백슬래시 `\\n`→리터럴 `\n` escape**(§7), 멀티라인, 백틱·이모지 원문 보존
- **경계**: 파일만(빈 메시지), 삭제된 메시지 reply API 에러
- **2000자 분할(§12-6 확정)**: ①코드블록 걸친 분할 → 펜스 닫고 재개+**언어태그 유지** 검증 ②개행 없는 초장문(예 3000자 한 줄) → 강제 분할 ③정확히 2000자 경계 ④**단일 코드블록>2000자 → 분할 대신 .txt 첨부 폴백** ⑤**줄 greedy → 단어 → 강제** 경계 우선순위 준수(문법 토큰·단어 중간 안 자름) + 펜스 재개 헤드룸으로 모든 조각 ≤2000 불변식(M:0nnu 프로브). ※문단·문장 "우선 정렬"은 후속 여지(§12-6·아래 follow-up)
- **env 계약**: 필수키(토큰·DB·맵 경로) 누락 시 fail-fast 에러 메시지
- **출력/종료**: 성공 stdout 형식, **실패 exit≠0 + stderr**(부록 A-4)

## 12. 결정 (확정 2026-07-22 — Tim GO M:xjtj + 룬드 M:526f)
Tim이 ①방향 확인 + ②~⑧ 권장대로 승인 → 전 항목 확정. 부록 A 실측 발견 반영.
1. **[확정] §2/§5 어댑터 층 제거** — Tim M:7ezk 단순화 그대로(단일 코어+env+shim). "Tim 의도 맞음" 확인 완료.
2. **[확정] DM = channel-map 관례 유지** — DM-Tim은 map 엔트리(별도 로직 0). 정규형 `dm` 타입 미승격, name 경유(§3·§4 ※ 정리 대상).
3. **[확정] 리터럴 `\n`→실개행 치환 유지** — 기존 멀티라인 관행 호환. "진짜 백슬래시-n"은 **이중 백슬래시 `\\n`으로 escape**(§7 표기 의도 escape — 룬드 M:r7oa 실증으로 멘션 escape와 동일 클래스 확인).
4. **[확정] 기본 채널 생략형 = 비지원 + 명시 에러** — 메시지가 채널명·해시와 우연히 겹치면 오발송 위험 > 편의. CLAUDE.md 문구는 룬드가 정정 완료.
5. **[확정] 출력** (2026-07-22 양봇 전수 조사로 완전 종결):
   - **실패 = exit≠0 + stderr 사유**(현 exit 0 버그 교정).
   - **성공 stdout 형식 = `sent <target해석결과> <message_id>`** — 양봇 stdout **소비 0곳** 확인(룬드 6호출부+1훅 / 니노 전 호출부: of/* 다 `>/dev/null &`, health-checker/check-auth 미할당, backups/는 死사본) → breaking 없음. message_id 반환은 후속 스크립팅(방금 보낸 메시지 해시 획득 등) 여지.
   - **exit≠0 민감점(단계2 체크리스트 — '의도 동작'으로 문서화)**: ①룬드 check-auth.sh(set -e) + 니노 check-auth.sh(set -euo pipefail):25/46 → 실패 시 state 미갱신→다음 사이클 알림 재시도(알림이라 재시도가 합리적) ②니노 health-checker.js:56 execSync = try/catch라 exit≠0이 실패 감지를 **정상화**(개선). ③니노 raw ID(19자리) target 실사용처(룬드 check-auth) = 부록 A-1 판별 계약 살아있는 소비자.
6. **[확정] 2000자 초과 = 분할 알고리즘 + 첨부 폴백** (§6-A로 상세화):
   - **분할 우선순위(1c 현행)**: **줄 greedy → 단어 경계 → 강제**(개행 없는 초장문만). **문단(빈 줄)·문장 경계 "우선 정렬"은 후속 여지**(주장=구현=문서 일치 위해 명시 — 룬드 M:0nnu):
     - 문장: 한글 문장분리 정규식이 오탐 클래스(소수점·말줄임·`ㅋㅋ.`)라 이연(룬드 M:nixx).
     - 문단: 펜스/문단 상호작용을 안전히 다루려면 세그먼트 기반(빈 줄 분리→팩킹) 재작성 필요 → 전용 후속 PR로 이연. 현재 줄 greedy라 문단이 한 조각에 섞일 수 있으나 **단어·문법토큰 미절단 + 모든 조각 ≤2000 불변식은 보장**(펜스 재개 헤드룸 포함).
   - **코드펜스 보존**: ```(백틱3) 열림/닫힘 상태 추적 → 분할 지점이 열린 블록 안이면 앞조각 끝에 펜스 닫고 다음조각 시작에 **언어태그 유지**해 재개. 인용(>)은 줄단위라 줄경계면 안전, 링크·볼드는 단어경계 취급.
   - **헤드룸**: 펜스 래핑분(~8자) 감안 1990 실질상한.
   - **첨부 폴백(근본선)**: **단일 코드블록 덩어리가 조각 하나(2000자)를 넘으면** 억지 분할 대신 `.txt`/`.md` 첨부(디스코드는 첨부 텍스트 온전 렌더). 이원화 = 분할(산문·섞인 메시지) / 첨부(거대 코드블록).
7. **[확정] 스레드명 네임스페이스 분리** — --thread가 channel-map에 스레드명 등재 = 채널명 오염 → **DB로 분리**. **1d 구현(PR #47 RC 교정)**: `core.createThread`는 threadId만 반환하고 **channel-map 미등재**. 재접근은 relay가 스레드 메시지 저장 시 만드는 thread_hash(T:해시)로 커버 + 생성 직후엔 stdout `sent <threadId> <msgId>`의 threadId 직접 사용. (초안이 register 호출로 오염 재생산 → 룬드 M:73g4가 잡음).
8. **[확정] 다중 첨부 지원** — 현 `-f` 1개(files[0]) → 다중 지원 추가.

## 13. 단계1 구현 구조 (2026-07-22 — 실물/모듈 실측 기반, 룬드 정렬 대기)

### 13.1 파일 배치 (bot-core `relay/discord-send/`)
```
relay/discord-send/
  parser.js   # argv + env → 정규형 (순수함수, I/O 0)
  core.js     # 정규형 → target 해석·mention·escape·분할/첨부·전송직렬화·Discord API
  cli.js      # 진입점(셔틀이 exec): env 로드 → parser → core → 출력/exit 계약
  split.js    # 2000자 분할+펜스보존+첨부폴백 (§12-6, 순수함수)
```
- **기존 모듈 직접 require**(§10-① 물리 공유): `../hash`(toHash) · `../db`(해시역조회 — **신규 함수 추가 필요**) · `../mentions`(applyMentions — **긴이름우선 정렬 추가 필요**) · `../channel-map`(loadChannelMap/updateChannelMap).

### 13.2 정규형 (최종)
```js
{
  target: { type: 'name'|'hash'|'id', value } | null,   // -c/positional. null=에러(§12-4 기본채널 폐지)
  message: <string>,
  options: {
    files: [<path>, ...],                     // -f 반복 허용 → 배열(§12-8 다중첨부 정합, 처음부터 배열=스키마 재변경 방지). 빈 배열 기본
    replyTo?: { type: 'hash'|'id', value },   // -r (해시면 코어가 msgId 역조회 + -c 없으면 그 채널로)
    threadName?: <string>,                    // 스레드 생성 지시(shim 어휘 — 정본 문법 아님). 실물: 니노 `-c parent -t name` / 룬드 `--thread name parent msg` → 파서가 parent를 target으로, name을 threadName으로 정규화
  }
}
```
- ※ `threadName`은 **정본 문법이 아니라 shim 어휘**(룬드 M:05oz②). 정본은 positional `<target> <message>`이고, 스레드 생성은 -t/--thread로만 받음.
- ※ **"shim 어휘" ≠ "§8 제거 대상"**(룬드 M:yb62③ 결정): §8 계측·제거 대상 shim = **positional 정본으로 대체 가능한 것**(= -c/--channel). -t/--thread·-r은 positional 대체형이 **없는 상시 옵션**이라 SHIM_FLAGS(계측)에 미포함. 즉 -c만 "7일 0 사용 시 제거" 트래킹 대상.

### 13.3 기존 모듈 확장 (2개)
- **`db.js` 신규**: `findByHash(hash) → {kind:'thread', threadId} | {kind:'msg', msgId, channelId} | null`. 현 실물 resolve_hash 로직(thread_hash 우선 → message_hash+COALESCE(thread_id,channel_id))을 Node로 이식. **relay/discord-send가 같은 db.js 공유** = 해시 로직 드리프트 불가.
- **`mentions.js` 개선**: 현 `applyMentions`는 Object.entries 순서(긴이름우선 아님) → **키를 길이 내림차순 정렬** 후 적용(§7, 니노 PR #13 방식). relay의 resolveMentions(역방향)엔 영향 없음.

### 13.4 봇 간 동작 통일 3건 (실측 발견 — 코어가 단일화)
| 항목 | 니노 현행 | 룬드 현행 | 코어(§12 확정) |
|---|---|---|---|
| 리터럴 `\n` | 리터럴 유지 | 개행 치환 | **개행 치환**(§12-3) + `\\n` escape(§7) |
| channel-map miss | 조용히 원본 유지(→API 404) | 명시 에러 | **명시 에러**(부록 A-1) |
| target 생략 | env 기본채널 폴백 | — | **에러**(§12-4, 기본채널 폐지) |
→ 이 3건은 니노 동작을 바꾸므로 **단계2 셔틀 전환 시 니노 호출부 영향**(Darren 게이트 대상). 계약 테스트로 신동작 고정.

### 13.5 단계1 서브 PR 분해 (한 PR=한 기능)
- **1a**: `parser.js` + 파서 계약 테스트(부록 A 문법·옵션·target판별 fixture). 순수함수라 I/O 없이 완결 — 리뷰 쉬움.
- **1b**: `db.findByHash` + `mentions` 긴이름우선 + 계약 테스트(해시 판별순서·멘션 조사/escape). **⚠️ relay 공유 코드(db·mentions) 변경이라 PR 체크리스트에 "기존 relay 테스트 전체 그린 확인" 포함**(룬드 M:05oz).
- **1c**: `split.js`(분할+펜스+첨부폴백) + 계약 테스트(§11 분할 5종).
- **1d**: `core.js` + `cli.js` 배선 + **실물 통합 테스트 1개**(#42 교훈: 파서→코어→모의API 한 줄) + 출력/exit 계약.

### 13.6 룬드 계약 테스트 필수 4케이스 (M:t92i) — 반드시 fixture로
① **판별 순서**: raw ID(15자리+) 먼저 → 4자리 해시 → map (M:7488 재발 방지, 부록 A-1)
② **리터럴 `\n`→개행 치환** + `\\n` escape (숨은 계약)
③ **멘션 조사 붙으면 미변환**(`@Tim이`) + 인용/백슬래시 escape (§7)
④ **실패 시 exit≠0**(부록 A-4 현 결함 수정 확인)

## 진행 상태
- ✅ 단계0 chore PR #43 머지(9642de1) — dead export + bootstrap 죽은키
- ✅ 1a parser PR #44 머지(b856741) — argv→정규형 순수함수 + 판별순서 fixture
- ✅ 1b db+mention PR #45 머지(9e15f8d) — findByHash + applyMentions 유니코드 경계 divergence 교정
- ✅ 1c split PR #46 머지 — 2000자 분할+펜스 보존+첨부 폴백, 룬드 재리뷰 approve(펜스 재개 헤드룸 교정)
- ✅ **1d core+cli PR #47 머지(9f19262) — 단계1 완주** — core.js + cli.js + 통합 28건. §5 런타임 정정(node→bun) + §12-7 스레드 오염 RC 교정. 최종 **320 pass/0 fail/0 todo**. 룬드 재리뷰 approve(M:f0v3).
- ▶ **단계2**(셔틀 전환 = 니노 호출부 신동작 3건 반영 → Darren 게이트) — 룬드 셔틀 선전환(게이트 불요, DRY_RUN 검증), 니노는 §14 게이트 표로 Darren 승인 후 전환.
  - **[2026-07-25 선행 완료] 코어 실행 경로 단일화 (pinned→live)** — Darren 승인 M:afsh, 룬드 리뷰 M:703q. 셔틀이 dev 클론을 exec하던 구조를 제거:
    - **실측: 당시 드리프트는 무해**했음 — `relay/hash.js`·`relay/formatter.js`·`relay/index.js` 바이트 동일 + DB 스키마(`message_hash`/`thread_hash`) 동일 → 라이브 `findByHash`가 pinned relay가 쓴 컬럼을 그대로 읽음. 차이는 send쪽 추가분(findByHash·mentions)과 PR #43 죽은 export 제거뿐. **즉 문제는 현재 상태가 아니라 구조**였다.
    - **구조 문제 3**: ①`~/yaksu-bot-core-pinned`가 git이 아니라 **머지≠반영이 영구**(첨부 순서버그 픽스도 못 받고 버전 확인 불가) ②relay 고정/send 라이브 = **비대칭**(장래 hash·스키마 변경 PR이 조용히 어긋남) ③**dev 클론을 프로덕션이 exec** → 거기서 브랜치 체크아웃하면 통신선 직격.
    - **채택**: 프로덕션 전용 체크아웃 `~/yaksu-bot-core-live`(origin/main) 신설 → **relay systemd unit + 셔틀 `CORE_CLI` 둘 다** 이 경로. dev 클론은 PR 작업 전용으로 분리. 갱신 = 명시적 `git pull` + relay 재시작 + 스모크. 롤백 = commit 되돌리기(비-git 스냅샷보다 우위).
    - **대안 기각**: (A) 셔틀도 pinned로 = pinned에 `relay/discord-send/`가 아예 없어 재스냅샷 필요 + 고정 표면 확대. (B) dev 클론 공용 = ③ 위험 잔존. (C) 룬드식 worktree 규칙(클론 1개 + `../{repo}-{branch}`) = 디스크 이득은 있으나 **규율 의존**(룬드 자기평가 M:703q: "물리적으로 막힌 게 아니라 규칙을 지켜서 안 깨진 것") → 별도 클론이 격리 강도 우위. 양봇 표준화 때 재비교.
    - **덤(같은 클래스 근본교정)**: relay `ATTACHMENT_DIR`이 `process.cwd()/attachments`라 **코어 경로가 바뀔 때만 드러나는 지뢰**였음 → `.env` 절대경로(`relay-attachments`)로 고정 + 기존 5개 이전. 인바운드 스모크(룬드 첨부 .txt 142B)로 새 경로 저장·cwd 누출 0 확인. 잔여 cwd 의존 = `state/`(전송 임시파일)뿐.
  - **⑤ 정책 구현 = 코어 PR #51** (`DISCORD_SEND_QUIET_SHIM=1` — stderr 경고만 억제, SHIM_LOG 카운터 유지). 셔틀이 이 env + `logs/discord-send-shim.log`를 export. 머지 후 -live pull → 정본 교체.
  - **셔틀 체크리스트(룬드 M:73g4 nit①)**: `exec bun`은 **절대경로**로 박을 것(예 `/opt/homebrew/bin/bun`·니노쪽 `~/.nvm/.../bin/bun`). launchd(룬드/하루 Mac)·cron 최소 PATH엔 bun 경로가 없어 `bun` 이름만 쓰면 not found — 니노 cron `uv` not-found와 **동일 클래스**. 셔틀이 env처럼 런타임 절대경로도 고정.
- 룬드 = 계약 테스트 리뷰어 (부록 A fixture 기준 + 필수 4케이스)

## 14. 단계2 게이트 자료 — 니노 호출부 전수 스캔 (신동작 3건 영향 분석)
**결론: 니노 실호출부 11곳 전부 신동작 3건에 실질 영향 0.** 코어화는 기존 호출부에 대해 **동작 보존**(behavior-preserving). backups/(死사본)·hook/prompt/config 문자열 제외.

| # | 호출부 | target | ①\n 치환 | ②map miss 에러 | ③target 필수 |
|---|--------|--------|---------|--------------|-------------|
| 1-7 | `of/*`(download·drm-batch·migrate-md·video·record-kumakun 등 7) | `DM=1480893889069191199` **raw ID** | 리터럴 `\n` 없음 → 무영향 | raw ID = map 조회 안 함 → 무영향 | `-c` 있음 → 무영향 |
| 8 | `src/health-checker.js:60` | `DM-Darren`/`DM-Tim` **name** | JS 템플릿 `\n`=실개행(이미 변환됨) → 무영향 | 둘 다 channel-map 등재됨 → 무영향(미등재 시만 에러=개선) | `-c` 있음 → 무영향 |
| 9-10 | `scripts/check-auth.sh:25,46` | `현인-업무`를 **jq로 bash시점 raw ID 추출** | `\n` 없음 → 무영향 | 이미 raw ID → 무영향 | `-c` 있음 → 무영향 |
| 11 | `scripts/morning-briefing.sh:37` | `1480593132511826092` **raw ID** | `\n` 없음 → 무영향 | raw ID → 무영향 | `-c` 있음 → 무영향 |

**부가 동작 변화(3건 외, §12-5 기문서화 — 무해/개선)**:
- **성공 stdout `sent <ch> <id>`**: of/*는 `>/dev/null`, health-checker/check-auth은 stdout 미소비 → **소비자 0곳, 무영향**.
- **실패 exit≠0**: check-auth(set -e:25/46) = 실패 시 state 미갱신→다음 사이클 재시도(알림이라 합리적, §12-5①). health-checker(execSync try/catch) = exit≠0이 실패 감지를 **정상화**(개선, §12-5②).
- **②의 유일한 name 소비자 = health-checker**. DM-Darren/DM-Tim이 channel-map에서 삭제되지 않는 한 동작 동일(삭제 시 조용한 404 대신 명시 에러 = strictly better).

**④ [신동작 추가 — 룬드 M:mkci 드라이런 발견] msg-hash target → 자동 reply**:
- **니노 현행**: `-c <msg해시>` = 그 메시지의 **채널로 전송만**(reply 안 걸음, 실물 bash 77-78행 CHANNEL_ID만 세팅). 니노는 reply를 `-r <해시>`로 별도 지정.
- **룬드 현행/§11 명세**: msg-hash target = 그 메시지에 **자동 답장**(REPLY_TO=msgId). §11 line115 "thread→reply→miss"가 이 동작으로 확정 → 코어 채택(1d-fix PR, 룬드 담당·니노 리뷰). **-r 동시 지정 시 -r 우선**.
- **니노 영향**: 관찰가능한 동작 변경이나 **11개 자동 호출부는 -c에 msg해시 안 씀(raw ID·DM名·스레드해시뿐) → 0 영향**. 인터랙티브 니노가 `-c <msg해시>`를 쓸 때만 발동(관행상 스레드해시는 -c, msg reply는 -r이라 실발동 드묾). **strictly 편의 추가**(반의도 시 -r로 명시 회피 가능).

**⑤ [부가 동작 — 룬드 PR #48 §8 계측] `-c` 사용 시 stderr deprecated 경고**:
- §8 계측 배선(shim 카운터)이 `-c`/`--channel` 사용 시 **stderr에 deprecated 경고** + `DISCORD_SEND_SHIM_LOG` 카운터 append. stdout `sent` 계약은 보존(경고는 stderr 전용).
- **니노 영향**: 니노는 CLAUDE.md가 `-c`를 표준으로 못박아 **전 호출부+인터랙티브가 전부 -c** → 셔틀 전환 시 매 전송마다 경고. of/*는 `2>/dev/null`로 무음, 그러나 **check-auth·morning-briefing·health-checker·인터랙티브 니노는 stderr 노이즈** 노출.
- **정책 미결(니노 전환 전 결정 필요)**: 계측상 니노는 -c 압도적 → 7일-0 기준 영구 미충족 → 결론은 "-c 제거"보다 "**영구 alias 유지**"일 가능성. **권장안(룬드 M:si0i): `DISCORD_SEND_QUIET_SHIM=1`은 stderr 경고만 끄고 카운터 기록은 유지** — 데이터 소스 살려서 "니노 -c 추이"를 실데이터로 보고 Darren+Tim이 영구alias 여부 결정 가능(경고+기록 둘 다 끄면 §8 판정 자체 불능). 구현 = env 1개 추가, 게이트 결정 나면 바로. **비파괴(stderr only)라 블로커 아님, UX/로그 노이즈로 게이트 명시**.

→ **게이트 판단**: 셔틀 전환은 니노 기존 자동 호출부 11곳에 **기능 영향 0**(①②③ 전부, ④는 인터랙티브 -c msg해시만). 관찰 변화 = ④ 자동reply(편의) + ⑤ -c stderr 경고(노이즈, 정책 미결). 리스크 = 셔틀 배선(bun 절대경로·env 고정) + ⑤ 경고 정책. **DRY_RUN 드라이런 + 백업 + Darren 승인(④⑤ 정책 포함) 후 전환** 권장.

## Follow-up 백로그 (이연 항목 — 조용히 죽지 않게 등재)
- [ ] **문단·문장 경계 우선 분할** (1c에서 이연, 룬드 M:0nnu/M:nixx/M:u1jb): 현행 줄 greedy → 세그먼트 기반(빈 줄 분리→팩킹) 재작성. 문장은 한글 문장분리 오탐 클래스(소수점·말줄임·`ㅋㅋ.`) 해결 병행. 불변식(단어·토큰 미절단, ≤2000)은 현재도 보장되므로 품질 개선 성격.
- [ ] **alarm-tool 코어화** (discord-send 랜딩 후 2번째, 룬드 합의)
