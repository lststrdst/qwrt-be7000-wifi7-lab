module('luci.controller.netscope_setup',package.seeall)
function index()
    entry({'admin','services','netscope_setup'},template('netscope/setup'),'VPN Quick setup',86).dependent=false
    entry({'admin','services','netscope_setup','status'},call('read_status')).leaf=true
    entry({'admin','services','netscope_setup','prepare'},post('prepare')).leaf=true
    entry({'admin','services','netscope_setup','download'},call('download')).leaf=true
end
local function headers()
    local h=require'luci.http';h.header('Cache-Control','no-store');h.header('X-Content-Type-Options','nosniff');h.header('Referrer-Policy','no-referrer');h.header('X-Frame-Options','SAMEORIGIN');return h
end
function read_status()
    local h=headers();h.prepare_content('application/json');h.write_json(require('luci.model.netscope_setup').status())
end
function prepare()
    local h=headers();h.prepare_content('application/json')
    if h.getenv('REQUEST_METHOD')~='POST' or tonumber(h.getenv('CONTENT_LENGTH') or 0)>20000 then h.status(400,'Invalid request');h.write_json({error='Invalid request'});return end
    local input={};for _,key in ipairs({'kind','endpoint','port','tunnel','lan','profile','mieru_endpoint','mieru_port','mieru_transport','mieru_user','mieru_password'}) do input[key]=h.formvalue(key) end
    local C=require'luci.model.netscope_setup_runtime';local fs=require'nixio.fs';C.mkdir(C.RUN)
    if not fs.mkdir(C.RUN..'/setup-lock','700') then h.status(409,'Busy');h.write_json({error='Another setup request is running'});return end
    local ok,result=pcall(function()return require('luci.model.netscope_setup').prepare(input)end);fs.rmdir(C.RUN..'/setup-lock')
    if not ok then h.status(400,'Preparation failed');h.write_json({error=tostring(result):match(':%d+: (.*)') or 'Preparation failed'}) else h.write_json(result) end
end
function download()
    local h=headers();if h.getenv('REQUEST_METHOD')~='GET' then h.status(405,'GET required');return end
    local ok,path=pcall(require('luci.model.netscope_setup').download,h.formvalue('draft'),h.formvalue('file'))
    if not ok then h.status(404,'Not found');return end
    h.header('Content-Disposition','attachment; filename="netscope-'..h.formvalue('file')..'"');h.prepare_content('application/octet-stream');h.write(require('luci.model.netscope_setup_runtime').read(path,20000))
end
