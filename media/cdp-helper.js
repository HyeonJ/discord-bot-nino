#!/usr/bin/env node
/**
 * CDP helper — navigate or eval JS on the first page tab via WebSocket.
 *
 * Usage:
 *   cdp-helper.js eval <js_expression>       # evaluate JS, print result
 *   cdp-helper.js eval-stdin                  # read JS from stdin, evaluate, print result
 *   cdp-helper.js navigate <url>              # navigate tab to URL
 *   cdp-helper.js screenshot <path>           # take screenshot, save to path
 *
 * Env: CDP_PORT (default 9222)
 */
const http = require('http');
const WebSocket = require('ws');
const fs = require('fs');

const PORT = process.env.CDP_PORT || '9222';
const [, , cmd, ...args] = process.argv;

function getFirstPageTab() {
  return new Promise((resolve, reject) => {
    http.get(`http://127.0.0.1:${PORT}/json/list`, res => {
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => {
        try {
          const tabs = JSON.parse(data);
          const page = tabs.find(t => t.type === 'page');
          if (!page) reject(new Error('no page tab'));
          else resolve(page);
        } catch (e) { reject(e); }
      });
    }).on('error', reject);
  });
}

function cdpCall(wsUrl, method, params = {}) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(wsUrl);
    const timeout = setTimeout(() => { ws.close(); reject(new Error('timeout')); }, 30000);
    ws.on('open', () => {
      ws.send(JSON.stringify({ id: 1, method, params }));
    });
    ws.on('message', msg => {
      const d = JSON.parse(msg);
      if (d.id === 1) {
        clearTimeout(timeout);
        ws.close();
        if (d.error) reject(new Error(d.error.message));
        else resolve(d.result);
      }
    });
    ws.on('error', e => { clearTimeout(timeout); reject(e); });
  });
}

async function main() {
  const tab = await getFirstPageTab();
  const wsUrl = tab.webSocketDebuggerUrl;

  if (cmd === 'eval' || cmd === 'eval-stdin') {
    const js = cmd === 'eval-stdin'
      ? fs.readFileSync(0, 'utf8')
      : args.join(' ');
    const result = await cdpCall(wsUrl, 'Runtime.evaluate', {
      expression: js,
      returnByValue: true,
      awaitPromise: true,
    });
    if (result.exceptionDetails) {
      console.error(result.exceptionDetails.text || 'eval error');
      process.exit(1);
    }
    const val = result.result?.value;
    console.log(typeof val === 'string' ? val : JSON.stringify(val));

  } else if (cmd === 'navigate') {
    const url = args[0];
    if (!url) { console.error('usage: navigate <url>'); process.exit(1); }
    await cdpCall(wsUrl, 'Page.navigate', { url });
    // Wait for load
    await new Promise(resolve => {
      const ws = new WebSocket(wsUrl);
      const timeout = setTimeout(() => { ws.close(); resolve(); }, 15000);
      ws.on('open', () => {
        ws.send(JSON.stringify({ id: 2, method: 'Page.enable' }));
      });
      ws.on('message', msg => {
        const d = JSON.parse(msg);
        if (d.method === 'Page.loadEventFired') {
          clearTimeout(timeout);
          ws.close();
          resolve();
        }
      });
    });
    console.log('ok');

  } else if (cmd === 'screenshot') {
    const outPath = args[0] || '/tmp/cdp-screenshot.png';
    const result = await cdpCall(wsUrl, 'Page.captureScreenshot', { format: 'png' });
    fs.writeFileSync(outPath, Buffer.from(result.data, 'base64'));
    console.log(outPath);

  } else {
    console.error('usage: cdp-helper.js [eval|eval-stdin|navigate|screenshot] ...');
    process.exit(1);
  }
}

main().catch(e => { console.error(e.message); process.exit(1); });
