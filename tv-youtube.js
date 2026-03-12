#!/usr/bin/env node
// LG webOS TV에서 YouTube 재생목록 실행
// 사용법: node tv-youtube.js <youtube-url>

process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';
const lgtv2 = require('lgtv2');

const TV_IP = '192.168.68.73';
const YOUTUBE_APP_ID = 'youtube.leanback.v4';
const url = process.argv[2];

if (!url) {
  console.error('Usage: node tv-youtube.js <youtube-url>');
  process.exit(1);
}

const lgtv = lgtv2({
  url: `wss://${TV_IP}:3001`,
  timeout: 15000,
  reconnect: 0,
  keyFile: `${process.env.HOME}/.lgtv2/keyfile`,
});

lgtv.on('error', (err) => {
  console.error('TV 연결 오류:', err.message);
  process.exit(1);
});

lgtv.on('connect', () => {
  // YouTube 앱 실행 + URL 전달 + darren 프로필(accountIndex:0) 자동 선택
  lgtv.request('ssap://system.launcher/launch', {
    id: YOUTUBE_APP_ID,
    contentId: url,
    params: { accountIndex: 0 },
  }, (err, res) => {
    if (err) {
      console.error('YouTube 실행 실패:', err.message);
      lgtv.disconnect();
      process.exit(1);
    }
    console.log('TV YouTube 실행 완료 (darren 프로필)');
    lgtv.disconnect();
  });
});
