#!/usr/bin/env node
// YouTube Lounge API로 LG TV YouTube 앱 원격 제어
// 사용법: node tv-lounge-youtube.js [playlist-id]
// 예: node tv-lounge-youtube.js PLa4zj40UDsB31u6XOJ2u5xCudeDSk3EOK
//
// 동작:
//   1. TV의 DIAL 엔드포인트에서 screenId 가져오기
//   2. YouTube Lounge API로 loungeToken 획득
//   3. setPlaylist 명령으로 노래방 플레이리스트 바로 재생
//   → 프로필 선택 화면 없음!

const http = require('http');
const https = require('https');

const TV_IP = '192.168.68.73';
const PLAYLIST_ID = process.argv[2] || 'PLa4zj40UDsB31u6XOJ2u5xCudeDSk3EOK';
const SHUFFLE = process.argv[3] !== 'false'; // 기본값: 셔플 ON

// DIAL 포트 캐시 (런타임 내에서 재사용)
let cachedDialPort = null;

async function findDialPort() {
  if (cachedDialPort) return cachedDialPort;

  // LG webOS DIAL 포트 후보 (SSDP 없이 스캔)
  const CANDIDATES = [36866, 8008, 8080, 52235, 56789];
  // 추가로 36000-37000 범위 10개 샘플링
  for (let p = 36000; p <= 37000; p += 100) {
    if (!CANDIDATES.includes(p)) CANDIDATES.push(p);
  }

  for (const port of CANDIDATES) {
    try {
      const result = await new Promise((resolve, reject) => {
        const req = http.get({
          hostname: TV_IP, port, path: '/apps/YouTube',
          headers: { 'Origin': 'https://www.youtube.com' }, timeout: 1500
        }, res => {
          let data = '';
          res.on('data', d => data += d);
          res.on('end', () => {
            if (res.statusCode === 200 && data.includes('<screenId>')) resolve(port);
            else reject(new Error('not DIAL'));
          });
        });
        req.on('error', reject);
      });
      cachedDialPort = result;
      return result;
    } catch (_) { /* 다음 포트 시도 */ }
  }
  throw new Error('DIAL 포트를 찾을 수 없습니다 (YouTube 앱이 실행 중인지 확인)');
}

async function getScreenId() {
  const port = await findDialPort();
  console.log(`DIAL 포트: ${port}`);
  return new Promise((resolve, reject) => {
    const req = http.get({
      hostname: TV_IP, port, path: '/apps/YouTube',
      headers: { 'Origin': 'https://www.youtube.com' }, timeout: 5000
    }, res => {
      let data = '';
      res.on('data', d => data += d);
      res.on('end', () => {
        const match = data.match(/<screenId>(.*?)<\/screenId>/);
        if (match) resolve(match[1]);
        else reject(new Error('screenId not found: ' + data.slice(0, 200)));
      });
    });
    req.on('error', reject);
  });
}

