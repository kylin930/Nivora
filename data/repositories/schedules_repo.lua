-- 日程数据访问：重复事件只保存规则，按查询区间展开为具体实例。
-- 单次修改/取消通过 schedule_exceptions 记录，不改动系列本身。
local M = {}

local dateUtils = require "utils.date_utils"
local jsonUtils = require "utils.json_utils"

local Repo = {}
Repo.__index = Repo

local MAX_OCCURRENCES_PER_SERIES = 750

-- ---------- 重复规则 ----------

function Repo:ruleOf(row)
  local rule = jsonUtils.decode(row.recurrence_rule, nil)
  if not rule or not rule.freq then return { freq = "none" } end
  rule.freq = tostring(rule.freq)
  if rule.byWeekday then rule.byWeekday = jsonUtils.toSet(rule.byWeekday) end
  return rule
end

function Repo:ruleLabel(row)
  local rule = self:ruleOf(row)
  local freq = rule.freq
  if freq == "none" then return "不重复" end
  if freq == "daily" then return "每天" end
  if freq == "weekly" then
    local names = {}
    for day = 1, 7 do
      if rule.byWeekday and rule.byWeekday[day] then names[#names + 1] = dateUtils.WEEK_CN[day] end
    end
    if #names == 0 then return "每周" end
    return "每周 " .. table.concat(names, "、")
  end
  if freq == "monthly" then
    local _, month, day = dateUtils.parts(dateUtils.dateOf(row.start_time))
    return string.format("每月 %d 日", day)
  end
  if freq == "yearly" then
    local _, month, day = dateUtils.parts(dateUtils.dateOf(row.start_time))
    return string.format("每年 %d 月 %d 日", month, day)
  end
  return "不重复"
end

local function dayMatches(rule, dateStr)
  if rule.freq == "weekly" then
    if not rule.byWeekday or next(rule.byWeekday) == nil then return false end
    return rule.byWeekday[dateUtils.weekday(dateStr)] == true
  end
  return true
end

-- 在 [fromDate, toDate] 内为某条记录生成实例开始时间（毫秒）
function Repo:occurrenceStarts(row, fromDate, toDate)
  local rule = self:ruleOf(row)
  local startDate = dateUtils.dateOf(row.start_time)
  local hour, minute = dateUtils.timeParts(row.start_time)
  local starts = {}

  if rule.freq == "none" then
    if dateUtils.diffDays(fromDate, startDate) >= 0 and dateUtils.diffDays(startDate, toDate) >= 0 then
      starts[#starts + 1] = row.start_time
    end
    return starts
  end

  local untilDate = rule.until
  local cursor = startDate

  if rule.freq == "daily" then
    local guard = 0
    while dateUtils.diffDays(cursor, toDate) >= 0 and guard < MAX_OCCURRENCES_PER_SERIES do
      guard = guard + 1
      if dateUtils.diffDays(fromDate, cursor) >= 0 and (not untilDate or dateUtils.diffDays(cursor, untilDate) >= 0) then
        starts[#starts + 1] = dateUtils.msOf(cursor, hour, minute)
      end
      cursor = dateUtils.addDays(cursor, 1)
    end
    return starts
  end

  if rule.freq == "weekly" then
    local weekdays = rule.byWeekday
    if not weekdays or next(weekdays) == nil then
      weekdays = { [dateUtils.weekday(startDate)] = true }
    end
    -- 从起始日所在周开始，逐日检查
    local weekCursor = dateUtils.startOfWeek(startDate, 1)
    local guard = 0
    while dateUtils.diffDays(weekCursor, toDate) >= 0 and guard < MAX_OCCURRENCES_PER_SERIES do
      guard = guard + 1
      for offset = 0, 6 do
        local day = dateUtils.addDays(weekCursor, offset)
        if dateUtils.diffDays(startDate, day) >= 0
          and dateUtils.diffDays(fromDate, day) >= 0
          and dateUtils.diffDays(day, toDate) >= 0
          and (not untilDate or dateUtils.diffDays(day, untilDate) >= 0)
          and dayMatches(rule, day) then
          starts[#starts + 1] = dateUtils.msOf(day, hour, minute)
        end
      end
      weekCursor = dateUtils.addDays(weekCursor, 7)
    end
    table.sort(starts)
    return starts
  end

  if rule.freq == "monthly" then
    local _, startMonth, startDay = dateUtils.parts(startDate)
    local guard = 0
    while dateUtils.diffDays(cursor, toDate) >= 0 and guard < MAX_OCCURRENCES_PER_SERIES do
      guard = guard + 1
      local year, month = dateUtils.parts(cursor)
      local _, _, lastDay = dateUtils.parts(dateUtils.endOfMonth(cursor))
      local day = math.min(startDay, lastDay)
      local candidate = string.format("%04d-%02d-%02d", year, month, day)
      if dateUtils.diffDays(fromDate, candidate) >= 0 and dateUtils.diffDays(candidate, toDate) >= 0
        and (not untilDate or dateUtils.diffDays(candidate, untilDate) >= 0) then
        starts[#starts + 1] = dateUtils.msOf(candidate, hour, minute)
      end
      cursor = dateUtils.addMonths(cursor, 1)
    end
    table.sort(starts)
    return starts
  end

  if rule.freq == "yearly" then
    local _, _, startDay = dateUtils.parts(startDate)
    local _, startMonth = dateUtils.parts(startDate)
    local guard = 0
    while dateUtils.diffDays(cursor, toDate) >= 0 and guard < MAX_OCCURRENCES_PER_SERIES do
      guard = guard + 1
      local year = dateUtils.parts(cursor)
      local candidate = dateUtils.yearlyOccurrence(
        string.format("%04d-%02d-%02d", year, startMonth, startDay), year)
      if dateUtils.diffDays(fromDate, candidate) >= 0 and dateUtils.diffDays(candidate, toDate) >= 0
        and (not untilDate or dateUtils.diffDays(candidate, untilDate) >= 0) then
        starts[#starts + 1] = dateUtils.msOf(candidate, hour, minute)
      end
      cursor = dateUtils.addYears(cursor, 1)
    end
    table.sort(starts)
    return starts
  end

  return starts
end

-- 把数据库行展开成实例
function Repo:expand(row, fromDate, toDate)
  local rule = self:ruleOf(row)
  local duration = 0
  if row.end_time and row.end_time > row.start_time then
    duration = row.end_time - row.start_time
  end
  -- 单次例外（取消或改期）
  local exceptions = self:exceptions(row.id, fromDate, toDate)
  local starts = self:occurrenceStarts(row, fromDate, toDate)
  local list = {}
  local seriesId = row.series_id and row.series_id > 0 and row.series_id or row.id

  for _, startMs in ipairs(starts) do
    local dateStr = dateUtils.dateOf(startMs)
    local exception = exceptions[dateStr]
    if not exception then
      list[#list + 1] = {
        id = row.id,
        series_id = seriesId,
        occurrence_date = dateStr,
        title = row.title,
        description = row.description,
        start_time = startMs,
        end_time = duration > 0 and (startMs + duration) or nil,
        is_all_day = row.is_all_day or 0,
        color = row.color,
        category_id = row.category_id,
        reminder_minutes = row.reminder_minutes or -1,
        is_recurring = rule.freq ~= "none",
        recurrence_label = self:ruleLabel(row),
        occurrence_key = tostring(row.id) .. "@" .. dateStr,
      }
    elseif not exception.is_canceled then
      local override = jsonUtils.decode(exception.override_json, {})
      list[#list + 1] = {
        id = row.id,
        series_id = seriesId,
        occurrence_date = dateStr,
        title = override.title or row.title,
        description = override.description or row.description,
        start_time = tonumber(override.start_time) or startMs,
        end_time = tonumber(override.end_time) or (duration > 0 and (startMs + duration) or nil),
        is_all_day = override.is_all_day or row.is_all_day or 0,
        color = override.color or row.color,
        category_id = override.category_id or row.category_id,
        reminder_minutes = override.reminder_minutes or row.reminder_minutes or -1,
        is_recurring = rule.freq ~= "none",
        recurrence_label = self:ruleLabel(row),
        is_exception = true,
        occurrence_key = tostring(row.id) .. "@" .. dateStr,
      }
    end
  end
  return list
end

function Repo:exceptions(seriesId, fromDate, toDate)
  local rows = self.db:query(
    "SELECT * FROM schedule_exceptions WHERE series_id = ? AND occurrence_date >= ? AND occurrence_date <= ?",
    { seriesId, fromDate, toDate })
  local map = {}
  for _, row in ipairs(rows or {}) do
    map[row.occurrence_date] = row
  end
  return map
end

-- ---------- 查询 ----------

-- 区间内的全部实例（含重复事件展开结果），按开始时间排序
function Repo:listRange(fromDate, toDate)
  local rows = self.db:query("SELECT * FROM schedules ORDER BY start_time ASC")
  local list = {}
  for _, row in ipairs(rows or {}) do
    local expanded = self:expand(row, fromDate, toDate)
    for _, item in ipairs(expanded) do list[#list + 1] = item end
  end
  table.sort(list, function(a, b)
    if a.start_time ~= b.start_time then return a.start_time < b.start_time end
    return a.id < b.id
  end)
  return list
end

function Repo:occurrencesOn(dateStr)
  return self:listRange(dateStr, dateStr)
end

function Repo:upcoming(limit, fromMs)
  local now = fromMs or dateUtils.nowMs()
  local today = dateUtils.dateOf(now)
  local list = self:listRange(today, dateUtils.addDays(today, 60))
  local result = {}
  for _, item in ipairs(list) do
    local endMs = item.end_time or item.start_time
    if endMs >= now then
      result[#result + 1] = item
      if #result >= (limit or 3) then break end
    end
  end
  return result
end

-- 区间内有事件的日期 → 数量（月历打点）
function Repo:dayCountMap(fromDate, toDate)
  local list = self:listRange(fromDate, toDate)
  local map = {}
  for _, item in ipairs(list) do
    local date = dateUtils.dateOf(item.start_time)
    map[date] = (map[date] or 0) + 1
  end
  return map
end

function Repo:get(id)
  return self.db:queryOne("SELECT * FROM schedules WHERE id = ?", { id })
end

-- 时间冲突提示：返回与给定时间段重叠的其他事件。
-- 扫描前后各一天，以涵盖跨天与全天事件，再按真实时间段判断。
function Repo:conflicts(startMs, endMs, excludeId)
  local myEnd = endMs or (startMs + 1800000)
  local fromDate = dateUtils.addDays(dateUtils.dateOf(startMs), -1)
  local toDate = dateUtils.addDays(dateUtils.dateOf(myEnd), 1)
  local list = self:listRange(fromDate, toDate)
  local found = {}
  for _, item in ipairs(list) do
    if item.id ~= excludeId then
      local itemStart = item.start_time
      local itemEnd = item.end_time or (item.start_time + 1800000)
      if startMs < itemEnd and itemStart < myEnd then
        found[#found + 1] = item
      end
    end
  end
  return found
end

-- ---------- 写入 ----------

local function encodeRule(rule)
  if type(rule) == "string" then return rule end
  if type(rule) ~= "table" then return jsonUtils.encode({ freq = "none" }) end
  local freq = rule.freq or "none"
  local payload = { freq = freq }
  if freq == "weekly" then
    local days = {}
    for day = 1, 7 do
      if rule.byWeekday and rule.byWeekday[day] then days[#days + 1] = day end
    end
    payload.byWeekday = days
  end
  if rule.until and rule.until ~= "" then payload.until = rule.until end
  return jsonUtils.encode(payload)
end

function Repo:create(data)
  local now = dateUtils.nowMs()
  local id = self.db:insert("schedules", {
    title = data.title,
    description = data.description,
    start_time = data.start_time,
    end_time = data.end_time,
    is_all_day = data.is_all_day and 1 or 0,
    category_id = data.category_id,
    color = data.color,
    reminder_minutes = data.reminder_minutes or -1,
    recurrence_rule = encodeRule(data.recurrence_rule),
    series_id = 0,
    created_at = now,
    updated_at = now,
  })
  if not id or id < 1 then return nil, "创建日程失败" end
  local rule = type(data.recurrence_rule) == "table" and data.recurrence_rule or {}
  if rule.freq and rule.freq ~= "none" then
    self.db:update("schedules", { series_id = id }, "id = ?", { id })
  end
  return id
end

function Repo:update(id, data)
  local row = { updated_at = dateUtils.nowMs() }
  local nulls = {}
  for _, key in ipairs({ "title", "description", "start_time",
    "color", "reminder_minutes" }) do
    if data[key] ~= nil then row[key] = data[key] end
  end
  -- 结束时间/分类可以显式清空
  if data.end_time ~= nil then row.end_time = data.end_time end
  if data.clear_end_time then nulls[#nulls + 1] = "end_time" end
  if data.category_id ~= nil then row.category_id = data.category_id end
  if data.clear_category then nulls[#nulls + 1] = "category_id" end
  if data.is_all_day ~= nil then row.is_all_day = data.is_all_day and 1 or 0 end
  if data.recurrence_rule ~= nil then row.recurrence_rule = encodeRule(data.recurrence_rule) end
  local affected = self.db:update("schedules", row, "id = ?", { id }, nulls)
  if not affected or affected < 1 then return nil, "更新日程失败" end
  return true
end

-- 仅修改某一次：写例外记录
function Repo:overrideOccurrence(row, occurrenceDate, data)
  local payload = {}
  for _, key in ipairs({ "title", "description", "start_time", "end_time",
    "color", "category_id", "reminder_minutes", "is_all_day" }) do
    if data[key] ~= nil then payload[key] = data[key] end
  end
  local existing = self.db:queryOne(
    "SELECT id FROM schedule_exceptions WHERE series_id = ? AND occurrence_date = ?",
    { row.id, occurrenceDate })
  if existing then
    self.db:update("schedule_exceptions", {
      override_json = jsonUtils.encode(payload),
      is_canceled = 0,
    }, "id = ?", { existing.id })
  else
    self.db:insert("schedule_exceptions", {
      series_id = row.id,
      occurrence_date = occurrenceDate,
      override_json = jsonUtils.encode(payload),
      is_canceled = 0,
    })
  end
  return true
end

-- 仅删除某一次
function Repo:cancelOccurrence(row, occurrenceDate)
  local existing = self.db:queryOne(
    "SELECT id FROM schedule_exceptions WHERE series_id = ? AND occurrence_date = ?",
    { row.id, occurrenceDate })
  if existing then
    self.db:update("schedule_exceptions", { is_canceled = 1 }, "id = ?", { existing.id },
      { "override_json" })
  else
    self.db:insert("schedule_exceptions", {
      series_id = row.id,
      occurrence_date = occurrenceDate,
      is_canceled = 1,
    })
  end
  return true
end

-- 删除本次及后续：把系列结束日期截断到 occurrenceDate 之前
function Repo:truncateSeries(row, occurrenceDate)
  local rule = self:ruleOf(row)
  local previous = dateUtils.addDays(occurrenceDate, -1)
  if rule.freq == "none" then
    return self:remove(row.id)
  end
  rule.until = previous
  self.db:update("schedules", {
    recurrence_rule = encodeRule(rule),
    updated_at = dateUtils.nowMs(),
  }, "id = ?", { row.id })
  -- 清掉该日期之后的例外记录
  self.db:delete("schedule_exceptions",
    "series_id = ? AND occurrence_date >= ?", { row.id, occurrenceDate })
  return true
end

function Repo:remove(id)
  local affected = self.db:delete("schedules", "id = ?", { id })
  if not affected or affected < 1 then return nil, "删除日程失败" end
  self.db:delete("schedule_exceptions", "series_id = ?", { id })
  return true
end

function Repo:countInRange(fromDate, toDate)
  return #self:listRange(fromDate, toDate)
end

-- 只返回「该天真正开始」的实例（月历打点、冲突检测需要排期主的实例）
function Repo:occurrencesStartingOn(dateStr)
  local list = self:occurrencesOn(dateStr)
  local result = {}
  for _, item in ipairs(list) do
    if dateUtils.dateOf(item.start_time) == dateStr then result[#result + 1] = item end
  end
  return result
end

function M.new(db, weekStart)
  return setmetatable({ db = db, weekStart = weekStart or 1 }, Repo)
end

return M
