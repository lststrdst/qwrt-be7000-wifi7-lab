/* Public screenshots: production views/assets with synthetic, local-only APIs.
 * No router requests, credentials, packet payloads or state-changing operations.
 */
'use strict';
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const theme = path.join(root, 'firmware/packages/luci-theme-netscope/files');
const setup = path.join(root, 'firmware/packages/luci-app-netscope-setup/files');
const read = p => fs.readFileSync(p, 'utf8');
const epoch = 1788692400;
const started = Date.now();
const devices = ['Рабочий ПК', 'Ноутбук', 'Телефон', 'Колонка', 'Пылесос'].map((name, i) => ({name, ip: `192.168.50.${10+i}`, connections: 2, observed: true, source: 'Демонстрационные данные'}));
const flows = Array.from({length: 10}, (_, i) => {
  const source = devices[i % devices.length].ip;
  const destination = `203.0.113.${20+i}`;
  const protocol = i === 3 || i === 5 ? 'udp' : 'tcp';
  const dport = i === 5 ? 50000 : 443;
  const tx_bytes = (i + 2) * 524288, rx_bytes = (12-i) * 1048576;
  return {id: `demo-flow-${i}`, source, destination, sport: 52000+i, dport, protocol, family: 'ipv4', state: protocol === 'tcp' ? 'ESTABLISHED' : 'TRACKED', accounting: true, bytes: tx_bytes+rx_bytes, tx_bytes, rx_bytes, tx_packets: 850+i*40, rx_packets: 1400+i*30, expires_in: 7200, assured: true, mark: i === 5 ? 2 : 0, reply_source: destination, reply_sport: dport, reply_destination: '198.51.100.10', reply_dport: 52000+i};
});
const voice = {available: true, active: true, healthy: true, mode: 'hy2-tun', fallback_ready: true, latency_ms: 54, jitter_ms: 1.2, loss_percent: 0, window: 30, route: 'HY2 primary · nshy2 · table 101', endpoints: [], history: []};
const capture = {active: false, state: 'OFF', counters: {dns: 0, http: 0, tls: 0}, written: 0, storage: {mounted: true, writable: true, free: 128000000000}, proxy: {ca: {ready: false}}, visibility: 'Демонстрационные данные; запись не запущена'};
const setupData = {
  status: {storage: {mounted:true,writable:true}, tools: {manager:true,wg:true,awg:true,xray:true,mieru:true,hev:true,hysteria:true}, lan:'192.168.50.0/24', recommended_port:51820, recommended_tunnel:'10.77.0.0/24'},
  drafts: {drafts: [{id:'demo-hy2-profile',kind:'hy2',protocol:'Hysteria 2',active:true,created:'2026-09-06T11:00:00Z',note:'Демонстрационный профиль. Секретов нет.'}]},
  voice_status: {...voice, upstream_probe:true, autostart:true, hy2:true, telegram_nets:8, discord_nets:2, discord_ips:4},
  voice_telemetry: voice,
  l2tp_status: {available:true,enabled:true,healthy:true,interface:'ppp-demo',mtu:1400,mss:1360,reconnects:0}
};
function shell(content, page) {
  const menu = [['Обзор','#'],['Wi-Fi','#'],['Интерфейсы','#'],['AmneziaWG','#'],['NETSCOPE','/netscope'],['Быстрая настройка VPN','/quick-setup']];
  return `<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>NETSCOPE — public gallery</title>
  <link rel="stylesheet" href="/luci-static/netscope/netscope.css">
  <style>@font-face{font-family:Inter;src:url(/luci-static/netscope/InterVariable.woff2)}*{box-sizing:border-box}body{margin:0;background:#1e1e1e;font:14px/1.5 Inter,Arial,sans-serif;color:#f5f5f5}.gallery-sidebar{position:fixed;inset:0 auto 0 0;width:252px;background:#2c2c2c;padding:24px 18px;display:flex;flex-direction:column;gap:16px}.gallery-sidebar b{font-size:24px;color:#cff7d3;padding:0 6px}.gallery-sidebar small{font-size:10px;color:#b5b5b5;padding:0 6px;letter-spacing:.04em}.gallery-sidebar nav{display:grid;gap:6px;margin:14px 0}.gallery-sidebar a{display:block;padding:14px;color:#ccc;text-decoration:none;font-size:13px;border-radius:8px}.gallery-sidebar a[aria-current]{background:#cff7d3;color:#17291b;font-weight:650}.gallery-sidebar input{width:100%;background:#262626;color:#aaa;border:1px solid #444;padding:12px;border-radius:8px}.gallery-sidebar p{padding:8px 12px;color:#bbb;font-size:13px}.gallery-header{margin-left:252px;border-bottom:1px solid #383838;padding:16px 32px;color:#aaa;font-size:12px}.gallery-main{margin-left:252px;padding:24px 32px}.gallery-demo{margin:0 0 22px;color:#a9b7ad;font-size:11px;letter-spacing:.04em}@media(max-width:992px){.gallery-sidebar{display:none}.gallery-main,.gallery-header{margin-left:0}.gallery-main{padding:18px 14px}}</style></head>
  <body class="netscope logged-in" data-theme="dark"><aside class="gallery-sidebar"><b>NETSCOPE</b><small>(QWRT R26.2.2)<br>для Xiaomi BE7000 · by lststrdst</small><nav>${menu.map(([label,href]) => `<a href="${href}" ${href === page ? 'aria-current="page"' : ''}>${label}</a>`).join('')}</nav><small>ВСЕ НАСТРОЙКИ</small><input aria-label="Поиск настроек" placeholder="Найти настройку…" disabled><p>Состояние</p><p>Система</p><p>Службы</p><p>VPN</p><p>Сеть</p></aside><header class="gallery-header">NETSCOPE (QWRT R26.2.2)</header><main class="gallery-main"><p class="gallery-demo">ДЕМО ИНТЕРФЕЙСА · адреса, устройства и показатели вымышлены · без подключения к роутеру</p>${content}</main></body></html>`;
}
const assets = new Map(['netscope.css','monitor.css','monitor.js','InterVariable.woff2'].map(name => [name,path.join(theme,'www/luci-static/netscope',name)]));
for(const name of ['setup.css','setup.js','import.js'])assets.set(name,path.join(setup,'www/luci-static/netscope',name));
const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://127.0.0.1');
  res.setHeader('Cache-Control','no-store');
  res.setHeader('Content-Security-Policy', "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; connect-src 'self'; font-src 'self'; img-src 'self'; frame-src 'none'; form-action 'none'; base-uri 'none'");
  if(req.method !== 'GET') {res.writeHead(405, {'Content-Type':'application/json'});res.end(JSON.stringify({error:'Галерея только для просмотра. Сеть не меняется.'}));return;}
  if(url.pathname.startsWith('/gallery-api/')) {
    let value;
    if(url.pathname === '/gallery-api/snapshot') {
      const elapsed = Math.floor((Date.now()-started)/1000);
      value = {devices,flows,updated_at:epoch+elapsed,interfaces:[{name:'eth0',rx_bytes:100000000+elapsed*2400000,tx_bytes:20000000+elapsed*400000}],warning:'Демо: искусственные записи conntrack, не домашняя история трафика.'};
    } else if(url.pathname === '/gallery-api/voice')value=voice;
    else if(url.pathname === '/gallery-api/capture/status')value=capture;
    else if(url.pathname.startsWith('/gallery-api/setup/'))value=setupData[url.pathname.split('/').pop()];
    if(!value){res.writeHead(404,{'Content-Type':'application/json'});res.end(JSON.stringify({error:'В галерее доступны только демонстрационные статусы.'}));return;}
    res.setHeader('Content-Type','application/json');res.end(JSON.stringify(value));return;
  }
  if(url.pathname.startsWith('/luci-static/netscope/')) {
    const name = url.pathname.slice('/luci-static/netscope/'.length), file=assets.get(name);
    if(!file || !fs.existsSync(file)){res.writeHead(404);res.end();return;}
    res.setHeader('Content-Type',name.endsWith('.css')?'text/css':name.endsWith('.js')?'text/javascript':'font/woff2');res.end(fs.readFileSync(file));return;
  }
  if(!['/','/netscope','/quick-setup'].includes(url.pathname)){res.writeHead(404);res.end();return;}
  const page = url.pathname === '/quick-setup' ? '/quick-setup' : '/netscope';
  let html = read(page === '/netscope' ? path.join(theme,'usr/lib/lua/luci/view/themes/netscope/monitor.htm') : path.join(setup,'usr/lib/lua/luci/view/netscope/setup.htm'))
    .replace(/<%=url\('admin','services','netscope_setup'\)%>/g,'/gallery-api/setup')
    .replace(/<%=url\('admin','status','netscope','(snapshot|voice|capture)'\)%>/g,'/gallery-api/$1')
    .replace(/<%=url\('admin','status','netscope'\)%>/g,'/netscope')
    .replace(/<%=token%>/g,'gallery-not-a-secret')
    .replace(/<%[\s\S]*?%>/g,'');
  res.setHeader('Content-Type','text/html; charset=utf-8');res.end(shell(html,page));
});
server.listen(4190,'127.0.0.1',()=>console.log('NETSCOPE public gallery: http://127.0.0.1:4190/netscope'));
