#!/usr/bin/env node
// CDP port forwarder: cdp-ports.json에 정의된 포트별로 프록시 생성
// 127.0.0.1:<listen> -> Windows host:<remote>
// agent-browser가 127.0.0.1로만 연결하기 때문에 필요
//
// cdp-ports.json 형식:
//   단순: { "edge": 9222 }              → listen=9222, remote=9222
//   분리: { "chrome": { "listen": 19224, "remote": 9224 } }
//   listen≠remote 이유: WSL wslrelay가 같은 포트를 미러링하면 루프 발생
const net = require('net');
const fs = require('fs');
const path = require('path');

const WINDOWS_HOST = process.env.WINDOWS_HOST || '172.25.160.1';
const PORTS_FILE = path.join(__dirname, 'cdp-ports.json');

let ports;
try {
  ports = JSON.parse(fs.readFileSync(PORTS_FILE, 'utf8'));
} catch (e) {
  console.error(`cdp-ports.json 읽기 실패: ${e.message}`);
  console.error('기본값 사용: { "edge": 9222 }');
  ports = { edge: 9222 };
}

for (const [name, entry] of Object.entries(ports)) {
  const listenPort = typeof entry === 'number' ? entry : entry.listen;
  const remotePort = typeof entry === 'number' ? entry : entry.remote;

  const server = net.createServer(client => {
    const proxy = net.connect(remotePort, WINDOWS_HOST, () => {
      client.pipe(proxy).pipe(client);
    });
    proxy.on('error', () => client.destroy());
    client.on('error', () => proxy.destroy());
  });

  server.on('error', (err) => {
    if (err.code === 'EADDRINUSE') {
      console.log(`[${name}] 포트 ${listenPort} 이미 사용 중 — 스킵`);
    } else {
      console.error(`[${name}] 에러: ${err.message}`);
    }
  });

  server.listen(listenPort, '127.0.0.1', () => {
    console.log(`[${name}] 127.0.0.1:${listenPort} -> ${WINDOWS_HOST}:${remotePort}`);
  });
}
