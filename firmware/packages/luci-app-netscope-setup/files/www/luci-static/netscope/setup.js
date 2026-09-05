'use strict';
(()=>{
 const root=document.getElementById('netscope-setup');if(!root)return;
 const el=name=>document.getElementById('ns-setup-'+name);let busy=false;const touched={port:false,subnet:false};
 el('port').addEventListener('input',()=>touched.port=true);el('subnet').addEventListener('input',()=>touched.subnet=true);
 async function api(kind,params,timeout=25000){
  const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),timeout);
  try{const r=await fetch(root.dataset.api+'/'+kind,{signal:controller.signal,credentials:'same-origin',cache:'no-store',...(params?{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:params}:{})});if(r.status===403)throw Error('Войдите в LuCI заново');if(!(r.headers.get('content-type')||'').includes('application/json'))throw Error('Сеанс завершён или мастер настройки недоступен');const v=await r.json();if(!r.ok)throw Error(v.error||'Запрос завершился ошибкой');return v;}
  catch(e){if(e.name==='AbortError')throw Error('Истекло время ожидания. Проверьте сохранённые черновики: VPN не был включён.');throw e;}
  finally{clearTimeout(timer);}
 }
 const post=(kind,values)=>{const params=new URLSearchParams(values);params.set('token',root.dataset.token);return api(kind,params);};
 function error(message){el('error').hidden=!message;el('error').textContent=message||'';}
 function list(name,items){const target=el(name);target.replaceChildren();for(const item of items||[])target.append(Object.assign(document.createElement('li'),{textContent:item}));}
 function action(label,handler){const button=document.createElement('button');button.type='button';button.className='cbi-button cbi-button-action';button.textContent=label;button.addEventListener('click',async()=>{button.disabled=true;error('');try{await handler(button);}catch(e){error(e.message);}finally{button.disabled=false;}});return button;}
 function protocolName(draft){return draft.protocol||({wg:'WireGuard',awg:'AmneziaWG',vless:'VLESS / Xray',mieru:'Mieru',hy2:'Hysteria 2'}[draft.kind])||'VPN';}
 async function loadDrafts(){
  const target=el('drafts'),value=await api('drafts');target.replaceChildren();
  if(!(value.drafts||[]).length){target.textContent='Сохранённых черновиков нет.';return;}
  for(const draft of value.drafts){
   const card=document.createElement('div');card.className='cbi-section-node';
   const title=document.createElement('h3');title.textContent=(draft.protocol||draft.kind||'VPN')+' · '+(draft.active?'АКТИВЕН':draft.pending?'ОЖИДАЕТ ПОДТВЕРЖДЕНИЯ':draft.state==='TEMPLATE'?'ШАБЛОН':'ЧЕРНОВИК');
   const meta=document.createElement('p');meta.textContent=draft.created+' · '+draft.id+(draft.listen_port?' · UDP '+draft.listen_port:'');
   const note=document.createElement('p');note.textContent=draft.note||'';
   const output=document.createElement('div');output.hidden=true;
   const controls=document.createElement('p');
   if(draft.active){const name=protocolName(draft);controls.append(action('Выключить '+name,async()=>{if(!window.confirm('Выключить отдельный профиль '+name+'? Другие VPN, L2TP и маршруты не изменятся.'))return;await post('deactivate',{draft:draft.id});await loadDrafts();}));}
   else controls.append(action('Запустить предварительную проверку',async()=>{const report=await post('preflight',{draft:draft.id});output.replaceChildren();const status=document.createElement('strong');status.textContent=report.ready?(report.activation_supported?'Проверка пройдена · доступно явное включение':'Проверка пройдена · диспетчер включения недоступен'):'Проверка заблокировала включение';const checks=document.createElement('ul');for(const text of report.checks||[])checks.append(Object.assign(document.createElement('li'),{textContent:text}));const rollback=document.createElement('p');rollback.textContent='Порядок отката: '+(report.rollback||[]).join(' → ');const note=document.createElement('p');note.textContent=report.note||'';output.append(status,checks,rollback,note);if(report.ready&&report.activation_supported){const name=protocolName(draft),activate=action('Включить '+name,async()=>{if(!window.confirm('Включить отдельный профиль '+name+'? Default route, DNS, UCI и существующие VPN не изменяются.'))return;await post('activate',{draft:draft.id});await loadDrafts();});const row=document.createElement('p');row.append(activate);output.append(row);}output.hidden=false;}));
   if(!draft.active&&!draft.pending)controls.append(document.createTextNode(' '),action('Удалить приватный черновик',async()=>{if(!window.confirm('Удалить этот неактивный приватный черновик с USB-накопителя роутера?'))return;await post('delete',{draft:draft.id});await loadDrafts();}));
   card.append(title,meta,note,controls,output);target.append(card);
  }
 }
 el('kind').onchange=()=>{const kind=el('kind').value;
  for(const name of ['tunnel','vless','mieru','hy2']){const enabled=name==='tunnel'?(kind==='wg'||kind==='awg'):name===kind;el(name).hidden=!enabled;el(name).querySelectorAll('input,select,textarea').forEach(field=>field.disabled=!enabled);}
  el('result').hidden=true;error('');
 };el('kind').onchange();
 el('form').onsubmit=async event=>{event.preventDefault();if(busy)return;busy=true;el('prepare').disabled=true;error('');el('result').hidden=true;el('kind').disabled=true;
  try{const params=new URLSearchParams(new FormData(el('form')));params.set('kind',el('kind').value);params.set('token',root.dataset.token);const v=await api('prepare',params);el('profile').value='';el('mieru-password').value='';el('hy2-uri').value='';el('result-title').textContent=v.state==='TEMPLATE'?'Шаблон · требуется сервер':'Черновик подготовлен · не активен';el('note').textContent=v.note;
   list('plan-list',v.planned_changes);list('check-list',v.checks);el('plan').hidden=!(v.planned_changes?.length||v.checks?.length);
   const downloads=el('downloads');downloads.replaceChildren();for(const file of [...(v.files||[]),'plan.json']){if(!['server.conf','client.conf','xray.json','mieru.json','hysteria.yaml','plan.json'].includes(file))continue;const a=document.createElement('a');a.textContent=file==='plan.json'?'Скачать обезличенный план':'Скачать '+file;a.href=root.dataset.api+'/download?'+new URLSearchParams({draft:v.id,file});a.download='';a.className='cbi-button cbi-button-link';downloads.append(a,document.createTextNode(' '));}el('result').hidden=false;await loadDrafts();}
  catch(e){error(e.message);}finally{busy=false;el('prepare').disabled=false;el('kind').disabled=false;}
 };
 async function loadStatus(){const v=await api('status');if(!el('lan').value)el('lan').value=v.lan||'';if(!touched.port)el('port').value=v.recommended_port||51820;if(!touched.subnet)el('subnet').value=v.recommended_tunnel||'10.77.0.0/24';el('port-note').textContent='Предложенный свободный UDP-порт: '+(v.recommended_port||51820)+'. Он будет проверен повторно при подготовке.';el('status').textContent='USB: '+(v.storage?.mounted&&v.storage?.writable?'готов':'требуется')+' · диспетчер: '+(v.tools?.manager?'готов':'не найден')+' · WireGuard: '+(v.tools?.wg?'готов':'не найден')+' · AmneziaWG: '+(v.tools?.awg?'готов':'не найден')+' · Xray: '+(v.tools?.xray?'готов':'не найден')+' · Mieru: '+(v.tools?.mieru?'готов':'не найден')+' · Hysteria 2: '+(v.tools?.hysteria?'готов':'не найден');el('runtime-actions').hidden=!!v.tools?.hysteria||!v.tools?.hysteria_installer;}
 el('install-hy2').addEventListener('click',async()=>{if(!window.confirm('Скачать официальную Hysteria 2 v2.11.0 ARM64 на USB и проверить SHA-256? VPN и маршруты не будут запущены.'))return;const button=el('install-hy2');button.disabled=true;error('');el('install-hy2-note').textContent='Скачивание и проверка…';try{const params=new URLSearchParams({token:root.dataset.token});const v=await api('install_hysteria',params,125000);el('install-hy2-note').textContent=v.note;await loadStatus();}catch(e){error(e.message);el('install-hy2-note').textContent='Установка не выполнена; существующие VPN не изменялись.';}finally{button.disabled=false;}});
 loadStatus().catch(e=>error(e.message));
 loadDrafts().catch(e=>error(e.message));
})();
