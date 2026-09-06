-- Integration checks for the real QWRT Lua/nixio runtime. All filesystem I/O
-- is redirected to a caller-created /tmp directory; iptables is fully mocked.
local model_path, proxy_path = arg[1], arg[2]
assert(type(model_path) == "string" and type(proxy_path) == "string", "model and proxy paths required")

local fs = require "nixio.fs"
local C = assert(dofile(model_path))
package.loaded["luci.model.netscope_capture"] = C
local P = assert(dofile(proxy_path))
local passed = 0

local function check(value, message)
  assert(value, message)
  passed = passed + 1
end

check(C.ROOT == os.getenv("NETSCOPE_CAPTURE_ROOT"), "test root override was ignored")
check(C.MOUNT == os.getenv("NETSCOPE_CAPTURE_MOUNT"), "test mount override was ignored")
check(C.RUN == os.getenv("NETSCOPE_CAPTURE_RUN"), "test runtime override was ignored")

local storage = C.storage(true)
check(storage.mounted == false, "unmounted USB fixture reported mounted")
check(storage.error == "USB is not mounted", "unexpected USB failure")

C.mkdir(C.RUN)
C.atomic(C.RUN .. "/status.json", { state = "OFF", active = false, heartbeat = os.time() })
local started, start_error = C.submit("start", C.defaults())
check(started == nil and start_error == "USB is not mounted", "start did not fail closed on missing USB")
check(not fs.access(C.RUN .. "/command.json"), "failed start queued a supervisor command")
check(not fs.access(C.RUN .. "/api-lock"), "API lock survived failed start")

local stopped, stop_error = C.submit("stop")
check(stopped and stopped.active == false and stop_error == nil, "idempotent stop failed")
check(not fs.access(C.RUN .. "/command.json"), "idempotent stop queued a command")

local invalid, invalid_error = C.submit("invalid-action")
check(invalid == nil and invalid_error == "Invalid action", "invalid API action was accepted")
check(not fs.access(C.RUN .. "/api-lock"), "API lock survived invalid action")

C.atomic(C.RUN .. "/status.json", { state = "RUNNING", active = true, heartbeat = os.time() - 20 })
local stale = C.status()
check(stale.active == false and stale.state == "INTERRUPTED", "stale supervisor was reported active")

local owned = "netscope-owned-v1"
local chains = {
  { "nat", "PREROUTING", "NETSCOPE-HTTPS" },
  { "nat", "OUTPUT", "NETSCOPE-EGRESS" },
  { "filter", "INPUT", "NETSCOPE-GUARD" },
  { "filter", "INPUT", "NETSCOPE-QUIC" },
  { "filter", "FORWARD", "NETSCOPE-QUIC" },
}
local jumps, bodies, operations = {}, {}, {}
for _, item in ipairs(chains) do
  jumps[table.concat(item, "|")] = 2
  bodies[item[1] .. "|" .. item[3]] = 2
end
local foreign = { chain = true, rules = 7 }

P.exec = function(argv)
  operations[#operations + 1] = table.concat(argv, " ")
  check(argv[1] == "/usr/sbin/iptables", "cleanup invoked a non-iptables process")
  local tab, operation = argv[5], argv[6]
  if operation == "-C" then
    local key = tab .. "|" .. argv[7] .. "|" .. argv[#argv]
    return (jumps[key] or 0) > 0, ""
  elseif operation == "-D" and argv[8] ~= "1" then
    local key = tab .. "|" .. argv[7] .. "|" .. argv[#argv]
    if (jumps[key] or 0) == 0 then return false, "missing" end
    jumps[key] = jumps[key] - 1
    return true, ""
  elseif operation == "-S" then
    local key = tab .. "|" .. argv[7]
    if bodies[key] == nil then return false, "missing" end
    return true, "-A " .. argv[7] .. " -m comment --comment " .. owned .. "\n"
  elseif operation == "-D" and argv[8] == "1" then
    local key = tab .. "|" .. argv[7]
    if (bodies[key] or 0) == 0 then return false, "empty" end
    bodies[key] = bodies[key] - 1
    return true, ""
  elseif operation == "-X" then
    local key = tab .. "|" .. argv[7]
    if bodies[key] ~= 0 then return false, "not empty" end
    bodies[key] = nil
    return true, ""
  end
  return false, "unexpected mock operation"
end

check(P.cleanup() == true, "owned firewall cleanup failed")
for key, value in pairs(jumps) do check(value == 0, "owned jump survived: " .. key) end
for _, item in ipairs(chains) do check(bodies[item[1] .. "|" .. item[3]] == nil, "owned chain survived") end
check(foreign.chain and foreign.rules == 7, "foreign firewall state was changed")
check(P.cleanup() == true, "firewall cleanup is not idempotent")
local trace = table.concat(operations, "\n")
check(not trace:find(" %-F "), "cleanup attempted a chain or table flush")
check(not trace:find("iptables %-F"), "cleanup attempted a filter table flush")

io.write("CAPTURE_INTEGRATION=PASS ASSERTIONS=", passed, "\n")
