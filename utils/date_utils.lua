-- 日期与时间工具：全应用唯一的日期数学入口。
-- 存储约定：纯日期 TEXT "YYYY-MM-DD"；时刻 INTEGER 毫秒。
local bindClass = luajava.bindClass
local Calendar = bindClass "java.util.Calendar"
local SimpleDateFormat = bindClass "java.text.SimpleDateFormat"
local Locale = bindClass "java.util.Locale"
local Date = bindClass "java.util.Date"

local M = {}

M.DAY_MS = 86400000
M.WEEK_CN = { "一", "二", "三", "四", "五", "六", "日" }
M.WEEK_FULL_CN = { "周一", "周二", "周三", "周四", "周五", "周六", "周日" }

local function newCalendar(dateStr, hour, minute)
  local cal = Calendar.getInstance()
  if dateStr then
    local y, m, d = dateStr:match("^(%d+)%-(%d+)%-(%d+)$")
    if not y then return nil end
    cal.set(tonumber(y), tonumber(m) - 1, tonumber(d), hour or 0, minute or 0, 0)
    cal.set(Calendar.MILLISECOND, 0)
  end
  return cal
end

local function pad2(value)
  if value < 10 then return "0" .. value end
  return tostring(value)
end

function M.pad2(value) return pad2(value) end

function M.nowMs()
  return Calendar.getInstance().getTimeInMillis()
end

-- 毫秒 → "YYYY-MM-DD"
function M.dateOf(ms)
  local cal = Calendar.getInstance()
  cal.setTimeInMillis(ms)
  return string.format("%04d-%s-%s", cal.get(Calendar.YEAR),
    pad2(cal.get(Calendar.MONTH) + 1), pad2(cal.get(Calendar.DAY_OF_MONTH)))
end

function M.today()
  return M.dateOf(M.nowMs())
end

-- "YYYY-MM-DD" + 时分 → 毫秒
function M.msOf(dateStr, hour, minute)
  local cal = newCalendar(dateStr, hour or 0, minute or 0)
  if not cal then return nil end
  return cal.getTimeInMillis()
end

function M.parts(dateStr)
  if not dateStr then return nil end
  local y, m, d = dateStr:match("^(%d+)%-(%d+)%-(%d+)$")
  if not y then return nil end
  return tonumber(y), tonumber(m), tonumber(d)
end

function M.isValidDate(dateStr)
  if type(dateStr) ~= "string" then return false end
  local y, m, d = M.parts(dateStr)
  if not y then return false end
  if m < 1 or m > 12 or d < 1 or d > 31 then return false end
  return M.addDays(dateStr, 0) == dateStr
end

-- 周一 = 1 … 周日 = 7
function M.weekday(dateStr)
  local cal = newCalendar(dateStr)
  if not cal then return 1 end
  local dow = cal.get(Calendar.DAY_OF_WEEK)
  return (dow + 5) % 7 + 1
end

function M.addDays(dateStr, days)
  local cal = newCalendar(dateStr)
  if not cal then return nil end
  cal.add(Calendar.DAY_OF_MONTH, days)
  return M.dateOf(cal.getTimeInMillis())
end

function M.addMonths(dateStr, months)
  local cal = newCalendar(dateStr)
  if not cal then return nil end
  cal.add(Calendar.MONTH, months)
  return M.dateOf(cal.getTimeInMillis())
end

function M.addYears(dateStr, years)
  local cal = newCalendar(dateStr)
  if not cal then return nil end
  cal.add(Calendar.YEAR, years)
  return M.dateOf(cal.getTimeInMillis())
end

-- b - a，单位天（两端都归一到当天 12:00，避免夏令时误差）
function M.diffDays(a, b)
  local ca = newCalendar(a, 12, 0)
  local cb = newCalendar(b, 12, 0)
  if not ca or not cb then return 0 end
  return math.floor((cb.getTimeInMillis() - ca.getTimeInMillis()) / M.DAY_MS + 0.5)
end

function M.isToday(dateStr)
  return dateStr == M.today()
end

function M.isPastDate(dateStr)
  return M.diffDays(M.today(), dateStr) < 0
end

function M.isFutureDate(dateStr)
  return M.diffDays(M.today(), dateStr) > 0
end

-- 一周起始日：1=周一，7=周日
function M.startOfWeek(dateStr, firstDay)
  local fd = firstDay or 1
  local wd = M.weekday(dateStr)
  local offset = (wd - fd) % 7
  return M.addDays(dateStr, -offset)
end

function M.endOfWeek(dateStr, firstDay)
  return M.addDays(M.startOfWeek(dateStr, firstDay), 6)
end

