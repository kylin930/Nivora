-- 提醒服务：AlarmManager 排期 + 运行时广播接收器 + 启动/回前台时补发。
-- 环境限制（已验证）：无法声明清单广播接收器，进程被杀死后闹钟不会送达；
-- 因此本服务在每次应用启动/回到前台时重排并补发过期提醒。
local bindClass = luajava.bindClass
local Context = bindClass "android.content.Context"
local Intent = bindClass "android.content.Intent"
local IntentFilter = bindClass "android.content.IntentFilter"
local PendingIntent = bindClass "android.app.PendingIntent"
local AlarmManager = bindClass "android.app.AlarmManager"
local BroadcastReceiver = bindClass "android.content.BroadcastReceiver"

local dateUtils = require "utils.date_utils"

local M = {}

local ACTION_REMINDER = "nivora.action.REMINDER"
local MAX_LOOKAHEAD_DAYS = 30

local Service = {}
Service.__index = Service

function Service:alarmManager()
  return activity.getSystemService(Context.ALARM_SERVICE)
end

function Service:exactAllowed()
  local manager = self:alarmManager()
  if not manager then return false end
  if bindClass("android.os.Build").VERSION.SDK_INT < 31 then return true end
  local ok, value = pcall(function() return manager.canScheduleExactAlarms() end)
  return ok and value == true
end

function Service:pendingIntent(row)
  local intent = Intent(ACTION_REMINDER)
  intent.setPackage(activity.getPackageName())
  intent.putExtra("request_code", row.request_code)
  intent.putExtra("title", row.title or "Nivora")
  intent.putExtra("body", row.body or "")
  return PendingIntent.getBroadcast(activity, row.request_code, intent, PendingIntent.FLAG_IMMUTABLE)
end

function Service:schedule(kind, refId, triggerAt, title, body)
  if triggerAt <= dateUtils.nowMs() then return false end
  self.repo:upsert(kind, refId, triggerAt, title, body)
  local row = self.repo:get(kind, refId)
  if not row then return false end
  local manager = self:alarmManager()
  if not manager then return false end
  local intent = self:pendingIntent(row)
  local ok = pcall(function()
    manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, intent)
  end)
  return ok
end

function Service:cancel(kind, refId)
  local row = self.repo:get(kind, refId)
  if row then
    local manager = self:alarmManager()
    if manager then
      pcall(function() manager.cancel(self:pendingIntent(row)) end)
    end
  end
  self.repo:removeFor(kind, refId)
end

