-- Optional mitmdump backend. Only NETSCOPE-owned rules and container are managed.
local M={IMAGE='mitmproxy/mitmproxy@sha256:00b77b5d8804c8ad18cb6caefbf9d5849e895e8986c5ce011f4ae30f4385962f',PORT=18088,UID=61087,NAME='netscope-inspection'}
local n=require'nixio';local fs=require'nixio.fs';local j=require'luci.jsonc'
local function C()return require'luci.model.netscope_capture'end
function M.exec(argv,seconds)
    local r,w=n.pipe();assert(r and w);local pid=n.fork();assert(pid)
    if pid==0 then
        r:close();local null=n.open('/dev/null','r');n.dup(null,n.stdin);n.dup(w,n.stdout);n.dup(w,n.stderr);w:close();n.exec(unpack(argv));os.exit(127)
    end
    w:close();r:setblocking(false);local out='';local started=os.time();local last=0
    while true do
        local s=r:read(8192);if s and #out<65536 then out=out..s:sub(1,65536-#out) end
        local got,why,code=n.waitpid(pid,'nohang')
        if got and got>0 then local tail=r:read(8192);if tail and #out<65536 then out=out..tail:sub(1,65536-#out) end;r:close();return why=='exited' and code==0,out end
        if os.time()-started>(seconds or 4) then n.kill(pid,9);n.waitpid(pid);r:close();return false,'Operation timed out' end
        if M.pulse and os.time()~=last then last=os.time();M.pulse() end
        n.nanosleep(0,50000000)
    end