function M.weekDates(dateStr, firstDay)
  local start = M.startOfWeek(dateStr, firstDay)
  local list = {}
  for i = 0, 6 do
    list[#list + 1] = M.addDays(start, i)
  end
  return list
end

function M.startOfMonth(dateStr)
  local y, m = M.parts(dateStr)
  return string.format("%04d-%s-01", y, pad2(m))
end

function M.endOfMonth(dateStr)
  local y, m = M.parts(dateStr)
  return M.addDays(M.addMonths(string.format("%04d-%s-01", y, pad2(m)), 1), -1)
end

-- 6 行 × 7 列的月历网格，返回 { {date=, day=, inMonth=}, ... }
function M.monthGrid(year, month, firstDay)
  local first = string.format("%04d-%s-01", year, pad2(month))
  local start = M.startOfWeek(first, firstDay or 1)
  local weeks = {}
  local cursor = start
  for _ = 1, 6 do
    local week = {}
    for _ = 1, 7 do
      local y2, m2, d2 = M.parts(cursor)
      week[#week + 1] = {
        date = cursor,
        day = d2,
        inMonth = (y2 == year and m2 == month),
      }
      cursor = M.addDays(cursor, 1)
    end
    weeks[#weeks + 1] = week
  end
  return weeks
end

function M.monthLabel(year, month)
  return string.format("%d年%d月", year, month)
end

-- 中文日期：11月15日 周六
function M.formatDateCN(dateStr)
  local y, m, d = M.parts(dateStr)
  if not y then return dateStr or "" end
  return string.format("%d月%d日 %s", m, d, M.WEEK_FULL_CN[M.weekday(dateStr)])
end

function M.formatFullCN(dateStr)
  local y, m, d = M.parts(dateStr)
  if not y then return dateStr or "" end
  return string.format("%d年%d月%d日", y, m, d)
end

function M.formatShortCN(dateStr)
  local _, m, d = M.parts(dateStr)
  if not m then return dateStr or "" end
  return string.format("%d月%d日", m, d)
end

function M.formatTime(ms)
  local cal = Calendar.getInstance()
  cal.setTimeInMillis(ms)
  return string.format("%s:%s", pad2(cal.get(Calendar.HOUR_OF_DAY)), pad2(cal.get(Calendar.MINUTE)))
end

function M.timeParts(ms)
  local cal = Calendar.getInstance()
  cal.setTimeInMillis(ms)
  return cal.get(Calendar.HOUR_OF_DAY), cal.get(Calendar.MINUTE)
end

function M.timeLabel(hour, minute)
  return string.format("%s:%s", pad2(hour), pad2(minute))
end

function M.msTimeLabel(ms)
  local h, mi = M.timeParts(ms)
  return M.timeLabel(h, mi)
end

function M.formatDateTime(ms)
  return M.formatDateCN(M.dateOf(ms)) .. " " .. M.formatTime(ms)
end

-- 相对日期：今天 / 明天 / 昨天 / n 天后 / n 天前
function M.relativeDay(dateStr)
  local delta = M.diffDays(M.today(), dateStr)
  if delta == 0 then return "今天" end
  if delta == 1 then return "明天" end
  if delta == -1 then return "昨天" end
  if delta > 1 then return delta .. " 天后" end
  return (-delta) .. " 天前"
end

-- 用于时间段展示：09:00 – 10:30
function M.timeRange(startMs, endMs)
  if not startMs then return "" end
  if not endMs or endMs <= startMs then return M.formatTime(startMs) end
  return M.formatTime(startMs) .. "–" .. M.formatTime(endMs)
end

-- 持续时长（秒）→ "25 分钟" / "1 小时 20 分钟"
function M.durationLabel(seconds)
  local total = math.floor((seconds or 0) / 60)
  if total < 60 then return total .. " 分钟" end
  local h = math.floor(total / 60)
  local m = total % 60
  if m == 0 then return h .. " 小时" end
  return h .. " 小时 " .. m .. " 分钟"
end

-- 秒 → mm:ss
function M.clockLabel(seconds)
  local total = math.max(0, math.floor(seconds))
  return string.format("%s:%s", pad2(math.floor(total / 60)), pad2(total % 60))
end

-- 每年重复的日期，在指定年份的对应日期（2/29 → 平年 2/28）
function M.yearlyOccurrence(dateStr, year)
  local _, m, d = M.parts(dateStr)
  if not m then return dateStr end
  local candidate = string.format("%04d-%s-%s", year, pad2(m), pad2(d))
  if not M.isValidDate(candidate) then
    -- 2 月 29 日在平年回退到 2 月 28 日
    return string.format("%04d-%s-28", year, pad2(m))
  end
  return candidate
end

-- 下一个年度纪念日（今天或之后）
function M.nextYearly(dateStr)
  local todayStr = M.today()
  local y = M.parts(todayStr)
  local thisYear = M.yearlyOccurrence(dateStr, y)
  if M.diffDays(todayStr, thisYear) >= 0 then return thisYear end
  return M.yearlyOccurrence(dateStr, y + 1)
end

function M.formatDurationSeconds(startMs, endMs)
  return M.durationLabel((endMs - startMs) / 1000)
end

-- 供备份/导出使用的日期时间戳
function M.isoNow()
  local cal = Calendar.getInstance()
  return string.format("%04d-%s-%s %s:%s:%s",
    cal.get(Calendar.YEAR), pad2(cal.get(Calendar.MONTH) + 1), pad2(cal.get(Calendar.DAY_OF_MONTH)),
    pad2(cal.get(Calendar.HOUR_OF_DAY)), pad2(cal.get(Calendar.MINUTE)), pad2(cal.get(Calendar.SECOND)))
end

function M.fileStamp()
  local cal = Calendar.getInstance()
  return string.format("%04d%s%s-%s%s", cal.get(Calendar.YEAR),
    pad2(cal.get(Calendar.MONTH) + 1), pad2(cal.get(Calendar.DAY_OF_MONTH)),
    pad2(cal.get(Calendar.HOUR_OF_DAY)), pad2(cal.get(Calendar.MINUTE)))
end

M.newCalendar = newCalendar

return M
