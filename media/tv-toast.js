#!/usr/bin/env node
// LG webOS TV 토스트 메시지 전송
// 사용법: node tv-toast.js "메시지 내용"
process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';
const lgtv2 = require('lgtv2');

const TV_IP = '192.168.68.73';
const message = process.argv[2];

if (!message) {
  console.error('Usage: node tv-toast.js "메시지 내용"');
  process.exit(1);
}

const lgtv = lgtv2({
  url: `wss://${TV_IP}:3001`,
  timeout: 10000,
  reconnect: 0,
  keyFile: `${process.env.HOME}/.lgtv2/keyfile`,
});

lgtv.on('error', (err) => {
  console.error('TV 오류:', err.message);
  process.exit(1);
});

lgtv.on('connect', () => {
  lgtv.request('ssap://system.notifications/createToast', { message }, (err, res) => {
    if (err) {
      console.error('토스트 실패:', err.message);
      lgtv.disconnect();
      process.exit(1);
    }
    console.log('TV 토스트 전송 완료:', message);
    lgtv.disconnect();
    process.exit(0);
  });
});
