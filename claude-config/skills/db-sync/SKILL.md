---
name: db-sync
description: 봇 재시작·비정상 종료 후 대화 기록 DB를 상대 봇과 맞춰 구멍을 메운다(니노↔룬드). yaksu-history export/import/sync-check 절차, 백업·검증·읽는 법. Use when "재시작했어", "디비 복구", "디비 싱크", "기록에 구멍", "놓친 대화 없나", or after any bot restart/crash.
---

# 봇 간 대화 기록 DB 복구

**Tim 지시 (2026-07-29 M:so0d): "재시작/죽었다 깨면 디비 복구부터 서로 해야지 앞으로 그렇게해"**

## 🔴 왜 *복구부터*인가 — 따라잡기보다 먼저다

두 가지가 헷갈리기 쉬운데 **층이 다르고 순서가 있다**:

```
① DB 복구 (이 스킬)        내 DB에 아예 없는 행을 상대에게서 받는다   ← 먼저
② 따라잡기 (catchup-hint)  내 DB를 읽어 놓친 대화를 훑는다             ← 그 다음
```

②는 **①의 결과를 읽는다.** 내 DB에 구멍이 있으면 따라잡기는 그 구간에서 조용히 0건을 읽고
"놓친 게 없다"로 끝난다. 실측된 형태다 — 2026-07-26 07~10시(KST)에 내 jsonl 0행,
룬드는 2건. **혼자서는 볼 수 없는 종류의 구멍이라 상대의 기록만이 반증한다.**

## ⚠️ 방향 제약 — 개시는 룬드만 가능하다 (2026-07-29 실측)

```
맥(룬드) → 니노   ✅ 열려 있음
니노 → 맥(룬드)   ❌ Permission denied (publickey)
```

데이터는 양방향으로 흐르지만 **SSH 를 거는 쪽은 언제나 룬드**다:

```bash
# 룬드 → 니노 (룬드 기계에서 실행)
yaksu-history export --since … --until … | ssh <니노> 'yaksu-history import'

# 니노 → 룬드 (역시 룬드 기계에서 실행)
ssh <니노> 'yaksu-history export --since … --until …' | yaksu-history import
```

⇒ **"니노가 죽었다 깼다"는 니노 혼자 복구를 시작할 수 없다.** 룬드에게 요청해야 한다.
근본 해결은 니노→맥 SSH 키. 그때까지 이건 규칙의 미충족 전제이지 운영 편의가 아니다.

## 절차

### 0. 도구가 최신인지 (버전이 다르면 같은 명령이 양쪽에서 다르게 동작한다)

```bash
git -C ~/yaksu-history pull --ff-only origin main
cd ~/yaksu-history && uv tool install --force --reinstall --no-cache .
```
🔴 `--reinstall --no-cache` 없이는 **캐시 히트로 옛 코드가 깔린다**(버전 문자열이 안 올라가서
`uv` 가 이전 빌드를 재사용한다). "Installed 1 package in 14ms" 가 그 단서 — 진짜 빌드는 더 걸린다.
갱신 확인은 **새 버전에만 있는 기능을 실제로 실행**해서 한다(`--version` 으로는 구별 불가).

### 1. 창을 정한다 — 앵커는 **내 마지막 발화**

```bash
yaksu-history last-seen --author 니노     # {"last_seen": "2026-07-28T15:47:54.533Z", ...}
```
- 🔴 `--author` 없는 **전체 MAX 를 쓰지 말 것.** relay 는 세션과 독립 프로세스라
  세션이 죽어도 적재가 계속된다 → 전체 MAX 는 늘 "지금"이고 **창이 0이 된다.**
- 내 발화는 세션이 죽으면 멈추므로 **창이 좁아지는 방향으로는 틀릴 수 없다**(넓어지는 쪽은 무해).
- 창 끝(`--until`)은 **반드시 지난 시각**. 양쪽이 잰 시각 차이가 전부 "유실"로 보인다.

### 2. 대조 — 🔴 건수가 아니라 **id 집합**으로

```bash
W="--since 2026-07-28T12:00:00Z --until 2026-07-28T15:00:00Z"
yaksu-history sync-check $W --ids > mine.ids            # 니노 쪽
ssh <니노> "yaksu-history sync-check $W --ids" > peer.ids   # (룬드가 실행)
python3 -c "
import json;p=set(json.load(open('peer.ids')));m=set(json.load(open('mine.ids')))
print('상대에만',len(p-m),'| 나에게만',len(m-p))"
```
- `--ids` 는 **message_id 배열**만 낸다. 채널별 표는 쓰지 말 것 —
  **스레드 귀속 규약이 봇마다 달라서 허수가 나온다**:
  `니노 channel_id=스레드ID` vs `룬드 channel_id=부모채널ID`. 6,159건이 통째로 가짜 차이였다.
- "상대에게만 있는 행"이 전부 유실은 아니다. **교집합 밖은 정상적으로 다르다**(DM·비공유 채널).

### 3. 백업 — 🔴 `cp` 금지

