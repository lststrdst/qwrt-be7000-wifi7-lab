/* Pure, bounded importer. No requests, storage, activation or DOM access. */
(function(root,factory){'use strict';const api=factory();if(typeof module==='object'&&module.exports)module.exports=api;else root.NetscopeImport=api;})(globalThis,function(){
 'use strict';
 const MAX=65535, LIMIT=100;
 const need=(ok,message)=>{if(!ok)throw Error(message);};
 const clean=value=>String(value||'').replace(/[\x00-\x1f\x7f\u202a-\u202e\u2066-\u2069]/g,'').slice(0,100);
 function text(value){need(typeof value==='string'&&value.length<=MAX&&new TextEncoder().encode(value).length<=MAX,'Размер импорта — не более 64 КБ');return value.trim();}
 function url(value){try{return new URL(value);}catch(_){throw Error('Некорректная ссылка');}}
 function subscription(value){
  let source=text(value);if(source.startsWith('happ'+':'+'//add/')){source=source.slice(11);if(!source.startsWith('https://'))try{source=decodeURIComponent(source);}catch(_){throw Error('Некорректная ссылка Happ');}}
  if(!/^https?:\/\//i.test(source))return null;
  const u=url(source);need(u.protocol==='https:'&&!u.username&&!u.password&&!u.hash&&(!u.port||u.port==='443')&&source.length<=4096,'Подписка: только HTTPS, порт 443, без логина в адресе и фрагмента');return u.href;
 }
 function vless(source){
  const u=url(source),q=u.searchParams,keys=[...q.keys()];
  need(new Set(keys).size===keys.length,'Повторяющиеся параметры VLESS');
  const allowed=new Set(['encryption','security','type','flow','sni','fp','alpn','pbk','sid','spx','path','host','mode','serviceName','authority','headerType']);
  need(keys.every(k=>allowed.has(k)),'Эта ссылка использует дополнительные параметры. Импортируйте исходящий JSON, чтобы их не потерять');
  let id;try{id=decodeURIComponent(u.username);}catch(_){throw Error('Некорректный идентификатор VLESS');}
  need(/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(id)&&!u.password,'Нужен UUID узла VLESS');
  need(/^[a-z0-9.-]+$/i.test(u.hostname)&&Number(u.port)>=1&&Number(u.port)<=65535,'Нужны сервер IPv4/DNS и порт VLESS');
  need((!u.pathname||u.pathname==='/')&&!/[\x00-\x20\x7f]/.test(source),'Некорректный адрес VLESS');
  need(!q.has('encryption')||q.get('encryption')==='none','Для этой версии мастера нужен VLESS encryption=none');
  const security=q.get('security'),network=q.get('type')||'tcp',flow=q.get('flow')||'';
  need(['tls','reality'].includes(security),'Для VLESS требуется TLS или Reality');
  need(['tcp','raw','ws','grpc','xhttp'].includes(network),'Транспорт VLESS пока не поддерживается');
  for(const key of ['path','host'])need(!q.has(key)||['ws','xhttp'].includes(network),'Параметры транспорта не соответствуют выбранному типу');
  for(const key of ['serviceName','authority'])need(!q.has(key)||network==='grpc','Параметры gRPC требуют type=grpc');
  need(!q.has('mode')||['grpc','xhttp'].includes(network),'Параметр mode не поддерживается для этого транспорта');
  for(const key of ['pbk','sid','spx'])need(!q.has(key)||security==='reality','Параметры Reality требуют security=reality');
  need(!q.has('alpn')||security==='tls','ALPN Reality требует ручной проверки исходящего JSON');
  need(!flow||flow==='xtls-rprx-vision','Неподдерживаемый flow VLESS');need(!flow||['tcp','raw'].includes(network),'Vision требует TCP/RAW');
  need(!q.has('headerType')||q.get('headerType')==='none','TCP headerType не поддерживается');
  const stream={network,security},tls={};
  if(q.has('sni'))tls.serverName=q.get('sni');if(q.has('fp'))tls.fingerprint=q.get('fp');
  if(security==='reality'){
   need(/^[\w-]{43}$/.test(q.get('pbk')||''),'Для Reality нужен public key');need(/^(?:[a-f0-9]{2}){0,8}$/i.test(q.get('sid')||''),'Некорректный short ID Reality');
   tls.publicKey=q.get('pbk');tls.shortId=q.get('sid')||'';if(q.has('spx'))tls.spiderX=q.get('spx');stream.realitySettings=tls;
  }else{if(q.has('alpn'))tls.alpn=q.get('alpn').split(',');stream.tlsSettings=tls;}
  if(network==='ws')stream.wsSettings={path:q.get('path')||'/',...(q.has('host')?{headers:{Host:q.get('host')}}:{})};
  if(network==='grpc'){
   need(!q.has('mode')||['gun','multi'].includes(q.get('mode')),'Неподдерживаемый режим gRPC');
   stream.grpcSettings={serviceName:q.get('serviceName')||'',multiMode:q.get('mode')==='multi',...(q.has('authority')?{authority:q.get('authority')}:{})};
  }
  if(network==='xhttp'){
   need(!q.has('mode')||['auto','packet-up','stream-up','stream-one'].includes(q.get('mode')),'Неподдерживаемый режим XHTTP');
   stream.xhttpSettings={path:q.get('path')||'/',mode:q.get('mode')||'auto',...(q.has('host')?{host:q.get('host')}:{})};
  }
  const user={id,encryption:'none'};if(flow)user.flow=flow;
  return {protocol:'vless',settings:{vnext:[{address:u.hostname,port:Number(u.port),users:[user]}]},streamSettings:stream};
 }
 function parse(value){
  let source=text(value);need(!subscription(source),'Нажмите «Загрузить и разобрать» для HTTPS-подписки');
  const nodes=[],warnings=[],seen=new Set();let visited=0;
  function add(kind,payload,label){
   need(payload.length<=12000,'Узел больше 12 КБ: используйте отдельный упрощённый профиль');
   const key=kind+payload;if(seen.has(key))return;need(nodes.length<LIMIT,'В подписке больше 100 узлов — экспортируйте нужную часть');seen.add(key);
   nodes.push({kind,payload,label:clean(label)||({vless:'VLESS',hy2:'Hysteria 2',mieru:'Mieru'}[kind]+' · узел '+(nodes.length+1))});
  }
  function visit(item,label,depth=0){
   need(++visited<=1000&&depth<=6,'Слишком сложная структура подписки');
   if(Array.isArray(item)){for(const value of item)visit(value,label,depth+1);return;}
   if(typeof item==='string'){
    const s=item.trim();if(!s)return;
    if(s.startsWith('vless'+':'+'//')){let name='';try{name=decodeURIComponent(url(s).hash.slice(1));}catch(_){throw Error('Некорректное имя узла');}add('vless',JSON.stringify(vless(s)),name||label);}
    else if(/^(hysteria2|hy2|mierus?)\:\/\//.test(s)){
     need(s.length<=12000&&!/[\s\x00-\x1f\x7f]/.test(s),'Некорректная ссылка узла');
     const kind=/^mieru/.test(s)?'mieru':'hy2';let name='';try{name=decodeURIComponent(s.split('#')[1]||'');}catch(_){throw Error('Некорректное имя узла');}add(kind,s,name||label);
    }else warnings.push('Неподдерживаемая строка пропущена');return;
   }
   if(!item||typeof item!=='object'){warnings.push('Неподдерживаемый элемент пропущен');return;}
   const name=typeof item.remarks==='string'?item.remarks:label;
   if(Array.isArray(item.outbounds)){warnings.push('Из полного профиля взяты только поддерживаемые исходящие узлы. DNS, inbound и маршруты приложения не импортируются');visit(item.outbounds,name,depth+1);return;}
   if(Array.isArray(item.configs)){visit(item.configs,name,depth+1);return;}
   if(item.protocol==='vless'||item.protocol==='hysteria'){
    need(!item.proxySettings&&!item.streamSettings?.sockopt,'Цепочки proxySettings/sockopt требуют ручной настройки');
    // Keep native transport options intact; authoritative validation happens on the router.
    const out={protocol:item.protocol,settings:item.settings,streamSettings:item.streamSettings};
    add(item.protocol==='vless'?'vless':'hy2',JSON.stringify(out),name||clean(item.tag));return;
   }
   warnings.push('Неподдерживаемый протокол пропущен');
  }
  if(!source.startsWith('{')&&!source.startsWith('[')&&!source.includes('://')){
   const packed=source.replace(/\s/g,'');need(/^[A-Za-z0-9+/_-]+={0,2}$/.test(packed),'Нужна ссылка, список ссылок или JSON-подписка');
   try{source=text(new TextDecoder('utf-8',{fatal:true}).decode(Uint8Array.from(atob(packed.replace(/-/g,'+').replace(/_/g,'/')),c=>c.charCodeAt(0))));}catch(_){throw Error('Не удалось прочитать base64-подписку');}
  }
  if(source.startsWith('{')||source.startsWith('[')){let value;try{value=JSON.parse(source);}catch(_){throw Error('JSON подписки повреждён');}visit(value);}
  else for(const line of source.split(/\r?\n/))visit(line);
  need(nodes.length,'В импорте нет поддерживаемых узлов VLESS, HY2 или Mieru');return {nodes,warnings:[...new Set(warnings)]};
 }
 return {parse,subscription,MAX};
});
