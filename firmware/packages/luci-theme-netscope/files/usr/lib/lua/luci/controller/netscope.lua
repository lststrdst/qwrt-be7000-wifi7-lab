-- Authenticated, read-only connection inventory and bounded own-device lab.
module('luci.controller.netscope', package.seeall)

function index()
    local p = entry({'admin','status','netscope'}, call('page'), 'NETSCOPE', 9)
    p.dependent = true
    entry({'admin','status','netscope','snapshot'}, call('snapshot')).leaf = true
    entry({'admin','status','netscope','voice'}, call('voice')).leaf = true
    entry({'admin','status','netscope','lab'}, post('lab')).leaf = true
    local capture = entry({'admin','status','netscope','capture'},call('capture_read','status'))
    capture.dependent = true -- Old Lua LuCI requires an explicit parent node.
    for _,name in ipairs({'status','live','dns','tls','http','https','sessions','session','pcap','body','settings','ca','proxy-status'}) do
        entry({'admin','status','netscope','capture',name},call('capture_read',name)).leaf=true
    end
    for _,name in ipairs({'start','stop','delete','save-settings','runtime-start','ca-prepare','ca-regenerate'}) do
        entry({'admin','status','netscope','capture',name},post('capture_write',name)).leaf=true
    end
end

local function headers()
    local h = require 'luci.http'
    h.header('Cache-Control', 'no-store')
    h.header('X-Content-Type-Options', 'nosniff')
    h.header('Referrer-Policy', 'no-referrer')
    h.header('X-Frame-Options', 'SAMEORIGIN')
end

function page()
    headers()
    if require('luci.model.uci').cursor():get('luci', 'main', 'mediaurlbase') == '/luci-static/netscope' then
        require('luci.template').render('themes/netscope/traffic')
        return
    end
    require('luci.http').header('Content-Security-Policy', "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'self'; base-uri 'self'; form-action 'self'")
    require('luci.template').render('netscope')
end

function snapshot()
    headers()
    local h = require 'luci.http'
    local ok, data = pcall(require('luci.model.netscope').snapshot)
    if not ok then h.status(503, 'Unavailable'); data = {error='Источник данных временно недоступен'} end
    h.prepare_content('application/json')
    h.write_json(data)
end

function voice()
    headers()
    local h=require'luci.http'
    if h.getenv('REQUEST_METHOD')~='GET' then h.status(405,'GET required');h.prepare_content('application/json');h.write_json({error='Требуется GET'});return end
    local ok,model=pcall(require,'luci.model.netscope_setup')
    local data=ok and model.voice_telemetry and model.voice_telemetry() or {available=false,active=false,healthy=false,history={},endpoints={}}
    h.prepare_content('application/json');h.write_json(data)
end

function lab()
    headers()
    local h = require 'luci.http'
    h.status(410,'Gone')
    h.prepare_content('application/json')
    h.write_json({error='Temporary lab retired. Use Capture.'})
end

local function result(data,err,code)
    local h=require'luci.http';h.prepare_content('application/json')
    if not data then h.status(code or 400,'Request failed');h.write_json({error=err or 'Unavailable'}) else h.write_json(data) end
end

