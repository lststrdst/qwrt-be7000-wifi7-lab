'use strict';
// Extends the existing panel, not a second application or API server.
(() => {
  const app=document.getElementById('ns-monitor')||document.getElementById('app');if(!app)return;
  const prefix=app.id==='ns-monitor'?'ns-':'', el=id=>app.querySelector('#'+prefix+id);
  const node=(tag,text,cls)=>{const e=document.createElement(tag);if(text!=null)e.textContent=String(text);if(cls)e.className=cls;return e;};
  const size=n=>Number.isFinite(Number(n))?(Number(n)/1e6).toLocaleString('ru-RU',{maximumFractionDigits:1})+' МБ':'—';
  const time=n=>n?new Date(n*1000).toLocaleString('ru-RU'):'—';
  const russianStatus={
    'NETSCOPE Docker runtime is stopped or unavailable':'Среда Docker NETSCOPE остановлена или недоступна',
    'Pinned ARM64 mitmproxy image missing':'Закреплённый ARM64-образ mitmproxy не найден',
    'Inspection CA is not prepared':'Центр сертификации анализа не подготовлен',
    'USB is not mounted':'USB-накопитель не смонтирован',
    'USB is not writable':'USB-накопитель недоступен для записи',
    'At least 230000 KiB available RAM required':'Требуется не менее 230000 КиБ свободной оперативной памяти',
    'Ready; IPv4 TCP/443 only. Private LAN/office destinations bypass inspection.':'Готово; только IPv4 TCP/443. Частные домашние и офисные адреса обходят анализ.',
    'HTTPS preflight has not completed. Interception remains disabled.':'Предварительная проверка HTTPS не завершена. Перехват остаётся выключенным.',
    'Passive br-lan capture; Qualcomm offload and switched L2 traffic can bypass it. Acceleration is unchanged.':'Пассивная запись br-lan: аппаратное ускорение Qualcomm и коммутируемый L2-трафик могут проходить мимо. Ускорение не изменено.',
    'Kernel has no seccomp and no swap accounting; memory limit only.':'В ядре нет seccomp и учёта swap; действует только ограничение памяти.',
    'Trust this CA only on devices you administer. Untrusted/pinned apps may fail.':'Доверяйте этому центру сертификации только на управляемых вами устройствах. Приложения с закреплением сертификата могут не работать.',
    'IPv6 and UDP/QUIC are not decrypted. No automatic certificate pinning or E2EE bypass.':'IPv6 и UDP/QUIC не расшифровываются. Обход закрепления сертификата и сквозного шифрования не выполняется.'
  };
  const ru=value=>russianStatus[value]||value;
  const base=app.dataset.capture;
  let status={},session='',mode='dns',cursor=0,rows=[],names=new Map(),polling=false,changing=false,viewGeneration=0,offset=0;
  async function api(kind,params={},post){
    const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),kind.startsWith('ca-')?25000:15000);
    try{
      const url=base+'/'+kind+(post?'':'?'+new URLSearchParams(params));
      const response=await fetch(url,{credentials:'same-origin',cache:'no-store',signal:controller.signal,...(post?{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({token:app.dataset.token,...params})}:{})});
      if(response.status===403||!(response.headers.get('content-type')||'').includes('application/json'))throw Error('Сеанс LuCI завершён. Обновите страницу и войдите снова.');
      const value=await response.json();if(!response.ok||(value.error&&!value.state))throw Error(value.error||'Ошибка роутера '+response.status);return value;
    }finally{clearTimeout(timer);}
  }
  const captureError=node('div',null,'notice error');captureError.id=prefix+'capture-error';captureError.hidden=true;captureError.setAttribute('role','alert');el('error').after(captureError);
  const notify=msg=>{captureError.hidden=!msg;captureError.textContent=msg||'';};
  const link=(kind,params,label)=>{const a=node('a',label);a.href=base+'/'+kind+'?'+new URLSearchParams(params);a.download='';return a;};
  function card(){
    el('capture-state').textContent=status.active?'ВКЛ':'ВЫКЛ';el('capture-toggle').textContent=status.active?'Выключить':'Включить';el('capture-toggle').disabled=changing;
    const c=status.counters||{},duration=status.active?Math.max(0,Math.floor(Date.now()/1000-status.started_at)):0;
    el('capture-summary').textContent=`${duration?duration+' с · ':''}${c.dns||0} DNS · ${c.http||0} HTTP · ${c.tls||0} TLS · расшифровано HTTPS: ${status.https_counters?.decrypted||0} · PCAP ${size(status.written||0)} · свободно ${size(status.storage?.free)}`;
    el('capture-summary').title=[ru(status.visibility),ru(status.error),status.decoder_backlog?`Очередь декодера ${size(status.decoder_backlog)}`:'',status.decoder_ring_loss?'Часть метаданных пакетов устарела до декодирования':''].filter(Boolean).join('\n');
    downloadCA.hidden=!status.proxy?.ca?.ready;
  }
  function details(value){
    el('detail-title').textContent='Инспектор записи';el('detail-subtitle').textContent='Записанные наблюдения · без догадок о расшифровке';el('details').replaceChildren();
    const pre=node('pre',JSON.stringify(value,null,2));el('details').append(pre);
  }
  // Owner requested unmasked inspection by default. API remains masked unless
  // this authenticated viewer explicitly sends reveal=1; logs stay payload-free.
  async function inspectHTTP(id,reveal=true){
    const selectedSession=session;const selectedMode=mode;const v=await api(mode==='https'?'https':'http',{session,id,reveal:reveal?'1':'0'});if(session!==selectedSession||mode!==selectedMode)return;
    details({id:v.id,time:time(v.timestamp),source:v.source,destination:v.destination,inspection:v.inspection,incomplete:v.incomplete,tls:v.tls,timing:v.timing,failure:v.failure});
    const target=el('details'),b=node('button',reveal?'Скрыть чувствительные значения':'Показать чувствительные значения');b.type='button';b.onclick=()=>inspectHTTP(id,!reveal).catch(e=>notify(e.message));target.append(b);
    for(const side of ['request','response']){
      const m=v[side];if(!m)continue;target.append(node('h3',side.toUpperCase()));
      const info={...m};delete info.text;target.append(node('pre',JSON.stringify(info,null,2)));
      if(m.text){let text=m.text;if(reveal&&m.content_type?.includes('json'))try{text=JSON.stringify(JSON.parse(text),null,2);}catch{}target.append(node('pre',text));}
      if(m.body_ref)target.append(link('body',{session,file:m.body_ref},'Скачать записанное тело (может содержать секреты)'));
    }
  }
  function render(){
    const filter=el('capture-search').value.trim().toLowerCase();const filtered=rows.filter(r=>JSON.stringify(r).toLowerCase().includes(filter)||(names.get(r.device||r.source)||'').toLowerCase().includes(filter));
    const list=el('capture-rows'),scroll=list.scrollTop;
    list.replaceChildren(...filtered.slice(-500).map(r=>{
      const b=node('button',null,'flow');b.type='button';
      const name=names.get(r.device||r.source)||r.device||r.source||'';
      if(mode==='sessions'){
        b.append(node('strong',r.id),node('span',`${r.state} · ${time(r.started_at)} · ${size(r.written)} · ${r.counters?.http||0} HTTP`));
        b.onclick=()=>openSession(r.id).catch(e=>notify(e.message));
      }else if(mode==='dns'){
        b.append(node('strong',`${name} → ${r.query} (${r.type})`),node('span',`${time(r.timestamp)} · ${r.response?'Ответ':'Запрос'} · ${(r.answers||[]).map(a=>a.value).join(', ')||'—'}`));b.onclick=()=>details(r);
      }else if(mode==='http'||mode==='https'){
        b.append(node('strong',`${name} · ${r.method} · ${r.host||r.destination}`),node('span',`${time(r.timestamp)} · ${r.status||'Нет ответа'} · ${r.inspection||'ОТКРЫТЫЙ HTTP'}`));b.onclick=()=>inspectHTTP(r.id).catch(e=>notify(e.message));
      }else if(mode==='tls'){
        b.append(node('strong',`${name} → ${r.sni||r.destination}`),node('span',`${time(r.timestamp)} · ClientHello · ЗАШИФРОВАНО`));b.onclick=()=>details(r);
      }else{
        b.append(node('strong',`${name} → ${r.destination}:${r.dport??''}`),node('span',`${r.protocol} · ${r.state} · ↑ ${size(r.tx_bytes)} ↓ ${size(r.rx_bytes)}`));b.onclick=()=>details(r);
      }
      return b;
    }));
    if(!filtered.length)list.append(node('p','В этом представлении нет записей. Полезная нагрузка TLS остаётся зашифрованной; трафик с аппаратным ускорением может отсутствовать.','empty'));
    list.scrollTop=scroll;
    el('capture-context').textContent=`${session||'Сессия не выбрана'} · ${mode} · загружено ${rows.length} (интерфейс хранит последние 500) · ${status.decoder_backlog?'очередь декодера '+size(status.decoder_backlog):'хранилище ограничено'}`;
  }
  async function openSession(id){
    const s=await api('session',{session:id});session=id;details(s.session);
    const actions=node('div',null,'lab-actions');
    for(const f of s.pcap||[])actions.append(link('pcap',{session:id,file:f.name},`${f.name} (${size(f.size)})`));
    actions.append(link('live',{session:id},'Экспортировать последний снимок соединений'));
    const del=node('button','Удалить сессию');del.type='button';del.disabled=status.active&&status.session===id;
    del.onclick=async()=>{if(!confirm(`Безвозвратно удалить сессию NETSCOPE ${id}? Её PCAP и тела HTTP восстановить нельзя.`))return;try{await api('delete',{session:id,confirm:id},true);session='';await load(true);}catch(e){notify(e.message);}};
    actions.append(del);el('details').append(actions);el('capture-context').textContent='Открыта '+id+' — выберите DNS, HTTP, TLS или сохранённые соединения. Запись не запускалась.';
  }
  async function load(reset=false){
    const generation=++viewGeneration;
    if(reset){cursor=0;offset=0;rows=[];}
    if(mode!=='sessions'&&!session)session=status.session||'';
    if(mode!=='sessions'&&!session){render();return;}
    let result;
    if(mode==='sessions')result=await api('sessions',{offset});
    else if(mode==='live')result=await api('live',{session});
    else result=await api(mode,{session,after:cursor,limit:100});
    if(generation!==viewGeneration)return;
    if(mode==='live'){rows=result.flows||[];names=new Map((result.devices||[]).map(d=>[d.ip,d.name]));el('capture-more').hidden=true;}
    else{rows=[...rows,...(result.items||[])].slice(-500);cursor=result.cursor||cursor;offset+=result.items?.length||0;el('capture-more').hidden=mode==='sessions'?offset>=result.total:!result.limited;}
    render();
  }
  async function startDialog(){
    const [settings,snapshot]=await Promise.all([api('settings'),fetch(app.dataset.api,{credentials:'same-origin',cache:'no-store'}).then(r=>{if(!r.ok)throw Error('Список устройств недоступен');return r.json();})]);
    const ds=snapshot.devices||[];names=new Map(ds.map(d=>[d.ip,d.name]));
    const dialog=node('dialog',null,'capture-dialog'),form=node('form');form.method='dialog';dialog.append(form);
    form.append(node('h2','Запустить запись трафика'),node('p','Записывайте только принадлежащие вам устройства или те, которыми вы имеете право управлять. PCAP и тела запросов могут содержать пароли и персональные данные.'));
    const scope=node('select');scope.setAttribute('aria-label','Устройства для записи');for(const [value,label] of [['all','Все устройства локальной сети'],['selected','Выбранные устройства']]){const opt=node('option',label);opt.value=value;scope.append(opt);}form.append(scope);
    const devices=node('div',null,'capture-device-picker');devices.hidden=true;const selected=[];
    for(const d of ds){const label=node('label'),input=node('input');input.type='checkbox';input.value=d.ip;label.append(input,node('span',`${d.name} (${d.ip})`));devices.append(label);selected.push(input);}form.append(devices);scope.onchange=()=>devices.hidden=scope.value!=='selected';
    const options={};for(const [key,label] of [['metadata','Метаданные соединений'],['dns','DNS'],['pcap','Полный PCAP'],['http','Анализ HTTP'],['https','Анализ HTTPS'],['quic','Блокировать QUIC во время анализа']]){
      const row=node('label'),input=node('input');input.type='checkbox';input.checked=key==='https'||key==='quic'?false:settings[key]!==false;input.disabled=(key==='https'&&!status.https_available)||key==='quic';options[key]=input;row.append(input,node('span',label));form.append(row);
    }
    options.https.onchange=()=>{options.quic.disabled=!options.https.checked;if(!options.https.checked)options.quic.checked=false;};
    form.append(node('p',ru(status.https_reason)||'HTTPS недоступен: требуется предварительная проверка Docker.','hint'));
    const quota=node('input'),chunk=node('input');quota.type=chunk.type='number';quota.value=settings.max_mb;quota.min=512;quota.max=64000;chunk.value=settings.chunk_mb;chunk.min=16;chunk.max=512;
    for(const [label,input] of [['Максимальный объём сессии (десятичные МБ)',quota],['Размер части PCAP (десятичные МБ)',chunk]]){const row=node('label');row.append(node('span',label),input);form.append(row);}
    form.append(node('p',`${status.storage?.path} · свободно ${size(status.storage?.free)}. Самые старые части PCAP перезаписываются. Журналы и тела HTTP также хранятся с ограничением. Даже без полного PCAP используется диагностическое кольцо PCAP по 2048 байт на пакет.`, 'hint'));
    const actions=node('div',null,'lab-actions'),cancel=node('button','Отмена'),start=node('button','Запустить','primary');cancel.type=start.type='button';cancel.onclick=()=>dialog.close();
    start.onclick=async()=>{if(changing)return;changing=true;start.disabled=true;card();try{
      const s={scope:scope.value,devices:selected.filter(i=>i.checked).map(i=>i.value),max_mb:Number(quota.value),chunk_mb:Number(chunk.value)};for(const [k,v]of Object.entries(options))s[k]=v.checked;
      if(s.https){if(!confirm('Включить анализ HTTPS для выбранных разрешённых устройств? Они должны доверять центру сертификации NETSCOPE. Приложения с закреплением сертификата или несовместимым хранилищем доверия могут перестать работать. Только IPv4 TCP/443; приватные домашние и офисные адреса обходят анализ.'))return;s.confirm_https=true;}
      status=await api('start',{settings:JSON.stringify(s)},true);if(!status.active)throw Error(status.error||'Запись не запустилась');session=status.session;dialog.close();
      if(el('pause').getAttribute('aria-pressed')!=='true')el('pause').click();
      await load(true);notify('');
    }catch(e){notify(e.message);}finally{changing=false;start.disabled=false;card();}};
    actions.append(cancel,start);form.append(actions);app.append(dialog);dialog.addEventListener('close',()=>dialog.remove(),{once:true});dialog.showModal();
  }
  el('capture-toggle').onclick=async()=>{try{if(!status.active)return await startDialog();changing=true;card();status=await api('stop',{},true);notify(status.error||'');}catch(e){notify(e.message);}finally{changing=false;card();}};
  el('capture-mode').onchange=()=>{mode=el('capture-mode').value;load(true).catch(e=>notify(e.message));};
  el('capture-search').oninput=render;el('capture-more').onclick=()=>load().catch(e=>notify(e.message));
  el('capture-current').onclick=()=>{session=status.session||'';load(true).catch(e=>notify(e.message));};
  const setup=node('button','Сертификаты и HTTPS');setup.type='button';el('capture-toggle').after(setup);
  const downloadCA=link('ca',{},'Скачать сертификат ЦС');downloadCA.hidden=true;downloadCA.title='Только публичный сертификат этого роутера, без приватного ключа';setup.after(downloadCA);
  const httpsOption=node('option','Анализ HTTPS');httpsOption.value='https';el('capture-mode').append(httpsOption);
  setup.onclick=async()=>{try{
    const show=async()=>{
      const p=await api('proxy-status');const area=el('details');area.replaceChildren();
      el('detail-title').textContent='Сертификаты и HTTPS';el('detail-subtitle').textContent='Отдельный центр сертификации для каждой установки NETSCOPE';
      area.append(node('p',ru(p.reason)||'Настройка HTTPS'),node('p','Центр сертификации создаётся локально на этом роутере. Прошивка и выпуски GitHub никогда не должны содержать общий центр сертификации или приватные ключи. Скачивание сертификата не запускает анализ.'));
      if(p.ca?.ready){
        area.append(link('ca',{},'Скачать публичный сертификат ЦС этого роутера'),node('h3','Отпечаток SHA-256'),node('pre',p.ca.fingerprint||'Недоступен'));
        area.append(node('p','Устанавливайте и добавляйте этот сертификат в доверенные только на принадлежащем вам или администрируемом вами устройстве. На iPhone: установите скачанный профиль, затем включите полное доверие в Настройки → Основные → Об этом устройстве → Доверие сертификатам. После тестирования удалите профиль.'));
      }else area.append(node('p','Центр сертификации ещё не создан. При необходимости запустите среду HTTPS, затем выберите создание центра сертификации этого роутера. Ключи создаются на устройстве и не скачиваются из проекта.'));
      area.append(node('p','Запись HTTPS остаётся выключенной, пока вы явно не выберете разрешённые устройства и не запустите сессию. Приложения с закреплением сертификата и сообщения со сквозным шифрованием не расшифровываются.'));
      const localized={...p,reason:ru(p.reason),warnings:(p.warnings||[]).map(ru)};
      const advanced=node('details'),summary=node('summary','Техническое состояние');advanced.append(summary,node('pre',JSON.stringify(localized,null,2)));area.append(advanced);
      for(const [kind,label,visible]of [['runtime-start','Запустить среду HTTPS',!p.docker_running],['ca-prepare','Создать центр сертификации роутера',p.docker_running&&!p.ca?.ready],['ca-regenerate','Пересоздать центр сертификации',p.ca?.ready]]){
        if(!visible)continue;const b=node('button',label);b.type='button';b.disabled=status.active;
        b.onclick=async()=>{if(kind==='ca-regenerate'&&!confirm('Пересоздать центр сертификации для анализа? Устройства, доверяющие старому сертификату, должны будут установить новый. Старый центр сертификации сохранится в приватной резервной копии на USB.'))return;b.disabled=true;try{await api(kind,kind==='ca-regenerate'?{confirm:p.ca.fingerprint}:{},true);await show();await poll();}catch(e){notify(e.message);b.disabled=false;}};area.append(b);
      }
    };await show();
  }catch(e){notify(e.message);}};
  el('nav-lab').addEventListener('click',()=>load(true).catch(e=>notify(e.message)));
  async function poll(){if(polling||document.hidden)return;polling=true;try{status=await api('status');card();if(status.error)notify(status.error);if(!el('lab-view').hidden&&mode!=='sessions'&&mode!=='live'&&(!session||session===status.session))await load();}catch(e){el('capture-state').textContent='НЕИЗВЕСТНО';notify(e.message);}finally{polling=false;}}
  poll();setInterval(poll,3000); // read-only; never starts a session
})();
