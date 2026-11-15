-- 习惯数据访问与统计规则。
-- 连续打卡不能按"记录条数"计算：必须按习惯的排期日跳过非计划日期，
-- 并正确处理暂停中的习惯与历史补录。
local M = {}

local dateUtils = require "utils.date_utils"
local jsonUtils = require "utils.json_utils"

local Repo = {}
Repo.__index = Repo

local function boolToInt(value)
  if value == nil then return 1 end
  if value == true or value == 1 or value == "1" then return 1 end
  return 0
end

-- ---------- 排期规则 ----------

function Repo:config(habit)
  local cfg = jsonUtils.decode(habit.frequency_config, {})
  cfg.days = jsonUtils.toSet(cfg.days or {})
  cfg.times = tonumber(cfg.times) or tonumber(habit.target_count) or 1
  if cfg.times < 1 then cfg.times = 1 end
  return cfg
end

-- 某天是否需要打卡
function Repo:isScheduledOn(habit, dateStr)
  if habit.is_active == 0 then return false end
  local freq = habit.frequency_type or "daily"
  if freq == "daily" then return true end
  if freq == "weekly_days" then
    local cfg = self:config(habit)
    return cfg.days[dateUtils.weekday(dateStr)] == true
  end
  -- weekly_count：任意一天都可以打卡，达标以周为单位计算
  return true
end

function Repo:targetCount(habit)
  return self:config(habit).times
end

