# 니노 relay → yaksu-bot-core 전환 계획 (PR-e)

작성: 2026-07-20 (조사 에이전트 실측 기반). Darren 승인 게이트.

## ⚠️ 조사 중 드러난 프레임-변경 발견 3가지

1. **룬드에 "복제할 어댑터 파일"은 없다.** 룬드는 bot-core `relay/index.js`를 직접 구동(2026-07-18 컷오버). `dazebug/assistant`의 discord-relay.js는 전환 전 구 모놀리스(벤티지얼). → 니노가 베낄 per-bot 어댑터 파일이 없고, **bot-core 자체 + 룬드 research 플레이북 3종**이 정본. WSL 어댑터층은 니노가 처음 채워야 함.

2. **니노는 SQLite에 안 쓴다(JSONL만).** bot-core는 SQLite가 1급. → 전환은 니노에 **DB 쓰기를 신규 추가**. 또한 db.js가 `bun:sqlite` 의존 → **bun 도입 필수**(현재 node 구동).

3. **메시지 포맷 계약이 바뀐다.** bot-core formatter는 `[M:raw ID]`가 아니라 **`[M:base36해시]`·`[T:스레드명:해시]`** 방출. 니노 CLAUDE.md/MEMORY.md의 `-c 채널ID`·`-r 메시지ID`·relay 형식 `[M:ID]` 계약이 전부 깨짐 → **bot-core의 해시-aware discord-send를 함께 채택 + 니노 CLAUDE.md 갱신 필수.** 이게 blast radius 제일 큼.

## bot-core가 못 덮는 니노 고유 동작 (addon 신설 필요)
- **P14/P19 pending-response 리마인더**(3분 타임아웃→tmux 알림, 30분 리마인더) — bot-core에 없음
- **P16 health-checker(타봇 감시→DM)** — bot-core엔 health-server(자기 노출)만 있고 타봇 감시 없음
- **P13 URL 300자+ 특수 파일화**(선택)
- 나머지 P1~P18 대부분은 bot-core addon(github-autopull/presence/health-server/jsonl-history)으로 커버

## 통합 표면 요약
- 진입점: `bun ~/yaksu-bot-core/relay/index.js` (⚠️ cwd/ADDON_DIR **절대경로** 필수 — 상대경로 사고 계열)
- 필수 env: DISCORD_BOT_TOKEN, DISCORD_APP_ID(=봇ID, selfMessage 판별), TMUX_SESSION=nino, GUILD_ID, YAKSU_HISTORY_DB, **HISTORY_JSONL_DIR=memory/discord-history(미설정=JSONL 회귀4호)**, HEALTH_PORT=58090, HEALTH_BIND=0.0.0.0(127 금지=회귀3호), AUTO_PULL_REPOS, PRESENCE_STATUS_FILE, config/user-map.json 신규
- addon: `{name, onMessage?, onIdle?, init?}` export. selfMessage엔 onMessage 미호출 → 자기 메시지 봐야 하는 addon은 init에서 자체 리스너 부착

## 전환 단계 (병렬 드라이런 후 원자 전환 + 한 줄 롤백)
0. 사전 정합: 니노판 동등성 체크리스트 + DM 스모크/포맷 diff 게이트 명문화 (코드 무수정)
1. 니노 전용 addon 3종(pending-response/health-checker/url-longmsg) — bot-core에 PR (니노 가동 무영향, TDD). ⚠️ bot-core=공유repo라 Tim 조율
2. 니노 config(user-map.json)·.env·DB 초기화·bun 도입
3. **discord-send 해시-aware 교체** (⚠️ relay 전환과 원자적 동시 — 포맷 불일치 방지) + 니노 CLAUDE.md 갱신
4. DRY_RUN 병렬 드라이런 (기존 relay 가동 중, diff N건 확인)
5. **DM 스모크 게이트** 통과 필수 → 못 통과면 6 진입 차단
6. 원자 전환: start-nino.sh relay 실행줄만 교체. 롤백=한 줄 원복. Darren 승인 + 24h 감시
7. 검증 후 구 relay/auto-pull/health 제거 (1주 무회귀 후)

## DM 스모크 게이트 5종 (사람 Darren 발신, diff로 못 잡는 DM 검증)
1. 수신: relay 로그에 smoke-<ts> 등장 (없으면 Partials.Channel 누락=회귀5호)
2. tmux 주입: capture-pane에 `[DM][Darren]...smoke-<ts>`
3. JSONL: 오늘자 .jsonl 마지막줄 type:dm+content 확인 (없으면 HISTORY_JSONL_DIR 미설정=회귀4호)
4. DB: sqlite messages 테이블에 type=dm 행
5. author 이름매핑: DB/JSONL의 author가 "Darren"(본명), raw id면 USER_MAP 회귀
→ 하나라도 ✗면 exit 1

## 회귀 5건 + flock 방어 위치
- ①/⑤ DM: core buildClientOptions partials+DirectMessages (스모크 관문1)
- ② presence: addons/presence.js Playing(0) 고정 (니노 현재도 Playing이라 정합)
- ③ health 바인딩: HEALTH_BIND=0.0.0.0 (127 금지)
- ③-b author raw id: config/user-map.json 로드 (스모크 관문5)
- ③-c 숫자해시: discord-send is_hash `^[0-9a-z]{4}$` — 18자리 채널ID는 안전
- ④ JSONL: HISTORY_JSONL_DIR 정확 지정 (스모크 관문3)
- ⑥ **flock**: bot-core addons/github-autopull.js의 execFileSync git을 `flock <repo락> git ... pull`로 감싸는 PR 필요. 니노가 자기 push하는 repo(discord-bot-nino)를 autopull 대상에 넣으므로 필수

## 참조
- 니노 현행: src/{discord-relay,auto-pull,health,health-checker,discord-send}.js, scripts/start-nino.sh
- bot-core(origin/main): relay/*.js, addons/*.js, discord-send, db/schema.sql, docs/{installation,architecture}.md, adapters/wsl/README.md
- 룬드 플레이북: dazebug/assistant memory/research/{relay-equivalence-checklist,bot-core-adapter-plan,bot-core-module-spec}.md
