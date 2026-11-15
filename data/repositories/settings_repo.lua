-- 应用设置：持久化在 app_settings 表（随备份一起导出），内存缓存避免重复查询
local M = {}

local DEFAULTS = {
  theme_mode = "system",          -- system / light / dark
  theme_seed = "",                -- 空表示跟随系统壁纸
  week_start = "1",               -- 1 周一 / 7 周日
  default_calendar_view = "month",-- month / week / day
  default_reminder_minutes = "15",
  habit_reminder_enabled = "0",
  habit_reminder_time = "21:00",
  notifications_enabled = "1",
  focus_minutes = "25",
  short_break_minutes = "5",
  long_break_minutes = "15",
  auto_start_break = "0",
  show_completed_in_today = "0",
}

local Repo = {}
Repo.__index = Repo

function Repo:all()
  local rows, err = self.db:query("SELECT key, value FROM app_settings")
  if not rows then return nil, err end
  local map = {}
  for _, row in ipairs(rows) do
    map[row.key] = row.value
  end
  self.cache = map
  return map
end

function Repo:get(key, fallback)
  local cached = self.cache[key]
  if cached ~= nil then return cached end
  local value = self.db:scalar("SELECT value FROM app_settings WHERE key = ?", { key }, nil)
  if value == nil then
    value = fallback or DEFAULTS[key]
    return value
  end
  self.cache[key] = value
  return value
end

function Repo:getNumber(key, fallback)
  local value = tonumber(self:get(key, fallback))
  if value == nil then return tonumber(DEFAULTS[key]) or 0 end
  return value
end

function Repo:getBool(key, fallback)
  local value = self:get(key, fallback)
  return value == "1" or value == 1 or value == true
end

function Repo:set(key, value)
  local text = tostring(value)
  if type(value) == "boolean" then text = value and "1" or "0" end
  self.db.db.execSQL("INSERT OR REPLACE INTO app_settings(key, value) VALUES(?, ?)", { key, text })
  self.cache[key] = text
  return true
end

function Repo:setMany(pairs)
  local ok, err = self.db:transaction(function()
    for key, value in pairs(pairs) do
      self.db.db.execSQL("INSERT OR REPLACE INTO app_settings(key, value) VALUES(?, ?)", { key, tostring(value) })
    end
  end)
  if not ok then return nil, err end
  for key, value in pairs(pairs) do
    self.cache[key] = tostring(value)
  end
  return true
end

function Repo:clearCache()
  self.cache = {}
end

function Repo:weekStart()
  local value = tonumber(self:get("week_start", "1"))
  if value ~= 7 then value = 1 end
  return value
end

function Repo:focusMinutes()
  local value = self:getNumber("focus_minutes", "25")
  if value < 1 then value = 25 end
  return math.floor(value)
end

function Repo:shortBreakMinutes()
  local value = self:getNumber("short_break_minutes", "5")
  if value < 1 then value = 5 end
  return math.floor(value)
end

function Repo:longBreakMinutes()
  local value = self:getNumber("long_break_minutes", "15")
  if value < 1 then value = 15 end
  return math.floor(value)
end

function Repo:defaultReminderMinutes()
  return self:getNumber("default_reminder_minutes", "15")
end

function M.new(db)
  local repo = setmetatable({ db = db, cache = {} }, Repo)
  repo:all()
  return repo
end

M.DEFAULTS = DEFAULTS

return M