async function getLoungeToken(screenId) {
  return new Promise((resolve, reject) => {
    const body = `screen_ids=${encodeURIComponent(screenId)}`;
    const req = https.request({
      hostname: 'www.youtube.com',
      path: '/api/lounge/pairing/get_lounge_token_batch',
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Origin': 'https://www.youtube.com',
        'Content-Length': Buffer.byteLength(body)
      }
    }, res => {
      let data = '';
      res.on('data', d => data += d);
      res.on('end', () => {
        try {
          const json = JSON.parse(data);
          const token = json.screens && json.screens[0] && json.screens[0].loungeToken;
          if (token) resolve(token);
          else reject(new Error('loungeToken not found: ' + data));
        } catch (e) {
          reject(new Error('JSON parse error: ' + data));
        }
      });
    });
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

async function bindSession(loungeToken) {
  return new Promise((resolve, reject) => {
    const bindData = new URLSearchParams({
      device: 'REMOTE_CONTROL',
      id: '12345678-9ABC-4DEF-0123-0123456789AB',
      name: 'NinoBot',
      'mdx-version': '3',
      pairing_type: 'cast',
      app: 'youtube-app'
    }).toString();

    const req = https.request({
      hostname: 'www.youtube.com',
      path: '/api/lounge/bc/bind?RID=0&VER=8&CVER=1',
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Origin': 'https://www.youtube.com',
        'X-YouTube-LoungeId-Token': loungeToken,
        'Content-Length': Buffer.byteLength(bindData)
      }
    }, res => {
      let data = '';
      res.on('data', d => data += d);
      res.on('end', () => {
        const sIdMatch = data.match(/"c","(.*?)","/) ;
        const gSessionMatch = data.match(/"S","(.*?)"]/);
        if (sIdMatch && gSessionMatch) {
          resolve({ sId: sIdMatch[1], gSessionId: gSessionMatch[1] });
        } else {
          reject(new Error('bind failed: ' + data.slice(0, 300)));
        }
      });
    });
    req.on('error', reject);
    req.write(bindData);
    req.end();
  });
}

async function setPlaylist(loungeToken, sId, gSessionId, listId, videoId = '') {
  return new Promise((resolve, reject) => {
    const params = new URLSearchParams({
      'req0_listId': listId,
      'req0__sc': 'setPlaylist',
      'req0_currentTime': '0',
      'req0_currentIndex': '-1',
      'req0_audioOnly': 'false',
      'req0_videoId': videoId,
      'count': '1'
    }).toString();

    const path = `/api/lounge/bc/bind?SID=${encodeURIComponent(sId)}&gsessionid=${encodeURIComponent(gSessionId)}&RID=1&VER=8&CVER=1`;
    const req = https.request({
      hostname: 'www.youtube.com',
      path,
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Origin': 'https://www.youtube.com',
        'X-YouTube-LoungeId-Token': loungeToken,
        'Content-Length': Buffer.byteLength(params)
      }
    }, res => {
      let data = '';
      res.on('data', d => data += d);
      res.on('end', () => {
        console.log(`setPlaylist 응답 [${res.statusCode}]:`, data.slice(0, 200));
        resolve(res.statusCode);
      });
    });
    req.on('error', reject);
    req.write(params);
    req.end();
  });
}

async function getRandomVideoId(listId) {
  return new Promise(resolve => {
    const req = https.get(`https://www.youtube.com/playlist?list=${listId}`, { headers: { 'User-Agent': 'Mozilla/5.0' } }, res => {
      let data = ''; res.on('data', d => data += d);
      res.on('end', () => {
        const ids = [...data.matchAll(/"videoId":"([A-Za-z0-9_-]{11})"/g)].map(m => m[1]);
        const unique = [...new Set(ids)];
        if (unique.length === 0) { resolve('P0esOeqk32I'); return; }
        resolve(unique[Math.floor(Math.random() * unique.length)]);
      });
    });
    req.on('error', () => resolve('P0esOeqk32I'));
  });
}

async function main() {
  console.log('1. screenId 가져오는 중...');
  const screenId = await getScreenId();
  console.log('screenId:', screenId);

  console.log('2. loungeToken 획득 중...');
  const loungeToken = await getLoungeToken(screenId);
  console.log('loungeToken:', loungeToken.slice(0, 30) + '...');

  console.log('3. 세션 바인드 중...');
  const { sId, gSessionId } = await bindSession(loungeToken);
  console.log('sId:', sId, 'gSessionId:', gSessionId);

  // 셔플: 플레이리스트에서 랜덤 영상 ID 선택
  const videoId = SHUFFLE ? await getRandomVideoId(PLAYLIST_ID) : 'P0esOeqk32I';
  console.log(`4. setPlaylist 전송 (listId: ${PLAYLIST_ID}, videoId: ${videoId}, shuffle: ${SHUFFLE})...`);
  await setPlaylist(loungeToken, sId, gSessionId, PLAYLIST_ID, videoId);

  console.log('완료!');
}

main().catch(err => {
  console.error('오류:', err.message);
  process.exit(1);
});
