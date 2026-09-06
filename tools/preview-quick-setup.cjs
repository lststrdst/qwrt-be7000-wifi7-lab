/* Loopback-only, synthetic UI fixture. Never calls a router or real VPN API. */
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const setup = path.join(root, 'firmware/packages/luci-app-netscope-setup/files');
const theme = path.join(root, 'firmware/packages/luci-theme-netscope/files');
const read = p => fs.readFileSync(p, 'utf8');
const state = {
  status: {storage:{mounted:true,writable:true},tools:{manager:true,wg:true,awg:true,xray:true,mieru:true,hev:true,hysteria:true},lan:'192.168.50.0/24',recommended_port:51820,recommended_tunnel:'10.77.0.0/24'},
  drafts:{drafts:[{id:'demo-hy2-profile',kind:'hy2',protocol:'Hysteria 2',active:true,created:'2026-09-06T10:00:00Z',note:'Изолированный профиль. Голосовой маршрут включается отдельно.'},{id:'demo-mieru-profile',kind:'mieru',protocol:'Mieru',active:false,created:'2026-09-06T10:01:00Z',note:'Пример неактивного профиля для проверки интерфейса.'}]},
  voice_status:{available:true,active:true,healthy:true,upstream_probe:true,mode:'hy2-tun',fallback_ready:true,autostart:false,hy2:true,telegram_nets:8,discord_nets:3,discord_ips:4},
  voice_telemetry:{available:true,latency_ms:53,jitter_ms:1.4,loss_percent:0,window:30},
  l2tp_status:{available:true,enabled:true,healthy:true,interface:'ppp0',mtu:1400,mss:1360,reconnects:0}
};
const server = http.createServer((req,res) => {
  const url = new URL(req.url,'http://127.0.0.1');
  res.setHeader('Cache-Control','no-store');
  if(url.pathname.startsWith('/fixture-api/')){
    res.setHeader('Content-Type','application/json');
    const name=url.pathname.split('/').pop();
    const scenario=(req.headers.referer||'').split('scenario=')[1]?.split('&')[0];
    if(req.method!=='GET'){
      // Exercise all UI paths without ever changing real state.
      let body='';req.on('data',c=>body+=c);req.on('end',()=>{
        const data=new URLSearchParams(body);
        if(name==='prepare')res.end(JSON.stringify({id:'demo-created',state:'DRAFT',note:'Тестовый черновик. Реальная конфигурация не создаётся.',checks:['Проверка выполнена на синтетических данных'],files:[],planned_changes:['Изолированный профиль '+data.get('kind')]}));
        else if(name==='preflight')res.end(JSON.stringify({ready:true,activation_supported:true,checks:['Тестовый runtime готов'],rollback:['Остановить только тестовый профиль'],note:'Локальная имитация проверки'}));
        else res.end(JSON.stringify({note:'Локальная имитация: сеть не менялась.'}));
      });return;
    }
    const result=structuredClone(state[name]||{});
    if(scenario==='empty'&&name==='drafts')result.drafts=[];
    if(scenario==='off'&&name==='voice_status'){result.active=false;result.healthy=false;result.fallback_ready=false;}
    if(scenario==='reserve'&&name==='voice_status')result.mode='mieru-tun';
    if(scenario==='missing'&&name==='status'){result.storage={mounted:false,writable:false};result.tools={manager:true,mieru_installer:true,hev_installer:true,hysteria_installer:true};}
    if(scenario==='error'){res.statusCode=503;res.end(JSON.stringify({error:'Тестовая ошибка соединения'}));return;}
    res.end(JSON.stringify(result));return;
  }
  if(url.pathname.startsWith('/luci-static/netscope/')){
    const name=path.basename(url.pathname);
    const allow=['setup.js','setup.css','import.js','netscope.css','InterVariable.woff2'];
    if(!allow.includes(name)){res.writeHead(404);res.end();return;}
    const file=path.join(name.startsWith('setup.')||name==='import.js'?setup:theme,'www/luci-static/netscope',name);
    if(!fs.existsSync(file)){res.writeHead(404);res.end();return;}
    res.setHeader('Content-Type',name.endsWith('.css')?'text/css':name.endsWith('.js')?'text/javascript':'font/woff2');res.end(fs.readFileSync(file));return;
  }
  let html=read(path.join(setup,'usr/lib/lua/luci/view/netscope/setup.htm'))
    .replace(/<%=url\('admin','services','netscope_setup'\)%>/g,'/fixture-api')
    .replace(/<%=token%>/g,'fixture-not-a-secret')
    .replace(/<%=url\('admin','status','netscope'\)%>/g,'#')
    .replace(/<%[\s\S]*?%>/g,'');
  const frame=url.searchParams.get('frame');
  if(frame){html='<iframe title="Мобильная версия" src="/?embedded=1" style="width:'+ (frame==='mobile'?390:820)+'px;height:1100px;border:1px solid #555"></iframe>';}
  const embedded=url.searchParams.has('embedded');
  const shell=embedded||frame?'':'<aside class="preview-sidebar"><b>NETSCOPE</b><small>На базе QWRT R26.2.2<br>для Xiaomi BE7000</small><span>Обзор</span><span>Wi-Fi</span><span>Интерфейсы</span><span>AmneziaWG</span><span>NETSCOPE</span><strong>Быстрая настройка VPN</strong><small>ВСЕ НАСТРОЙКИ</small><span>Состояние</span><span>Система</span><span>Службы</span><span>VPN</span><span>Сеть</span></aside>';
  res.setHeader('Content-Type','text/html; charset=utf-8');
  res.end('<!doctype html><html lang="ru"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>NETSCOPE · Quick Setup preview</title><link rel="stylesheet" href="/luci-static/netscope/netscope.css"><style>@font-face{font-family:Inter;src:url(/luci-static/netscope/InterVariable.woff2)}body{margin:0;background:#1e1e1e;font:14px/1.5 Inter,Arial,sans-serif;color:#f5f5f5}.preview-sidebar{position:fixed;inset:0 auto 0 0;width:252px;background:#2c2c2c;padding:24px;box-sizing:border-box;display:flex;flex-direction:column;gap:26px;font-size:13px}.preview-sidebar b{font-size:24px;color:#cff7d3}.preview-sidebar small{font-size:10px;color:#aaa}.preview-sidebar strong{background:#cff7d3;color:#18291c;padding:14px 10px;border-radius:8px}.preview-main{padding:24px 32px;margin-left:'+(shell?'252px':'0')+'}.fixture-label{font-size:11px;color:#acb9ad;margin:0 0 12px}@media(max-width:992px){.preview-sidebar{display:none}.preview-main{margin-left:0;padding:18px 14px}}</style><body class="netscope logged-in">'+shell+'<main class="preview-main"><p class="fixture-label">Локальный макет · демонстрационные данные · без доступа к роутеру</p>'+html+'</main></body></html>');
});
server.listen(4187,'127.0.0.1',()=>console.log('NETSCOPE preview: http://127.0.0.1:4187/'));
