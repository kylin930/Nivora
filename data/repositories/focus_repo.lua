-- 专注记录：番茄钟落库与统计
local M = {}

local dateUtils = require "utils.date_utils"

local Repo = {}
Repo.__index = Repo

function Repo:create(record)
  local id = self.db:insert("focus_records", {
    todo_id = record.todo_id,
    start_time = record.start_time,
    end_time = record.end_time,
    duration_seconds = math.floor(record.duration_seconds or 0),
    completed = record.completed and 1 or 0,
    note = record.note,
    created_at = dateUtils.nowMs(),
  })
  if not id or id < 1 then return nil, "保存专注记录失败" end
  return id
end

function Repo:recent(limit)
  return self.db:query(
    "SELECT f.*, t.title AS todo_title FROM focus_records f " ..
    "LEFT JOIN todos t ON t.id = f.todo_id ORDER BY f.start_time DESC LIMIT ?",
    { limit or 30 }) or {}
end

function Repo:totalSeconds(fromMs, toMs)
  local sql = "SELECT COALESCE(SUM(duration_seconds), 0) AS total FROM focus_records"
  local args = {}
  if fromMs and toMs then
    sql = sql .. " WHERE start_time >= ? AND start_time <= ?"
    args = { fromMs, toMs }
  end
  return self.db:scalar(sql, args, 0) or 0
end

function Repo:countBetween(fromMs, toMs)
  return self.db:scalar(
    "SELECT COUNT(*) FROM focus_records WHERE start_time >= ? AND start_time <= ? AND completed = 1",
    { fromMs, toMs }, 0)
end

-- 指定区间内按天汇总秒数
function Repo:secondsByDay(fromDate, toDate)
  local rows = self.db:query(
    "SELECT date(start_time/1000, 'unixepoch', 'localtime') AS day, " ..
    "COALESCE(SUM(duration_seconds), 0) AS total FROM focus_records " ..
    "WHERE start_time >= ? AND start_time <= ? GROUP BY day",
    { dateUtils.msOf(fromDate, 0, 0), dateUtils.msOf(toDate, 23, 59) })
  local map = {}
  for _, row in ipairs(rows or {}) do
    map[row.day] = tonumber(row.total) or 0
  end
  return map
end

function Repo:remove(id)
  local affected = self.db:delete("focus_records", "id = ?", { id })
  if not affected or affected < 1 then return nil, "删除专注记录失败" end
  return true
end

function Repo:weekSeconds()
  local today = dateUtils.today()
  local start = dateUtils.startOfWeek(today, 1)
  return self:totalSeconds(dateUtils.msOf(start, 0, 0), dateUtils.msOf(today, 23, 59)), start
end

M.new = function(db) return setmetatable({ db = db }, Repo) end

return M
