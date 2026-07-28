#!/usr/bin/env node
// LG webOS TV에서 YouTube 재생목록 실행 + darren 프로필 자동 선택
// 사용법: node tv-youtube.js <youtube-url>
// 예: node tv-youtube.js "https://www.youtube.com/playlist?list=PLxxx"

process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';
const lgtv2 = require('lgtv2');

const TV_IP = '192.168.68.73';
const YOUTUBE_APP_ID = 'youtube.leanback.v4';

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

// 🗑 `selectDarrenProfile()`(포인터를 픽셀 단위로 옮겨 프로필을 클릭) 를 지웠다 —
//    아래 Step 1 의 `params: { accountIndex: 0 }` 로 **프로필 선택창 자체를 건너뛰게** 바뀐
//    뒤로 한 번도 호출되지 않는 죽은 코드였다(좌표 상수 PROFILE_X/Y, `ws` 의존도 같이 감).
//    eslint 도입(2026-07-28) 때 처음 드러났다. 포인터 방식이 다시 필요하면 같은 구현이
//    살아 있는 media/tv-select-profile.js 를 쓴다(grep getPointerInputSocket → 그 파일 하나).

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

  // Step 1: contentId 없이 실행 → 프로필 선택창 없이 darren 피드로 직행
  await new Promise((resolve, reject) => {
    lgtv.request('ssap://system.launcher/launch', {
      id: YOUTUBE_APP_ID,
      params: { accountIndex: 0 },
    }, (err) => { if (err) reject(err); else resolve(); });
  });
  console.log('YouTube 실행됨, darren 피드 로딩 대기 중...');

  // darren 피드 로딩 대기
  await sleep(5000);

  // Step 2: contentTarget으로 원하는 URL로 이동
  let contentTarget;
  if (playlistId) {
    contentTarget = `https://www.youtube.com/tv?autoplay=1&list=${playlistId}&listType=playlist`;
    if (videoId) contentTarget += `&v=${videoId}`;
  } else {
    contentTarget = rawUrl;
  }

  await new Promise((resolve, reject) => {
    lgtv.request('ssap://system.launcher/launch', {
      id: YOUTUBE_APP_ID,
      params: { contentTarget, accountIndex: 0 },
    }, (err) => { if (err) reject(err); else resolve(); });
  });
  console.log('콘텐츠 이동 완료');

  lgtv.disconnect();
  process.exit(0);
});
