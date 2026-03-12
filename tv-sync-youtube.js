#!/usr/bin/env node
// 유튜브 재생목록을 TV(거실) + PC/JBL(내방) 동시 재생 (멀티룸 오디오)
// 사용법: node tv-sync-youtube.js <youtube-music-playlist-url>
// 예: node tv-sync-youtube.js "https://music.youtube.com/playlist?list=PLxxx"

process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';
const lgtv2 = require('lgtv2');
const WebSocket = require('ws');

const TV_IP = '192.168.68.73';
const CHROME_CDP = 'http://172.25.160.1:9222';

const ytmUrl = process.argv[2];
if (!ytmUrl) {
  console.error('Usage: node tv-sync-youtube.js <youtube-music-playlist-url>');
  process.exit(1);
}

let playlistId = null;
try {
  playlistId = new URL(ytmUrl).searchParams.get('list');
} catch (e) {}

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

// TV: YouTube 재생목록 바로 재생 (프로필 선택창 없음)
// 핵심: contentId = playlist ID (full URL X), accountIndex:0 → 프로필 선택창 없이 재생목록 바로 시작
async function playOnTV() {
  return new Promise(async (resolve, reject) => {
    const lgtv = lgtv2({
      url: `wss://${TV_IP}:3001`,
      timeout: 30000,
      reconnect: 0,
      keyFile: `${process.env.HOME}/.lgtv2/keyfile`,
    });

    lgtv.on('error', e => reject(new Error('TV: ' + e.message)));
    lgtv.on('connect', async () => {
      // YouTube 앱 닫기
      await new Promise(r => lgtv.request('ssap://system.launcher/close', { id: 'youtube.leanback.v4' }, r));
      await sleep(1000);

      // contentId = playlist ID만 (URL 아님) + accountIndex:0 → 프로필 선택창 없이 재생목록 바로 재생
      await new Promise((res, rej) => {
        lgtv.request('ssap://system.launcher/launch', {
          id: 'youtube.leanback.v4',
          contentId: playlistId,
          params: { accountIndex: 0 },
        }, (err) => { if (err) rej(err); else res(); });
      });

      lgtv.disconnect();
      resolve('TV YouTube 재생목록 재생 시작 (darren 계정, 프로필 선택 없음)');
    });
  });
}

// Chrome: YouTube Music 재생목록으로 이동
async function playOnChrome() {
  const tabs = await fetch(`${CHROME_CDP}/json`).then(r => r.json());
  const ytmTab = tabs.find(t => t.url && t.url.includes('music.youtube.com') && t.type === 'page');

  if (ytmTab) {
    const ws = new WebSocket(ytmTab.webSocketDebuggerUrl);
    await new Promise(r => ws.once('open', r));
    let msgId = 1;
    const send = (method, params) => new Promise(resolve => {
      const id = msgId++;
      const handler = (data) => {
        const msg = JSON.parse(data);
        if (msg.id === id) resolve(msg);
        else ws.once('message', handler);
      };
      ws.once('message', handler);
      ws.send(JSON.stringify({ id, method, params: params || {} }));
    });
    await send('Page.navigate', { url: ytmUrl });
    await sleep(2000);
    ws.close();
    return 'Chrome YouTube Music 재생 완료';
  } else {
    await fetch(`${CHROME_CDP}/json/new?${ytmUrl}`);
    return 'Chrome YouTube Music 새 탭 열기 완료';
  }
}

// TV + Chrome 동시 실행
Promise.all([playOnTV(), playOnChrome()])
  .then(([tv, chrome]) => {
    console.log(tv);
    console.log(chrome);
    console.log('멀티룸 동시 재생 시작!');
  })
  .catch(err => {
    console.error('오류:', err.message);
    process.exit(1);
  });
