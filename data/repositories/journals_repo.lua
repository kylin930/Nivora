-- 每日记录（轻量日记）：每天最多一份，按日期唯一
local M = {}

local dateUtils = require "utils.date_utils"

local Repo = {}
Repo.__index = Repo

function Repo:getByDate(dateStr)
  return self.db:queryOne("SELECT * FROM journals WHERE record_date = ?", { dateStr })
end

function Repo:get(id)
  return self.db:queryOne("SELECT * FROM journals WHERE id = ?", { id })
end

function Repo:list(limit, offset)
  local rows = self.db:query(
    "SELECT * FROM journals ORDER BY record_date DESC LIMIT ? OFFSET ?",
    { limit or 60, offset or 0 })
  return rows or {}
end

function Repo:listMonth(year, month)
  local first = string.format("%04d-%02d-01", year, month)
  local last = dateUtils.endOfMonth(first)
  return self.db:query(
    "SELECT * FROM journals WHERE record_date >= ? AND record_date <= ? ORDER BY record_date ASC",
    { first, last }) or {}
end

function Repo:monthMap(year, month)
  local rows = self:listMonth(year, month)
  local map = {}
  for _, row in ipairs(rows) do
    map[row.record_date] = row
  end
  return map
end

-- 同一天再次保存视为编辑
function Repo:save(dateStr, content, mood, tags)
  local now = dateUtils.nowMs()
  local existing = self:getByDate(dateStr)
  local tagText = tags
  if type(tags) == "table" then
    tagText = table.concat(tags, ",")
  end
  if existing then
    local affected = self.db:update("journals", {
      content = content,
      mood = mood or 0,
      tags = tagText,
      updated_at = now,
    }, "id = ?", { existing.id })
    if not affected or affected < 1 then return nil, "保存记录失败" end
    return existing.id
  end
  local id = self.db:insert("journals", {
    record_date = dateStr,
    content = content,
    mood = mood or 0,
    tags = tagText,
    created_at = now,
    updated_at = now,
  })
  if not id or id < 1 then return nil, "保存记录失败" end
  return id
end

function Repo:remove(id)
  local affected = self.db:delete("journals", "id = ?", { id })
  if not affected or affected < 1 then return nil, "删除记录失败" end
  return true
end

function Repo:count()
  return self.db:scalar("SELECT COUNT(*) FROM journals", nil, 0)
end

function Repo:countBetween(fromDate, toDate)
  return self.db:scalar(
    "SELECT COUNT(*) FROM journals WHERE record_date >= ? AND record_date <= ?",
    { fromDate, toDate }, 0)
end

M.new = function(db) return setmetatable({ db = db }, Repo) end

return M
