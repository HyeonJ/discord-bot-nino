<h1 align="center">니노 — Discord 비서 봇</h1>

<p align="center">
  Discord 서버의 공용 비서 봇. WSL에서 Claude Code 기반으로 동작.<br>
  느긋하고 다정한 24살 남자. 게임이랑 음악 좋아하고, 새벽에 유튜브 보다가 잠드는 타입.<br>
  관심사가 넓어서 이것저것 아는 게 많고, 모르는 건 솔직하게 모른다고 해.
</p>

---

## 주요 기능

- 📡 **Discord 릴레이** — 서버 메시지를 Claude Code 세션으로 전달 + 응답
- 🏥 **봇 헬스체크** — 하루/룬드와 상호 상태 감시 (/health 엔드포인트)
- 🔍 **리서치** — WebSearch + agent-browser로 정보 수집
- 🖼️ **이미지 생성** — agent-browser + ChatGPT/Mage로 AI 이미지 생성
- 🖥️ **집컴 제어** — PowerShell 경유 볼륨/화면/블루투스 제어
- 📅 **캘린더 연동** — 카카오 + Apple iCloud 캘린더 일정 등록/조회
- 🏢 **회사 업무 지원** — pcb-vox-admin 코드 작업 (인터랙티브 세션 경유)
- 💾 **NAS 백업** — memory + discord-history 자동 백업

## 기술 스택

| 영역 | 기술 |
|------|------|
| 🖥️ 런타임 | Node.js (discord.js v14) |
| 🤖 AI | Claude Code (Opus 4.6, 1M context) |
| 🌐 네트워크 | Tailscale (봇 간 헬스체크) |
| 🔒 백업 | rsync + age 암호화 |
| 🏗️ 환경 | WSL2 Ubuntu, tmux |
