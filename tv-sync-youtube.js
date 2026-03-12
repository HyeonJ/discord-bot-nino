#!/usr/bin/env node
// 유튜브 재생목록을 TV(거실) + PC/JBL(내방) 동시 재생 (멀티룸 오디오)
// 사용법: node tv-sync-youtube.js <youtube-music-playlist-url>
// 예: node tv-sync-youtube.js "https://music.youtube.com/playlist?list=PLxxx"

process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';
const lgtv2 = require('lgtv2');
const WebSocket = require('ws');
const http = require('http');
const https = require('https');

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

// DIAL 포트 탐색 + screenId 가져오기
async function getScreenId() {
  const CANDIDATES = [36866, 8008, 8080, 52235, 56789];
  for (let p = 36000; p <= 37000; p += 100) if (!CANDIDATES.includes(p)) CANDIDATES.push(p);
  for (const port of CANDIDATES) {
    try {
      const result = await new Promise((resolve, reject) => {
        const req = http.get({ hostname: TV_IP, port, path: '/apps/YouTube', headers: { 'Origin': 'https://www.youtube.com' }, timeout: 1500 }, res => {
          let data = ''; res.on('data', d => data += d);
          res.on('end', () => {
            const m = data.match(/<screenId>(.*?)<\/screenId>/);
            if (res.statusCode === 200 && m) resolve(m[1]);
            else reject(new Error('not DIAL'));
          });
        });
        req.on('error', reject);
      });
      return result;
    } catch (_) {}
  }
  throw new Error('DIAL 포트를 찾을 수 없습니다 (YouTube 앱이 실행 중인지 확인)');
}

// YouTube Lounge API로 TV에서 플레이리스트 재생 (프로필 선택 없음!)
async function playOnTV() {
  // 1. YouTube가 실행 중인지 확인, 아니면 실행
  const lgtv = lgtv2({ url: `wss://${TV_IP}:3001`, timeout: 15000, reconnect: 0, keyFile: `${process.env.HOME}/.lgtv2/keyfile` });
  await new Promise((resolve, reject) => {
    lgtv.on('error', e => reject(new Error('TV: ' + e.message)));
    lgtv.on('connect', async () => {
      const fgApp = await new Promise(r => lgtv.request('ssap://com.webos.applicationManager/getForegroundAppInfo', {}, (e, res) => r(res)));
      const isYouTube = fgApp && fgApp.appId && fgApp.appId.includes('youtube');
      if (!isYouTube) {
        await new Promise(r => lgtv.request('ssap://system.launcher/close', { id: 'youtube.leanback.v4' }, r));
        await sleep(1000);
        await new Promise((res, rej) => lgtv.request('ssap://system.launcher/launch', { id: 'youtube.leanback.v4', params: { accountIndex: 0 } }, err => err ? rej(err) : res()));
        await sleep(6000); // YouTube 로딩 대기
      }
      lgtv.disconnect();
      resolve();
    });
  });

  // 2. Lounge API로 플레이리스트 재생
  const screenId = await getScreenId();

  // loungeToken 획득
  const loungeToken = await new Promise((resolve, reject) => {
    const body = `screen_ids=${encodeURIComponent(screenId)}`;
    const req = https.request({ hostname: 'www.youtube.com', path: '/api/lounge/pairing/get_lounge_token_batch', method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'Origin': 'https://www.youtube.com', 'Content-Length': Buffer.byteLength(body) } }, res => {
      let data = ''; res.on('data', d => data += d);
      res.on('end', () => { try { const j = JSON.parse(data); resolve(j.screens[0].loungeToken); } catch (e) { reject(new Error(data)); } });
    });
    req.on('error', reject); req.write(body); req.end();
  });

  // bind
  const { sId, gSessionId } = await new Promise((resolve, reject) => {
    const bindData = new URLSearchParams({ device: 'REMOTE_CONTROL', id: '12345678-9ABC-4DEF-0123-0123456789AB', name: 'NinoBot', 'mdx-version': '3', pairing_type: 'cast', app: 'youtube-app' }).toString();
    const req = https.request({ hostname: 'www.youtube.com', path: '/api/lounge/bc/bind?RID=0&VER=8&CVER=1', method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'Origin': 'https://www.youtube.com', 'X-YouTube-LoungeId-Token': loungeToken, 'Content-Length': Buffer.byteLength(bindData) } }, res => {
      let data = ''; res.on('data', d => data += d);
      res.on('end', () => {
        const s = data.match(/"c","(.*?)","/) ; const g = data.match(/"S","(.*?)"]/);
        if (s && g) resolve({ sId: s[1], gSessionId: g[1] }); else reject(new Error('bind failed: ' + data.slice(0, 200)));
      });
    });
    req.on('error', reject); req.write(bindData); req.end();
  });

  // setPlaylist: 플레이리스트에서 랜덤 영상 ID 뽑아서 시작 (셔플 효과)
  const startVideoId = await new Promise((resolve) => {
    const req = https.get(`https://www.youtube.com/playlist?list=${playlistId}`, { headers: { 'User-Agent': 'Mozilla/5.0' } }, res => {
      let data = ''; res.on('data', d => data += d);
      res.on('end', () => {
        const ids = [...new Set([...data.matchAll(/"videoId":"([A-Za-z0-9_-]{11})"/g)].map(m => m[1]))];
        resolve(ids.length > 0 ? ids[Math.floor(Math.random() * ids.length)] : '');
      });
    });
    req.on('error', () => resolve(''));
  });

  const params = new URLSearchParams({ 'req0_listId': playlistId, 'req0__sc': 'setPlaylist', 'req0_currentTime': '0', 'req0_currentIndex': '-1', 'req0_audioOnly': 'false', 'req0_videoId': startVideoId, 'count': '1' }).toString();
  await new Promise((resolve, reject) => {
    const req = https.request({ hostname: 'www.youtube.com', path: `/api/lounge/bc/bind?SID=${encodeURIComponent(sId)}&gsessionid=${encodeURIComponent(gSessionId)}&RID=1&VER=8&CVER=1`, method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'Origin': 'https://www.youtube.com', 'X-YouTube-LoungeId-Token': loungeToken, 'Content-Length': Buffer.byteLength(params) } }, res => {
      res.on('data', () => {}); res.on('end', () => resolve(res.statusCode));
    });
    req.on('error', reject); req.write(params); req.end();
  });

  return 'TV YouTube Lounge API로 노래방 재생 완료 (프로필 선택 없음)';
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
