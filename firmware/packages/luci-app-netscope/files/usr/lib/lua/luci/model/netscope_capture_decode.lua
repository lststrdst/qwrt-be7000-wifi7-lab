-- Bounded passive decoder. No sockets, external lookups or TLS interception.
local M = {}
local function u16(s,p) local a,b=s:byte(p,p+1); if b then return a*256+b end end
local function u32(s,p) local a,b,c,d=s:byte(p,p+3); if d then return a*16777216+b*65536+c*256+d end end
M.u16=u16; M.u32=u32
local function ip(s,p,v6)
    local a={}; if v6 then for i=p,p+15,2 do a[#a+1]=string.format('%x',u16(s,i) or 0) end
    else for i=p,p+3 do a[#a+1]=s:byte(i) end end
    return table.concat(a,v6 and ':' or '.')
end
function M.packet(s,link,time)
    local p,et=1,nil
    if link==1 then et=u16(s,13);p=15
        for _=1,2 do if et==0x8100 or et==0x88a8 then et=u16(s,p+2);p=p+4 end end
    elseif link==113 then et=u16(s,15);p=17
    elseif link==276 then et=u16(s,1);p=21
    elseif link~=101 and link~=12 then return nil end
    if #s<p+19 then return nil end
    local version=math.floor(s:byte(p)/16); local src,dst,proto,finish
    if version==4 and (not et or et==0x0800) then
        local ihl=s:byte(p)%16*4; local total=u16(s,p+2); local frag=u16(s,p+6)
        if ihl<20 or total<ihl or frag%16384~=0 then return nil end -- no fragment reassembly
        src=ip(s,p+12);dst=ip(s,p+16);proto=s:byte(p+9);finish=math.min(#s,p+total-1);p=p+ihl
    elseif version==6 and (not et or et==0x86dd) and #s>=p+39 then
        src=ip(s,p+8,true);dst=ip(s,p+24,true);proto=s:byte(p+6);finish=math.min(#s,p+39+u16(s,p+4));p=p+40
        for _=1,4 do
            if proto==0 or proto==43 or proto==60 then
                if p+1>finish then return nil end
                local nextp=proto;proto=s:byte(p);p=p+(s:byte(p+1)+1)*8
            end
        end
    else return nil end
    local r={time=time,source=src,destination=dst,family='ipv'..version,protocol=proto==6 and 'tcp' or proto==17 and 'udp' or 'other'}
    if proto==6 then
        if p+19>finish then return nil end
        local size=math.floor(s:byte(p+12)/16)*4;if size<20 or p+size-1>finish then return nil end
        r.sport=u16(s,p);r.dport=u16(s,p+2);r.seq=u32(s,p+4);r.flags=s:byte(p+13);r.payload=s:sub(p+size,finish)
    elseif proto==17 then
        if p+7>finish then return nil end
        local len=u16(s,p+4);if len<8 then return nil end
        r.sport=u16(s,p);r.dport=u16(s,p+2);r.payload=s:sub(p+8,math.min(finish,p+len-1))
    else r.payload='' end
    return r
end
local function dnsname(s,p)
    local parts,seen={},{};local resume
    for _=1,64 do
        local n=s:byte(p);if not n or seen[p] then return nil end;seen[p]=true
        if n==0 then return table.concat(parts,'.'),resume or p+1 end
        if n>=192 then local b=s:byte(p+1);if not b then return nil end;resume=resume or p+2;p=(n-192)*256+b+1
        elseif n<=63 and #s>=p+n then
            local label=s:sub(p+1,p+n);if label:find('[^%w_%-]') then return nil end
            parts[#parts+1]=label;p=p+n+1
        else return nil end
    end
end
function M.dns(r)
    if r.sport~=53 and r.dport~=53 then return nil end
    local s=r.payload
    if r.protocol=='tcp' then local n=u16(s,1);if not n or #s<n+2 then return nil end;s=s:sub(3,n+2) end
    if #s<12 or u16(s,5)~=1 then return nil end
    local name,p=dnsname(s,13);if not name or #s<p+3 then return nil end
    local typ=u16(s,p);p=p+4;local flags=u16(s,3);local response=flags>=32768
    local answers={}
    for _=1,math.min(u16(s,7),32) do
        local owner,q=dnsname(s,p);if not owner or #s<q+9 then break end
        local kind,ttl,n=u16(s,q),u32(s,q+4),u16(s,q+8);p=q+10+n
        if p-1>#s then break end
        local value
        if kind==1 and n==4 then value=ip(s,q+10)
        elseif kind==28 and n==16 then value=ip(s,q+10,true)
        elseif kind==5 then value=dnsname(s,q+10) end
        if value then answers[#answers+1]={name=owner,type=kind,value=value,ttl=ttl} end
    end
    return {timestamp=r.time,device=response and r.destination or r.source,query=name,
        type=({[1]='A',[28]='AAAA',[5]='CNAME',[15]='MX',[16]='TXT',[65]='HTTPS'})[typ] or tostring(typ),
        response=response,rcode=flags%16,answers=answers,transaction=u16(s,1)}
end
function M.tls(s)
    if #s<9 or s:byte(1)~=22 or s:byte(2)~=3 or s:byte(6)~=1 then return nil end
    local len=u16(s,4);if len>18432 or #s<5+len then return nil end
    local p=44;local sid=s:byte(p);if not sid then return nil end;p=p+sid+1
    local c=u16(s,p);if not c then return nil end;p=p+2+c
    local comp=s:byte(p);if not comp then return nil end;p=p+1+comp
    local ext=u16(s,p);if not ext then return nil end;p=p+2
    local finish=math.min(#s,p+ext-1);local out={decrypted=false,inspection='ENCRYPTED',hello_version=u16(s,10)}
    for _=1,64 do
        if p+3>finish then break end
        local kind,n=u16(s,p),u16(s,p+2);local q=p+4;p=q+n;if p-1>finish then return nil end
        if kind==0 and n>=5 and s:byte(q+2)==0 then
            local size=u16(s,q+3);local host=s:sub(q+5,q+4+size)
            if size<=253 and #host==size and not host:find('[^%w%.%-]') then out.sni=host end
        elseif kind==16 and n>=3 then
            out.alpn_offered={};local t=q+2
            while t<p and #out.alpn_offered<8 do local l=s:byte(t);if not l or l==0 or t+l>=p then break end
                local v=s:sub(t+1,t+l);if not v:find('[^%w/%-.]') then out.alpn_offered[#out.alpn_offered+1]=v end;t=t+l+1 end
        end
    end
    return out -- negotiated TLS version/certificate cannot be inferred from ClientHello
end
local function headers(s)
    local e=s:find('\r\n\r\n',1,true);if not e or e>32768 then return nil end
    local first=s:match('^(.-)\r\n');local h={}
    for k,v in s:sub(#first+3,e+1):gmatch('([^\r\n:]+):%s*([^\r\n]*)\r\n') do
        h[#h+1]={name=k,value=v}
    end
    return first,h,e+4
end
function M.header(h,key)
    for _,v in ipairs(h or {}) do if v.name:lower()==key then return v.value end end
    return nil
end
local function message(s,response,closed,head)
    local first,h,p=headers(s);if not first then return nil end
    local method,path,status
    if response then status=tonumber(first:match('^HTTP/1%.[01] (%d%d%d)'))
        if not status then return nil end
    else method,path=first:match('^(%u+) (%S+) HTTP/1%.[01]$');if not method then return nil end end
    local body=s:sub(p);local truncated=false
    local len=tonumber(M.header(h,'content-length'))
    local enc=M.header(h,'transfer-encoding')
    if response and (head or status==204 or status==304 or status<200) then body=''
    elseif enc and enc:lower():find('chunked',1,true) then
        local chunks={};local x=1;local total=0
        for _=1,256 do
            local e=body:find('\r\n',x,true);if not e then return nil end
            local n=tonumber(body:sub(x,e-1):match('^(%x+)'),16);if not n or n>1048576 then return nil end
            if n==0 then body=table.concat(chunks);break end
            if #body<e+1+n+2 then return nil end
            total=total+n;if total>65536 then truncated=true;body=table.concat(chunks);break end
            chunks[#chunks+1]=body:sub(e+2,e+1+n);x=e+2+n+2
            if _==256 then return nil end
        end
    elseif len then
        if len<0 then return nil end
        if #body<math.min(len,65536) and not closed then return nil end
        truncated=len>65536 or #body<len;body=body:sub(1,math.min(len,65536))
    elseif response then if not closed then return nil end;truncated=#body>65536;body=body:sub(1,65536)
    else body='' end
    return {method=method,path=path,status=status,headers=h,content_type=M.header(h,'content-type'),
        content_encoding=M.header(h,'content-encoding'),body=body,size=len or #body,truncated=truncated,
        host=M.header(h,'host'),reassembly='bounded; HTTP/1 only; pipelining and gaps may be omitted'}
end
M.message=message
function M.new(emit)
    local self={streams={},count=0,seen=0,omitted=0}
    local function output(k,v) emit(k,v) end
    function self:packet(r)
        self.seen=self.seen+1
        local d=M.dns(r);if d then output('dns',d) end
        if r.protocol~='tcp' then return end
        local forward=table.concat({r.source,r.sport,r.destination,r.dport},'|')
        local reverse=table.concat({r.destination,r.dport,r.source,r.sport},'|')
        local st=self.streams[forward] or self.streams[reverse]
        if not st and #r.payload>0 then
            if self.count>=64 then self.omitted=self.omitted+1;return end
            if not r.payload:match('^%u+ %S*') and not (r.payload:byte(1)==22 and r.payload:byte(2)==3) then return end
            st={key=forward,time=r.time,last=r.time,source=r.source,destination=r.destination,sport=r.sport,dport=r.dport,a='',b='',seq={},tls=false}
            self.streams[forward]=st;self.count=self.count+1
        end
        if not st then return end
        st.last=r.time;local side=forward==st.key and 'a' or 'b';local text=r.payload
        local expected=st.seq[side]
        if expected and r.seq~=expected and #text>0 then
            local skip=(expected-r.seq)%4294967296
            if skip<=#text then text=text:sub(skip+1) else st.gap=true end
        end
        if not st.gap then
            st.seq[side]=(r.seq+#r.payload)%4294967296
            st[side]=(st[side]..text):sub(1,98304)
        end
        if #st.a>=98304 or #st.b>=98304 then st.full=true end
        local tls=M.tls(st.a)
        if tls then
            tls.source=st.source;tls.destination=st.destination;tls.sport=st.sport;tls.dport=st.dport;tls.timestamp=st.time
            output('tls',tls);self.streams[st.key]=nil;self.count=self.count-1;return
        end
        local closed=r.flags%2==1 or math.floor(r.flags/4)%2==1 or st.full
        local request=not st.gap and message(st.a,false,closed)
        local response=request and message(st.b,true,closed,request.method=='HEAD')
        if request and (response or closed) then
            output('http',{timestamp=st.time,last_timestamp=r.time,source=st.source,sport=st.sport,destination=st.destination,dport=st.dport,
                request=request,response=response,inspection='PLAIN HTTP'})
            self.streams[st.key]=nil;self.count=self.count-1
        elseif closed then self.streams[st.key]=nil;self.count=self.count-1;self.omitted=self.omitted+1 end
    end
    function self:expire(now)
        for key,st in pairs(self.streams) do if now-st.last>30 then
            local req=not st.gap and message(st.a,false,true)
            if req then output('http',{timestamp=st.time,last_timestamp=st.last,source=st.source,destination=st.destination,sport=st.sport,dport=st.dport,
                request=req,response=message(st.b,true,true,req.method=='HEAD'),inspection='PLAIN HTTP',incomplete=true}) end
            self.streams[key]=nil;self.count=self.count-1
        end end
    end
    return self
end
return M
