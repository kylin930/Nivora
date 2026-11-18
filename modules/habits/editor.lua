-- 习惯编辑表单
local M = {}

local Form = require "components.form_dialog"
local constants = require "config.constants"

local FREQ_OPTIONS = {
  { value = "daily", name = "每天" },
  { value = "weekly_days", name = "每周指定日期" },
  { value = "weekly_count", name = "每周完成次数" },
}

function M.open(ctx, habit, onSaved)
  local app = ctx.app
  local editing = habit ~= nil
  local config = {}
  if editing then
    local parsed = require("utils.json_utils").decode(habit.frequency_config, {})
    for _, value in ipairs(parsed.days or {}) do
      config[tonumber(value)] = true
    end
    for day = 1, 7 do
      if config[day] == nil then config[day] = false end
    end
  end

  local values = {
    name = editing and habit.name or "",
    description = editing and (habit.description or "") or "",
    freq = editing and (habit.frequency_type or "daily") or "daily",
    target = editing and (habit.target_count or 1) or 1,
    weekdays = config,
    icon = editing and (habit.icon or "check") or "check",
    color = editing and (habit.color or constants.PALETTE[1]) or constants.PALETTE[1],
    reminder = editing and (habit.reminder_time or "") or "",
  }

  return Form.open({
    title = editing and "编辑习惯" or "新建习惯",
    values = values,
    saveLabel = editing and "保存" or "创建",
    fields = {
      { type = "text", key = "name", label = "习惯名称" },
      { type = "multiline", key = "description", label = "描述（可选）" },
      { type = "choice", key = "freq", label = "周期", options = FREQ_OPTIONS },
      { type = "weekdays", key = "weekdays", label = "每周打卡日（周期选「每周指定日期」时生效）" },
      { type = "number", key = "target", label = "每周目标次数（周期选「每周完成次数」时生效）" },
      { type = "time", key = "reminder", label = "每日提醒时间", allowEmpty = true },
      { type = "icon", key = "icon", label = "图标" },
      { type = "color", key = "color", label = "颜色" },
    },
    onSave = function(result)
      local id, err = M.persist(ctx, habit, result)
      if not id then return false, err end
      if onSaved then onSaved(id) end
      return true
    end,
  })
end

-- 保存逻辑（与界面分离，便于校验）：返回 id 或 nil, 错误
function M.persist(ctx, existingHabit, result)
  local app = ctx.app
  local name = Form.trim(result.name)
  if name == "" then return nil, "请填写习惯名称" end
  if #name > 40 then return nil, "名称不要超过 40 个字符" end

  local freq = result.freq or "daily"
  local frequencyConfig = nil
  if freq == "weekly_days" then
    local days = {}
    for day = 1, 7 do
      if result.weekdays and result.weekdays[day] then days[#days + 1] = day end
    end
    if #days == 0 then return nil, "请至少选择一个打卡日" end
    frequencyConfig = { days = days }
  elseif freq == "weekly_count" then
    local target = tonumber(result.target) or 0
    if target < 1 or target > 7 then return nil, "每周次数请填 1–7" end
    frequencyConfig = { times = target }
  end

  local payload = {
    name = name,
    description = result.description or "",
    frequency_type = freq,
    frequency_config = frequencyConfig,
    target_count = math.max(1, math.min(7, tonumber(result.target) or 1)),
    icon = result.icon or "check",
    color = result.color,
    reminder_time = (result.reminder ~= "" and result.reminder) or nil,
  }

  local id, err
  if existingHabit then
    local ok
    ok, err = app.habits:update(existingHabit.id, payload)
    if ok then id = existingHabit.id end
  else
    id, err = app.habits:create(payload)
  end
  if not id then return nil, err or "保存失败" end

  app:changed(require("core.event_bus").EVENTS.HABITS_CHANGED)
  return id
end

return M
