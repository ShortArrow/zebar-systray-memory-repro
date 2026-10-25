// Usage: node gc.mjs
// Forces a garbage collection in the widget over the Chrome DevTools Protocol
// and prints its JS heap before and after. Zebar must run with
// --remote-debugging-port=9222 (see README).
const targets = await (await fetch('http://127.0.0.1:9222/json/list')).json();
const widget = targets.find((t) => t.type === 'page' && t.url.endsWith('/index.html'));
if (!widget) throw new Error('widget page not found; is the widget running?');

const ws = new WebSocket(widget.webSocketDebuggerUrl);
await new Promise((resolve) => ws.addEventListener('open', resolve, { once: true }));
let nextId = 1;
const send = (method) =>
  new Promise((resolve) => {
    const id = nextId++;
    ws.addEventListener('message', function onMessage({ data }) {
      const message = JSON.parse(data);
      if (message.id !== id) return;
      ws.removeEventListener('message', onMessage);
      resolve(message.result);
    });
    ws.send(JSON.stringify({ id, method }));
  });

const mb = (bytes) => `${(bytes / 1048576).toFixed(1)} MB`;
const before = await send('Runtime.getHeapUsage');
await send('HeapProfiler.collectGarbage');
const after = await send('Runtime.getHeapUsage');
console.log(`JS heap ${mb(before.usedSize)} -> ${mb(after.usedSize)} after GC`);
ws.close();
