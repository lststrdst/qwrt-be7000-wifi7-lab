local M = {}

local function read(path, limit)
    local f=io.open(path,'rb'); if not f then return nil end
    local s=f:read(limit or '*a'); f:close(); return s
end

function M.parse_conntrack(line)
    local family, proto, number, ttl, rest = line:match('^(ipv[46])%s+%d+%s+(%S+)%s+(%d+)%s+(%d+)%s+(.+)$')
    if not family then return nil end
    local a,b={},{}; local side=a
    for k,v in rest:gmatch('([%w_]+)=([^%s]+)') do
        if k=='src' and a.src then side=b end
        if k=='src' or k=='dst' or k=='sport' or k=='dport' or k=='bytes' or k=='packets' then side[k]=v end
    end
    if not a.src or not a.dst then return nil end
    local bytes1,bytes2=tonumber(a.bytes),tonumber(b.bytes)
    local packets1,packets2=tonumber(a.packets),tonumber(b.packets)
    local state=rest:match('^([A-Z_]+)%s') or (rest:find('[UNREPLIED]',1,true) and 'UNREPLIED' or 'TRACKED')
    local mark=rest:match('mark=(%d+)')
    return {id=table.concat({family,proto,a.src,a.sport or '',a.dst,a.dport or '',rest:match('zone=(%d+)') or '0'},'|'),
        family=family, protocol=proto, source=a.src, destination=a.dst,
        sport=tonumber(a.sport),dport=tonumber(a.dport),state=state,expires_in=tonumber(ttl),
        tx_bytes=bytes1,rx_bytes=bytes2,bytes=(bytes1 or 0)+(bytes2 or 0),
        tx_packets=packets1,rx_packets=packets2,packets=(packets1 or 0)+(packets2 or 0),
        accounting=bytes1~=nil and bytes2~=nil,reply_source=b.src,reply_destination=b.dst,
        reply_sport=tonumber(b.sport),reply_dport=tonumber(b.dport),mark=tonumber(mark),
        assured=rest:find('[ASSURED]',1,true)~=nil}
end

local function inventory()
    local byip={}
    local function add(ip,name,source,mac,expires)
        if not ip or ip=='' then return end
        local d=byip[ip] or {ip=ip,name=ip,source=source,connections=0,observed=false}
        if name and name~='' and name~='*' and (not byip[ip] or byip[ip].source~='reservation') then d.name=name:sub(1,80) end
        if mac then d.mac=mac end
        if expires then d.lease_expires=expires end
        byip[ip]=d
    end
    local uci=require('luci.model.uci').cursor()
    uci:foreach('dhcp','host',function(s)
        if type(s.ip)=='string' then add(s.ip,s.name,'reservation',type(s.mac)=='string' and s.mac or nil) end
    end)
    for line in (read('/tmp/dhcp.leases',65536) or ''):gmatch('[^\n]+') do
        local exp,mac,ip,name=line:match('^(%d+)%s+(%S+)%s+(%S+)%s+(%S+)')
        if ip then add(ip,name,'lease',mac,tonumber(exp)) end
    end
    for line in (read('/proc/net/arp',65536) or ''):gmatch('[^\n]+') do
        local ip,flags,mac,dev=line:match('^(%S+)%s+%S+%s+(%S+)%s+(%S+)%s+%S+%s+(%S+)')
        if ip and dev=='br-lan' and flags~='0x0' then
            add(ip,nil,'arp',mac); byip[ip].arp_cached=true
        end
    end
    return byip
end
M.inventory=inventory

function M.lab_state()
    -- Kept only for compatibility with older frontends. The fixed-client HTTP
    -- listener was retired; all packet capture is handled by NETSCOPE Capture.
    return {active=false,available=false,retired=true,packets={},remaining=0,
        error='Temporary lab retired. Use Capture.'}
end

function M.snapshot()
    local byip=inventory(); local flows={}; local total=0
    local f=io.open('/proc/net/nf_conntrack','r')
    if not f then error('Conntrack unavailable') end
    for line in f:lines() do
        total=total+1; if total>12000 then break end
        local c=M.parse_conntrack(line)
        if c and #flows<2500 then
            flows[#flows+1]=c
            for _,ip in ipairs({c.source,c.destination}) do
                if byip[ip] then byip[ip].connections=byip[ip].connections+1;byip[ip].observed=true end
            end
        end
    end
    f:close()
    local ok,capture=pcall(require,'luci.model.netscope_capture')
    if ok then pcall(capture.enrich,flows) end
    table.sort(flows,function(a,b) return a.bytes>b.bytes end)
    local devices={};for _,d in pairs(byip) do devices[#devices+1]=d end
    table.sort(devices,function(a,b) if a.connections~=b.connections then return a.connections>b.connections end;return a.ip<b.ip end)
    local interfaces={}
    for line in (read('/proc/net/dev',32768) or ''):gmatch('[^\n]+') do
        local name,rest=line:match('^%s*([^:]+):%s*(.+)$')
        if name then local vals={};for v in rest:gmatch('%d+') do vals[#vals+1]=tonumber(v) end
            interfaces[#interfaces+1]={name=name,rx_bytes=vals[1],tx_bytes=vals[9],rx_packets=vals[2],tx_packets=vals[10]}
        end
    end
    return {version=1,updated_at=os.time(),source='nf_conntrack',flows=flows,devices=devices,
        interfaces=interfaces,total_entries=total,limited=total>#flows,lab=M.lab_state(),
        warning='Conntrack — соединения, не запись пакетов. Аппаратный offload/L2 могут обходить счётчики. Домен и приложение по IP/порту достоверно не определяются.'}
end
return M
