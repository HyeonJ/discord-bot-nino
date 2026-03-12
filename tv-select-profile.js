#!/usr/bin/env node
// TV YouTube에서 darren 프로필 선택 (픽셀 단위 이동, 마우스 가속 우회)
// darren 위치: x≈200, y≈526 (1920x1080 기준)
process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';
const lgtv2 = require('lgtv2');
const WebSocket = require('ws');

const TV_IP = '192.168.68.73';
const TARGET_X = 200; // darren 프로필 x좌표 (전체 해상도 기준)
const TARGET_Y = 526; // darren 프로필 y좌표 (전체 해상도 기준)

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

const lgtv = lgtv2({
  url: `wss://${TV_IP}:3001`,
  timeout: 30000,
  reconnect: 0,
  keyFile: `${process.env.HOME}/.lgtv2/keyfile`,
});

lgtv.on('error', (err) => {
  console.error('TV 오류:', err.message);
  process.exit(1);
});

lgtv.on('connect', async () => {
  lgtv.request('ssap://com.webos.service.networkinput/getPointerInputSocket', {}, async (err, res) => {
    if (err || !res || !res.socketPath) {
      console.error('포인터 소켓 오류');
      lgtv.disconnect();
      process.exit(1);
    }

    const ws = new WebSocket(res.socketPath, { rejectUnauthorized: false });
    ws.on('open', async () => {
      // 1. 커서를 좌상단으로 리셋 (1px씩 이동 - 마우스 가속 없음)
      for (let i = 0; i < 300; i++) {
        ws.send(JSON.stringify({ type: 'move', dx: -1, dy: -1, down: 0 }));
      }
      await sleep(200);

      // 2. darren 프로필 위치로 1px씩 이동 (가속 없이 정확하게)
      for (let i = 0; i < TARGET_X; i++) {
        ws.send(JSON.stringify({ type: 'move', dx: 1, dy: 0, down: 0 }));
      }
      for (let i = 0; i < TARGET_Y; i++) {
        ws.send(JSON.stringify({ type: 'move', dx: 0, dy: 1, down: 0 }));
      }
      await sleep(300);

      // 3. 클릭
      ws.send(JSON.stringify({ type: 'down' }));
      await sleep(100);
      ws.send(JSON.stringify({ type: 'up' }));
      await sleep(1000);

      ws.close();
      lgtv.disconnect();
      console.log('darren 프로필 클릭 완료');
      process.exit(0);
    });
    ws.on('error', (e) => {
      console.error('포인터 소켓 오류:', e.message);
      lgtv.disconnect();
      process.exit(1);
    });
  });
});
