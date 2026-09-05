-- Private, on-device configuration preparation and explicit transactional activation.
local M={VERSION='0.6.0-dev'}
local fs=require'nixio.fs';local json=require'luci.jsonc'
local C=require'luci.model.netscope_setup_runtime';local P=C
local function need(v,msg)assert(v,msg);return v end
local function host(v)
    need(type(v)=='string' and #v>0 and #v<=253 and v:match('^[%w%.%-]+$') and not v:find('%.%.') and v:sub(-1)~='.','Введите IPv4-адрес или DNS-имя')
    for label in v:gmatch('[^.]+') do need(#label<=63 and label:match('^%w') and label:match('%w$'),'Некорректное DNS-имя') end
    if v:match('^[%d%.]+$') then
        local count=0;for octet in v:gmatch('[^.]+') do count=count+1;need(tonumber(octet)<=255 and tostring(tonumber(octet))==octet,'Некорректный IPv4-адрес точки подключения') end
        need(count==4,'Некорректный IPv4-адрес точки подключения')
    end
    return v
end
local function port(v)local n=tonumber(v);need(n and n%1==0 and n>=1 and n<=65535,'Некорректный порт');return n end
local function ip(v)
    local a,b,c,d=tostring(v):match('^(%d+)%.(%d+)%.(%d+)%.(%d+)$');local parts={a,b,c,d};need(#parts==4,'Некорректный IPv4-адрес')
    local value=0;for _,s in ipairs(parts) do local n=tonumber(s);need(n<=255 and tostring(n)==s,'Некорректный IPv4-адрес');value=value*256+n end
    return value
end
local function ipv4(n)return string.format('%d.%d.%d.%d',math.floor(n/16777216)%256,math.floor(n/65536)%256,math.floor(n/256)%256,n%256)end
local function cidr(s)
    local a,b=tostring(s):match('^([^/]+)/(%d+)$');local bits=tonumber(b);need(bits and bits>=8 and bits<=30,'Укажите IPv4-подсеть с префиксом от /8 до /30')
    local value=ip(a);local span=2^(32-bits);local first=value-value%span
    return {first=first,last=first+span-1,bits=bits,text=ipv4(first)..'/'..bits}
end
M.cidr=cidr
local function candidates(paths)for _,p in ipairs(paths) do if fs.access(p,'x') then return p end end end
function M.tools()
    return {awg=candidates({'/usr/bin/awg','/usr/sbin/awg','/mnt/sda1/qwrt-services/amneziawg/bin/awg'}),
        wg=candidates({'/usr/bin/wg','/usr/sbin/wg'}),xray=candidates({'/usr/bin/xray','/usr/sbin/xray'}),mieru=candidates({'/usr/bin/mieru','/usr/sbin/mieru','/mnt/sda1/qwrt-services/mieru/bin/mieru'}),
        hysteria=candidates({'/usr/bin/hysteria','/usr/sbin/hysteria','/mnt/sda1/qwrt-services/hysteria/bin/hysteria'}),
        hysteria_installer=candidates({'/usr/libexec/netscope-install-hysteria'}),manager=candidates({'/usr/libexec/netscope-vpn-profile'})}
end
local function inventory()
    local used_udp,used_tcp,routes={},{},{}
    local netstat=candidates({'/sbin/netstat','/bin/netstat','/usr/bin/netstat'})
    if netstat then
        local ok,out=P.exec({netstat,'-lntu'},3)
        if ok then for line in out:gmatch('[^\n]+') do
            local proto=line:match('^(%S+)') or '';local p=tonumber(line:match(':(%d+)%s'))
            if p and proto:match('^udp') then used_udp[p]=true elseif p and proto:match('^tcp') then used_tcp[p]=true end
        end end
    end
    local ipbin=candidates({'/sbin/ip','/bin/ip','/usr/sbin/ip','/usr/bin/ip'})
    if ipbin then
        local ok,out=P.exec({ipbin,'-4','route','show','table','main'},3)
        if ok then for line in out:gmatch('[^\n]+') do
            local value=line:match('^(%d+%.%d+%.%d+%.%d+/%d+)') or line:match('^blackhole%s+(%d+%.%d+%.%d+%.%d+/%d+)')
                or line:match('^(%d+%.%d+%.%d+%.%d+)%s')
            if value then local ok,block=pcall(cidr,value:find('/',1,true) and value or value..'/32');if ok then routes[#routes+1]=block end end
        end end
    end
    local recommended_port
    for _,candidate in ipairs({51820,51822,51823,51824,51825}) do if not used_udp[candidate] then recommended_port=candidate;break end end
    local recommended_tunnel
    for _,candidate in ipairs({'10.77.0.0/24','10.88.0.0/24','172.31.253.0/24','192.168.77.0/24'}) do
        local block=cidr(candidate);local overlap=false
        for _,live in ipairs(routes) do if block.first<=live.last and live.first<=block.last then overlap=true;break end end
        if not overlap then recommended_tunnel=candidate;break end
    end
    return {used=used_udp,used_udp=used_udp,used_tcp=used_tcp,routes=routes,recommended_port=recommended_port or 51820,recommended_tunnel=recommended_tunnel or '10.77.0.0/24'}
end
M.inventory=inventory
function M.status()
    local u=require('luci.model.uci').cursor();local address=u:get('network','lan','ipaddr');local mask=u:get('network','lan','netmask') or '255.255.255.0';local lan=''
    local ok,value=pcall(function()local span=4294967296-ip(mask);local bits=32
        while span>1 and span%2==0 do span=span/2;bits=bits-1 end
        need(span==1,'Некорректная маска сети');return cidr(address..'/'..bits).text end)
    if ok then lan=value end
    local t=M.tools();local live=inventory();return {version=M.VERSION,lan=lan,recommended_port=live.recommended_port,recommended_tunnel=live.recommended_tunnel,
        tools={awg=t.awg~=nil,wg=t.wg~=nil,xray=t.xray~=nil,mieru=t.mieru~=nil,hysteria=t.hysteria~=nil,hysteria_installer=t.hysteria_installer~=nil,manager=t.manager~=nil},storage=C.storage(),mode=t.manager and 'transactional-activation' or 'prepare-only',
        note=t.manager and 'Приватные черновики и независимое транзакционное включение WG, AWG, VLESS/Xray, Mieru и Hysteria 2. Каждый профиль использует только собственный интерфейс или loopback-порт.'
            or 'Создаёт и проверяет приватные черновики. Существующие VPN, межсетевой экран и маршруты не изменяются. Диспетчер включения не установлен.'}
end
local function write(path,data)
    need(C.safe(path) and not fs.lstat(path),'Путь черновика уже существует или небезопасен')
    local f=assert(io.open(path,'wb'));assert(f:write(data));assert(f:close());assert(fs.chmod(path,'600'))
end
local function key(tool,dir,name)
    local ok,private=P.exec({tool,'genkey'},3);need(ok,'Не удалось создать ключ VPN');private=private:match('^%s*(.-)%s*$');need(#private==44 and private:match('^[%w+/]+=+$'),'Создан некорректный ключ')
    local path=dir..'/'..name..'.key';write(path,private..'\n')
    -- Fixed shell program; executable and private path are separate positional args.
    local good,public=P.exec({'/bin/sh','-c','exec "$1" pubkey < "$2"','netscope-key',tool,path},3)
    fs.unlink(path);need(good,'Не удалось получить публичный ключ VPN');public=public:match('^%s*(.-)%s*$');need(#public==44 and public:match('^[%w+/]+=+$'),'Получен некорректный публичный ключ')
    return private,public
end
local function tunnel_plan(input,dir)
    local kind=input.kind;local t=M.tools();local tool=t.wg or t.awg;if kind=='awg' then tool=t.awg end;need(tool,'Не установлены подходящие инструменты WireGuard/AmneziaWG')
    local endpoint=host(input.endpoint);local listen=port(input.port);local net=cidr(input.tunnel);need(net.bits>=24 and net.bits<=28,'Префикс туннеля должен быть от /24 до /28')
    local live=inventory();need(not live.used[listen],'UDP-порт '..listen..' уже занят; выберите предложенный свободный порт')
    for _,block in ipairs(live.routes) do need(net.last<block.first or block.last<net.first,'Подсеть туннеля пересекается с активным маршрутом: '..block.text) end
    local allowed={};local overlaps=false
    for value in tostring(input.lan or ''):gmatch('[^,%s]+') do
        local block=cidr(value);need(#allowed<16,'Допускается не более 16 маршрутов клиента');allowed[#allowed+1]=block.text
        if net.first<=block.last and block.first<=net.last then overlaps=true end
    end
    need(#allowed>0 and not overlaps,'Домашние или офисные маршруты отсутствуют либо пересекаются с туннелем')
    local dns=ipv4(net.first+1);local client=ipv4(net.first+2)
    local server_key,server_pub=key(tool,dir,'server');local client_key,client_pub=key(tool,dir,'client')
    local obfuscation=''
    if kind=='awg' then
        -- Explicit AWG v1-compatible profile; no claim of AWG 2/3 compatibility.
        local unique={};local numbers={}
        for _=1,32 do local h=tonumber(require('luci.sys').uniqueid(4),16);if h and h>4 and not unique[h] then unique[h]=true;numbers[#numbers+1]=h end;if #numbers==4 then break end end
        need(#numbers==4,'Не удалось безопасно создать случайные заголовки')
        -- QWRT Lua uses a signed formatter even on aarch64; H values are uint32.
        obfuscation=string.format('Jc = 4\nJmin = 40\nJmax = 70\nS1 = 0\nS2 = 0\nH1 = %.0f\nH2 = %.0f\nH3 = %.0f\nH4 = %.0f\n',unpack(numbers))
    end
    local server='[Interface]\nPrivateKey = '..server_key..'\nListenPort = '..listen..'\n'..obfuscation..'\n[Peer]\nPublicKey = '..client_pub..'\nAllowedIPs = '..client..'/32\n'
    -- No DNS directive before a DNS listener/input rule has been configured.
    local client_config='[Interface]\nPrivateKey = '..client_key..'\nAddress = '..client..'/32\n'..obfuscation..'\n[Peer]\nPublicKey = '..server_pub..'\nEndpoint = '..endpoint..':'..listen..'\nAllowedIPs = '..table.concat(allowed,', ')..', '..dns..'/32\nPersistentKeepalive = 25\n'
    write(dir..'/server.conf',server);write(dir..'/client.conf',client_config)
    return {kind=kind,protocol=kind=='awg' and 'AmneziaWG v1-совместимый' or 'WireGuard',state='DRAFT',server_address=dns..'/'..net.bits,client_address=client..'/32',listen_port=listen,
        routes=allowed,files={'server.conf','client.conf'},checks={'UDP-порт был свободен во время подготовки','Подсеть туннеля не пересекалась с активными маршрутами основной таблицы','Приватные ключи хранятся только в скачиваемых файлах конфигурации'},
        planned_changes={'Создать новый интерфейс VPN','Открыть UDP '..listen..' со стороны WAN','Разрешить клиентам VPN выбранные домашние и офисные маршруты','Разрешить DNS роутера только после проверки его прослушивания'},
        note='Созданы уникальные ключи. DNS, вход с WAN, пересылка в LAN и включение интерфейса намеренно не применялись. Существующие VPN не затронуты.'}
end
local function vless_plan(input,dir)
    need(type(input.profile)=='string' and #input.profile<=12000,'Вставьте исходящий объект VLESS в JSON (не более 12 КБ)')
    local out=json.parse(input.profile);need(type(out)=='table' and out.protocol=='vless','Ожидается один исходящий объект VLESS в JSON, а не подписка или полная конфигурация')
    local stream=out.streamSettings or {};need(stream.security=='tls' or stream.security=='reality','Требуется TLS или Reality')
    need(stream.network=='tcp' or stream.network=='raw' or stream.network=='xhttp' or stream.network=='ws' or stream.network=='grpc','Неподдерживаемый транспорт VLESS')
    need(not out.proxySettings and not stream.sockopt,'Удалите пользовательские proxySettings/sockopt из первоначального профиля')
    local servers=out.settings and out.settings.vnext;need(type(servers)=='table' and #servers==1,'Требуется ровно один сервер VLESS')
    local v=servers[1];host(v.address);port(v.port);need(type(v.users)=='table' and #v.users==1,'Требуется ровно один пользователь VLESS')
    need(type(v.users[1].id)=='string' and v.users[1].id:match('^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$'),'Некорректный UUID VLESS')
    local tls=stream.security=='tls' and stream.tlsSettings or stream.realitySettings;need(type(tls)=='table' and tls.allowInsecure~=true,'Проверка сертификата должна оставаться включённой')
    out={tag='proxy',protocol='vless',settings=out.settings,streamSettings=stream}
    local config={log={loglevel='none'},inbounds={{tag='local-test',listen='127.0.0.1',port=2081,protocol='socks',settings={udp=true}}},outbounds={out},routing={domainStrategy='AsIs'}}
    write(dir..'/xray.json',json.stringify(config))
    local binary=M.tools().xray;local tested=false
    if binary then local ok=P.exec({binary,'run','-test','-config',dir..'/xray.json'},6);need(ok,'Xray отклонил профиль; настройки VPN не изменялись');tested=true end
    return {kind='vless',protocol='VLESS / Xray',state='DRAFT',validated=tested,files={'xray.json'},local_port=2081,
        checks={'Конфигурация принимает ровно один VLESS outbound с TLS или Reality','SOCKS слушает только 127.0.0.1:2081','Проверка сертификата upstream не отключена'},
        planned_changes={'Запустить отдельный процесс Xray из приватного черновика','Проверить процесс и SOCKS-listener 127.0.0.1:2081','Не менять default route, DNS, UCI и существующий vless-router'},
        note='Подготовлен отдельный локальный SOCKS-профиль. Он начнёт принимать подключения только после preflight и явного включения; автоматическая маршрутизация трафика не добавляется.'}
end
local function mieru_plan(input,dir)
    local endpoint=input.mieru_endpoint or '';local username=input.mieru_user or '';local password=input.mieru_password or ''
    local template=endpoint=='' and username=='' and password==''
    if template then endpoint='server.example.invalid';username='CHANGE_ME';password='CHANGE_ME'
    else host(endpoint);need(#username>0 and #username<=128 and not username:find('%c'),'Введите имя пользователя сервера Mieru')
        need(#password>0 and #password<=512 and not password:find('%c'),'Введите пароль сервера Mieru') end
    local protocol=input.mieru_transport or 'TCP';need(protocol=='TCP' or protocol=='UDP','Выберите TCP или UDP')
    local server={portBindings={{port=port(input.mieru_port or 443),protocol=protocol}}}
    if endpoint:match('^[%d%.]+$') then server.ipAddress=endpoint else server.domainName=endpoint end
    local config={profiles={{profileName='netscope',user={name=username,password=password},servers={server},mtu=1400}},
        activeProfile='netscope',rpcPort=8964,socks5Port=2082,socks5ListenLAN=false,loggingLevel='WARN'}
    write(dir..'/mieru.json',json.stringify(config))
    return {kind='mieru',protocol='Mieru',state=template and 'TEMPLATE' or 'DRAFT',validated=false,files={'mieru.json'},local_port=2082,
        checks={'SOCKS слушает только 127.0.0.1:2082','Runtime использует конфигурацию выбранного черновика, не глобальный профиль','Логи и служебный HOME ограничены каталогом NETSCOPE runtime'},
        planned_changes={'Запустить отдельный процесс Mieru из приватного черновика','Проверить процесс и SOCKS-listener 127.0.0.1:2082','Не менять default route, DNS, UCI и другие VPN'},
        note=template and 'Только шаблон: замените server.example.invalid и оба значения CHANGE_ME данными будущего сервера Mieru. Служба и резервирование не настраивались.'
            or 'Подготовлен отдельный локальный SOCKS-профиль. Он начнёт принимать подключения только после preflight и явного включения; автоматическая маршрутизация трафика не добавляется.'}
end
local function hy2_plan(input,dir)
    local uri=input.hy2_uri or ''
    need(type(uri)=='string' and #uri>=16 and #uri<=4096 and not uri:find('%s') and not uri:find('%c'),'Вставьте одну ссылку Hysteria 2 без пробелов (не более 4 КБ)')
    need(uri:match('^hysteria2://') or uri:match('^hy2://'),'Ожидается одна ссылка hysteria2:// или hy2://, а не подписка')
    local lower=uri:lower();local insecure=lower:find('[?&]insecure=1') or lower:find('[?&]insecure=true')
    local pinned=lower:find('[?&]pinsha256=[^&#]+')
    need(not insecure or pinned,'Нельзя отключать проверку TLS без pinSHA256')
    -- JSON string syntax is a valid quoted YAML scalar and avoids YAML injection.
    local config='server: '..json.stringify(uri)..'\nlazy: true\nsocks5:\n  listen: 127.0.0.1:2083\n  disableUDP: false\nudpTProxy:\n  listen: :12347\n  timeout: 20s\n'
    write(dir..'/hysteria.yaml',config)
    return {kind='hy2',protocol='Hysteria 2',state='DRAFT',validated=false,files={'hysteria.yaml'},local_port=2083,tproxy_port=12347,
        checks={'Принимается ровно одна ссылка hysteria2:// или hy2://','SOCKS5 с UDP слушает только 127.0.0.1:2083','Native UDP TProxy подготовлен на отдельном порту 12347','Отключение проверки TLS разрешено только вместе с pinSHA256'},
        planned_changes={'Запустить отдельный процесс Hysteria 2 из приватного черновика','Проверить SOCKS 127.0.0.1:2083 и UDP TProxy :12347','Не менять default route, DNS, UCI, voice-маршруты и другие VPN'},
        note='Подготовлен отдельный HY2 SOCKS5/UDP + native UDP TProxy-профиль. Сам listener ничего не перехватывает: узкая policy routing для звонков включается отдельно после A/B-теста.'}
end
function M.prepare(input)
    need(type(input)=='table' and (input.kind=='wg' or input.kind=='awg' or input.kind=='vless' or input.kind=='mieru' or input.kind=='hy2'),'Выберите WireGuard, AmneziaWG, VLESS, Mieru или Hysteria 2')
    local storage=C.storage(true);need(storage.mounted and storage.writable and not storage.error and storage.free>16000000,'Требуется доступный для записи USB-накопитель со свободным местом')
    local root=C.ROOT..'/config/setup';C.mkdir(C.ROOT..'/config');C.mkdir(root)
    local count=0;for _ in fs.dir(root) do count=count+1 end;need(count<20,'Достигнут предел в 20 черновиков; безопасно архивируйте или удалите старые')
    local id=os.date('!%Y%m%dT%H%M%S')..'-'..require('luci.sys').uniqueid(5);need(id:match('^[%w%-]+$'),'Некорректный идентификатор черновика')
    local dir=root..'/'..id;need(not fs.lstat(dir),'Конфликт идентификатора черновика');C.mkdir(dir)
    local ok,result=pcall(function()
        local result=(input.kind=='vless' and vless_plan or input.kind=='mieru' and mieru_plan or input.kind=='hy2' and hy2_plan or tunnel_plan)(input,dir)
        result.id=id;C.atomic(dir..'/plan.json',result);return result
    end)
    if not ok then
        for _,name in ipairs({'server.key','client.key','server.conf','client.conf','xray.json','mieru.json','hysteria.yaml','plan.json','plan.json.new'}) do fs.unlink(dir..'/'..name) end
        fs.rmdir(dir);error(tostring(result):match(':%d+: (.*)') or 'Подготовка завершилась ошибкой')
    end
    return result
end
function M.download(id,file)
    local storage=C.storage();need(storage.mounted and not storage.error,'USB недоступен')
    need(C.valid_id(id),'Некорректный черновик')
    need(file=='server.conf' or file=='client.conf' or file=='xray.json' or file=='mieru.json' or file=='hysteria.yaml' or file=='plan.json','Некорректный файл')
    local path=C.ROOT..'/config/setup/'..id..'/'..file;need(C.safe(path) and (fs.lstat(path) or {}).type=='reg','Черновик недоступен');return path
end
local allowed_files={['server.conf']=true,['client.conf']=true,['xray.json']=true,['mieru.json']=true,['hysteria.yaml']=true,['plan.json']=true}
local function draft(id)
    need(C.valid_id(id),'Некорректный черновик')
    local dir=C.ROOT..'/config/setup/'..id;need(C.safe(dir) and (fs.lstat(dir) or {}).type=='dir','Черновик недоступен')
    local path=dir..'/plan.json';need(C.safe(path) and (fs.lstat(path) or {}).type=='reg','План черновика недоступен')
    local value=json.parse(need(C.read(path,20000),'План черновика недоступен'));need(type(value)=='table' and value.id==id,'Некорректный план черновика')
    return value,dir
end
local function runtime_status(manager,kind)
    if not manager then return {active=false,pending=false,healthy=false,id='',kind=kind} end
    local ok,out=P.exec({manager,'status',kind or 'wg'},3);if not ok then return {active=false,pending=false,healthy=false,id='',kind=kind,error='Состояние среды выполнения недоступно'} end
    local value=json.parse(out);if type(value)~='table' or value.kind~=(kind or 'wg') or (value.id~='' and not C.valid_id(value.id)) then
        return {active=false,pending=false,healthy=false,id='',kind=kind,error='Некорректное состояние среды выполнения'}
    end
    return {active=value.active==true,pending=value.pending==true,healthy=value.healthy==true,id=value.id or '',kind=value.kind,interface=value.interface,listen=value.listen,local_port=value.local_port,tproxy_port=value.tproxy_port}
end
M.runtime_status=function(kind)return runtime_status(M.tools().manager,kind or 'wg')end
function M.install_hysteria()
    local tools=M.tools();need(not tools.hysteria,'Hysteria 2 уже установлена')
    local installer=need(tools.hysteria_installer,'Проверенный установщик Hysteria 2 отсутствует')
    local storage=C.storage(true);need(storage.mounted and storage.writable and not storage.error and storage.free>33554432,'Требуется writable USB со свободными 32 МиБ')
    local ok,out=P.exec({installer},120);need(ok,'Установка Hysteria 2 не выполнена: '..tostring(out):sub(1,240))
    local installed=M.tools().hysteria;need(installed~=nil,'Установщик завершился без доступного runtime')
    return {installed=true,path=installed,version='v2.11.0',note='Runtime проверен по закреплённому SHA-256 и установлен на USB. Он не запущен; DNS, маршруты и firewall не менялись.'}
end
function M.list()
    local storage=C.storage();if not storage.mounted or storage.error then return {} end
    local root=C.ROOT..'/config/setup';if (fs.lstat(root) or {}).type~='dir' then return {} end
    local manager=M.tools().manager;local active={};for _,kind in ipairs({'wg','awg','vless','mieru','hy2'}) do active[kind]=runtime_status(manager,kind) end
    local out={};for id in fs.dir(root) do
        if C.valid_id(id) and #out<20 then local ok,value=pcall(draft,id);if ok then
            local live=active[value.kind] or {}
            out[#out+1]={id=id,created=id:sub(1,8)..' '..id:sub(10,15)..' UTC',kind=value.kind,protocol=value.protocol,
                state=value.state,validated=value.validated==true,listen_port=value.listen_port,server_address=value.server_address,
                local_port=value.local_port,tproxy_port=value.tproxy_port,files=value.files or {},note=value.note,active=live.active and live.id==id,pending=live.pending and live.id==id,healthy=live.healthy and live.id==id}
        end end
    end
    table.sort(out,function(a,b)return a.id>b.id end);return out
end
function M.preflight(id)
    local value,dir=draft(id);local checks,blockers={},{}
    local function result(ok,label)checks[#checks+1]=(ok and 'ПРОЙДЕНО · ' or 'БЛОКИРОВКА · ')..label;if not ok then blockers[#blockers+1]=label end end
    local storage=C.storage(true);result(storage.mounted and storage.writable and not storage.error,'USB-накопитель подключён и доступен для записи')
    for _,name in ipairs(value.files or {}) do
        local st=allowed_files[name] and fs.lstat(dir..'/'..name);result(st and st.type=='reg','Приватный файл '..tostring(name)..' существует и не является символической ссылкой')
    end
    local tools=M.tools();local live=inventory();local activation_supported=false
    if value.kind=='wg' or value.kind=='awg' then
        result((value.kind=='wg' and tools.wg or tools.awg)~=nil,'Установлены подходящие инструменты туннеля')
        result(type(value.listen_port)=='number' and not live.used[value.listen_port],'UDP '..tostring(value.listen_port)..' по-прежнему свободен')
        local net=cidr(need(value.server_address,'В черновике нет адреса туннеля'));local overlap=false
        for _,route in ipairs(live.routes) do if net.first<=route.last and route.first<=net.last then overlap=true;break end end
        result(not overlap,'Подсеть туннеля по-прежнему не пересекается с основной таблицей маршрутизации')
        result((C.read('/proc/sys/net/ipv4/ip_forward',8) or ''):match('1')~=nil,'Пересылка IPv4 включена')
        result(candidates({'/usr/sbin/iptables','/sbin/iptables','/usr/bin/iptables'})~=nil,'iptables доступен')
        activation_supported=tools.manager~=nil;result(activation_supported,'Установлен транзакционный диспетчер NETSCOPE')
    elseif value.kind=='vless' then
        result(tools.xray~=nil,'Среда Xray установлена')
        if tools.xray then local ok=P.exec({tools.xray,'run','-test','-config',dir..'/xray.json'},6);result(ok,'Xray принимает сохранённую конфигурацию') end
        result(type(value.local_port)=='number' and not live.used_tcp[value.local_port],'Локальный TCP-порт '..tostring(value.local_port)..' свободен')
        activation_supported=tools.manager~=nil;result(activation_supported,'Установлен транзакционный диспетчер NETSCOPE')
    elseif value.kind=='mieru' then
        result(value.state~='TEMPLATE','Данные сервера Mieru настроены')
        result(tools.mieru~=nil,'Среда Mieru установлена')
        result(type(value.local_port)=='number' and not live.used_tcp[value.local_port],'Локальный TCP-порт '..tostring(value.local_port)..' свободен')
        activation_supported=tools.manager~=nil;result(activation_supported,'Установлен транзакционный диспетчер NETSCOPE')
    elseif value.kind=='hy2' then
        result(tools.hysteria~=nil,'Среда Hysteria 2 установлена')
        result(type(value.local_port)=='number' and not live.used_tcp[value.local_port],'Локальный TCP-порт '..tostring(value.local_port)..' свободен')
        result(type(value.tproxy_port)=='number' and not live.used_udp[value.tproxy_port],'Локальный UDP TProxy-порт '..tostring(value.tproxy_port)..' свободен')
        activation_supported=tools.manager~=nil;result(activation_supported,'Установлен транзакционный диспетчер NETSCOPE')
    else result(false,'Протокол черновика поддерживается') end
    return {id=id,kind=value.kind,ready=#blockers==0,activation_supported=activation_supported,stage='activation-ready',checks=checks,blockers=blockers,
        rollback={'Сначала удалить собственные правила NETSCOPE для перенаправления, входа и пересылки','Остановить только процесс нового профиля','Удалить только его отдельный интерфейс','Восстановить только его файлы; не перезапускать сеть и межсетевой экран'},
        note='Предварительная проверка без изменений завершена. Интерфейсы, процессы, маршруты, DNS и правила межсетевого экрана не менялись.'}
end
function M.delete(id)
    local value,dir=draft(id);local active=runtime_status(M.tools().manager,value.kind);need(active.id~=id or not (active.active or active.pending),'Остановите профиль перед удалением его приватных файлов')
    local seen={};for name in fs.dir(dir) do
        need(allowed_files[name] and not seen[name],'Черновик содержит неожиданный файл; автоматическое удаление отменено')
        local st=fs.lstat(dir..'/'..name);need(st and st.type=='reg','Черновик содержит файл неподдерживаемого типа; автоматическое удаление отменено');seen[name]=true
    end
    for name in pairs(seen) do need(fs.unlink(dir..'/'..name),'Не удалось удалить файл приватного черновика') end
    need(fs.rmdir(dir),'Не удалось удалить каталог приватного черновика')
    return {id=id,deleted=true,kind=value.kind,note='Приватный черновик удалён. Работающие VPN и настройки сети не изменялись.'}
end
function M.activate(id)
    local value=draft(id)
    local report=M.preflight(id);need(report.ready and report.activation_supported,'Предварительная проверка заблокировала включение')
    local manager=need(M.tools().manager,'Транзакционный диспетчер не установлен');local argv={manager,'start',value.kind,id}
    if value.kind=='wg' or value.kind=='awg' then
        local network=cidr(value.server_address).text;argv[#argv+1]=value.server_address;argv[#argv+1]=network;argv[#argv+1]=tostring(value.listen_port)
        for _,route in ipairs(value.routes or {}) do argv[#argv+1]=route end
    end
    local ok,out=P.exec(argv,15);if not ok then error('Запуск '..tostring(value.protocol or value.kind)..' завершился ошибкой и был отменён: '..tostring(out):sub(1,240)) end
    local pending=json.parse(out);if type(pending)~='table' or pending.kind~=value.kind or not pending.pending or pending.id~=id or not pending.healthy then
        P.exec({manager,'rollback',value.kind,id},8);error('Профиль не достиг исправного состояния ожидания; выполнен откат')
    end
    local confirmed,final=P.exec({manager,'confirm',value.kind,id},8);if not confirmed then P.exec({manager,'rollback',value.kind,id},8);error('Не удалось подтвердить профиль; выполнен откат') end
    local state=json.parse(final);need(type(state)=='table' and state.kind==value.kind and state.active and state.healthy and state.id==id,'Подтверждение профиля вернуло некорректное состояние')
    return {id=id,active=true,healthy=true,kind=value.kind,interface=state.interface,listen=state.listen,local_port=state.local_port,tproxy_port=state.tproxy_port,
        note='Отдельный профиль '..tostring(value.protocol or value.kind)..' активен. Существующие VPN, L2TP, UCI, DNS и маршрут по умолчанию не изменялись.'}
end
function M.deactivate(id)
    need(C.valid_id(id),'Некорректный черновик');local value=draft(id);local manager=need(M.tools().manager,'Транзакционный диспетчер не установлен');local state=runtime_status(manager,value.kind)
    need(state.id==id and (state.active or state.pending),'Выбранный профиль не активен')
    local ok,out=P.exec({manager,'stop',value.kind,id},12);need(ok,'Не удалось очистить профиль; перед повтором проверьте только собственные объекты NETSCOPE')
    local final=json.parse(out);need(type(final)=='table' and final.kind==value.kind and not final.active and not final.pending and not final.healthy,'Очистка профиля вернула некорректное состояние')
    return {id=id,active=false,kind=value.kind,note='Сначала удалены собственные правила NETSCOPE, затем отдельный интерфейс или процесс. Другие VPN и маршруты не затронуты.'}
end
return M
