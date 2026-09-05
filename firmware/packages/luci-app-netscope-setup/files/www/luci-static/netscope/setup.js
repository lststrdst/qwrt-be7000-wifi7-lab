'use strict';
(()=>{
 const root=document.getElementById('netscope-setup');if(!root)return;
 const el=name=>document.getElementById('ns-setup-'+name);let busy=false;
 async function api(kind,params){
  const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),25000);
  try{const r=await fetch(root.dataset.api+'/'+kind,{signal:controller.signal,credentials:'same-origin',cache:'no-store',...(params?{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:params}:{})});if(r.status===403)throw Error('Sign in to LuCI again');if(!(r.headers.get('content-type')||'').includes('application/json'))throw Error('Session expired or setup unavailable');const v=await r.json();if(!r.ok)throw Error(v.error||'Preparation failed');return v;}
  catch(e){if(e.name==='AbortError')throw Error('Request timed out. A private draft may have been saved; no VPN was activated.');throw e;}
  finally{clearTimeout(timer);}
 }
 function error(message){el('error').hidden=!message;el('error').textContent=message||'';}
 el('kind').onchange=()=>{const kind=el('kind').value;
  for(const name of ['tunnel','vless','mieru']){const enabled=name==='tunnel'?(kind==='wg'||kind==='awg'):name===kind;el(name).hidden=!enabled;el(name).querySelectorAll('input,select,textarea').forEach(field=>field.disabled=!enabled);}
  el('result').hidden=true;error('');
 };el('kind').onchange();
 el('form').onsubmit=async event=>{event.preventDefault();if(busy)return;busy=true;el('prepare').disabled=true;error('');el('result').hidden=true;
  el('kind').disabled=true;
  try{const params=new URLSearchParams(new FormData(el('form')));params.set('kind',el('kind').value);params.set('token',root.dataset.token);const v=await api('prepare',params);el('profile').value='';el('mieru-password').value='';el('result-title').textContent=v.state==='TEMPLATE'?'Template · server required':'Prepared draft · not active';el('note').textContent=v.note;const downloads=el('downloads');downloads.replaceChildren();for(const file of v.files||[]){if(!['server.conf','client.conf','xray.json','mieru.json'].includes(file))continue;const a=document.createElement('a');a.textContent='Download '+file;a.href=root.dataset.api+'/download?'+new URLSearchParams({draft:v.id,file});a.download='';a.className='cbi-button cbi-button-link';downloads.append(a,document.createTextNode(' '));}el('result').hidden=false;}
  catch(e){error(e.message);}finally{busy=false;el('prepare').disabled=false;el('kind').disabled=false;}
 };
 api('status').then(v=>{if(!el('lan').value)el('lan').value=v.lan||'';el('status').textContent='USB: '+(v.storage?.mounted&&v.storage?.writable?'ready':'required')+' · WireGuard key tools: '+(v.tools?.wg?'ready':'missing')+' · AmneziaWG tools: '+(v.tools?.awg?'ready':'missing')+' · Xray: '+(v.tools?.xray?'ready':'missing')+' · Mieru: '+(v.tools?.mieru?'installed':'template only');}).catch(e=>error(e.message));
})();
