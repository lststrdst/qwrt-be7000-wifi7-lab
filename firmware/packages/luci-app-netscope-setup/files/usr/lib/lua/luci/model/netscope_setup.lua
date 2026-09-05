-- Private, on-device configuration preparation. No network/service changes.
local M={VERSION='0.1.0'}
local fs=require'nixio.fs';local json=require'luci.jsonc'
local C=require'luci.model.netscope_setup_runtime';local P=C
local function need(v,msg)assert(v,msg);return v end
local function host(v)
    need(type(v)=='string' and #v>0 and #v<=253 and v:match('^[%w%.%-]+$') and not v:find('%.%.') and v:sub(-1)~='.','Enter an IPv4 address or DNS hostname')
    for label in v:gmatch('[^.]+') do need(#label<=63 and label:match('^%w') and label:match('%w$'),'Invalid DNS hostname') end
    if v:match('^[%d%.]+$') then
        local count=0;for octet in v:gmatch('[^.]+') do count=count+1;need(tonumber(octet)<=255 and tostring(tonumber(octet))==octet,'Invalid IPv4 endpoint') end
        need(count==4,'Invalid IPv4 endpoint')
    end
    return v
end
local function port(v)local n=tonumber(v);need(n and n%1==0 and n>=1 and n<=65535,'Invalid port');return n end
local function ip(v)
    local a,b,c,d=tostring(v):match('^(%d+)%.(%d+)%.(%d+)%.(%d+)$');local parts={a,b,c,d};need(#parts==4,'Invalid IPv4 address')
    local value=0;for _,s in ipairs(parts) do local n=tonumber(s);need(n<=255 and tostring(n)==s,'Invalid IPv4 address');value=value*256+n end
    return value
end
local function ipv4(n)return string.format('%d.%d.%d.%d',math.floor(n/16777216)%256,math.floor(n/65536)%256,math.floor(n/256)%256,n%256)end
local function cidr(s)
    local a,b=tostring(s):match('^([^/]+)/(%d+)$');local bits=tonumber(b);need(bits and bits>=8 and bits<=30,'Use an IPv4 CIDR with prefix /8 to /30')
    local value=ip(a);local span=2^(32-bits);local first=value-value%span
    return {first=first,last=first+span-1,bits=bits,text=ipv4(first)..'/'..bits}
end
M.cidr=cidr
local function candidates(paths)for _,p in ipairs(paths) do if fs.access(p,'x') then return p end end end
function M.tools()
    return {awg=candidates({'/usr/bin/awg','/usr/sbin/awg','/mnt/sda1/qwrt-services/amneziawg/bin/awg'}),
        wg=candidates({'/usr/bin/wg','/usr/sbin/wg'}),xray=candidates({'/usr/bin/xray','/usr/sbin/xray'}),mieru=candidates({'/usr/bin/mieru','/usr/sbin/mieru'})}
end
function M.status()
    local u=require('luci.model.uci').cursor();local address=u:get('network','lan','ipaddr');local mask=u:get('network','lan','netmask') or '255.255.255.0';local lan=''
    local ok,value=pcall(function()local span=4294967296-ip(mask);local bits=32
        while span>1 and span%2==0 do span=span/2;bits=bits-1 end
        need(span==1,'Invalid netmask');return cidr(address..'/'..bits).text end)
    if ok then lan=value end
    local t=M.tools();return {version=M.VERSION,lan=lan,tools={awg=t.awg~=nil,wg=t.wg~=nil or t.awg~=nil,xray=t.xray~=nil,mieru=t.mieru~=nil},storage=C.storage(),mode='prepare-only',
        note='Creates private drafts and checks them. Existing VPNs, firewall and routes are not modified. Activation wizard is not released yet.'}
end
local function write(path,data)
    need(C.safe(path) and not fs.lstat(path),'Draft path already exists or is unsafe')
    local f=assert(io.open(path,'wb'));assert(f:write(data));assert(f:close());assert(fs.chmod(path,'600'))
end
local function key(tool,dir,name)
    local ok,private=P.exec({tool,'genkey'},3);need(ok,'VPN key generation failed');private=private:match('^%s*(.-)%s*$');need(#private==44 and private:match('^[%w+/]+=+$'),'Invalid generated key')
    local path=dir..'/'..name..'.key';write(path,private..'\n')
    -- Fixed shell program; executable and private path are separate positional args.
    local good,public=P.exec({'/bin/sh','-c','exec "$1" pubkey < "$2"','netscope-key',tool,path},3)
    fs.unlink(path);need(good,'VPN public key derivation failed');public=public:match('^%s*(.-)%s*$');need(#public==44 and public:match('^[%w+/]+=+$'),'Invalid derived public key')
    return private,public
end
local function tunnel_plan(input,dir)
    local kind=input.kind;local t=M.tools();local tool=t.wg or t.awg;if kind=='awg' then tool=t.awg end;need(tool,'Matching WireGuard/AmneziaWG tools are not installed')
    local endpoint=host(input.endpoint);local listen=port(input.port);local net=cidr(input.tunnel);need(net.bits>=24 and net.bits<=28,'Tunnel prefix must be /24 to /28')
    local allowed={};local overlaps=false
    for value in tostring(input.lan or ''):gmatch('[^,%s]+') do
        local block=cidr(value);need(#allowed<16,'At most 16 client routes');allowed[#allowed+1]=block.text
        if net.first<=block.last and block.first<=net.last then overlaps=true end
    end
    need(#allowed>0 and not overlaps,'LAN/office routes are missing or overlap the tunnel')
    local dns=ipv4(net.first+1);local client=ipv4(net.first+2)
    local server_key,server_pub=key(tool,dir,'server');local client_key,client_pub=key(tool,dir,'client')
    local obfuscation=''
    if kind=='awg' then
        -- Explicit AWG v1-compatible profile; no claim of AWG 2/3 compatibility.
        local unique={};local numbers={}
        for _=1,32 do local h=tonumber(require('luci.sys').uniqueid(4),16);if h and h>4 and not unique[h] then unique[h]=true;numbers[#numbers+1]=h end;if #numbers==4 then break end end
        need(#numbers==4,'Secure random header generation failed')
        -- QWRT Lua uses a signed formatter even on aarch64; H values are uint32.
        obfuscation=string.format('Jc = 4\nJmin = 40\nJmax = 70\nS1 = 0\nS2 = 0\nH1 = %.0f\nH2 = %.0f\nH3 = %.0f\nH4 = %.0f\n',unpack(numbers))
    end
    local server='[Interface]\nPrivateKey = '..server_key..'\nListenPort = '..listen..'\n'..obfuscation..'\n[Peer]\nPublicKey = '..client_pub..'\nAllowedIPs = '..client..'/32\n'
    -- No DNS directive before a DNS listener/input rule has been configured.
    local client_config='[Interface]\nPrivateKey = '..client_key..'\nAddress = '..client..'/32\n'..obfuscation..'\n[Peer]\nPublicKey = '..server_pub..'\nEndpoint = '..endpoint..':'..listen..'\nAllowedIPs = '..table.concat(allowed,', ')..', '..dns..'/32\nPersistentKeepalive = 25\n'
    write(dir..'/server.conf',server);write(dir..'/client.conf',client_config)
    return {kind=kind,protocol=kind=='awg' and 'AmneziaWG v1-compatible' or 'WireGuard',state='DRAFT',server_address=dns..'/'..net.bits,client_address=client..'/32',listen_port=listen,
        routes=allowed,files={'server.conf','client.conf'},note='Unique keys generated. DNS, WAN input, LAN forwarding and interface activation are intentionally not applied. Existing VPNs are untouched.'}
end
local function vless_plan(input,dir)
    need(type(input.profile)=='string' and #input.profile<=12000,'Paste a VLESS outbound JSON (maximum 12 KB)')
    local out=json.parse(input.profile);need(type(out)=='table' and out.protocol=='vless','Expected one VLESS outbound JSON object, not a subscription or full configuration')
    local stream=out.streamSettings or {};need(stream.security=='tls' or stream.security=='reality','TLS or Reality is required')
    need(stream.network=='tcp' or stream.network=='raw' or stream.network=='xhttp' or stream.network=='ws' or stream.network=='grpc','Unsupported VLESS transport')
    need(not out.proxySettings and not stream.sockopt,'Remove custom proxySettings/sockopt from this initial profile')
    local servers=out.settings and out.settings.vnext;need(type(servers)=='table' and #servers==1,'Exactly one VLESS server is required')
    local v=servers[1];host(v.address);port(v.port);need(type(v.users)=='table' and #v.users==1,'Exactly one VLESS user is required')
    need(type(v.users[1].id)=='string' and v.users[1].id:match('^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$'),'Invalid VLESS UUID')
    local tls=stream.security=='tls' and stream.tlsSettings or stream.realitySettings;need(type(tls)=='table' and tls.allowInsecure~=true,'Certificate validation must remain enabled')
    out={tag='proxy',protocol='vless',settings=out.settings,streamSettings=stream}
    local config={log={loglevel='none'},inbounds={{tag='local-test',listen='127.0.0.1',port=2081,protocol='socks',settings={udp=true}}},outbounds={out},routing={domainStrategy='AsIs'}}
    write(dir..'/xray.json',json.stringify(config))
    local binary=M.tools().xray;local tested=false
    if binary then local ok=P.exec({binary,'run','-test','-config',dir..'/xray.json'},6);need(ok,'Xray rejected the profile; no VPN changes were made');tested=true end
    return {kind='vless',state='DRAFT',validated=tested,files={'xray.json'},note='Loopback SOCKS test configuration only. No daemon, split routes, DNS policy or firewall rules were started.'}
end
local function mieru_plan(input,dir)
    local endpoint=input.mieru_endpoint or '';local username=input.mieru_user or '';local password=input.mieru_password or ''
    local template=endpoint=='' and username=='' and password==''
    if template then endpoint='server.example.invalid';username='CHANGE_ME';password='CHANGE_ME'
    else host(endpoint);need(#username>0 and #username<=128 and not username:find('%c'),'Enter the Mieru server username')
        need(#password>0 and #password<=512 and not password:find('%c'),'Enter the Mieru server password') end
    local protocol=input.mieru_transport or 'TCP';need(protocol=='TCP' or protocol=='UDP','Choose TCP or UDP')
    local server={portBindings={{port=port(input.mieru_port or 443),protocol=protocol}}}
    if endpoint:match('^[%d%.]+$') then server.ipAddress=endpoint else server.domainName=endpoint end
    local config={profiles={{profileName='netscope',user={name=username,password=password},servers={server},mtu=1400}},
        activeProfile='netscope',rpcPort=8964,socks5Port=2082,socks5ListenLAN=false,loggingLevel='WARN'}
    write(dir..'/mieru.json',json.stringify(config))
    return {kind='mieru',state=template and 'TEMPLATE' or 'DRAFT',validated=false,files={'mieru.json'},
        note=template and 'Template only: replace server.example.invalid and both CHANGE_ME values with your future Mieru server credentials. No service or failover was configured.'
            or 'Prepared a loopback-only Mieru client configuration. Server credentials, runtime compatibility and connectivity are not tested. No service, routes or failover were started.'}
end
function M.prepare(input)
    need(type(input)=='table' and (input.kind=='wg' or input.kind=='awg' or input.kind=='vless' or input.kind=='mieru'),'Choose WireGuard, AmneziaWG, VLESS or Mieru')
    local storage=C.storage(true);need(storage.mounted and storage.writable and not storage.error and storage.free>16000000,'Writable USB with free space required')
    local root=C.ROOT..'/config/setup';C.mkdir(C.ROOT..'/config');C.mkdir(root)
    local count=0;for _ in fs.dir(root) do count=count+1 end;need(count<20,'20 saved drafts reached; securely archive/remove old drafts before creating more')
    local id=os.date('!%Y%m%dT%H%M%S')..'-'..require('luci.sys').uniqueid(5);need(id:match('^[%w%-]+$'),'Invalid draft id')
    local dir=root..'/'..id;need(not fs.lstat(dir),'Draft collision');C.mkdir(dir)
    local ok,result=pcall(function()
        local result=(input.kind=='vless' and vless_plan or input.kind=='mieru' and mieru_plan or tunnel_plan)(input,dir)
        result.id=id;C.atomic(dir..'/plan.json',result);return result
    end)
    if not ok then
        for _,name in ipairs({'server.key','client.key','server.conf','client.conf','xray.json','mieru.json','plan.json','plan.json.new'}) do fs.unlink(dir..'/'..name) end
        fs.rmdir(dir);error(tostring(result):match(':%d+: (.*)') or 'Preparation failed')
    end
    return result
end
function M.download(id,file)
    local storage=C.storage();need(storage.mounted and not storage.error,'USB unavailable')
    need(C.valid_id(id),'Invalid draft')
    need(file=='server.conf' or file=='client.conf' or file=='xray.json' or file=='mieru.json' or file=='plan.json','Invalid file')
    local path=C.ROOT..'/config/setup/'..id..'/'..file;need(C.safe(path) and (fs.lstat(path) or {}).type=='reg','Draft unavailable');return path
end
return M
