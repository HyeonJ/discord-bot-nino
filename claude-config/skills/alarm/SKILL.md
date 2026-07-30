---
name: alarm
description: 알람/리마인더 설정, 조회, 취소 — alarm-tool CLI + TTS 지원
---

알람과 리마인더를 설정하고 관리하는 스킬.

## 🔴 먼저 — `--context` 는 **필수**다

`set` 은 `--context <파일경로>` 없이는 **실패한다** (`error: the following arguments are required: --context`).
그 파일은 **미리 만들어져 있어야** 한다(`set` 이 존재 여부를 검증함).

```bash
# ① 컨텍스트 파일부터 만든다  (관례 경로: memory/alarms/)
#    배경 + 액션 체크리스트를 적는다 — 발동 시 니노가 이 파일을 읽고 맥락을 잡는다
vi ~/discord-bot-nino/memory/alarms/darren-study-0805.md

# ② 그 다음 알람 등록
/home/bpx27/discord-bot-nino/alarm-tool set "공부 시작" --at "20:00" \
  --context memory/alarms/darren-study-0805.md
```

- **관례 경로**: `~/discord-bot-nino/memory/alarms/` (실사용 25개 · 살아있는 알람 전부 여기)
  ⚠️ `memory/alarm-contexts/` 는 1개짜리 잔재다. 새로 만들면 `alarms/` 에 넣을 것.
- 발동 시 tmux 니노 세션에 `[Alarm][HH:MM] 메시지 @파일경로` 로 주입 → 니노가 Read 로 읽는다.
  즉 **메시지는 짧게, 자세한 건 컨텍스트 파일에** 적는 구조다.

## 🔴 그리고 — **짧은 메시지는 조용히 거절된다 (`rc=0`)**

메시지가 짧거나 뭉뚱그려져 있으면 도구가 **등록을 거부하는데 종료코드는 0** 이다.
힌트만 출력하고 알람은 안 생긴다 — `rc` 로는 성공과 구별이 안 된다.

```bash
$ alarm-tool set "문서검증" --at "+90m" --context <파일>
💡 알람 메시지가 짧습니다. …구체적으로 써주세요.
$ echo $?
0            ← 🔴 성공처럼 보이지만 등록 안 됨
```

⇒ **등록 확인은 rc 가 아니라 개수로 한다:**
```bash
before=$(alarm-tool list | grep -c '"id"')
alarm-tool set "…" --at "…" --context "…"
after=$(alarm-tool list | grep -c '"id"')
[ "$after" -gt "$before" ] || echo "🔴 등록 안 됨"
```
⚠️ *"출력에 error 가 없다"* 로 판정하지 말 것 — 이 거절에는 `error` 라는 낱말이 안 나온다.

**메시지는 나중에 봐도 바로 행동할 수 있게** 쓴다 (도구가 요구하는 바이기도 하다):
`❌ '약'` → `✅ '혈압약 1알 식후 복용'` / `❌ '회의'` → `✅ '팀 주간 미팅 참석 (회의실 B)'`

## 사용법

### 알람 설정
```bash
# 특정 시각
/home/bpx27/discord-bot-nino/alarm-tool set "메시지" --at "HH:MM" --context <파일>
/home/bpx27/discord-bot-nino/alarm-tool set "메시지" --at "YYYY-MM-DD HH:MM" --context <파일>

# 상대 시간
/home/bpx27/discord-bot-nino/alarm-tool set "메시지" --at "+30m" --context <파일>
/home/bpx27/discord-bot-nino/alarm-tool set "메시지" --at "+2h" --context <파일>

# 반복
/home/bpx27/discord-bot-nino/alarm-tool set "메시지" --at "09:00" --repeat daily --context <파일>
/home/bpx27/discord-bot-nino/alarm-tool set "메시지" --at "09:00" --repeat weekdays --context <파일>
/home/bpx27/discord-bot-nino/alarm-tool set "메시지" --at "09:00" --repeat 30m --until "2026-03-20 10:00" --context <파일>
```

### 조회/취소
```bash
/home/bpx27/discord-bot-nino/alarm-tool list
/home/bpx27/discord-bot-nino/alarm-tool cancel --id 아이디
```

### 확실치 않으면 `--help`
```bash
/home/bpx27/discord-bot-nino/alarm-tool set --help
```
🔴 **이 문서보다 `--help` 가 정본이다.** 이 문서는 2026-07-21~29 동안 `--context` 필수를 안 적어둬서
같은 오류를 두 번 냈다. 문서와 도구가 갈리면 도구가 맞다.

## 시간 형식
- `HH:MM` — 오늘 해당 시각 (지났으면 내일)
- `+30m`, `+2h`, `+1h30m` — 상대 시간
- `YYYY-MM-DD HH:MM` — 절대 시간
- 모든 시간은 KST 기준

## 반복 옵션
- `daily` — 매일
- `weekly` — 매주
- `weekdays` — 평일만
- `30m`, `2h` 등 — 시간 간격

## TTS 연동
알람에 TTS가 필요한 경우 (예: 사람 깨우기), Discord 메시지와 함께 TTS도 실행:
```bash
# Discord 메시지 전송
/home/bpx27/discord-bot-nino/src/discord-send 채널명 "알람 메시지"

# TTS (Windows 집컴 스피커로 출력)
/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -Command "Add-Type -AssemblyName System.Speech; (New-Object System.Speech.Synthesis.SpeechSynthesizer).Speak('알람 메시지')"
```

## 사람 깨우기 패턴
Tim/Darren을 깨울 때는 Discord 멘션 + TTS + 반복 알람 조합:
1. `alarm-tool set` 으로 반복 알람 등록 (예: 5분 간격)
2. 알람 발동 시 Discord 채널에 멘션 메시지 전송
3. TTS로 스피커에 음성 출력
4. 응답 올 때까지 반복

## ⚠️ 점검(디버깅) 시 주의
- **수동 `fire` 금지** — 발화는 cron(`* * * * * alarm-tool fire`)이 매분 호출한다.
  손으로 부르면 실제 알람이 소비되거나 중복 발화된다.
- 등록 확인은 `list` 로만 한다.

$ARGUMENTS가 있으면 알람 메시지로 사용할 것.
