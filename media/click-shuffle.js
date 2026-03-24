const WebSocket = require('ws');

async function run() {
  const res = await fetch('http://172.25.160.1:9222/json');
  const tabs = await res.json();
  const ytTab = tabs.find(t => t.url && t.url.includes('music.youtube.com'));
  if (!ytTab) { console.log('YTM tab not found'); return; }

  await fetch(`http://172.25.160.1:9222/json/activate/${ytTab.id}`);
  await new Promise(r => setTimeout(r, 500));

  const ws = new WebSocket(ytTab.webSocketDebuggerUrl);
  let id = 1;
  const send = (method, params) => new Promise(resolve => {
    const msgId = id++;
    const handler = (data) => {
      const msg = JSON.parse(data);
      if (msg.id === msgId) resolve(msg);
      else ws.once('message', handler);
    };
    ws.once('message', handler);
    ws.send(JSON.stringify({id: msgId, method, params: params || {}}));
  });

  await new Promise(r => ws.once('open', r));

  await send('Page.bringToFront');
  await new Promise(r => setTimeout(r, 500));

  // Approach: focus the button, then dispatch Enter key via CDP Input
  const nodeRes = await send('Runtime.evaluate', {
    expression: `
      (() => {
        const btn = [...document.querySelectorAll('button[aria-label]')].find(b => b.getAttribute('aria-label') === '\uC154\uD50C' && b.getBoundingClientRect().width > 0);
        if (!btn) return null;
        btn.focus();
        const rect = btn.getBoundingClientRect();
        return {cx: Math.round(rect.x + rect.width/2), cy: Math.round(rect.y + rect.height/2)};
      })()
    `,
    returnByValue: true
  });
  const pos = nodeRes.result && nodeRes.result.result && nodeRes.result.result.value;
  console.log('Position:', pos);

  // Dispatch keyboard Enter on focused element via CDP
  await send('Input.dispatchKeyEvent', {
    type: 'keyDown',
    key: 'Enter',
    code: 'Enter',
    nativeVirtualKeyCode: 13,
    windowsVirtualKeyCode: 13
  });
  await new Promise(r => setTimeout(r, 100));
  await send('Input.dispatchKeyEvent', {
    type: 'keyUp',
    key: 'Enter',
    code: 'Enter',
    nativeVirtualKeyCode: 13,
    windowsVirtualKeyCode: 13
  });
  await new Promise(r => setTimeout(r, 500));

  let check = await send('Runtime.evaluate', {
    expression: `[...document.querySelectorAll('button[aria-label]')].filter(b => b.getAttribute('aria-label').includes('\uC154\uD50C') && b.getBoundingClientRect().width > 0).map(b => b.getAttribute('aria-label')).join(', ')`,
    returnByValue: true
  });
  console.log('After Enter key:', check.result && check.result.result && check.result.result.value);

  // Try CDP Input.dispatchMouseEvent with correct x,y
  if (pos) {
    console.log('Trying Input.dispatchMouseEvent at', pos.cx, pos.cy);
    await send('Input.dispatchMouseEvent', { type: 'mouseMoved', x: pos.cx, y: pos.cy, buttons: 0 });
    await new Promise(r => setTimeout(r, 100));
    await send('Input.dispatchMouseEvent', { type: 'mousePressed', x: pos.cx, y: pos.cy, button: 'left', buttons: 1, clickCount: 1 });
    await new Promise(r => setTimeout(r, 100));
    await send('Input.dispatchMouseEvent', { type: 'mouseReleased', x: pos.cx, y: pos.cy, button: 'left', buttons: 0, clickCount: 1 });
    await new Promise(r => setTimeout(r, 500));

    check = await send('Runtime.evaluate', {
      expression: `[...document.querySelectorAll('button[aria-label]')].filter(b => b.getAttribute('aria-label').includes('\uC154\uD50C') && b.getBoundingClientRect().width > 0).map(b => b.getAttribute('aria-label')).join(', ')`,
      returnByValue: true
    });
    console.log('After mouse click:', check.result && check.result.result && check.result.result.value);
  }

  ws.close();
}
run().catch(console.error);
