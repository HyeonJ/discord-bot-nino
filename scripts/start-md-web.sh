#!/usr/bin/env bash
# md-web 기동 래퍼 — systemd --user 유닛(nino-mdweb.service)이 이걸 호출한다.
#
# 왜 래퍼인가 (환경변수 원칙): 유닛 파일에 경로·환경변수를 하드코딩하지 않는다.
#   .env 가 필요해지면 여기 한 곳에서 source 하면 되고, bun 경로도 여기서만 정한다.
#
# 왜 유닛인가 (2026-07-28, Darren 승인): md-web 은 니노 Claude 세션의 **자식 프로세스**로
#   떠 있어서 세션이 죽으면 같이 죽었다 — 7/17 에 실제로 502 사고가 났고, 그 뒤로도
#   내가 세션 재시작을 하려면 md-web 이 함께 끊겼다. 부모를 systemd 로 바꾸면 끊기지 않는다.
set -uo pipefail
#
# 설치 (새 기계에서 · 2026-07-28 이 기계에 적용한 그대로):
#   ~/.config/systemd/user/nino-mdweb.service 에
#     [Unit] Description=니노 md-web (포트 58082) / After=default.target
#     [Service] Type=simple · ExecStart=<이 파일의 절대경로> · Restart=always · RestartSec=5
#               StandardOutput/StandardError=append:~/discord-bot-nino/logs/md-web.log
#     [Install] WantedBy=default.target
#   systemctl --user daemon-reload && systemctl --user enable --now nino-mdweb.service
#   ⚠️ 부팅 시 자동 기동은 `loginctl enable-linger <user>` 가 켜져 있어야 한다(이 기계는 켜짐).
#   ⚠️ 유닛 파일 자체는 레포에 두지 않는다 — relay 유닛도 그렇고, 두 벌이 되면 갈릴 자리가 생긴다.
#      대신 여기 한 곳에 적어서 재현 가능하게 남긴다.
#
# 첫 기동은 **인덱싱 때문에 리슨까지 20~30초** 걸린다. 그 사이 502 는 정상이다.
#   확인: ss -ltnp | grep 58082  ·  curl -s -o /dev/null -w '%{http_code}' http://localhost/md-web/
#   ⚠️ 200 만 보고 판단하지 말 것 — SPA 라 아무 경로나 shell 을 200 으로 준다.
#      `/api/tree` 로 **루트에 실제 항목이 오는지** 봐야 한다.

MD_WEB_DIR="${MD_WEB_DIR:-$HOME/md-web}"
BOT_ENV="${BOT_ENV:-$HOME/discord-bot-nino/.env}"
BUN="${BUN:-$HOME/.nvm/versions/node/v24.14.0/bin/bun}"

[ -d "$MD_WEB_DIR" ] || { echo "ERROR: md-web 디렉터리 없음 — $MD_WEB_DIR" >&2; exit 1; }
[ -x "$BUN" ]        || { echo "ERROR: bun 실행 파일 없음 — $BUN" >&2; exit 1; }

# .env 는 **있으면** 읽는다. md-web 자체는 지금 봇 .env 를 필요로 하지 않지만,
# 필요해졌을 때 유닛을 고치지 않아도 되게 경로를 한 곳에 둔다.
if [ -f "$BOT_ENV" ]; then
  set -a; . "$BOT_ENV"; set +a
fi

cd "$MD_WEB_DIR" || exit 1
exec "$BUN" run src/cli.ts serve
