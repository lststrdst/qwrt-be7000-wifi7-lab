-- Shared lifecycle/storage contract for the existing authenticated Lua LuCI API.
local M={VERSION='0.2.0',ROOT=os.getenv('NETSCOPE_CAPTURE_ROOT') or '/mnt/sda1/NETSCOPE',
    MOUNT=os.getenv('NETSCOPE_CAPTURE_MOUNT') or '/mnt/sda1',RUN=os.getenv('NETSCOPE_CAPTURE_RUN') or '/tmp/netscope-capture'}
local fs=require'nixio.fs';local n=require'nixio';local j=require'luci.jsonc'
function M.read(path,limit) local f=io.open(path,'rb');if not f then return nil end;local s=f:read(limit or 1048576);f:close();return s end
function M.json(path) if not M.safe(path) then return nil end;local ok,v=pcall(j.parse,M.read(path,2097152) or '');return ok and type(v)=='table' and v or nil end
function M.safe(path)
    if type(path)~='string' or path:find('..',1,true) or path:sub(1,1)~='/' then return false end
    local p='';for v in path:gmatch('[^/]+') do p=p..'/'..v;local st=fs.lstat(p);if st and st.type=='lnk' then return false end end
    return true
end
function M.mkdir(path) assert(M.safe(path),'Unsafe storage path');assert(fs.mkdirr(path,'700'));assert(fs.chmod(path,'700'));return path end
function M.atomic(path,value)
    assert(M.safe(path) and M.safe(path..'.new'),'Unsafe file')
    local f=assert(io.open(path..'.new','wb'));assert(f:write(j.stringify(value)));assert(f:close());assert(fs.chmod(path..'.new','600'));assert(fs.rename(path..'.new',path))
end
function M.storage(test)
    local out={path=M.ROOT,mount=M.MOUNT,mounted=false,writable=false,free=0}
    if not M.safe(M.ROOT) then out.error='Unsafe USB path';return out end
    for line in (M.read('/proc/mounts',65536) or ''):gmatch('[^\n]+') do
        local dev,path,kind,opts=line:match('^(%S+) (%S+) (%S+) (%S+)')
        if path==M.MOUNT then out.mounted=true;out.filesystem=kind;out.identity=dev..':'..tostring((fs.stat(M.MOUNT) or {}).dev);out.writable=opts:match('^rw[, ]')~=nil or opts=='rw' end
    end
    if not out.mounted then out.error='USB is not mounted';return out end
    local st=fs.statvfs(M.MOUNT);if st then out.free=(st.bavail or 0)*(st.frsize or st.bsize or 4096) end
    if test and out.writable then
        local path=M.MOUNT..'/.netscope-write-'..n.getpid();if not M.safe(path) or fs.lstat(path) then out.error='Write-test path collision';return out end
        local f=io.open(path,'wb');out.writable=f~=nil
        if f then local ok=f:write('NETSCOPE write test\n');local close=f:close();fs.unlink(path);out.writable=ok~=nil and close~=nil end
    end
    if not out.writable then out.error='USB is read-only or write test failed' end
    return out
end
function M.valid_id(id) return type(id)=='string' and #id==26 and id:match('^%d%d%d%d%d%d%d%dT%d%d%d%d%d%d%-%x%x%x%x%x%x%x%x%x%x$')~=nil end
function M.session(id)
    if not M.valid_id(id) then return nil,'Invalid session ID' end
    local storage=M.storage();if not storage.mounted or storage.error then return nil,'USB unavailable' end
    local path=M.ROOT..'/sessions/'..id
    if not M.safe(path) or (fs.lstat(path) or {}).type~='dir' then return nil,'Session unavailable' end
    return path
end
function M.status()
    local state=M.json(M.RUN..'/status.json') or {state='OFF',active=false}
    if state.active and (os.time()-(state.heartbeat or 0)>6) then state.state='INTERRUPTED';state.active=false;state.error='Capture supervisor is not responding' end
    state.version=M.VERSION;state.storage=M.storage()
    local proxy=M.json(M.RUN..'/proxy-preflight.json') or {}
    state.https_available=proxy.available==true;state.proxy=proxy
    state.https_reason=proxy.reason or 'HTTPS preflight has not completed. Interception remains disabled.'
    state.visibility='Passive br-lan capture; Qualcomm offload and switched L2 traffic can bypass it. Acceleration is unchanged.'
    return state