function capture_read(kind)
    headers();local h=require'luci.http';local C=require'luci.model.netscope_capture'
    if h.getenv('REQUEST_METHOD')~='GET' then return result(nil,'GET required',405) end
    local id=h.formvalue('session') or C.status().session
    if kind=='status' then return result(C.status()) end
    if kind=='settings' then return result(C.settings()) end
    if kind=='proxy-status' then return result(require('luci.model.netscope_capture_proxy').preflight()) end
    if kind=='ca' then
        local ca=require('luci.model.netscope_capture_proxy').ca()
        if not ca.ready then return result(nil,'Inspection CA is not prepared',409) end
        local pem=C.read(ca.file,8192);if not pem or pem:find('PRIVATE KEY',1,true) then return result(nil,'Public CA unavailable',409) end
        h.header('Content-Disposition','attachment; filename="netscope-inspection-ca.cer"');h.prepare_content('application/x-x509-ca-cert');h.write(pem);return
    end
    if kind=='sessions' then return result(C.sessions(h.formvalue('offset'))) end
    if kind=='dns' or kind=='tls' or (kind=='http' or kind=='https') and not h.formvalue('id') then return result(C.events(id,kind,h.formvalue('after'),h.formvalue('limit'))) end
    if kind=='http' or kind=='https' then return result(C.http(id,h.formvalue('id'),h.formvalue('reveal')=='1',kind)) end
    local path,err=C.session(id);if not path then return result(nil,err,404) end
    if kind=='session' then return result({session=C.json(path..'/session.json'),pcap=C.files(id)}) end
    if kind=='live' then
        local file=path..'/flows/connections.json';if not C.safe(file) then return result(nil,'Unsafe path') end
        return result(C.json(file) or {flows={},devices={},warning='Waiting for the first captured snapshot'})
    end
    if kind=='pcap' or kind=='body' then
        local state=C.status();if state.active and state.session==id and kind=='pcap' then return result(nil,'Stop this capture before downloading a stable PCAP chunk',409) end
        local file=h.formvalue('file') or '';local folder=kind=='pcap' and '/pcap/' or '/flows/'
        if kind=='pcap' and not file:match('^capture%.pcap%d*$') or kind=='body' and not (file:match('^body%-%d+%-[a-z]+%.bin$') or file:match('^https%-body%-%d+%-[a-z]+%.bin$')) then return result(nil,'Invalid filename') end
        local full=path..folder..file;local fs=require'nixio.fs';local stat=fs.lstat(full)
        if not C.safe(full) or not stat or stat.type~='reg' then return result(nil,'File unavailable',404) end
        local f=io.open(full,'rb');if not f then return result(nil,'File unavailable',404) end
        h.header('Content-Disposition','attachment; filename="'..file..'"');h.header('Content-Length',tostring(stat.size))
        h.prepare_content(kind=='pcap' and 'application/vnd.tcpdump.pcap' or 'application/octet-stream')
        while true do local chunk=f:read(65536);if not chunk then break end;h.write(chunk) end;f:close();return
    end
    result(nil,'Unknown endpoint',404)
end

function capture_write(kind)
    headers();local h=require'luci.http';local C=require'luci.model.netscope_capture'
    -- post() enforces the existing LuCI CSRF token before dispatch.
    if h.getenv('REQUEST_METHOD')~='POST' then return result(nil,'POST required',405) end
    if tonumber(h.getenv('CONTENT_LENGTH') or 0)>8192 then return result(nil,'Request too large',413) end
    if kind=='runtime-start' or kind=='ca-prepare' or kind=='ca-regenerate' then
        if C.status().active then return result(nil,'Stop Capture before HTTPS setup',409) end
        local fs=require'nixio.fs';C.mkdir(C.RUN)
        if not fs.mkdir(C.RUN..'/api-lock','700') then return result(nil,'Another request is in progress',409) end
        local ok,data=pcall(function()
            local P=require'luci.model.netscope_capture_proxy'
            if kind=='runtime-start' then assert(P.exec({'/etc/init.d/netscope-docker','start'},4),'Runtime start failed')
            elseif kind=='ca-prepare' then assert(P.prepare_ca().ready,'CA preparation failed')
            else assert(P.regenerate(h.formvalue('confirm')),'CA regeneration failed') end
            local st=P.preflight();C.atomic(C.RUN..'/proxy-preflight.json',st);return st
        end)
        fs.rmdir(C.RUN..'/api-lock');return result(ok and data or nil,ok and nil or 'HTTPS setup failed; no interception started',409)
    end
    if kind=='delete' then
        local id=h.formvalue('session');if h.formvalue('confirm')~=id then return result(nil,'Explicit session confirmation required') end
        local ok,err=C.delete(id);return result(ok and {ok=true} or nil,err,409)
    end
    local settings
    if kind=='start' or kind=='save-settings' then
        local raw=h.formvalue('settings') or '';if #raw>4096 then return result(nil,'Settings too large') end
        settings=require('luci.jsonc').parse(raw);local valid,err=C.validate(settings);if not valid then return result(nil,err) end;settings=valid
    end
    if kind=='save-settings' then
        local st=C.storage(true);if st.error then return result(nil,st.error,409) end
        C.mkdir(C.ROOT);C.mkdir(C.ROOT..'/config');C.atomic(C.ROOT..'/config/settings.json',settings);return result({ok=true})
    end
    local state,err=C.submit(kind,settings);return result(state,err,409)
end
