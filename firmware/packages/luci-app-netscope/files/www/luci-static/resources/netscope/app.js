'use strict';
const Netscope = (() => {
  const list = x => Array.isArray(x) ? x : [];
  function bytes(n) {
    if (n == null || !Number.isFinite(Number(n))) return '—';
    let v = Number(n), i = 0; const units = ['Б', 'КиБ', 'МиБ', 'ГиБ', 'ТиБ'];
    while (v >= 1024 && i < units.length - 1) { v /= 1024; i++; }
    return `${v.toLocaleString('ru-RU', {maximumFractionDigits: i ? 1 : 0})} ${units[i]}`;
  }
  function service(f) {
    if (f.dport === 443 || f.sport === 443) return f.protocol === 'udp' ? 'Возможно QUIC / порт 443' : 'Возможно TLS / порт 443';
    if (f.dport === 53 || f.sport === 53) return 'Возможно DNS / порт 53';
    if (f.dport === 80 || f.sport === 80) return 'Возможно HTTP / порт 80';
    return 'Назначение приложения неизвестно';
  }
  function filter(flows, devices, ip, query, protocol) {
    const names = new Map(list(devices).map(d => [d.ip, d.name]));
    const q = query.toLowerCase().trim();
    return list(flows).filter(f => (!ip || f.source === ip || f.destination === ip) &&
      (protocol === 'all' || f.protocol === protocol) && (!q ||
        [f.source, f.destination, f.sport, f.dport, f.protocol, f.state, f.tls?.sni, ...list(f.dns_candidates).map(d=>d.query), names.get(f.source), names.get(f.destination)].join(' ').toLowerCase().includes(q)));
  }
  function rate(previous, current) {
    if (!previous || !current || current.time <= previous.time || current.rx < previous.rx || current.tx < previous.tx) return null;
    return {rx: (current.rx - previous.rx) * 8 / (current.time - previous.time) / 1e6,
      tx: (current.tx - previous.tx) * 8 / (current.time - previous.time) / 1e6};
  }
  return {list, bytes, service, filter, rate};
})();
if (typeof module !== 'undefined') module.exports = Netscope;

