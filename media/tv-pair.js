#!/usr/bin/env node
// LG TV 페어링 테스트 - 연결 상태 상세 로깅
process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';
const lgtv2 = require('lgtv2');

const TV_IP = '192.168.68.73';

const lgtv = lgtv2({
  url: `wss://${TV_IP}:3001`,
  timeout: 30000,
  reconnect: 0,
  keyFile: `${process.env.HOME}/.lgtv2/keyfile`,
});

lgtv.on('error', (err) => {
  console.log('[ERROR]', err.message, err.code);
});

lgtv.on('connecting', (host) => {
  console.log('[CONNECTING]', host);
});

lgtv.on('connect', () => {
  console.log('[CONNECTED] 페어링 성공!');
  lgtv.request('ssap://com.webos.applicationManager/listApps', {}, (err, res) => {
    if (err) { console.log('[ERROR] listApps:', err.message); }
    else {
      const yt = (res.apps || []).find(a => a.id && a.id.toLowerCase().includes('youtube'));
      console.log('[YouTube 앱]', yt ? yt.id : '없음');
    }
    lgtv.disconnect();
    process.exit(0);
  });
});

lgtv.on('close', () => {
  console.log('[CLOSED]');
});

lgtv.on('prompt', () => {
  console.log('[PROMPT] TV에서 팝업 허용해줘!');
});

setTimeout(() => {
  console.log('[TIMEOUT] 30초 초과');
  process.exit(1);
}, 30000);
