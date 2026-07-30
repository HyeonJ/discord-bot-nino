---
name: pebble-ytm
description: Pebble V3 스피커로 YouTube Music 재생 — Windows 기본 출력장치 전환, 볼륨 20 설정, YTM 링크 재생
---

Darren이 자연어로 "Pebble로 음악 틀어줘", "유튜브 뮤직 재생해줘", "몇 시에 음악 켜줘", "스피커 볼륨 20으로 맞추고 틀어줘"처럼 요청할 때 사용하는 스킬.

## 동작

1. Windows 기본 출력장치를 `Pebble V3`로 전환
2. 시스템 볼륨을 기본 `20`으로 설정
3. YouTube Music 링크가 있으면 Windows Chrome에서 열고 재생
4. 시간이 지정되면 KST 기준으로 알람/예약 실행에 연결

## 바로 재생

```bash
cd /home/bpx27/discord-bot-nino
media/pebble-ytm.sh --url "https://music.youtube.com/..."
```

링크가 아직 없고 장치/볼륨만 맞출 때:

```bash
cd /home/bpx27/discord-bot-nino
media/pebble-ytm.sh
```

## 예약 재생

시간이 포함된 요청이면 `alarm-tool`로 예약한다. 알람 메시지에는 실제 실행할 명령을 명확히 넣는다.

```bash
/home/bpx27/discord-bot-nino/alarm-tool set 'Pebble YTM 재생: cd /home/bpx27/discord-bot-nino && media/pebble-ytm.sh --url "https://music.youtube.com/..."' --at "HH:MM"
```

반복 요청이면 `--repeat daily`, `--repeat weekdays` 등을 사용한다.

## 필요 조건

- Windows에 NirSoft `SoundVolumeView.exe` 또는 `svcl.exe`가 있어야 한다.
- 도구 위치는 다음 중 하나로 둔다.
  - `/home/bpx27/discord-bot-nino/tools/SoundVolumeView.exe`
  - `/home/bpx27/discord-bot-nino/tools/svcl.exe`
  - Windows 환경변수 `NINO_SOUNDVOLUMEVIEW`
  - 실행 시 `--tool "C:\path\SoundVolumeView.exe"`
- Windows Chrome이 CDP 포트 `9222`로 실행 중이어야 한다.
- 해당 Chrome 프로필에서 YouTube Music 로그인이 되어 있어야 한다.

## Chrome CDP 실행 예시

Windows에서 Chrome을 다음처럼 실행한다.

```powershell
Start-Process "$env:ProgramFiles\Google\Chrome\Application\chrome.exe" -ArgumentList '--remote-debugging-port=9222','--user-data-dir=C:\Users\bpx27\AppData\Local\Google\Chrome\User Data'
```

이미 같은 프로필의 Chrome이 떠 있으면 원격 디버깅 포트가 붙지 않을 수 있다. 테스트 전에는 원격 디버깅용 Chrome을 따로 띄우는 편이 안정적이다.

## 규칙

- 볼륨을 따로 말하지 않으면 `20`을 사용한다.
- 스피커를 따로 말하지 않아도 Darren의 집컴 음악 재생 요청이면 `Pebble V3`를 대상으로 한다.
- YouTube Music 링크가 없으면 링크를 요청한다.
- "지금", "바로", "틀어줘"는 즉시 실행한다.
- "내일 7시", "평일 8시"처럼 시간이 있으면 KST 기준으로 예약한다.
- 실행 후 결과를 Discord로 짧게 보고한다.
