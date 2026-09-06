-- Pure production-module tests: mocked DNS/curl/fs; no network or real credentials.
local root=arg[1] or 'firmware/packages/luci-app-netscope-setup/files/usr/lib/lua/'
package.path=root..'?.lua;'..package.path
local files={}
local addresses='1.1.1.1\n'
local response='[{}]\n200'
local curl_ok=true
local commands={}
local C={RUN='/test-ram',safe=function()return true end,mkdir=function()end}
function C.exec(argv)
    commands[#commands+1]=argv
    for _,value in ipairs(argv)do assert(not value:find('access=REPLACE',1,true),'secret in argv')end
    if argv[1]=='/usr/bin/lua' then return true,addresses end
    assert(files['/test-ram/subscription-1/request.conf']:find('access=REPLACE',1,true))
    return curl_ok,response
end
package.preload['luci.model.netscope_setup_runtime']=function()return C end
package.preload['nixio']=function()return {getpid=function()return 1 end} end
package.preload['nixio.fs']=function()return {access=function()return true end,lstat=function(p)return files[p]end,mkdir=function()return true end,chmod=function()return true end,unlink=function(p)files[p]=nil end,rmdir=function()end}end
local open=io.open
io.open=function(path)return {write=function(_,data)files[path]=data;return true end,close=function()return true end}end
local M=require'luci.model.netscope_subscription'
for _,ip in ipairs({'127.0.0.1','10.0.0.1','172.16.0.1','192.168.0.1','169.254.169.254','100.64.0.1','0.0.0.0','224.0.0.1','198.18.0.1','198.51.100.2','203.0.113.1','192.0.2.1','0177.0.0.1','2130706433','1.2.3.256','1..2.3.4'})do assert(not M.public_ipv4(ip),ip) end
assert(M.public_ipv4('1.1.1.1'))
for _,url in ipairs({'http://example.com','https://localhost','https://a.localhost','https://example.com:8443','https://user@example.com','https://127.0.0.1','https://[::1]','https://example.com/\nheader','https://example.com/"','https://example.com/#foo'})do assert(not pcall(M.validate,url),url)end
local url='https://example.com/sub?access=REPLACE'
assert(M.validate(url)=='example.com')
assert(M.fetch(url).content=='[{}]')
assert(next(files)==nil,'temporary request not cleaned')
local flags=table.concat(commands[#commands],' ')
assert(flags:find('--resolve example.com:443:1.1.1.1',1,true))
assert(flags:find('--noproxy *',1,true) and not flags:find('--location',1,true))
for _,bad in ipairs({'127.0.0.1\n','1.1.1.1\n10.0.0.1\n',''})do addresses=bad;assert(not pcall(M.fetch,url));assert(next(files)==nil)end
addresses='1.1.1.1\n'
for _,bad in ipairs({'redirect\n302',string.rep('x',65536),'bad\n403','\n200'})do response=bad;assert(not pcall(M.fetch,url));assert(next(files)==nil)end
response='secret server diagnostic';curl_ok=false;local ok,err=pcall(M.fetch,url);assert(not ok and not tostring(err):find(response,1,true));assert(next(files)==nil)
io.open=open
print('subscription: validation, SSRF pinning, bounded response, status and cleanup OK')