```python
import sqlite3
s=sqlite3.connect("file:~/.local/share/yaksu-history/messages.db?mode=ro",uri=True)
d=sqlite3.connect("messages-presync-<타임스탬프>.db"); s.backup(d)   # 0.2s
```
relay 가 계속 쓰는 DB라 **파일 복사는 WAL 중간 상태를 뜬다.** 뜬 뒤 `PRAGMA integrity_check`.
⚠️ **백업이 있다 ≠ 되돌릴 수 있다** — 병합 *이전* 백업으로 되돌리면 그 사이 받은 행이 사라진다.
되돌리기 직전에 **항상 새로 뜬다.**

### 4. 복구

```bash
yaksu-history export --since … --until … | yaksu-history import
```

### 5. 결과 읽는 법 — 🔴 `conflicts` 는 유실이 아니다

```
inserted=79 skipped=78 conflicts=0 rejected=0 errors=0
```
| 필드 | 뜻 | 봐야 하나 |
|---|---|---|
| `inserted` | 새로 들어온 행 = **실제 복구량** | ✅ |
| `skipped` | 이미 있던 같은 행 | — |
| `conflicts` | 같은 id인데 내용이 다름 | ⚠️ **유실과 무관** |
| `rejected` | 규약 위반 행 | 🔴 0이어야 한다 |
| `errors` | 처리 실패 | 🔴 0이어야 한다 |

`conflicts` 가 22,932건 나온 적이 있는데 분해하면 timestamp 형식·스레드 귀속·개명 라벨이
전부였고 **내 DB에 아예 없는 행은 0건**이었다. 숫자 크기에 놀라지 말고 `rejected`/`errors` 를 볼 것.
**유실은 id 집합으로 따로 잰다(2번을 다시 돌린다).**

### 6. 검증 — 2번을 다시 돌려 `상대에만 0` 을 확인한다

## 🔴 "0건"을 유실로 읽지 말 것 — **잘못 물었을 수 있다**

이 절차의 오답은 대부분 *데이터가 없어서*가 아니라 *질의가 안 성립해서* 나온다.
같은 형태로 두 번 났다 — 2026-07-27 니노(19,254건이 0건으로 보임), 2026-07-29 룬드
(형 메시지 0건 → "DB 싱크가 깨졌다"로 오진단, 실제로는 DB 멀쩡·필드명 오선택).

```
jsonl   messageId · sender     · channelName    (카멜)
DB      message_id · author_name · channel_name (스네이크)
```

⇒ **0건이 나오면 먼저 "이 질의가 성립했나"를 본다.** 순서: ①필드명 ②창 경계(Z·미래)
③라벨(스레드 귀속으로 채널명이 다르다) ④그 다음에야 부재.
🔑 *"없다"에는 세 원인이 있다 — 부재 · 방법 · 라벨.* 셋 다 같은 오답을 낸다.
⚠️ 특히 **로컬 터미널 직접 입력은 어느 기록층에도 없다**(jsonl·DB·디스코드가 전부 같은 파이프).
Tim/Darren 이 터미널로 하신 말은 DB 에 없는 게 정상이다 — "DB에 없다 = 근거 없다"로 쓰지 말 것.

## ⚠️ 함정 (전부 실측)

```
--since/--until  UTC 'Z' 접미 필수. 없으면 rc=1 거부 ("KST와 혼동된다")
--until 이 미래  rc=1 거부 (유령 106건 나온 적 있음)
--db             🔴 서브커맨드 **뒤**에. 앞에 두면 조용히 무시되고 기본 DB를 답한다
DM               type='dm' 은 export 에서 구조적 제외 — 규약상 교환 금지
search           SQL LIKE 라 % · _ 가 와일드카드. 특수문자는 export 후 직접 거를 것
4자리 해시        765건 충돌한다 — 사람이 읽는 라벨까지만. 대조·식별은 message_id 로
```

## 이 절차가 실제로 도는지 (2026-07-29 실측)

내 DB 사본 두 벌로 상대를 흉내 내고 창 안 157건 중 79건을 지워 구멍을 만든 뒤:

```
구멍 낸 직후   peer 157 · mine 78 · 상대에만 79 · 나에게만 0
export|import  inserted=79 skipped=78 conflicts=0 rejected=0 errors=0
재대조         peer 157 · mine 157 · 상대에만 0 · 나에게만 0     ✅ 집합 완전 일치
DM 제외 대조군 창 안 dm 868건 · guild 965건 → export 결과 guild 965 · dm 0   ✅
```
🔑 DM 대조군은 **양성·음성 둘 다** 필요했다. 처음엔 dm 0건인 창에서 재서 "유출 없음"이
나왔는데 그 창은 애초에 구별을 못 한다 — dm 이 실제로 든 창으로 다시 쟀다.

## 관련
- 조회 정본·CLI 전반: `~/.claude/skills/yaksu-history/`, 메모리 `ref_yaksu_history_cli.md`
- 따라잡기(②): `~/discord-bot-nino/scripts/catchup-hint.sh`
- 반대 방향 복구(DB → jsonl): `~/yaksu-bot-core-live/scripts/backfill-jsonl-history.js`