if (typeof document !== 'undefined') (() => {
  const el = id => document.getElementById(id), app = el('app'), N = Netscope;
  let data = null, voiceData = null, device = '', tab = 'connections', selected = null, packet = null;
  let paused = true, busy = false, actionBusy = false, limit = 100, wanPrevious = null, speed = null;
  const node = (tag, text, cls) => { const e = document.createElement(tag); if (text != null) e.textContent = String(text); if (cls) e.className = cls; return e; };
  const endpoint = (ip, port) => `${ip && ip.includes(':') ? '[' + ip + ']' : ip}${port != null ? ':' + port : ''}`;
  const decimal = value => value == null || !Number.isFinite(Number(value)) ? '—' : Number(value).toLocaleString('ru-RU',{maximumFractionDigits:1});
  const names = () => new Map(N.list(data?.devices).map(d => [d.ip, d.name]));
  function replaceRows(container, rows, key) {
    const focus = document.activeElement?.dataset?.[key], scroll = container.scrollTop;
    container.replaceChildren(...rows);
    if (Number.isFinite(scroll)) container.scrollTop = scroll;
    if (focus) rows.find(row => row.dataset?.[key] === focus)?.focus({preventScroll:true});
  }
  function error(message) { el('error').hidden = !message; el('error').textContent = message || ''; }
  function showTab(value) {
    tab = value; el('live-view').hidden = tab !== 'connections'; el('voice-view').hidden = tab !== 'voice'; el('lab-view').hidden = tab !== 'lab';
    el('nav-connections').classList.toggle('active', tab === 'connections'); el('nav-voice').classList.toggle('active', tab === 'voice'); el('nav-lab').classList.toggle('active', tab === 'lab');
    if(tab==='voice')renderVoice();
    renderDetails();
  }
  function selectDevice(ip) { device = ip; selected = null; limit = 100; showTab('connections'); renderDevices(); renderFlows(); renderDetails(); }
  function renderDevices() {
    const ds = N.list(data?.devices);
    el('inventory-count').textContent = ds.length;
    el('all-devices').classList.toggle('active', !device);
    replaceRows(el('devices'), ds.map(d => {
      const b = node('button', null, 'device' + (device === d.ip ? ' active' : '')); b.type = 'button';
      b.append(node('strong', d.name), node('span', `${d.ip} · ${d.connections} соед.`));
      b.dataset.device = d.ip;
      b.setAttribute('aria-pressed', String(device === d.ip));
      b.title = `${d.source || 'DHCP'}${d.mac ? ' · ' + d.mac : ''} · наличие записи не доказывает онлайн`;
      b.onclick = () => selectDevice(d.ip); return b;
    }), 'device');
  }
  function renderFlows() {
    if (!data) return;
    const results = N.filter(data.flows, data.devices, device, el('search').value, el('protocol').value), ns = names();
    el('filter-label').textContent = device ? (ns.get(device) || device) : 'Вся сеть';
    el('results').textContent = `${results.length} по фильтру · показано ${Math.min(limit, results.length)}${data.limited ? ' · сервер ограничил выборку' : ''}`;
    el('more').hidden = results.length <= limit;
    replaceRows(el('flows'), results.slice(0, limit).map(f => {
      const b = node('button', null, 'flow' + (selected === f.id ? ' selected' : '')); b.type = 'button';
      b.className += ' connection-flow'; b.dataset.flow = f.id;
      b.setAttribute('aria-pressed', String(selected === f.id));
      const src = node('div', null, 'flow-endpoint'), dst = node('div', null, 'flow-endpoint');
      src.append(node('strong', ns.get(f.source) || f.source), node('span', endpoint(f.source, f.sport), 'mono'));
      dst.append(node('strong', f.tls?.sni || ns.get(f.destination) || f.destination), node('span', f.dport == null ? 'Порт не указан' : `${f.destination} · ${f.dport}`, 'mono'));
      if(f.dns_candidates?.length)dst.append(node('span',(f.dns_ambiguous?'Неоднозначный DNS: ':'Возможный DNS: ')+f.dns_candidates.map(d=>d.query).join(', ')));
      const meta = node('div', null, 'flow-measure');
      meta.append(node('span', f.protocol.toUpperCase(), 'protocol-tag'), node('strong', f.accounting ? N.bytes(f.bytes) : '—'), node('span', f.state, 'flow-state'));
      b.append(src, dst, meta); b.title = `${f.source} → ${f.destination} · ${f.accounting ? 'Сумма двух направлений' : 'Счётчик недоступен'}`;
      b.onclick = () => { selected = f.id; renderFlows(); renderDetails(); }; return b;
    }), 'flow');
    if (!results.length) el('flows').append(node('p', 'Подходящих соединений сейчас нет.', 'empty'));
    el('source-note').textContent = data.warning;
  }
  function pairs(values) {
    const dl = node('dl'); for (const [label, value] of values) dl.append(node('dt', label), node('dd', value == null ? '—' : value)); return dl;
  }
  function section(title, text, cls) { const fragment = document.createDocumentFragment(); fragment.append(node('h3', title), node('pre', text, cls)); return fragment; }
  function renderDetails() {
    const target = el('details'); target.replaceChildren();
    if (tab === 'lab' || tab === 'voice') return; // The selected feature owns the shared inspector.
    const f = N.list(data?.flows).find(f => f.id === selected);
    el('detail-title').textContent = 'Инспектор соединения';
    el('detail-subtitle').textContent = 'Conntrack · не отдельный пакет';
    if (!f) {
      const empty = node('div', null, 'empty-state inspector-empty');
      empty.append(node('strong', selected ? 'Соединение завершилось' : 'Разобрать соединение'), node('p', selected ? 'Запись исчезла из таблицы. Выбери другую строку.' : 'Нажми на строку слева — покажу её адреса, счётчики и NAT.'));
      target.append(empty); return;
    }
    const endpoints = node('div', null, 'end-box');
    endpoints.append(node('span', 'ИНИЦИАТОР', 'small-label'), node('div', endpoint(f.source,f.sport), 'mono'), node('span', '↓ НАЗНАЧЕНИЕ', 'small-label'), node('div', endpoint(f.destination,f.dport), 'mono'));
    target.append(endpoints);
    const traffic = node('div', null, 'direction-metrics');
    for (const [label, value] of [['От инициатора ↑', f.tx_bytes], ['Ответ ↓', f.rx_bytes]]) {
      const box = node('div'); box.append(node('span', label), node('strong', f.accounting ? N.bytes(value) : '—')); traffic.append(box);
    }
    target.append(traffic);
    target.append(pairs([
      ['Семейство', f.family], ['Протокол / состояние', `${f.protocol.toUpperCase()} / ${f.state}`],
      ['Пакеты → / ←', `${f.tx_packets ?? '—'} / ${f.rx_packets ?? '—'}`], ['Таймер conntrack', `${f.expires_in} с (не возраст)`],
      ['ASSURED', f.assured ? 'Да' : 'Нет'], ['Conntrack mark', f.mark],
      ['Ответ: источник', endpoint(f.reply_source || '—', f.reply_sport)], ['Ответ: назначение', endpoint(f.reply_destination || '—', f.reply_dport)]
    ]));
    target.append(node('h3', 'Протокол приложения'), node('p', N.service(f), 'hint'));
    if(f.tls)target.append(section('Наблюдаемый TLS ClientHello · ЗАШИФРОВАНО',JSON.stringify(f.tls,null,2)));
    if(f.dns_candidates)target.append(section('Сопоставление DNS · предположение, а не доказательство имени HTTP',JSON.stringify(f.dns_candidates,null,2)));
    target.append(node('h3', 'Содержимое'), node('p', 'Здесь нет записи payload. HTTPS шифруется уже на устройстве; сообщение или URL страницы из этой таблицы не извлечь.', 'hint'));
    target.append(node('h3', 'Маршрут и NAT'), node('p', 'Показаны исходная и ответная пары адресов conntrack — по ним видно преобразование NAT. Выходной интерфейс и прохождение Xray/L2TP эта таблица не доказывает.', 'hint'));
  }
  function renderLab() {} // Compatibility hook; Capture owns its lifecycle/card.
  function renderVoice() {
    const v=voiceData||{},endpoint=v.endpoint;
    const channel=v.mode==='mieru-tun'?'MIERU':v.mode==='hy2-tun'?'HY2':'—';
    el('voice-state').textContent=v.active?(v.healthy?channel:'СБОЙ'):'ВЫКЛ';
    el('voice-summary').textContent=v.available===false?'Модуль не установлен':`${v.active?(channel+' · '):''}${decimal(v.latency_ms)} мс · jitter ${decimal(v.jitter_ms)} · потери ${decimal(v.loss_percent)}%`;
    const current=el('voice-current');current.replaceChildren();
    current.append(node('span','МАРШРУТ','small-label'),node('div',v.route||'Состояние маршрута недоступно','mono'),node('span','АКТИВНЫЙ ENDPOINT','small-label'),node('div',endpoint?`${endpoint.device||endpoint.client} → ${endpoint.destination}:${endpoint.port} · ${endpoint.service}`:'Сейчас не найден','mono'));
    const metrics=el('voice-metrics');metrics.replaceChildren();
    for(const [label,value] of [['Контрольный UDP',decimal(v.latency_ms)+' мс'],['Jitter проб',decimal(v.jitter_ms)+' мс'],['Потери проб',decimal(v.loss_percent)+'%'],['Резерв Mieru',v.fallback_ready?'ГОТОВ':'НЕТ'],['Окно',`${v.window||0} проб`]]){const box=node('div');box.append(node('span',label),node('strong',value));metrics.append(box);}
    const endpoints=el('voice-endpoints'),endpointRows=N.list(v.endpoints).map(item=>{const row=node('div',null,'flow connection-flow');const src=node('div',null,'flow-endpoint'),dst=node('div',null,'flow-endpoint'),measure=node('div',null,'flow-measure');src.append(node('strong',item.device||item.client),node('span',item.client,'mono'));dst.append(node('strong',item.service),node('span',`${item.destination}:${item.port}`,'mono'));measure.append(node('span','UDP','protocol-tag'),node('strong',`${N.bytes(item.tx_bytes)} ↑ / ${N.bytes(item.rx_bytes)} ↓`),node('span',item.assured?'ASSURED':'TRACKED','flow-state'));row.append(src,dst,measure);return row;});replaceRows(endpoints,endpointRows,'endpoint');if(!endpointRows.length)endpoints.append(node('p','Активных Telegram/Discord UDP endpoint сейчас нет.','empty'));
    const history=el('voice-history'),historyRows=N.list(v.history).slice().reverse().map(item=>{const row=node('div',null,'voice-history-row');row.append(node('span',new Date((item.at||0)*1000).toLocaleTimeString('ru-RU'),'mono'),node('strong',item.ok?`${decimal(item.latency_ms)} мс`:'сбой пробы'),node('span',`jitter ${decimal(item.jitter_ms)} · потери ${decimal(item.loss_percent)}%`));return row;});history.replaceChildren(...historyRows);if(!historyRows.length)history.append(node('p','История появится после первой UDP-пробы.','empty'));
  }
  async function getJSON(url, options={}) {
    const controller = new AbortController(), timer=setTimeout(()=>controller.abort(),9000);
    try {
      const response=await fetch(url,{cache:'no-store',credentials:'same-origin',...options,signal:controller.signal});
      if (response.status===403) throw Error('Сессия LuCI завершилась. Обнови страницу и войди в роутер.');
      if (!response.ok) throw Error(`Роутер вернул ошибку ${response.status}. Сессию мог запустить другой клиент.`);
      if (!(response.headers.get('content-type')||'').includes('application/json')) throw Error('Нужен повторный вход в LuCI. Обнови страницу.');
      return await response.json();
    } finally {clearTimeout(timer);}
  }
  async function refresh(force=false) {
    if (busy || (!force && (paused || document.hidden))) return;
    busy=true;
    try {
      const next=await getJSON(app.dataset.api); if (next.error) throw Error(next.error);
      const wan=N.list(next.interfaces).find(i=>i.name==='eth0');
      if (wan) {const now={time:next.updated_at,rx:wan.rx_bytes,tx:wan.tx_bytes};speed=N.rate(wanPrevious,now);wanPrevious=now;}
      data=next;error('');el('status').textContent=paused?'Выключено · последний снимок':'ВКЛ · только метаданные';el('status').dataset.state=paused?'off':'live';
      el('device-count').textContent=N.list(data.devices).filter(d=>d.observed).length;
      el('flow-count').textContent=N.list(data.flows).length;
      el('speed').textContent=speed?`${speed.rx.toFixed(1)} / ${speed.tx.toFixed(1)} Мбит/с`:'Первый замер…';
      el('updated').textContent='Обновлено '+new Date(data.updated_at*1000).toLocaleTimeString('ru-RU');
      renderDevices();renderFlows();renderLab();renderDetails();
    } catch(e) { error(e.message || 'Нет связи с роутером.');el('status').textContent='Нет связи · данные устарели';el('status').dataset.state='error'; }
    finally {busy=false;}
  }
  async function refreshVoice(){
    try{const value=await getJSON(app.dataset.voice);if(value.error)throw Error(value.error);voiceData=value;renderVoice();}
    catch(e){el('voice-state').textContent='НЕТ ДАННЫХ';el('voice-summary').textContent=e.message||'Телеметрия недоступна';}
  }
  el('all-devices').onclick=()=>selectDevice('');
  el('nav-connections').onclick=()=>showTab('connections');el('nav-voice').onclick=()=>showTab('voice');el('nav-lab').onclick=()=>showTab('lab');
  el('search').oninput=()=>{limit=100;renderFlows();};el('protocol').onchange=()=>{limit=100;renderFlows();};
  el('more').onclick=()=>{limit+=100;renderFlows();};
  el('pause').onclick=()=>{paused=!paused;el('pause').textContent=paused?'Включить наблюдение':'Выключить наблюдение';el('pause').setAttribute('aria-pressed',String(!paused));el('pause').classList.toggle('primary',paused);el('status').textContent=paused?'Выключено · последний снимок':'Подключение…';el('status').dataset.state=paused?'off':'connecting';wanPrevious=null;if(!paused)refresh(true);};
  document.addEventListener('visibilitychange',()=>{if(!document.hidden)refresh();});
  setInterval(refresh,3000);
  refreshVoice();setInterval(()=>{if(!document.hidden)refreshVoice();},3000);
})();