function Repo:frequencyLabel(habit)
  local freq = habit.frequency_type or "daily"
  if freq == "daily" then return "每天" end
  if freq == "weekly_days" then
    local cfg = self:config(habit)
    local names = {}
    for day = 1, 7 do
      if cfg.days[day] then names[#names + 1] = "周" .. dateUtils.WEEK_CN[day] end
    end
    if #names == 0 then return "每周（未选择日期）" end
    return "每周 " .. table.concat(names, "、")
  end
  return "每周 " .. self:targetCount(habit) .. " 次"
end

-- ---------- 查询 ----------

function Repo:list(activeOnly)
  local sql = "SELECT * FROM habits"
  if activeOnly then sql = sql .. " WHERE is_active = 1" end
  sql = sql .. " ORDER BY sort_order ASC, id ASC"
  return self.db:query(sql)
end

function Repo:get(id)
  return self.db:queryOne("SELECT * FROM habits WHERE id = ?", { id })
end

function Repo:records(habitId, fromDate, toDate)
  local sql = "SELECT * FROM habit_records WHERE habit_id = ?"
  local args = { habitId }
  if fromDate then
    sql = sql .. " AND record_date >= ?"
    args[#args + 1] = fromDate
  end
  if toDate then
    sql = sql .. " AND record_date <= ?"
    args[#args + 1] = toDate
  end
  sql = sql .. " ORDER BY record_date ASC"
  return self.db:query(sql, args)
end

-- dateStr → 已打卡的 habitId 集合
function Repo:recordsOn(dateStr)
  local rows = self.db:query("SELECT habit_id FROM habit_records WHERE record_date = ?", { dateStr })
  local map = {}
  for _, row in ipairs(rows or {}) do
    map[row.habit_id] = true
  end
  return map
end

function Repo:recordSet(habitId)
  local rows = self.db:query("SELECT record_date FROM habit_records WHERE habit_id = ?", { habitId })
  local set = {}
  for _, row in ipairs(rows or {}) do
    set[row.record_date] = true
  end
  return set
end

-- ---------- 写入 ----------

function Repo:create(data)
  local now = dateUtils.nowMs()
  local config = data.frequency_config
  if type(config) == "table" then config = jsonUtils.encode(config) end
  local id = self.db:insert("habits", {
    name = data.name,
    description = data.description,
    icon = data.icon or "check",
    color = data.color or "#6750A4",
    frequency_type = data.frequency_type or "daily",
    frequency_config = config,
    target_count = data.target_count or 1,
    reminder_time = data.reminder_time,
    is_active = 1,
    sort_order = data.sort_order or 0,
    created_at = now,
    updated_at = now,
  })
  if not id or id < 1 then return nil, "创建习惯失败" end
  return id
end

function Repo:update(id, data)
  local row = { updated_at = dateUtils.nowMs() }
  for _, key in ipairs({ "name", "description", "icon", "color", "frequency_type",
    "target_count", "reminder_time" }) do
    if data[key] ~= nil then row[key] = data[key] end
  end
  if data.frequency_config ~= nil then
    if type(data.frequency_config) == "table" then
      row.frequency_config = jsonUtils.encode(data.frequency_config)
    else
      row.frequency_config = tostring(data.frequency_config)
    end
  end
  if data.is_active ~= nil then row.is_active = boolToInt(data.is_active) end
  local affected = self.db:update("habits", row, "id = ?", { id })
  if not affected or affected < 1 then return nil, "更新习惯失败" end
  return true
end

function Repo:remove(id)
  local affected = self.db:delete("habits", "id = ?", { id })
  if not affected or affected < 1 then return nil, "删除习惯失败" end
  return true
end

function Repo:setActive(id, active)
  local affected = self.db:update("habits", {
    is_active = active and 1 or 0,
    updated_at = dateUtils.nowMs(),
  }, "id = ?", { id })
  if not affected or affected < 1 then return nil, "更新习惯状态失败" end
  return true
end

-- 打卡：依靠 UNIQUE(habit_id, record_date) + INSERT OR IGNORE 保证同一天只记一次
function Repo:checkIn(habitId, dateStr, note)
  local id = self.db:insert("habit_records", {
    habit_id = habitId,
    record_date = dateStr,
    completed_at = dateUtils.nowMs(),
    note = note,
  }, true)
  if id == -1 then return false, "该习惯今天已经打卡" end
  if not id or id < 1 then return nil, "打卡失败" end
  return true
end

function Repo:cancelCheckIn(habitId, dateStr)
  local affected = self.db:delete("habit_records", "habit_id = ? AND record_date = ?", { habitId, dateStr })
  if affected == 0 then return false, "没有找到打卡记录" end
  return true
end

function Repo:toggle(habitId, dateStr)
  local exists = self.db:scalar(
    "SELECT COUNT(*) FROM habit_records WHERE habit_id = ? AND record_date = ?",
    { habitId, dateStr }, 0)
  if exists and exists > 0 then
    return self:cancelCheckIn(habitId, dateStr)
  end
  return self:checkIn(habitId, dateStr)
end

-- ---------- 统计 ----------

-- 当前连续：从今天（或昨天，如果今天还没打卡）向前数，跳过非计划日
function Repo:currentStreak(habit, todayStr)
  local freq = habit.frequency_type or "daily"
  if freq == "weekly_count" then
    return self:currentWeekStreak(habit, todayStr), "周"
  end
  local done = self:recordSet(habit.id)
  local cursor = todayStr or dateUtils.today()
  if self:isScheduledOn(habit, cursor) and not done[cursor] then
    cursor = dateUtils.addDays(cursor, -1)
  end
  local streak = 0
  for _ = 1, 1825 do
    if done[cursor] then
      streak = streak + 1
    elseif self:isScheduledOn(habit, cursor) then
      break
    end
    cursor = dateUtils.addDays(cursor, -1)
  end
  return streak, "天"
end

-- weekly_count 类型：连续达标周数
function Repo:currentWeekStreak(habit, todayStr)
  local today = todayStr or dateUtils.today()
  local weekStart = dateUtils.startOfWeek(today, self.weekStart)
  local target = self:targetCount(habit)
  local streak = 0
  local cursorStart = weekStart
  -- 本周未达标不打断连续（还在进行中）
  local thisWeekCount = self:countBetween(habit.id, cursorStart, dateUtils.addDays(cursorStart, 6))
  if thisWeekCount >= target then streak = 1 end
  cursorStart = dateUtils.addDays(cursorStart, -7)
  for _ = 1, 260 do
    local count = self:countBetween(habit.id, cursorStart, dateUtils.addDays(cursorStart, 6))
    if count >= target then
      streak = streak + 1
    else
      break
    end
    cursorStart = dateUtils.addDays(cursorStart, -7)
  end
  return streak
end

-- 历史最长连续
function Repo:longestStreak(habit)
  local rows = self:records(habit.id)
  if #rows == 0 then return 0 end
  if habit.frequency_type == "weekly_count" then
    return self:longestWeekStreak(habit)
  end
  local done = {}
  for _, row in ipairs(rows) do done[row.record_date] = true end
  local firstDate = rows[1].record_date
  local lastDate = rows[#rows].record_date
  local days = dateUtils.diffDays(firstDate, lastDate)
  if days < 0 then return 0 end
  local best, current = 0, 0
  local cursor = firstDate
  for _ = 0, days do
    if done[cursor] then
      current = current + 1
      if current > best then best = current end
    elseif self:isScheduledOn(habit, cursor) then
      current = 0
    end
    cursor = dateUtils.addDays(cursor, 1)
  end
  return best
end

function Repo:longestWeekStreak(habit)
  local rows = self:records(habit.id)
  if #rows == 0 then return 0 end
  local target = self:targetCount(habit)
  local counts = {}
  for _, row in ipairs(rows) do
    local weekStart = dateUtils.startOfWeek(row.record_date, self.weekStart)
    counts[weekStart] = (counts[weekStart] or 0) + 1
  end
  local weeks = {}
  for weekStart in pairs(counts) do weeks[#weeks + 1] = weekStart end
  table.sort(weeks)
  local best, current = 0, 0
  for _, weekStart in ipairs(weeks) do
    if counts[weekStart] >= target then
      current = current + 1
      if current > best then best = current end
    else
      current = 0
    end
  end
  return best
end

function Repo:countBetween(habitId, fromDate, toDate)
  return self.db:scalar(
    "SELECT COUNT(*) FROM habit_records WHERE habit_id = ? AND record_date >= ? AND record_date <= ?",
    { habitId, fromDate, toDate }, 0)
end

-- 全部习惯在某区间的打卡总次数（统计页用）
function Repo:totalChecksBetween(fromDate, toDate)
  return self.db:scalar(
    "SELECT COUNT(*) FROM habit_records WHERE record_date >= ? AND record_date <= ?",
    { fromDate, toDate }, 0)
end

-- 一段时间内计数的打卡
function Repo:countOn(habitId, dateStr)
  return self.db:scalar(
    "SELECT COUNT(*) FROM habit_records WHERE habit_id = ? AND record_date = ?",
    { habitId, dateStr }, 0)
end

function Repo:weekCount(habit, todayStr)
  local today = todayStr or dateUtils.today()
  local start = dateUtils.startOfWeek(today, self.weekStart)
  return self:countBetween(habit.id, start, dateUtils.addDays(start, 6))
end

function Repo:monthCount(habit, todayStr)
  local today = todayStr or dateUtils.today()
  return self:countBetween(habit.id, dateUtils.startOfMonth(today), dateUtils.endOfMonth(today))
end

-- 完成率：计划日与已完成数之比（weekly_count 按周目标折算）
function Repo:completionRate(habit, fromDate, toDate)
  local freq = habit.frequency_type or "daily"
  local done = self:recordSet(habit.id)
  if freq == "weekly_count" then
    local weeks = 0
    local cursor = dateUtils.startOfWeek(fromDate, self.weekStart)
    local met = 0
    local target = self:targetCount(habit)
    while dateUtils.diffDays(cursor, toDate) >= 0 do
      weeks = weeks + 1
      local weekEnd = dateUtils.addDays(cursor, 6)
      local count = 0
      local day = cursor
      while dateUtils.diffDays(day, weekEnd) >= 0 do
        if day >= fromDate and day <= toDate and done[day] then count = count + 1 end
        day = dateUtils.addDays(day, 1)
      end
      if count >= target then met = met + 1 end
      cursor = dateUtils.addDays(cursor, 7)
    end
    if weeks == 0 then return 0 end
    return math.min(100, math.floor(met / weeks * 100 + 0.5))
  end

  local expected, completed = 0, 0
  local cursor = fromDate
  local span = dateUtils.diffDays(fromDate, toDate)
  if span < 0 then return 0 end
  for _ = 0, span do
    if self:isScheduledOn(habit, cursor) then
      expected = expected + 1
      if done[cursor] then completed = completed + 1 end
    elseif done[cursor] then
      -- 补录在非计划日：计入完成数，不增加分母
      completed = completed + 0
    end
    cursor = dateUtils.addDays(cursor, 1)
  end
  if expected == 0 then return 0 end
  return math.floor(completed / expected * 100 + 0.5)
end

-- 月历打卡分布：返回按日期索引的 {scheduled=, done=}
function Repo:monthCalendar(habit, year, month)
  local map = {}
  local first = string.format("%04d-%02d-01", year, month)
  local last = dateUtils.endOfMonth(first)
  local done = self:recordSet(habit.id)
  local cursor = first
  local span = dateUtils.diffDays(first, last)
  for _ = 0, span do
    map[cursor] = {
      date = cursor,
      scheduled = self:isScheduledOn(habit, cursor),
      done = done[cursor] == true,
    }
    cursor = dateUtils.addDays(cursor, 1)
  end
  return map
end

-- 今日应打卡与已完成（用于首页进度）
function Repo:todaySummary(dateStr)
  local today = dateStr or dateUtils.today()
  local rows = self:list(true)
  local scheduled, completed, doneMap = 0, 0, self:recordsOn(today)
  for _, habit in ipairs(rows or {}) do
    if self:isScheduledOn(habit, today) then
      scheduled = scheduled + 1
      if doneMap[habit.id] then completed = completed + 1 end
    end
  end
  return completed, scheduled
end

-- weekly_count 习惯在今日列表里也展示（提示本周进度）
function Repo:todayList(dateStr)
  local today = dateStr or dateUtils.today()
  local rows = self:list(true)
  local doneMap = self:recordsOn(today)
  local list = {}
  for _, habit in ipairs(rows or {}) do
    if self:isScheduledOn(habit, today) then
      habit.doneToday = doneMap[habit.id] == true
      habit.weekCount = self:weekCount(habit, today)
      habit.target = self:targetCount(habit)
      list[#list + 1] = habit
    end
  end
  table.sort(list, function(a, b)
    if a.doneToday ~= b.doneToday then return b.doneToday end
    return a.id < b.id
  end)
  return list
end

function Repo:allActiveCount()
  return self.db:scalar("SELECT COUNT(*) FROM habits WHERE is_active = 1", nil, 0)
end

function M.new(db, weekStart)
  local repo = setmetatable({ db = db, weekStart = weekStart or 1 }, Repo)
  return repo
end

return M
