#!/usr/bin/env node
// LG webOS TV에서 YouTube 재생목록 실행 + darren 프로필 자동 선택
// 사용법: node tv-youtube.js <youtube-url>
// 예: node tv-youtube.js "https://www.youtube.com/playlist?list=PLxxx"

process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';
const lgtv2 = require('lgtv2');
const WebSocket = require('ws');

const TV_IP = '192.168.68.73';
const YOUTUBE_APP_ID = 'youtube.leanback.v4';
// darren 프로필 좌표 (1920x1080 기준, 픽셀 단위 이동으로 정확히 클릭)
const PROFILE_X = 200;
const PROFILE_Y = 526;

const rawUrl = process.argv[2];
if (!rawUrl) {
  console.error('Usage: node tv-youtube.js <youtube-url>');
  process.exit(1);
}

// playlist ID 추출
let playlistId = null;
let videoId = null;
try {
  const u = new URL(rawUrl);
  playlistId = u.searchParams.get('list');
  videoId = u.searchParams.get('v');
} catch (e) {}

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

// darren 프로필 선택 (픽셀 단위 이동)
function selectDarrenProfile(lgtv) {
  return new Promise((resolve, reject) => {
    lgtv.request('ssap://com.webos.service.networkinput/getPointerInputSocket', {}, async (err, res) => {
      if (err || !res || !res.socketPath) { resolve(); return; }
      const ws = new WebSocket(res.socketPath, { rejectUnauthorized: false });
      ws.on('open', async () => {
        // 커서 리셋
        for (let i = 0; i < 300; i++) ws.send(JSON.stringify({ type: 'move', dx: -1, dy: -1, down: 0 }));
        await sleep(200);
        // darren 위치로 이동
        for (let i = 0; i < PROFILE_X; i++) ws.send(JSON.stringify({ type: 'move', dx: 1, dy: 0, down: 0 }));
        for (let i = 0; i < PROFILE_Y; i++) ws.send(JSON.stringify({ type: 'move', dx: 0, dy: 1, down: 0 }));
        await sleep(300);
        // 클릭
        ws.send(JSON.stringify({ type: 'down' }));
        await sleep(100);
        ws.send(JSON.stringify({ type: 'up' }));
        await sleep(1000);
        ws.close();
        resolve();
      });
      ws.on('error', () => resolve()); // 실패해도 계속
    });
  });
}

const lgtv = lgtv2({
  url: `wss://${TV_IP}:3001`,
  timeout: 30000,
  reconnect: 0,
  keyFile: `${process.env.HOME}/.lgtv2/keyfile`,
});

lgtv.on('error', (err) => {
  console.error('TV 연결 오류:', err.message);
  process.exit(1);
});

lgtv.on('connect', async () => {
  // YouTube 앱 닫기
  await new Promise(r => lgtv.request('ssap://system.launcher/close', { id: YOUTUBE_APP_ID }, r));
  await sleep(1000);

  // YouTube 실행: playlist URL이면 비디오ID+listParam, 아니면 URL 직접
  const launchParams = {
    id: YOUTUBE_APP_ID,
    params: { accountIndex: 0 },
  };
  if (playlistId && videoId) {
    launchParams.contentId = videoId;
    launchParams.params.list = playlistId;
  } else if (playlistId) {
    // playlist만 있는 경우: playlist ID로 시도
    launchParams.contentId = rawUrl;
    launchParams.params.list = playlistId;
  } else {
    launchParams.contentId = rawUrl;
  }

  await new Promise((resolve, reject) => {
    lgtv.request('ssap://system.launcher/launch', launchParams, (err) => {
      if (err) reject(err); else resolve();
    });
  });
  console.log('YouTube 실행됨, 프로필 선택 대기 중...');

  // 프로필 선택창이 나타날 때까지 대기
  await sleep(3000);

  // darren 프로필 자동 클릭
  await selectDarrenProfile(lgtv);
  console.log('darren 프로필 선택 완료');

  lgtv.disconnect();
  process.exit(0);
});
