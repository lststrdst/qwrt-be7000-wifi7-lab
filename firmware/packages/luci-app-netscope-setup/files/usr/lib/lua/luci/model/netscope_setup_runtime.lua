-- Small standalone subset of NETSCOPE's proven storage/process helpers.
-- No Capture, Docker, packet inspection or network configuration dependency.
local M={ROOT='/mnt/sda1/NETSCOPE',MOUNT='/mnt/sda1',RUN='/tmp/netscope-setup'}
local fs,n,j=require'nixio.fs',require'nixio',require'luci.jsonc'
function M.read(path,limit)local f=io.open(path,'rb');if not f then return nil end;local s=f:read(limit or 20000);f:close();return s end
function M.safe(path)
    if type(path)~='string' or path:find('..',1,true) or path:sub(1,1)~='/' then return false end
    local p='';for v in path:gmatch('[^/]+')do p=p..'/'..v;local st=fs.lstat(p);if st and st.type=='lnk' then return false end end;return true
end
function M.mkdir(path)assert(M.safe(path),'Unsafe storage path');assert(fs.mkdirr(path,'700'));assert(fs.chmod(path,'700'));return path end
function M.atomic(path,value)
    assert(M.safe(path) and M.safe(path..'.new'),'Unsafe file');local f=assert(io.open(path..'.new','wb'))
    assert(f:write(j.stringify(value)));assert(f:close());assert(fs.chmod(path..'.new','600'));assert(fs.rename(path..'.new',path))
end
function M.storage(test)
    local out={path=M.ROOT,mount=M.MOUNT,mounted=false,writable=false,free=0}
    if not M.safe(M.ROOT) then out.error='Unsafe USB path';return out end
    for line in (M.read('/proc/mounts',65536) or ''):gmatch('[^\n]+')do
        local _,path,kind,opts=line:match('^(%S+) (%S+) (%S+) (%S+)')
        if path==M.MOUNT then out.mounted=true;out.filesystem=kind;out.writable=opts=='rw' or opts:match('^rw,')~=nil end
    end
    if not out.mounted then out.error='USB is not mounted';return out end
    local st=fs.statvfs(M.MOUNT);if st then out.free=(st.bavail or 0)*(st.frsize or st.bsize or 4096) end
    if test and out.writable then
        local path=M.MOUNT..'/.netscope-setup-write-'..n.getpid();if not M.safe(path) or fs.lstat(path) then out.error='Write-test path collision';return out end
        local f=io.open(path,'wb');out.writable=f~=nil
        if f then local wrote=f:write('NETSCOPE setup write test\n');local closed=f:close();fs.unlink(path);out.writable=wrote~=nil and closed~=nil end
    end
    if not out.writable then out.error='USB is read-only or write test failed' end;return out
end
function M.valid_id(id)return type(id)=='string' and #id==26 and id:match('^%d%d%d%d%d%d%d%dT%d%d%d%d%d%d%-%x%x%x%x%x%x%x%x%x%x$')~=nil end
function M.exec(argv,seconds)
    local r,w=n.pipe();assert(r and w);local pid=n.fork();assert(pid)
    if pid==0 then
        r:close();local null=n.open('/dev/null','r');n.dup(null,n.stdin);n.dup(w,n.stdout);n.dup(w,n.stderr);w:close();n.exec(unpack(argv));os.exit(127)
    end
    w:close();r:setblocking(false);local out='';local started=os.time()
    while true do
        local s=r:read(8192);if s and #out<65536 then out=out..s:sub(1,65536-#out)end
        local got,why,code=n.waitpid(pid,'nohang')
        if got and got>0 then local tail=r:read(8192);if tail and #out<65536 then out=out..tail:sub(1,65536-#out)end;r:close();return why=='exited' and code==0,out end
        if os.time()-started>(seconds or 4)then n.kill(pid,9);n.waitpid(pid);r:close();return false,'Operation timed out'end
        n.nanosleep(0,50000000)
    end
end
return M
