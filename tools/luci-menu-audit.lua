-- Read-only LuCI menu audit for the exact QWRT base used by NETSCOPE.
-- Run locally on the router: lua /tmp/luci-menu-audit.lua
local dispatcher = require "luci.dispatcher"
local http = require "luci.http"

dispatcher.context.path = {}
dispatcher.context.request = {}
http.formvalue = function() return nil end
http.getenv = function(name)
  if name == "SCRIPT_NAME" then return "/cgi-bin/luci" end
  return nil
end

local tree = dispatcher.createtree()
local total = 0
local missing = {}
local duplicate_labels = {}
local english = {}

local function plain(value)
  return tostring(value or ""):gsub("<[^>]+>", ""):gsub("&#38;", "&")
end

local function readable(path)
  local handle = io.open(path, "rb")
  if not handle then return false end
  handle:close()
  return true
end

local function walk(node, path)
  if type(node) ~= "table" then return end
  if node.title or node.target then
    total = total + 1
    local route = table.concat(path, "/")
    local title = plain(node.title)
    if title:find("[A-Za-z]") then english[title] = english[title] or route end
    local target = node.target
    if type(target) == "table" and target.type == "cbi" and type(target.model) == "string" then
      local file = "/usr/lib/lua/luci/model/cbi/" .. target.model .. ".lua"
      if not readable(file) then missing[#missing + 1] = route .. " -> " .. file end
    elseif type(target) == "table" and target.type == "template" and type(target.view) == "string" then
      local file = "/usr/lib/lua/luci/view/" .. target.view .. ".htm"
      if not readable(file) then missing[#missing + 1] = route .. " -> " .. file end
    end
  end
  local labels = {}
  for key, child in pairs(node.nodes or {}) do
    local title = plain(child.title)
    if title ~= "" then
      if labels[title] then
        duplicate_labels[#duplicate_labels + 1] = table.concat(path, "/") .. " -> " .. title .. " (" .. labels[title] .. ", " .. key .. ")"
      else
        labels[title] = key
      end
    end
  end
  for key, child in pairs(node.nodes or {}) do
    local child_path = {}
    for index, value in ipairs(path) do child_path[index] = value end
    child_path[#child_path + 1] = key
    walk(child, child_path)
  end
end

walk(tree, {})
local english_titles = {}
for title, route in pairs(english) do english_titles[#english_titles + 1] = { title, route } end
table.sort(english_titles, function(a, b) return a[1] < b[1] end)

io.write("TOTAL=", total, "\n")
io.write("MISSING_TARGETS=", #missing, "\n")
for _, value in ipairs(missing) do io.write("MISSING\t", value, "\n") end
io.write("DUPLICATE_SIBLING_LABELS=", #duplicate_labels, "\n")
for _, value in ipairs(duplicate_labels) do io.write("DUPLICATE\t", value, "\n") end
io.write("ENGLISH_TITLES=", #english_titles, "\n")
for _, value in ipairs(english_titles) do io.write("ENGLISH\t", value[1], "\t", value[2], "\n") end

if #missing > 0 or #duplicate_labels > 0 then os.exit(1) end
