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
 const purpose={wg:'Удалённый доступ к домашней сети',awg:'Удалённый доступ домой через AmneziaWG v1',vless:'Исходящее подключение через VLESS / Xray',mieru:'Исходящий канал и UDP-резерв',hy2:'Hysteria 2 — отдельный UDP-канал'};
 let imported=[];
 function clearImport(){imported=[];el('import-source').value='';el('import-file').value='';el('import-nodes').replaceChildren();el('import-result').hidden=true;el('import-use').disabled=true;el('import-warnings').replaceChildren();}
 function clearSecrets(){clearImport();el('profile').value='';el('hy2-uri').value='';el('mieru-uri').value='';el('mieru-user').value='';el('mieru-password').value='';}
 el('import-clear').onclick=()=>{clearImport();el('import-status').textContent='Импорт очищен. Сохранённые профили не затронуты.';};
 el('import-nodes').onchange=()=>{el('import-use').disabled=el('import-nodes').value==='';};
 async function importSource(source){
  if(busy)return;busy=true;el('import-parse').disabled=true;el('import-file').disabled=true;el('prepare').disabled=true;el('import-use').disabled=true;error('');
  try{
   const parser=window.NetscopeImport;if(!parser)throw Error('Модуль импорта не загрузился. Обновите страницу.');
   const remote=parser.subscription(source);if(remote){if(!window.confirm('Загрузить подписку с указанного HTTPS-сервера через роутер? VPN и маршруты не изменятся.'))return;el('import-status').textContent='Загружаю подписку…';source=(await post('subscription',{url:remote})).content;}
   const result=parser.parse(source);clearImport();imported=result.nodes;const select=el('import-nodes');select.append(new Option('Выберите узел…',''));imported.forEach((node,i)=>select.append(new Option(node.label+' · '+protocolName(node),String(i))));
   list('import-warnings',result.warnings);el('import-result').hidden=false;el('import-status').textContent='Найдено узлов: '+imported.length+'. Выберите один для подготовки.';select.focus();
  }catch(e){clearImport();el('import-status').textContent='Импорт не выполнен. Сеть не изменена.';error(e.message);}
  finally{busy=false;el('import-parse').disabled=false;el('import-file').disabled=false;el('prepare').disabled=false;el('import-use').disabled=el('import-nodes').value==='';}
 }
 el('import-parse').onclick=()=>importSource(el('import-source').value);
 el('import-file').onchange=async()=>{const file=el('import-file').files[0];if(!file)return;if(file.size>65535){error('Размер файла — не более 64 КБ');el('import-file').value='';return;}try{await importSource(await file.text());}catch(_){error('Не удалось прочитать файл');}};
 el('import-use').onclick=()=>{if(busy||el('import-nodes').value==='')return;const node=imported[Number(el('import-nodes').value)];if(!node)return;clearSecrets();el('kind').value=node.kind;el('kind').onchange();el({vless:'profile',hy2:'hy2-uri',mieru:'mieru-uri'}[node.kind]).value=node.payload;el('import-status').textContent='Узел выбран. Нажмите «Подготовить конфигурацию» ниже — затем будет проверка перед включением.';el('prepare').scrollIntoView({block:'center'});el('prepare').focus();};
 window.addEventListener('pagehide',clearSecrets);
 const scenarioButtons=Array.from(root.querySelectorAll('button[data-scenario]'));
 for(const button of scenarioButtons)button.addEventListener('click',()=>{if(busy)return;el('kind').value={home:'wg',vpn:'vless',voice:'hy2'}[button.dataset.scenario];el('kind').onchange();el(button.dataset.scenario==='home'?'form':'import').scrollIntoView({block:'start',behavior:'auto'});});
 const protocolButtons=Array.from(el('protocols').querySelectorAll('button[data-kind]'));
 for(const button of protocolButtons)button.addEventListener('click',()=>{if(busy)return;el('kind').value=button.dataset.kind;el('kind').onchange();});
 el('protocols').hidden=false;root.classList.add('nsq-enhanced');
 function metric(name,value){el(name).textContent=typeof value==='number'&&Number.isFinite(value)?value.toLocaleString('ru-RU',{maximumFractionDigits:1}):'—';}
 async function loadDrafts(){
  const target=el('drafts'),value=await api('drafts');target.replaceChildren();el('profile-count').textContent=String((value.drafts||[]).length);
  if(!(value.drafts||[]).length){const empty=document.createElement('div');empty.className='nsq-empty';empty.textContent='Пока нет профилей. Подготовьте первую конфигурацию в форме выше — подключение ещё не запустится.';target.append(empty);return;}
  for(const draft of value.drafts){
   const card=document.createElement('div');card.className='nsq-draft';
   const identity=document.createElement('div'),heading=document.createElement('div');heading.className='nsq-draft-heading';
   const title=document.createElement('h3');title.textContent=protocolName(draft);
   const badge=document.createElement('span');badge.className='nsq-badge';badge.textContent=draft.active?'Активен':draft.pending?'Ожидает подтверждения':draft.state==='TEMPLATE'?'Шаблон':'Черновик';heading.append(title,badge);
   const meta=document.createElement('p');meta.className='nsq-draft-meta';meta.textContent=draft.created+' · '+draft.id+(draft.listen_port?' · UDP '+draft.listen_port:'');
   const note=document.createElement('p');note.textContent=draft.note||'';
   const output=document.createElement('div');output.hidden=true;output.className='ns-setup-draft-output';
   const controls=document.createElement('div');controls.className='ns-setup-button-row ns-setup-draft-actions';
   if(draft.active){const name=protocolName(draft);controls.append(action('Выключить '+name,async()=>{if(!window.confirm('Выключить отдельный профиль '+name+'? Другие VPN, L2TP и маршруты не изменятся.'))return;await post('deactivate',{draft:draft.id});await loadDrafts();}));}
   else controls.append(action('Проверить и подключить',async()=>{const report=await post('preflight',{draft:draft.id});output.replaceChildren();const status=document.createElement('strong');status.textContent=report.ready?(report.activation_supported?'Проверка пройдена · доступно явное включение':'Проверка пройдена · диспетчер включения недоступен'):'Проверка заблокировала включение';const checks=document.createElement('ul');for(const text of report.checks||[])checks.append(Object.assign(document.createElement('li'),{textContent:text}));const rollback=document.createElement('p');rollback.textContent='Порядок отката: '+(report.rollback||[]).join(' → ');const note=document.createElement('p');note.textContent=report.note||'';output.append(status,checks,rollback,note);if(report.ready&&report.activation_supported){const name=protocolName(draft),activate=action('Включить '+name,async()=>{if(!window.confirm('Включить отдельный профиль '+name+'? Default route, DNS, UCI и существующие VPN не изменяются.'))return;await post('activate',{draft:draft.id});await loadDrafts();});const row=document.createElement('div');row.className='ns-setup-button-row';row.append(activate);output.append(row);}output.hidden=false;}));
   if(!draft.active&&!draft.pending)controls.append(action('Удалить профиль',async()=>{if(!window.confirm('Удалить этот неактивный приватный черновик с USB-накопителя роутера?'))return;await post('delete',{draft:draft.id});await loadDrafts();}));
   identity.append(heading);
   const details=document.createElement('details');details.className='nsq-details';const summary=document.createElement('summary');summary.textContent='Подробности профиля';details.append(summary,meta,note);
   card.append(identity,controls,details,output);target.append(card);
  }
 }
 el('kind').onchange=()=>{const kind=el('kind').value;
  el('import').hidden=['wg','awg'].includes(kind);
  for(const name of ['tunnel','vless','mieru','hy2']){const enabled=name==='tunnel'?(kind==='wg'||kind==='awg'):name===kind;el(name).hidden=!enabled;el(name).querySelectorAll('input,select,textarea').forEach(field=>field.disabled=!enabled);}
  for(const button of protocolButtons)button.setAttribute('aria-pressed',String(button.dataset.kind===kind));
  for(const button of scenarioButtons)button.setAttribute('aria-pressed',String(button.dataset.scenario===(['wg','awg'].includes(kind)?'home':kind==='hy2'?'voice':'vpn')));
  el('purpose').textContent=purpose[kind]||'Настройка подключения';
  el('result').hidden=true;error('');
 };el('kind').onchange();
 el('form').onsubmit=async event=>{event.preventDefault();if(busy)return;busy=true;el('prepare').disabled=true;error('');el('result').hidden=true;el('kind').disabled=true;protocolButtons.forEach(button=>button.disabled=true);
  try{const params=new URLSearchParams(new FormData(el('form')));params.set('kind',el('kind').value);params.set('token',root.dataset.token);const v=await api('prepare',params);clearSecrets();el('result-title').textContent=v.state==='TEMPLATE'?'Шаблон · требуется сервер':'Черновик подготовлен · не активен';el('note').textContent=v.note;
   list('plan-list',v.planned_changes);list('check-list',v.checks);el('plan').hidden=!(v.planned_changes?.length||v.checks?.length);
   const downloads=el('downloads');downloads.replaceChildren();for(const file of [...(v.files||[]),'plan.json']){if(!['server.conf','client.conf','xray.json','mieru.json','hysteria.yaml','plan.json'].includes(file))continue;const a=document.createElement('a');a.textContent=file==='plan.json'?'Скачать обезличенный план':'Скачать '+file;a.href=root.dataset.api+'/download?'+new URLSearchParams({draft:v.id,file});a.download='';a.className='cbi-button cbi-button-link';downloads.append(a,document.createTextNode(' '));}el('result').hidden=false;await loadDrafts();}
  catch(e){error(e.message);}finally{busy=false;el('prepare').disabled=false;el('kind').disabled=false;protocolButtons.forEach(button=>button.disabled=false);}
 };
 async function loadStatus(){const v=await api('status');if(!el('lan').value)el('lan').value=v.lan||'';if(!touched.port)el('port').value=v.recommended_port||51820;if(!touched.subnet)el('subnet').value=v.recommended_tunnel||'10.77.0.0/24';el('port-note').textContent='Предложенный свободный UDP-порт: '+(v.recommended_port||51820)+'. Он будет проверен повторно при подготовке.';const storageReady=!!(v.storage?.mounted&&v.storage?.writable);
  el('status').textContent=storageReady?'USB доступен. Приватные профили остаются на роутере.':'Нужен доступный для записи USB-накопитель.';
  const chips=el('runtime-chips');chips.replaceChildren();for(const [label,ready] of [['USB',storageReady],['Диспетчер',v.tools?.manager],['WireGuard',v.tools?.wg],['AmneziaWG',v.tools?.awg],['Xray',v.tools?.xray],['Mieru',v.tools?.mieru],['Mieru TUN',v.tools?.hev],['HY2',v.tools?.hysteria]]){const chip=document.createElement('span');chip.dataset.ready=String(!!ready);chip.textContent=label+' · '+(ready?'готов':'нужен компонент');chips.append(chip);}
  if(!storageReady)el('components').open=true;
  el('runtime-mieru').hidden=!!v.tools?.mieru||!v.tools?.mieru_installer;el('runtime-hev').hidden=!!v.tools?.hev||!v.tools?.hev_installer;el('runtime-hy2').hidden=!!v.tools?.hysteria||!v.tools?.hysteria_installer;el('runtime-actions').hidden=el('runtime-mieru').hidden&&el('runtime-hev').hidden&&el('runtime-hy2').hidden;}
 async function loadVoice(){const v=await api('voice_status'),channel=v.mode==='mieru-tun'?'Mieru reserve':'HY2 primary';el('voice-status').textContent=!v.available?'Маршрутизация звонков не установлена':v.active?(v.healthy&&v.upstream_probe?'Включена · '+channel+' · UDP-канал исправен':v.healthy?'Включена · '+channel+' · ожидается очередная UDP-проба':'Аварийно отключается'):'Выключена · сетей Telegram: '+(v.telegram_nets||0)+' · голосовых сетей Discord: '+(v.discord_nets||0)+' · IP Discord в DNS-кэше: '+(v.discord_ips||0);if(v.active&&v.mode==='hy2-tun')el('voice-status').textContent+=' · резерв Mieru '+(v.fallback_ready?'готов':'не готов');el('voice-start').disabled=!v.available||!v.hy2||v.active||(v.telegram_nets||0)<6;el('voice-stop').disabled=!v.active;el('voice-autostart').disabled=!v.autostart&&(!v.hy2||!v.healthy);el('voice-autostart').dataset.enabled=String(!!v.autostart);el('voice-autostart').textContent=v.autostart?'Выключить автозапуск':'Включить автозапуск';el('voice-detail-status').textContent=el('voice-status').textContent;
  el('voice-status').textContent=!v.available?'Не настроен':v.active?(v.healthy?'● Маршрут включён':'Восстанавливаем соединение…'):'Маршрут выключен';
  el('voice-status').dataset.state=v.active&&v.healthy?'ok':v.active?'warning':'idle';
  el('voice-channel').textContent=!v.available?'Модуль не установлен':!v.active?'Маршрут выключен':v.mode==='mieru-tun'?'Mieru → резервный канал':'HY2 → основной канал';
  el('voice-reserve').textContent=v.fallback_ready?'Mieru · резерв готов':'Mieru · резерв не готов';
  el('voice-start').hidden=!!v.active;el('voice-stop').hidden=!v.active;
  return v;}
 async function loadVoiceTelemetry(){const v=await api('voice_telemetry');metric('latency',v.available?v.latency_ms:null);metric('jitter',v.available?v.jitter_ms:null);metric('loss',v.available?v.loss_percent:null);const endpoint=v.endpoint?`${v.endpoint.device||v.endpoint.client} → ${v.endpoint.destination}:${v.endpoint.port} (${v.endpoint.service})`:'активного голосового endpoint нет';el('voice-health').textContent=!v.available?'Модуль телеметрии не установлен':`Контрольный UDP: ${v.latency_ms??'—'} мс · jitter ${v.jitter_ms??'—'} мс · потери проб ${v.loss_percent??'—'}% · ${endpoint}. Окно: ${v.window||0} проб.`;}
 async function loadL2tp(){const v=await api('l2tp_status');el('l2tp-status').dataset.state=v.enabled&&v.healthy?'ok':v.enabled?'warning':'idle';el('l2tp-detail-status').textContent=!v.available?'Watchdog не установлен':!v.enabled?'Выключен · приватная конфигурация не задана':`${v.healthy?'Исправен':'Ожидает восстановления'} · ${v.interface||'PPP'} · MTU ${v.mtu||'—'} · MSS ${v.mss||'—'} · переподключений ${v.reconnects||0}. ${v.message||''}`;el('l2tp-status').textContent=!v.available?'Восстановление не настроено':!v.enabled?'Автовосстановление выключено':v.healthy?'● Проверка соединения: всё в порядке':'Восстанавливаем соединение…';}
 el('install-hy2').addEventListener('click',async()=>{if(!window.confirm('Скачать официальную Hysteria 2 v2.11.0 ARM64 на USB и проверить SHA-256? VPN и маршруты не будут запущены.'))return;const button=el('install-hy2');button.disabled=true;error('');el('install-hy2-note').textContent='Скачивание и проверка…';try{const params=new URLSearchParams({token:root.dataset.token});const v=await api('install_hysteria',params,125000);el('install-hy2-note').textContent=v.note;await loadStatus();}catch(e){error(e.message);el('install-hy2-note').textContent='Установка не выполнена; существующие VPN не изменялись.';}finally{button.disabled=false;}});
 el('install-mieru').addEventListener('click',async()=>{if(!window.confirm('Скачать официальный Mieru v3.36.1 ARM64 на USB и проверить SHA-256? Профиль, процесс и маршруты не будут запущены.'))return;const button=el('install-mieru');button.disabled=true;error('');el('install-mieru-note').textContent='Скачивание и проверка…';try{const params=new URLSearchParams({token:root.dataset.token});const v=await api('install_mieru',params,125000);el('install-mieru-note').textContent=v.note;await loadStatus();}catch(e){error(e.message);el('install-mieru-note').textContent='Установка не выполнена; существующие VPN не изменялись.';}finally{button.disabled=false;}});
 el('install-hev').addEventListener('click',async()=>{if(!window.confirm('Скачать официальный hev-socks5-tunnel 2.17.0 ARM64 на USB и проверить SHA-256? Интерфейс, процесс и маршруты не будут созданы.'))return;const button=el('install-hev');button.disabled=true;error('');el('install-hev-note').textContent='Скачивание и проверка…';try{const params=new URLSearchParams({token:root.dataset.token});const v=await api('install_hev',params,125000);el('install-hev-note').textContent=v.note;await loadStatus();}catch(e){error(e.message);el('install-hev-note').textContent='Установка не выполнена; маршруты и VPN не изменялись.';}finally{button.disabled=false;}});
 el('voice-update').addEventListener('click',async()=>{const button=el('voice-update');button.disabled=true;error('');el('voice-note').textContent='Сверяю два независимых источника и проверяю CIDR…';try{const params=new URLSearchParams({token:root.dataset.token});const v=await api('voice_update',params,125000);el('voice-note').textContent=v.note;await loadVoice();}catch(e){error(e.message);el('voice-note').textContent='Старый проверенный набор не изменён.';}finally{button.disabled=false;}});
 el('voice-start').addEventListener('click',async()=>{if(!window.confirm('Направить только Telegram relay и Discord voice UDP через HY2, используя активный Mieru как резерв при наличии? DNS перезапустится один раз; default route, игры и L2TP не изменятся.'))return;const button=el('voice-start');button.disabled=true;error('');try{const v=await post('voice_activate',{});el('voice-note').textContent=v.note;await loadVoice();}catch(e){error(e.message);}finally{button.disabled=false;}});
 el('voice-stop').addEventListener('click',async()=>{const button=el('voice-stop');button.disabled=true;error('');try{const v=await post('voice_deactivate',{});el('voice-note').textContent=v.note;await loadVoice();}catch(e){error(e.message);}finally{button.disabled=false;}});
 el('voice-autostart').addEventListener('click',async()=>{const button=el('voice-autostart'),enable=button.dataset.enabled!=='true';if(!window.confirm(enable?'Включить безопасный автозапуск текущего HY2, активного Mieru-резерва и голосового маршрута после перезагрузки?':'Выключить автозапуск и снять голосовой маршрут? Вручную запущенные VPN останутся активны.'))return;button.disabled=true;error('');try{const v=await post('voice_autostart',{enabled:enable?'1':'0'});el('voice-note').textContent=v.note;}catch(e){error(e.message);}finally{await loadVoice().catch(()=>{});}});
 function telemetryUnavailable(){for(const name of ['latency','jitter','loss'])metric(name,null);el('voice-health').textContent='Нет свежих данных. Проверяю связь с роутером…';}
 function voiceUnavailable(){el('voice-status').textContent='Не удалось обновить состояние маршрута';el('voice-status').dataset.state='warning';el('voice-detail-status').textContent='Нет свежих данных маршрута';el('voice-channel').textContent='Состояние неизвестно';el('voice-reserve').textContent='Данные резерва не обновлены';for(const name of ['voice-start','voice-stop','voice-autostart'])el(name).disabled=true;}
 function l2tpUnavailable(){el('l2tp-status').textContent='Нет свежих данных L2TP';el('l2tp-status').dataset.state='warning';el('l2tp-detail-status').textContent='Не удалось обновить проверку соединения';}
 loadStatus().catch(e=>{el('status').textContent='Не удалось проверить USB и компоненты. Обновите страницу после восстановления связи.';el('components').open=true;error(e.message);});
 loadDrafts().catch(e=>{el('drafts').textContent='Не удалось загрузить подключения. Обновите страницу после восстановления связи.';error(e.message);});
 loadVoice().catch(e=>{voiceUnavailable();error(e.message);});
 loadVoiceTelemetry().catch(e=>{telemetryUnavailable();error(e.message);});
 loadL2tp().catch(e=>{l2tpUnavailable();error(e.message);});
 setInterval(()=>{if(!document.hidden)loadVoiceTelemetry().catch(telemetryUnavailable);},3000);
 setInterval(()=>{if(!document.hidden){loadVoice().catch(voiceUnavailable);loadL2tp().catch(l2tpUnavailable);}},10000);
})();
