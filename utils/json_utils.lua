-- JSON 字段容错：数据库里存的是 TEXT，解析失败时退回安全默认值，不抛错给 UI
local M = {}

function M.decode(text, fallback)
  if text == nil or text == "" then return fallback end
  local ok, value = pcall(function() return json.decode(tostring(text)) end)
  if not ok or type(value) ~= "table" then return fallback end
  return value
end

function M.encode(value)
  if value == nil then return nil end
  local ok, text = pcall(function() return json.encode(value) end)
  if not ok then return nil end
  return tostring(text)
end

-- 把数组表转成按数值比较用的 set
function M.toSet(list)
  local set = {}
  if type(list) ~= "table" then return set end
  for _, item in ipairs(list) do
    set[tonumber(item)] = true
  end
  return set
end

return M
