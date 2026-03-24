const http = require('http');
const https = require('https');
const WebSocket = require('ws');
const lgtv2 = require('lgtv2');
process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';

const TV_IP = '192.168.68.73';
const CHROME_CDP = 'http://172.25.160.1:9222';
const PLAYLIST_ID = 'PLa4zj40UDsB31u6XOJ2u5xCudeDSk3EOK';

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

async function getRandomVideoId() {
  return new Promise((resolve) => {
    https.get('https://www.youtube.com/playlist?list='+PLAYLIST_ID, { headers: { 'User-Agent': 'Mozilla/5.0' } }, res => {
      let d=''; res.on('data',c=>d+=c);
      res.on('end',()=>{
        const ids = [...new Set([...d.matchAll(/"videoId":"([A-Za-z0-9_-]{11})"/g)].map(m=>m[1]))];
        resolve(ids[Math.floor(Math.random()*ids.length)]);
      });
    }).on('error',()=>resolve('P0esOeqk32I'));
  });
}

async function ensureYouTubeOnTV() {
  const tv = lgtv2({ url: 'wss://'+TV_IP+':3001', timeout: 15000, reconnect: 0, keyFile: process.env.HOME+'/.lgtv2/keyfile' });
  return new Promise((resolve, reject) => {
    tv.on('error', e => reject(e));
    tv.on('connect', async () => {
      const fg = await new Promise(r => tv.request('ssap://com.webos.applicationManager/getForegroundAppInfo', {}, (e, res) => r(res)));
      const isYT = fg && fg.appId && fg.appId.includes('youtube');
      if (!isYT) {
        await new Promise(r => tv.request('ssap://system.launcher/close', { id: 'youtube.leanback.v4' }, r));
        await sleep(1000);
        await new Promise((res, rej) => tv.request('ssap://system.launcher/launch', { id: 'youtube.leanback.v4', params: { accountIndex: 0 } }, err => err ? rej(err) : res()));
        await sleep(6000);
      }
      tv.disconnect();
      resolve();
    });
  });
}

async function prepareTV() {
  const screenId = await new Promise((resolve, reject) => {
    http.get({ hostname: TV_IP, port: 36866, path: '/apps/YouTube', headers: { 'Origin': 'https://www.youtube.com' }, timeout: 3000 }, res => {
      let d=''; res.on('data',c=>d+=c); res.on('end',()=>{ const m=d.match(/<screenId>(.*?)<\/screenId>/); m?resolve(m[1]):reject('no screenId'); });
    }).on('error',reject);
  });
  const body = 'screen_ids='+encodeURIComponent(screenId);
  const loungeToken = await new Promise((resolve,reject) => {
    const req = https.request({hostname:'www.youtube.com',path:'/api/lounge/pairing/get_lounge_token_batch',method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded','Origin':'https://www.youtube.com','Content-Length':Buffer.byteLength(body)}},res=>{
      let d='';res.on('data',c=>d+=c);res.on('end',()=>{resolve(JSON.parse(d).screens[0].loungeToken)});
    }); req.on('error',reject); req.write(body); req.end();
  });
  const bindData = new URLSearchParams({device:'REMOTE_CONTROL',id:'12345678-9ABC-4DEF-0123-0123456789AB',name:'NinoBot','mdx-version':'3',pairing_type:'cast',app:'youtube-app'}).toString();
  const {sId,gSessionId} = await new Promise((resolve,reject) => {
    const req = https.request({hostname:'www.youtube.com',path:'/api/lounge/bc/bind?RID=0&VER=8&CVER=1',method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded','Origin':'https://www.youtube.com','X-YouTube-LoungeId-Token':loungeToken,'Content-Length':Buffer.byteLength(bindData)}},res=>{
      let d='';res.on('data',c=>d+=c);res.on('end',()=>{const s=d.match(/"c","(.*?)","/);const g=d.match(/"S","(.*?)"/);s&&g?resolve({sId:s[1],gSessionId:g[1]}):reject('bind fail')});
    }); req.on('error',reject); req.write(bindData); req.end();
  });
  return { loungeToken, sId, gSessionId };
}

async function prepareChromeWS() {
  const tabs = await fetch(CHROME_CDP+'/json').then(r=>r.json());
  let tab = tabs.find(t=>t.url && t.url.includes('music.youtube.com') && t.type==='page');
  if (!tab) {
    await fetch(CHROME_CDP+'/json/new?https://music.youtube.com');
    await sleep(2000);
    const tabs2 = await fetch(CHROME_CDP+'/json').then(r=>r.json());
    tab = tabs2.find(t=>t.url && t.url.includes('music.youtube.com') && t.type==='page');
  }
  const ws = new WebSocket(tab.webSocketDebuggerUrl);
  await new Promise(r=>ws.once('open',r));
  return ws;
}

async function main() {
  const videoId = await getRandomVideoId();
  console.log('랜덤 곡:', videoId);

  await ensureYouTubeOnTV();
  console.log('TV YouTube 준비 완료');

  const [tv, ws] = await Promise.all([prepareTV(), prepareChromeWS()]);
  console.log('둘 다 준비 완료. 동시 재생!');

  const params = new URLSearchParams({'req0_listId':PLAYLIST_ID,'req0__sc':'setPlaylist','req0_currentTime':'0','req0_currentIndex':'-1','req0_audioOnly':'false','req0_videoId':videoId,'count':'1'}).toString();
  const tvPlay = new Promise((resolve,reject) => {
    const req = https.request({hostname:'www.youtube.com',path:'/api/lounge/bc/bind?SID='+encodeURIComponent(tv.sId)+'&gsessionid='+encodeURIComponent(tv.gSessionId)+'&RID=1&VER=8&CVER=1',method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded','Origin':'https://www.youtube.com','X-YouTube-LoungeId-Token':tv.loungeToken,'Content-Length':Buffer.byteLength(params)}},res=>{
      res.on('data',()=>{});res.on('end',()=>resolve(res.statusCode));
    }); req.on('error',reject); req.write(params); req.end();
  });
  const chromePlay = new Promise(resolve => {
    ws.send(JSON.stringify({ id: 1, method: 'Page.navigate', params: { url: 'https://music.youtube.com/watch?v='+videoId+'&list='+PLAYLIST_ID } }));
    ws.once('message', () => { resolve('ok'); ws.close(); });
  });

  const [tvRes, chromeRes] = await Promise.all([tvPlay, chromePlay]);
  console.log('TV:', tvRes, '| Chrome:', chromeRes, '| videoId:', videoId);
}
main().catch(e=>console.error(e));