end
function M.defaults() return {scope='all',devices={},metadata=true,dns=true,pcap=true,http=true,https=false,quic=false,max_mb=16000,chunk_mb=256,quota_policy='overwrite-oldest-pcap'} end
function M.enrich(flows)
    local status=M.status();if not status.active or not status.session then return end
    local path=M.session(status.session);if not path or not M.safe(path..'/flows/enrichment.json') then return end
    local index=M.json(path..'/flows/enrichment.json');if not index then return end
    local dn,tl={},{}
    for _,v in ipairs(index.dns or {}) do
        if v.expires and v.expires>os.time() then
            local key=v.device..'|'..v.ip;dn[key]=dn[key] or {};dn[key][v.query]=v.timestamp
        end
    end
    for _,v in ipairs(index.tls or {}) do tl[table.concat({v.source,v.sport,v.destination,v.dport},'|')]=v end
    for _,flow in ipairs(flows) do
        if flow.sport and flow.dport then flow.tls=tl[table.concat({flow.source,flow.sport,flow.destination,flow.dport},'|')] end
        local candidates=dn[flow.source..'|'..flow.destination]
        if candidates then flow.dns_candidates={};for name,stamp in pairs(candidates) do flow.dns_candidates[#flow.dns_candidates+1]={query=name,timestamp=stamp} end
            flow.dns_ambiguous=#flow.dns_candidates>1
        end
    end
end
function M.validate(v)
    if type(v)~='table' then return nil,'Invalid settings' end
    local o=M.defaults()
    for _,key in ipairs({'metadata','dns','pcap','http','https','quic'}) do if v[key]~=nil then if type(v[key])~='boolean' then return nil,'Invalid option: '..key end;o[key]=v[key] end end
    if o.quic and not o.https then return nil,'QUIC blocking requires HTTPS inspection' end
    if o.https and not M.status().https_available then return nil,'HTTPS inspection unavailable: complete runtime/CA preflight first' end
    if o.https and v.confirm_https~=true then return nil,'Explicit HTTPS inspection and CA trust confirmation required' end
    o.confirm_https=o.https and true or false
    o.scope=v.scope or 'all';if o.scope~='all' and o.scope~='selected' then return nil,'Invalid device scope' end
    if o.scope=='selected' then
        local inventory=require('luci.model.netscope').inventory()
        if type(v.devices)~='table' or #v.devices<1 or #v.devices>64 then return nil,'Choose 1–64 inventory devices' end
        for _,ip in ipairs(v.devices) do
            if type(ip)~='string' or not inventory[ip] or not ip:match('^[%d%.]+$') then return nil,'Unknown inventory address' end
            o.devices[#o.devices+1]=ip
        end
    end
    o.max_mb=tonumber(v.max_mb) or o.max_mb;o.chunk_mb=tonumber(v.chunk_mb) or o.chunk_mb
    if o.max_mb%1~=0 or o.max_mb<512 or o.max_mb>64000 or o.chunk_mb%1~=0 or o.chunk_mb<16 or o.chunk_mb>512 or o.chunk_mb>o.max_mb-256 then return nil,'Storage limits: total 512–64000 MB; chunk 16–512 MB with 256 MB reserved' end
    return o
end
function M.settings() return M.json(M.ROOT..'/config/settings.json') or M.defaults() end
function M.submit(action,settings)
    M.mkdir(M.RUN)
    if not fs.mkdir(M.RUN..'/api-lock','700') then return nil,'Another request is in progress' end
    local ok,result,err=pcall(function()
        local status=M.status()
        if action=='start' and status.active then return status end
        if action=='stop' and not status.active then return status end
        if os.time()-(status.heartbeat or 0)>6 then return nil,'Capture supervisor is offline' end
        if action=='start' then
            local valid,why=M.validate(settings);if not valid then return nil,why end
            local storage=M.storage(true);if storage.error or storage.free<128000000 then return nil,storage.error or 'USB free space below 128 MB' end
            settings=valid
        elseif action~='stop' then return nil,'Invalid action' end
        local req={action=action,settings=settings,id=tostring(os.time())..'-'..n.getpid()}
        M.atomic(M.RUN..'/command.json',req)
        for _=1,40 do n.nanosleep(0,100000000);local s=M.json(M.RUN..'/status.json');if s and s.command_id==req.id then return s end end
        return nil,'Request pending; refresh status before retrying'
    end)
    fs.rmdir(M.RUN..'/api-lock')
    if not ok then return nil,'Capture request failed' end
    return result,err
end
function M.events(id,kind,after,limit)
    if kind~='dns' and kind~='tls' and kind~='http' and kind~='https' then return nil,'Invalid stream' end
    local path,err=M.session(id);if not path then return nil,err end
    local dir=path..(kind=='dns' and '/dns' or '/flows');local files={}
    for f in fs.dir(dir) or function() end do if f:match('^'..kind..'%-%d%d%d%d%d%d%d%d%.jsonl$') then files[#files+1]=f end end
    table.sort(files);after=math.max(0,tonumber(after) or 0);limit=math.min(100,math.max(1,tonumber(limit) or 100))
    local out={};local scanned=0;local cursor=after;local truncated=false
    -- At most sixteen 256 KiB journals per stream. Responses are <=100 entries.
    for i=1,#files do
        if M.safe(dir..'/'..files[i]) then
            for line in (M.read(dir..'/'..files[i],300000) or ''):gmatch('[^\n]+') do
                scanned=scanned+#line;if scanned>4500000 then truncated=true;break end
                local v=j.parse(line)
                if v and (v.id or 0)>after then out[#out+1]=v;cursor=v.id;if #out>=limit then break end end
            end
        end
        if #out>=limit or truncated then break end
    end
    return {items=out,cursor=cursor,retention='bounded ring; older entries may have expired',limited=#out>=limit or truncated}
end
function M.sessions(offset)
    local st=M.storage();if not st.mounted or st.error then return {items={},error=st.error} end
    local root=M.ROOT..'/sessions';if not M.safe(root) then return {items={},error='Unsafe storage path'} end
    local ids={};for id in fs.dir(root) or function() end do if M.valid_id(id) then ids[#ids+1]=id end end
    table.sort(ids,function(a,b)return a>b end)
    offset=math.max(0,math.min(10000,tonumber(offset) or 0));local out={}
    for i=offset+1,math.min(#ids,offset+20) do local p=M.session(ids[i]);if p then local s=M.json(p..'/session.json');if s then out[#out+1]=s end end end
    return {items=out,total=#ids,offset=offset}
end
function M.files(id)
    local path,err=M.session(id);if not path then return nil,err end
    local out={};if not M.safe(path..'/pcap') then return nil,'Unsafe path' end
    for name in fs.dir(path..'/pcap') or function() end do
        if name:match('^capture%.pcap%d*$') and M.safe(path..'/pcap/'..name) then local s=fs.lstat(path..'/pcap/'..name);if s and s.type=='reg' then out[#out+1]={name=name,size=s.size,modified=s.mtime} end end
    end
    table.sort(out,function(a,b)return a.modified<b.modified end);return out
end
function M.delete(id)
    local p,err=M.session(id);if not p then return nil,err end
    local state=M.status();if state.active and state.session==id then return nil,'Stop capture before deleting its session' end
    local manifest=M.json(p..'/session.json');if not manifest or manifest.id~=id or manifest.owner~='NETSCOPE' then return nil,'Not a NETSCOPE session' end
    local function walk(path,remove)
        if not M.safe(path) then return false end
        local s=fs.lstat(path);if not s or (s.type~='dir' and s.type~='reg') then return false end
        if s.type=='dir' then for name in fs.dir(path) do if not walk(path..'/'..name,remove) then return false end end;return not remove or fs.rmdir(path) end
        return not remove or fs.unlink(path)
    end
    if not walk(p,false) then return nil,'Unsafe session contents; deletion refused' end
    return walk(p,true)
end
function M.http(id,event,reveal,kind)
    kind=kind=='https' and 'https' or 'http'
    local p,e=M.session(id);event=tonumber(event);if not p or not event or event%1~=0 or event<1 then return nil,e or 'Invalid flow ID' end
    local file=p..'/flows/'..kind..'-'..string.format('%04d',event%512)..'.json';if not M.safe(file) then return nil,'Unsafe path' end
    local v=M.json(file);if not v or v.id~=event then return nil,'Flow expired from bounded storage' end
    for _,side in ipairs({'request','response'}) do
        local m=v[side];if m then
            for _,h in ipairs(m.headers or {}) do if not reveal and h.name:lower():match('authorization') or not reveal and h.name:lower():match('cookie') or not reveal and h.name:lower():match('token') or not reveal and h.name:lower():match('key') then h.value='••••••••' end end
            if m.body_ref then
                local bodypath=p..'/flows/'..m.body_ref
                if M.safe(bodypath) and (m.body_ref:match('^body%-%d+%-[a-z]+%.bin$') or m.body_ref:match('^https%-body%-%d+%-[a-z]+%.bin$')) then
                    local text=M.read(bodypath,65536) or ''
                    local ct=(m.content_type or ''):lower();local textual=ct:find('text/',1,true) or ct:find('json',1,true) or ct:find('xml',1,true) or ct:find('x-www-form-urlencoded',1,true)
                    if textual and not m.content_encoding and not text:find('%z') and not text:find('[\1-\8\11\12\14-\31]') then m.text=reveal and text or '[Body hidden — Reveal may show credentials or personal data]';m.body_format='text' else m.body_format='binary or encoded' end
                end
            end
            if not reveal then m.path='[Reveal URL]';m.host=m.host;end
        end
    end
    return v
end
return M
