-- 倒数日：支持每年重复，闰年与月末边界由 date_utils 处理
local M = {}

local dateUtils = require "utils.date_utils"

local Repo = {}
Repo.__index = Repo

function Repo:decorate(item)
  if not item then return nil end
  local repeatYearly = item.repeat_yearly == 1
  local today = dateUtils.today()
  local effective = item.target_date
  if repeatYearly then
    effective = dateUtils.nextYearly(item.target_date)
  end
  local delta = dateUtils.diffDays(today, effective)
  item.effective_date = effective
  item.daysLeft = delta
  item.isYearly = repeatYearly
  if delta > 0 then
    item.statusText = "还有 " .. delta .. " 天"
  elseif delta == 0 then
    item.statusText = "就是今天"
  else
    item.statusText = "已过去 " .. (-delta) .. " 天"
  end
  return item
end

function Repo:list()
  local rows = self.db:query("SELECT * FROM countdowns ORDER BY target_date ASC") or {}
  local list = {}
  for _, row in ipairs(rows) do
    list[#list + 1] = self:decorate(row)
  end
  table.sort(list, function(a, b)
    local aKey = a.daysLeft >= 0 and a.daysLeft or (100000 + (-a.daysLeft))
    local bKey = b.daysLeft >= 0 and b.daysLeft or (100000 + (-b.daysLeft))
    return aKey < bKey
  end)
  return list
end

function Repo:get(id)
  return self:decorate(self.db:queryOne("SELECT * FROM countdowns WHERE id = ?", { id }))
end

function Repo:create(data)
  local now = dateUtils.nowMs()
  local id = self.db:insert("countdowns", {
    title = data.title,
    description = data.description,
    target_date = data.target_date,
    repeat_yearly = data.repeat_yearly and 1 or 0,
    icon = data.icon or "star",
    color = data.color or "#6750A4",
    kind = data.kind,
    reminder_days = data.reminder_days or 0,
    created_at = now,
    updated_at = now,
  })
  if not id or id < 1 then return nil, "创建倒数日失败" end
  return id
end

function Repo:update(id, data)
  local row = { updated_at = dateUtils.nowMs() }
  for _, key in ipairs({ "title", "description", "target_date", "icon", "color", "kind" }) do
    if data[key] ~= nil then row[key] = data[key] end
  end
  if data.repeat_yearly ~= nil then row.repeat_yearly = data.repeat_yearly and 1 or 0 end
  if data.reminder_days ~= nil then row.reminder_days = data.reminder_days end
  local affected = self.db:update("countdowns", row, "id = ?", { id })
  if not affected or affected < 1 then return nil, "更新倒数日失败" end
  return true
end

function Repo:remove(id)
  local affected = self.db:delete("countdowns", "id = ?", { id })
  if not affected or affected < 1 then return nil, "删除倒数日失败" end
  return true
end

-- 首页展示：最近 3 条
function Repo:upcoming(limit)
  local list = self:list()
  local result = {}
  for _, item in ipairs(list) do
    result[#result + 1] = item
    if #result >= (limit or 3) then break end
  end
  return result
end

M.new = function(db) return setmetatable({ db = db }, Repo) end

return M
