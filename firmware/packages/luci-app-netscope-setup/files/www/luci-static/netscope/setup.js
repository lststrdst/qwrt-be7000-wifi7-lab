'use strict';
(()=>{
 const root=document.getElementById('netscope-setup');if(!root)return;
 const el=name=>document.getElementById('ns-setup-'+name);let busy=false;const touched={port:false,subnet:false};
 el('port').addEventListener('input',()=>touched.port=true);el('subnet').addEventListener('input',()=>touched.subnet=true);
 async function api(kind,params){
  const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),25000);
  try{const r=await fetch(root.dataset.api+'/'+kind,{signal:controller.signal,credentials:'same-origin',cache:'no-store',...(params?{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:params}:{})});if(r.status===403)throw Error('Sign in to LuCI again');if(!(r.headers.get('content-type')||'').includes('application/json'))throw Error('Session expired or setup unavailable');const v=await r.json();if(!r.ok)throw Error(v.error||'Request failed');return v;}
  catch(e){if(e.name==='AbortError')throw Error('Request timed out. Check saved drafts; no VPN was activated.');throw e;}
  finally{clearTimeout(timer);}
 }
 const post=(kind,values)=>{const params=new URLSearchParams(values);params.set('token',root.dataset.token);return api(kind,params);};
 function error(message){el('error').hidden=!message;el('error').textContent=message||'';}
 function list(name,items){const target=el(name);target.replaceChildren();for(const item of items||[])target.append(Object.assign(document.createElement('li'),{textContent:item}));}
 function action(label,handler){const button=document.createElement('button');button.type='button';button.className='cbi-button cbi-button-action';button.textContent=label;button.addEventListener('click',async()=>{button.disabled=true;error('');try{await handler(button);}catch(e){error(e.message);}finally{button.disabled=false;}});return button;}
 async function loadDrafts(){
  const target=el('drafts'),value=await api('drafts');target.replaceChildren();
  if(!(value.drafts||[]).length){target.textContent='No saved drafts.';return;}
  for(const draft of value.drafts){
   const card=document.createElement('div');card.className='cbi-section-node';
   const title=document.createElement('h3');title.textContent=(draft.protocol||draft.kind||'VPN')+' · '+draft.state;
   const meta=document.createElement('p');meta.textContent=draft.created+' · '+draft.id+(draft.listen_port?' · UDP '+draft.listen_port:'');
   const note=document.createElement('p');note.textContent=draft.note||'';
   const output=document.createElement('div');output.hidden=true;
   const controls=document.createElement('p');
   controls.append(action('Run activation preflight',async()=>{const report=await post('preflight',{draft:draft.id});output.replaceChildren();const status=document.createElement('strong');status.textContent=report.ready?'Preflight ready · activation still disabled':'Preflight blocked';const checks=document.createElement('ul');for(const text of report.checks||[])checks.append(Object.assign(document.createElement('li'),{textContent:text}));const rollback=document.createElement('p');rollback.textContent='Rollback order: '+(report.rollback||[]).join(' → ');const note=document.createElement('p');note.textContent=report.note||'';output.append(status,checks,rollback,note);output.hidden=false;}));
   controls.append(document.createTextNode(' '),action('Delete private draft',async()=>{if(!window.confirm('Delete this inactive private draft from router USB?'))return;await post('delete',{draft:draft.id});await loadDrafts();}));
   card.append(title,meta,note,controls,output);target.append(card);
  }
 }
 el('kind').onchange=()=>{const kind=el('kind').value;
  for(const name of ['tunnel','vless','mieru']){const enabled=name==='tunnel'?(kind==='wg'||kind==='awg'):name===kind;el(name).hidden=!enabled;el(name).querySelectorAll('input,select,textarea').forEach(field=>field.disabled=!enabled);}
  el('result').hidden=true;error('');
 };el('kind').onchange();
 el('form').onsubmit=async event=>{event.preventDefault();if(busy)return;busy=true;el('prepare').disabled=true;error('');el('result').hidden=true;el('kind').disabled=true;
  try{const params=new URLSearchParams(new FormData(el('form')));params.set('kind',el('kind').value);params.set('token',root.dataset.token);const v=await api('prepare',params);el('profile').value='';el('mieru-password').value='';el('result-title').textContent=v.state==='TEMPLATE'?'Template · server required':'Prepared draft · not active';el('note').textContent=v.note;
   list('plan-list',v.planned_changes);list('check-list',v.checks);el('plan').hidden=!(v.planned_changes?.length||v.checks?.length);
   const downloads=el('downloads');downloads.replaceChildren();for(const file of [...(v.files||[]),'plan.json']){if(!['server.conf','client.conf','xray.json','mieru.json','plan.json'].includes(file))continue;const a=document.createElement('a');a.textContent=file==='plan.json'?'Download sanitized plan':'Download '+file;a.href=root.dataset.api+'/download?'+new URLSearchParams({draft:v.id,file});a.download='';a.className='cbi-button cbi-button-link';downloads.append(a,document.createTextNode(' '));}el('result').hidden=false;await loadDrafts();}
  catch(e){error(e.message);}finally{busy=false;el('prepare').disabled=false;el('kind').disabled=false;}
 };
 api('status').then(v=>{if(!el('lan').value)el('lan').value=v.lan||'';if(!touched.port)el('port').value=v.recommended_port||51820;if(!touched.subnet)el('subnet').value=v.recommended_tunnel||'10.77.0.0/24';el('port-note').textContent='Suggested free UDP port: '+(v.recommended_port||51820)+'. Rechecked when preparing.';el('status').textContent='USB: '+(v.storage?.mounted&&v.storage?.writable?'ready':'required')+' · WireGuard key tools: '+(v.tools?.wg?'ready':'missing')+' · AmneziaWG tools: '+(v.tools?.awg?'ready':'missing')+' · Xray: '+(v.tools?.xray?'ready':'missing')+' · Mieru: '+(v.tools?.mieru?'installed':'template only');}).catch(e=>error(e.message));
 loadDrafts().catch(e=>error(e.message));
})();