end
function M.docker(args,seconds)local argv={'/usr/libexec/netscope-docker','client'};for _,v in ipairs(args) do argv[#argv+1]=tostring(v) end;return M.exec(argv,seconds)end
local function ipt(tab,args,strict)
    local argv={'/usr/sbin/iptables','-w','2','-t',tab};for _,v in ipairs(args) do argv[#argv+1]=tostring(v) end
    local ok,out=M.exec(argv,4);if strict then assert(ok,'NETSCOPE firewall operation failed') end;return ok,out
end
local owned='netscope-owned-v1'
local chains={{'nat','PREROUTING','NETSCOPE-HTTPS'},{'nat','OUTPUT','NETSCOPE-EGRESS'},{'filter','INPUT','NETSCOPE-GUARD'},{'filter','INPUT','NETSCOPE-QUIC'},{'filter','FORWARD','NETSCOPE-QUIC'}}
function M.cleanup()
    local good=true;local cleared={}
    -- Entry redirects first, then QUIC/guard; never flush any table or chain.
    for _,v in ipairs(chains) do
        local tab,parent,chain=unpack(v)
        for _=1,8 do
            if not ipt(tab,{'-C',parent,'-m','comment','--comment',owned,'-j',chain}) then break end
            if not ipt(tab,{'-D',parent,'-m','comment','--comment',owned,'-j',chain}) then good=false;break end
        end
        cleared[tab..'|'..chain]={tab,chain}
    end
    for _,v in pairs(cleared) do
        local ok,rules=ipt(v[1],{'-S',v[2]})
        if ok then
            if not rules:find('--comment '..owned,1,true) then good=false
            else
                for _=1,256 do if not ipt(v[1],{'-D',v[2],'1'}) then break end end
                if not ipt(v[1],{'-X',v[2]}) then good=false end
            end
        end
    end
    return good
end
local exempt={'0.0.0.0/8','10.0.0.0/8','100.64.0.0/10','127.0.0.0/8','169.254.0.0/16','172.16.0.0/12','192.0.0.0/24','192.168.0.0/16','198.18.0.0/15','224.0.0.0/4','240.0.0.0/4'}
function M.rules(settings)
    assert(M.cleanup(),'Stale NETSCOPE rules could not be removed')
    local function chain(tab,name)
        ipt(tab,{'-N',name},true);ipt(tab,{'-A',name,'-m','comment','--comment',owned},true)
    end
    local function jump(tab,parent,name)ipt(tab,{'-I',parent,'1','-m','comment','--comment',owned,'-j',name},true)end
    local function private(tab,name)for _,net in ipairs(exempt) do ipt(tab,{'-A',name,'-d',net,'-j','RETURN'},true) end end
    local function sources(tab,name,args)
        local list=settings.scope=='selected' and settings.devices or {'0.0.0.0/0'}
        for _,src in ipairs(list) do local a={'-A',name,'-s',src};for _,v in ipairs(args) do a[#a+1]=v end;ipt(tab,a,true) end
    end
    chain('filter','NETSCOPE-GUARD')
    ipt('filter',{'-A','NETSCOPE-GUARD','-p','tcp','!','--dport',M.PORT,'-j','RETURN'},true)
    ipt('filter',{'-A','NETSCOPE-GUARD','!','-p','tcp','-j','RETURN'},true)
    ipt('filter',{'-A','NETSCOPE-GUARD','-i','lo','-j','ACCEPT'},true)
    ipt('filter',{'-A','NETSCOPE-GUARD','-i','br-lan','-m','conntrack','--ctstate','DNAT','-j','ACCEPT'},true)
    ipt('filter',{'-A','NETSCOPE-GUARD','-j','REJECT'},true);jump('filter','INPUT','NETSCOPE-GUARD')
    chain('nat','NETSCOPE-EGRESS')
    ipt('nat',{'-A','NETSCOPE-EGRESS','-m','owner','!','--uid-owner',M.UID,'-j','RETURN'},true)
    -- Reuse the existing decision chain, without changing its rules. The proxy's
    -- upstream sockets must not silently bypass the owner's VLESS destination sets.
    assert(ipt('nat',{'-S','VLESS_ROUTER_TCP'}),'Existing VLESS TCP chain unavailable')
    ipt('nat',{'-A','NETSCOPE-EGRESS','-p','tcp','-j','VLESS_ROUTER_TCP'},true);jump('nat','OUTPUT','NETSCOPE-EGRESS')
    if settings.quic then
        chain('filter','NETSCOPE-QUIC');private('filter','NETSCOPE-QUIC')
        sources('filter','NETSCOPE-QUIC',{'-i','br-lan','-p','udp','--dport','443','-j','REJECT'})
        jump('filter','INPUT','NETSCOPE-QUIC');jump('filter','FORWARD','NETSCOPE-QUIC')
    end
    chain('nat','NETSCOPE-HTTPS');private('nat','NETSCOPE-HTTPS')
    sources('nat','NETSCOPE-HTTPS',{'-i','br-lan','-p','tcp','--dport','443','-j','REDIRECT','--to-ports',M.PORT})
    jump('nat','PREROUTING','NETSCOPE-HTTPS') -- LAST: proxy is healthy before caller gets here.
end
function M.ca()
    local c=C();local dir=c.ROOT..'/config/mitmproxy';local file=dir..'/mitmproxy-ca-cert.pem'
    local pem=c.safe(file) and c.read(file,8192)
    if not pem or pem:find('PRIVATE KEY',1,true) or not pem:match('^%-%-%-%-%-BEGIN CERTIFICATE%-%-%-%-%-') then return {ready=false} end
    local ok,out=M.exec({'/usr/bin/openssl','x509','-in',file,'-noout','-fingerprint','-sha256','-startdate'},3)
    local stat=fs.stat(file)
    return {ready=ok,fingerprint=out:match('[Ff]ingerprint=([%x:]+)'),created=stat and stat.mtime,
        valid_from=out:match('notBefore=([^\n]+)'),file=file}
end
function M.preflight()
    local c=C();local storage=c.storage();local mem=tonumber((c.read('/proc/meminfo',8192) or ''):match('MemAvailable:%s*(%d+)')) or 0
    local ok,info=M.docker({'info','--format','{{.Architecture}}|{{.CgroupVersion}}|{{.Driver}}'},3)
    local image_ok=ok and M.docker({'image','inspect',M.IMAGE,'--format','{{.Architecture}}'},3) or false
    local ca=M.ca();local available=ok and image_ok and ca.ready and storage.mounted and storage.writable and mem>=230000
    return {available=available or false,docker_running=ok,image_ready=image_ok or false,ca=ca,available_ram_kib=mem,
        reason=not ok and 'NETSCOPE Docker runtime is stopped or unavailable' or not image_ok and 'Pinned ARM64 mitmproxy image missing' or not ca.ready and 'Inspection CA is not prepared' or not storage.mounted and 'USB is not mounted' or not storage.writable and 'USB is not writable' or mem<230000 and 'At least 230000 KiB available RAM required' or 'Ready; IPv4 TCP/443 only. Private LAN/office destinations bypass inspection.',
        warnings={'Kernel has no seccomp and no swap accounting; memory limit only.','Trust this CA only on devices you administer. Untrusted/pinned apps may fail.','IPv6 and UDP/QUIC are not decrypted. No automatic certificate pinning or E2EE bypass.'},runtime=ok and info or nil}
end
function M.prepare_ca()
    local c=C();assert(not c.status().active,'Stop Capture before CA setup')
    local dir=c.ROOT..'/config/mitmproxy';c.mkdir(c.ROOT..'/config');c.mkdir(dir)
    assert(M.exec({'/bin/chown',M.UID..':'..M.UID,dir}))
    local ok=M.docker({'run','--rm','--network','none','--memory','160m','--pids-limit','80',
        '--cap-drop','ALL','--security-opt','no-new-privileges','--read-only','--log-driver','none',
        '--user',M.UID..':'..M.UID,'--workdir','/tmp','--tmpfs','/tmp:rw,noexec,nosuid,size=16m',
        '--mount','type=bind,src='..dir..',dst=/ca','--mount','type=bind,src=/usr/libexec/netscope-prepare-ca.py,dst=/prepare.py,readonly',
        '--entrypoint','python',M.IMAGE,'/prepare.py'},15)
    assert(ok,'CA setup failed');return M.ca()
end
function M.regenerate(fingerprint)
    local c=C();assert(not c.status().active,'Stop Capture first');assert(M.ca().fingerprint==fingerprint,'CA fingerprint changed')
    local dir=c.ROOT..'/config/mitmproxy';local backup=dir..'-backup-'..os.time()
    assert(c.safe(dir) and c.safe(backup) and not fs.lstat(backup));assert(fs.rename(dir,backup))
    local ok,result=pcall(M.prepare_ca)
    if not ok then return nil,'CA setup failed; old private CA retained in local backup' end
    return result
end
function M.stop()
    local clean=M.cleanup()
    if not clean then return false,'Redirect cleanup failed; proxy deliberately kept running' end
    local exists,owner=M.docker({'inspect',M.NAME,'--format','{{index .Config.Labels "netscope.owner"}}'},3)
    if exists and owner:match('^NETSCOPE') then M.docker({'stop','-t','2',M.NAME},5);M.docker({'rm',M.NAME},3) end
    return true
end
function M.start(session,path)
    local p=M.preflight();assert(p.available,p.reason);assert(M.stop())
    local c=C();local ca=c.ROOT..'/config/mitmproxy';assert(c.safe(ca) and c.safe(path..'/flows'))
    -- Dedicated non-login UID: only these sockets enter NETSCOPE-EGRESS.
    assert(M.exec({'/bin/chown',M.UID..':'..M.UID,path..'/flows'}))
    local uci=require'luci.model.uci'.cursor();local lan=uci:get('network','lan','ipaddr');assert(type(lan)=='string' and lan:match('^[%d%.]+$'),'LAN address unavailable')
    local ok=M.docker({'run','-d','--name',M.NAME,'--label','netscope.owner=NETSCOPE','--restart','no','--network','host',
        '--memory','160m','--pids-limit','80','--cap-drop','ALL','--security-opt','no-new-privileges','--read-only','--log-driver','none',
        '--user',M.UID..':'..M.UID,'--workdir','/tmp','--tmpfs','/tmp:rw,noexec,nosuid,size=16m','-e','HOME=/tmp',
        '--mount','type=bind,src='..ca..',dst=/ca,readonly','--mount','type=bind,src='..path..'/flows,dst=/capture/flows',
        '--mount','type=bind,src=/usr/libexec/netscope-flow-export.py,dst=/addon.py,readonly','--entrypoint','mitmdump',M.IMAGE,
        '--mode','transparent','--listen-host',lan,'--listen-port',M.PORT,'--set','confdir=/ca','--set','ssl_insecure=false',
        '--set','flow_detail=0','--set','termlog_verbosity=error','--set','connection_strategy=lazy',
        '--set','block_global=false','--set','anticomp=false','-q','-s','/addon.py'},8)
    assert(ok,'mitmdump container failed to start');return lan
end
function M.healthy(path,lan)
    local h=C().json(path..'/flows/https-health.json')
    if not h or h.ready~=true or os.time()-math.floor(h.heartbeat or 0)>4 then return false,h end
    local sock=n.socket('inet','stream');sock:setopt('socket','sndtimeo',1);sock:setopt('socket','rcvtimeo',1)
    local ok=sock:connect(lan,M.PORT);sock:close();return ok and true or false,h
end
return M
