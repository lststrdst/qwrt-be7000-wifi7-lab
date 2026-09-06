-- Authenticated, explicit, one-shot HTTPS import. Never installs routes or profiles.
local M={}
local C=require'luci.model.netscope_setup_runtime'
local fs=require'nixio.fs'
local function need(ok,message)assert(ok,message);return ok end
function M.public_ipv4(value)
    if type(value)~='string' then return false end
    local parts={};for p in value:gmatch('[^.]+') do
        if not p:match('^%d+$') or (#p>1 and p:sub(1,1)=='0') or tonumber(p)>255 then return false end
        parts[#parts+1]=tonumber(p)
    end
    if #parts~=4 or table.concat(parts,'.')~=value then return false end
    local a,b,c=unpack(parts)
    return not (a==0 or a==10 or a==127 or a>=224 or (a==100 and b>=64 and b<=127)
        or (a==169 and b==254) or (a==172 and b>=16 and b<=31)
        or (a==192 and (b==168 or (b==0 and (c==0 or c==2)) or (b==88 and c==99)))
        or (a==198 and (b==18 or b==19 or (b==51 and c==100))) or (a==203 and b==0 and c==113))
end
function M.validate(value)
    need(type(value)=='string' and #value<=4096 and not value:find('[%c%s"\\#]'),'Некорректный адрес подписки')
    local authority=value:match('^https://([^/?]+)');need(authority,'Нужна HTTPS-подписка')
    local host=authority:gsub(':443$',''):lower()
    need(#host>0 and #host<=253 and host:match('^[a-z0-9%.%-]+$') and not host:find('..',1,true),'Нужен публичный DNS-адрес, порт 443')
    for label in host:gmatch('[^.]+') do need(#label<=63 and label:match('^[a-z0-9]') and label:match('[a-z0-9]$'),'Некорректный DNS-адрес') end
    need(host:sub(1,1)~='.' and host:sub(-1)~='.' and host~='localhost' and not host:match('%.localhost$'),'Локальные адреса запрещены')
    if host:match('^[%d%.]+$') then need(M.public_ipv4(host),'Нужен публичный адрес подписки') end
    return host
end
function M.fetch(value)
    local host=M.validate(value)
    need(fs.access('/usr/bin/curl') and fs.access('/usr/bin/lua'),'Для загрузки подписки нужны curl с проверкой TLS и Lua; пока импортируйте файл')
    -- DNS in a bounded child, then pin a validated IPv4 in curl: no second resolution/rebinding.
    local code="local a=require('nixio').getaddrinfo('"..host.."');for _,v in ipairs(a or {})do if v.family=='inet' and v.address then print(v.address) end end"
    local ok,addresses=C.exec({'/usr/bin/lua','-e',code},5);need(ok,'Не удалось разрешить адрес подписки')
    local selected=nil;for address in addresses:gmatch('[^\r\n]+')do need(M.public_ipv4(address),'Подписка указывает на непубличную сеть');selected=selected or address end
    need(selected,'Нет публичного IPv4 для подписки')
    C.mkdir(C.RUN);local dir=C.RUN..'/subscription-'..require'nixio'.getpid()
    need(C.safe(dir) and not fs.lstat(dir),'Импорт уже выполняется');need(fs.mkdir(dir,'700'),'Не удалось создать временный каталог')
    local path=dir..'/request.conf'
    local success,result=pcall(function()
        local f=need(io.open(path,'wb'),'Не удалось открыть запрос');local wrote=f:write('url = "'..value..'"\n');local closed=f:close();need(wrote and closed and fs.chmod(path,'600'),'Не удалось подготовить запрос')
        -- No URL/credentials in argv, inherited proxies, redirect following, verbose logs or disk response.
        local good,out=C.exec({'/usr/bin/curl','--disable','--config',path,'--silent','--fail','--proto','=https','--noproxy','*','--ipv4',
            '--resolve',host..':443:'..selected,'--connect-timeout','5','--max-time','12','--max-filesize','65535','--max-redirs','0',
            '--write-out','\n%{http_code}'},15)
        need(good and #out<65536,'Загрузка не удалась: проверьте ссылку, сертификат сервера или размер (до 64 КБ)')
        local body,status=out:match('^(.*)\n(%d%d%d)$');need(status=='200' and body and #body>0,'Сервер не вернул подписку (ожидается HTTP 200 без перенаправлений)')
        return {content=body}
    end)
    fs.unlink(path);fs.rmdir(dir)
    if not success then error(tostring(result):match(':%d+: (.*)') or 'Импорт подписки не выполнен') end
    return result
end
return M