-- 重新构建全部提醒：先清空，再按当前数据排期
function Service:resync()
  local now = dateUtils.nowMs()
  local today = dateUtils.dateOf(now)
  local horizon = dateUtils.addDays(today, MAX_LOOKAHEAD_DAYS)
  local scheduled = 0
  local missed = {}

  -- 1. 日程提醒
  local occurrences = self.app.schedules:listRange(today, horizon)
  local scheduleSeen = {}
  for _, item in ipairs(occurrences) do
    local minutes = tonumber(item.reminder_minutes) or -1
    if minutes >= 0 and not scheduleSeen[item.id] then
      local trigger = item.start_time - minutes * 60000
      if trigger > now then
        scheduleSeen[item.id] = true
        local ok = self:schedule("schedule", item.id, trigger, item.title,
          dateUtils.formatTime(item.start_time) .. " 开始")
        if ok then scheduled = scheduled + 1 end
      elseif item.start_time > now - 3600000 then
        missed[#missed + 1] = { title = item.title, body = "日程已开始：" .. dateUtils.formatTime(item.start_time) }
      end
    end
  end

  -- 2. 待办提醒（当天 09:00 或创建时设定的提前量）
  local pendingTodos = self.app.todos:list({ status = "active" })
  for _, todo in ipairs(pendingTodos) do
    if todo.due_date and todo.due_date ~= "" then
      local defaultMinutes = self.app.settings:defaultReminderMinutes()
      if defaultMinutes >= 0 then
        local dueMs = dateUtils.msOf(todo.due_date, 9, 0)
        if dueMs then
          local trigger = dueMs - defaultMinutes * 60000
          if trigger > now then
            local ok = self:schedule("todo", todo.id, trigger, todo.title, "今天到期")
            if ok then scheduled = scheduled + 1 end
          end
        end
      end
    end
  end

  -- 3. 倒数日提醒
  for _, item in ipairs(self.app.countdowns:list()) do
    local days = tonumber(item.reminder_days) or 0
    if days >= 0 then
      local target = dateUtils.msOf(item.effective_date, 8, 0)
      if target then
        local trigger = target - days * dateUtils.DAY_MS
        if trigger > now then
          local ok = self:schedule("countdown", item.id, trigger, item.title,
            (days > 0 and (days .. " 天后") or "就是今天"))
          if ok then scheduled = scheduled + 1 end
        end
      end
    end
  end

  -- 4. 习惯每日提醒
  if self.app.settings:getBool("habit_reminder_enabled", false) then
    local timeText = self.app.settings:get("habit_reminder_time", "21:00")
    local hour, minute = tostring(timeText):match("^(%d+):(%d+)$")
    hour, minute = tonumber(hour) or 21, tonumber(minute) or 0
    local list = self.app.habits:todayList(today)
    for _, habit in ipairs(list) do
      if not habit.doneToday then
        local trigger = dateUtils.msOf(today, hour, minute)
        if trigger and trigger > now then
          local ok = self:schedule("habit", habit.id, trigger, habit.name, "今天还没打卡")
          if ok then scheduled = scheduled + 1 end
        end
      end
    end
  end

  -- 5. 清理期外的旧提醒行
  self.repo.db.db.execSQL("DELETE FROM reminders WHERE trigger_at < ?", { now - 7200000 })

  -- 6. 补发：应用启动时把短时间内的过期提醒显示出来
  for _, item in ipairs(missed) do
    self.app.notifier:post(math.floor(now / 1000) % 100000, item.title, item.body)
  end

  return scheduled
end

-- 闹钟广播
function Service:handleAlarm(intent)
  local code = intent.getIntExtra("request_code", 0)
  local title = intent.getStringExtra("title") or "Nivora"
  local body = intent.getStringExtra("body") or ""
  if code == 0 then return end
  self.app.notifier:post(code, title, body)
  self.repo.db.db.execSQL("DELETE FROM reminders WHERE request_code = ?", { code })
end

function Service:register()
  if self.receiver then return end
  local ServiceRef = self
  local Receiver = BroadcastReceiver.override {
    onReceive = function(superCall, context, intent)
      local ok, err = pcall(function()
        ServiceRef:handleAlarm(intent)
      end)
      if not ok then print("reminder receiver error: " .. tostring(err)) end
    end,
  }
  self.receiver = Receiver()
  local filter = IntentFilter(ACTION_REMINDER)
  local ok, err = pcall(function()
    activity.registerReceiver(self.receiver, filter)
  end)
  if not ok then
    self.receiver = nil
    print("registerReceiver failed: " .. tostring(err))
  end
end

function Service:unregister()
  if not self.receiver then return end
  pcall(function() activity.unregisterReceiver(self.receiver) end)
  self.receiver = nil
end

-- 主动补发：把已经到期但没投递的提醒显示出来
function Service:flushDue()
  local now = dateUtils.nowMs()
  local rows = self.repo:dueNow(now)
  for _, row in ipairs(rows) do
    if now - row.trigger_at <= 3600000 then
      self.app.notifier:post(row.request_code, row.title, row.body)
    end
  end
  self.repo.db.db.execSQL("DELETE FROM reminders WHERE trigger_at <= ?", { now - 3600000 })
end

function M.new(app)
  local service = setmetatable({
    app = app,
    repo = app.reminders,
    receiver = nil,
  }, Service)
  return service
end

M.ACTION_REMINDER = ACTION_REMINDER

return M
