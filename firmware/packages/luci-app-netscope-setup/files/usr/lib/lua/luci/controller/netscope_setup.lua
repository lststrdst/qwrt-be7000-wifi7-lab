module('luci.controller.netscope_setup',package.seeall)
function index()
    entry({'admin','services','netscope_setup'},template('netscope/setup'),'Быстрая настройка VPN',86).dependent=false
    entry({'admin','services','netscope_setup','status'},call('read_status')).leaf=true
    entry({'admin','services','netscope_setup','drafts'},call('drafts')).leaf=true
    entry({'admin','services','netscope_setup','prepare'},post('prepare')).leaf=true
    entry({'admin','services','netscope_setup','preflight'},post('preflight')).leaf=true
    entry({'admin','services','netscope_setup','activate'},post('activate')).leaf=true
    entry({'admin','services','netscope_setup','deactivate'},post('deactivate')).leaf=true
    entry({'admin','services','netscope_setup','delete'},post('delete')).leaf=true
    entry({'admin','services','netscope_setup','download'},call('download')).leaf=true
end
local function headers()
    local h=require'luci.http';h.header('Cache-Control','no-store');h.header('X-Content-Type-Options','nosniff');h.header('Referrer-Policy','no-referrer');h.header('X-Frame-Options','SAMEORIGIN');return h
end
function read_status()
    local h=headers();h.prepare_content('application/json');h.write_json(require('luci.model.netscope_setup').status())
end
function drafts()
    local h=headers();h.prepare_content('application/json');h.write_json({drafts=require('luci.model.netscope_setup').list()})
end
local function locked(action)
    local h=headers();h.prepare_content('application/json')
    if h.getenv('REQUEST_METHOD')~='POST' or tonumber(h.getenv('CONTENT_LENGTH') or 0)>20000 then h.status(400,'Некорректный запрос');h.write_json({error='Некорректный запрос'});return end
    local C=require'luci.model.netscope_setup_runtime';local fs=require'nixio.fs';C.mkdir(C.RUN)
    if not fs.mkdir(C.RUN..'/setup-lock','700') then h.status(409,'Занято');h.write_json({error='Уже выполняется другой запрос настройки'});return end
    local ok,result=pcall(action,h);fs.rmdir(C.RUN..'/setup-lock')
    if not ok then h.status(400,'Ошибка запроса');h.write_json({error=tostring(result):match(':%d+: (.*)') or 'Запрос завершился ошибкой'}) else h.write_json(result) end
end
function prepare()
    locked(function(h)local input={};for _,key in ipairs({'kind','endpoint','port','tunnel','lan','profile','mieru_endpoint','mieru_port','mieru_transport','mieru_user','mieru_password','hy2_uri'}) do input[key]=h.formvalue(key) end
        return require('luci.model.netscope_setup').prepare(input) end)
end
function preflight()locked(function(h)return require('luci.model.netscope_setup').preflight(h.formvalue('draft'))end)end
function activate()locked(function(h)return require('luci.model.netscope_setup').activate(h.formvalue('draft'))end)end
function deactivate()locked(function(h)return require('luci.model.netscope_setup').deactivate(h.formvalue('draft'))end)end
function delete()locked(function(h)return require('luci.model.netscope_setup').delete(h.formvalue('draft'))end)end
function download()
    local h=headers();if h.getenv('REQUEST_METHOD')~='GET' then h.status(405,'Требуется GET');return end
    local ok,path=pcall(require('luci.model.netscope_setup').download,h.formvalue('draft'),h.formvalue('file'))
    if not ok then h.status(404,'Не найдено');return end
    h.header('Content-Disposition','attachment; filename="netscope-'..h.formvalue('file')..'"');h.prepare_content('application/octet-stream');h.write(require('luci.model.netscope_setup_runtime').read(path,20000))
end
