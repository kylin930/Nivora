-- 日程编辑表单：支持重复规则、提醒、全天事件与冲突提示
local M = {}

local Form = require "components.form_dialog"
local ui = require "components.ui"
local dateUtils = require "utils.date_utils"
local eventBus = require "core.event_bus"

local FREQ_OPTIONS = {
  { value = "none", name = "不重复" },
  { value = "daily", name = "每天" },
  { value = "weekly", name = "每周" },
  { value = "monthly", name = "每月" },
  { value = "yearly", name = "每年" },
}

local function categoryOptions(app)
  local list = { { value = 0, name = "未分类" } }
  for _, item in ipairs(app.categories:list("schedule")) do
    list[#list + 1] = { value = item.id, name = item.name }
  end
  return list
end

local function reminderOptions()
  local list = {}
  for _, item in ipairs(require("config.constants").REMINDER_OPTIONS) do
    list[#list + 1] = { value = item.value, name = item.name }
  end
  return list
end

-- occurrence：编辑重复事件的某一次时传入 { row = 母记录, date = "YYYY-MM-DD" }
function M.open(ctx, existing, onSaved, occurrence)
  local app = ctx.app
  local editing = existing ~= nil
  local values

  if editing then
    local rule = app.schedules:ruleOf(existing)
    local ruleDays = {}
    if rule.byWeekday then
      for day = 1, 7 do ruleDays[day] = rule.byWeekday[day] == true end
    end
    local startHour, startMinute = dateUtils.timeParts(existing.start_time)
    local endHour, endMinute = 0, 0
    if existing.end_time then
      endHour, endMinute = dateUtils.timeParts(existing.end_time)
    end
    values = {
      title = existing.title,
      description = existing.description or "",
      date = dateUtils.dateOf(existing.start_time),
      startTime = dateUtils.timeLabel(startHour, startMinute),
      endTime = existing.end_time and dateUtils.timeLabel(endHour, endMinute) or "",
      allDay = existing.is_all_day == 1,
      freq = rule.freq or "none",
      weekdays = ruleDays,
      category_id = existing.category_id or 0,
      reminder = tonumber(existing.reminder_minutes) or -1,
    }
  else
    local now = dateUtils.nowMs()
    local hour, minute = dateUtils.timeParts(now)
    values = {
      title = "",
      description = "",
      date = dateUtils.today(),
      startTime = dateUtils.timeLabel(hour, 0),
      endTime = dateUtils.timeLabel(math.min(23, hour + 1), 0),
      allDay = false,
      freq = "none",
      weekdays = {},
      category_id = 0,
      reminder = app.settings:defaultReminderMinutes(),
    }
  end

  return Form.open({
    title = editing and "编辑日程" or "新建日程",
    subtitle = occurrence and ("仅修改 " .. dateUtils.formatDateCN(occurrence.date) .. " 这一次") or nil,
    values = values,
    saveLabel = editing and "保存" or "创建",
    fields = {
      { type = "text", key = "title", label = "标题" },
      { type = "multiline", key = "description", label = "描述" },
      { type = "date", key = "date", label = "日期" },
      { type = "time", key = "startTime", label = "开始时间" },
      { type = "time", key = "endTime", label = "结束时间", allowEmpty = true },
      { type = "toggle", key = "allDay", label = "全天事件" },
      { type = "choice", key = "freq", label = "重复", options = FREQ_OPTIONS },
      { type = "weekdays", key = "weekdays", label = "每周重复日" },
      { type = "choice", key = "category_id", label = "分类", options = categoryOptions(app) },
      { type = "choice", key = "reminder", label = "提醒", options = reminderOptions() },
    },
    onSave = function(result)
      local id, err = M.persist(ctx, existing, result, occurrence)
      if not id then return false, err end
      if onSaved then onSaved(id) end
      return true
    end,
  })
end

-- 保存逻辑（与界面分离）：返回 id 或 nil, 错误
function M.persist(ctx, existing, result, occurrence)
  local app = ctx.app
  local editing = existing ~= nil

  local title = Form.trim(result.title)
  if title == "" then return nil, "请填写日程标题" end
  if not dateUtils.isValidDate(result.date) then return nil, "请选择有效日期" end

  local startHour, startMinute = tostring(result.startTime or ""):match("^(%d+):(%d+)$")
  if not startHour then return nil, "请设置开始时间" end
  local startMs = dateUtils.msOf(result.date, tonumber(startHour), tonumber(startMinute))
  local endMs
  if result.endTime and result.endTime ~= "" then
    local endHour, endMinute = tostring(result.endTime):match("^(%d+):(%d+)$")
    if endHour then
      endMs = dateUtils.msOf(result.date, tonumber(endHour), tonumber(endMinute))
      if endMs <= startMs then endMs = startMs + 3600000 end
    end
  end
  if result.allDay then
    startMs = dateUtils.msOf(result.date, 0, 0)
    endMs = dateUtils.msOf(result.date, 23, 59)
  end

  local rule = { freq = result.freq or "none" }
  if rule.freq == "weekly" then
    local days = {}
    for day = 1, 7 do
      if result.weekdays and result.weekdays[day] then days[#days + 1] = day end
    end
    if #days == 0 then days = { dateUtils.weekday(result.date) } end
    rule.byWeekday = days
  end

  local categoryId = tonumber(result.category_id) or 0
  local payload = {
    title = title,
    description = result.description or "",
    start_time = startMs,
    end_time = endMs,
    is_all_day = result.allDay == true,
    category_id = categoryId > 0 and categoryId or nil,
    reminder_minutes = tonumber(result.reminder) or -1,
    recurrence_rule = rule,
  }
  if editing then
    payload.clear_category = categoryId <= 0
    payload.clear_end_time = endMs == nil
  end

  local id, err
  if occurrence then
    local ok
    ok, err = app.schedules:overrideOccurrence(occurrence.row, occurrence.date, payload)
    if ok then id = occurrence.row.id end
  elseif editing then
    local ok
    ok, err = app.schedules:update(existing.id, payload)
    if ok then id = existing.id end
  else
    id, err = app.schedules:create(payload)
  end
  if not id then return nil, err or "保存失败" end

  app:changed(eventBus.EVENTS.SCHEDULES_CHANGED)

  -- 冲突只提示，不阻止保存
  local conflicts = app.schedules:conflicts(startMs, endMs, editing and existing.id or 0)
  if #conflicts > 0 then
    local names = {}
    for index, item in ipairs(conflicts) do
      if index <= 2 then names[#names + 1] = item.title end
    end
    ui.alert("时间有重叠",
      "与「" .. table.concat(names, "」「") .. "」时间重叠，已保存。")
  end

  return id
end

-- 删除入口：区分单次、本次及后续、整个系列
function M.confirmDelete(ctx, occurrence, onDeleted)
  local app = ctx.app
  local row = app.schedules:get(occurrence.id)
  if not row then return end
  local isRecurring = occurrence.is_recurring == true

  if not isRecurring then
    ui.confirm({
      title = "删除日程",
      message = "确定删除「" .. occurrence.title .. "」吗？",
      confirmText = "删除",
    }, function()
      local ok, err = app.schedules:remove(occurrence.id)
      if not ok then ui.alert("删除失败", tostring(err)) return end
      app:changed(eventBus.EVENTS.SCHEDULES_CHANGED)
      if onDeleted then onDeleted() end
    end)
    return
  end

  ui.choose("删除重复日程", { "仅删除这一次", "删除本次及以后", "删除整个系列" }, function(index)
    local ok, err
    if index == 1 then
      ok, err = app.schedules:cancelOccurrence(row, occurrence.occurrence_date)
    elseif index == 2 then
      ok, err = app.schedules:truncateSeries(row, occurrence.occurrence_date)
    else
      ok, err = app.schedules:remove(occurrence.id)
    end
    if not ok then
      ui.alert("删除失败", tostring(err))
      return
    end
    app:changed(eventBus.EVENTS.SCHEDULES_CHANGED)
    if onDeleted then onDeleted() end
  end)
end

return M
