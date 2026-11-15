-- 倒数日编辑表单：支持每年重复与提前提醒
local M = {}

local Form = require "components.form_dialog"
local constants = require "config.constants"
local eventBus = require "core.event_bus"
local dateUtils = require "utils.date_utils"

local KIND_OPTIONS = {}
for _, name in ipairs(constants.COUNTDOWN_KINDS) do
  KIND_OPTIONS[#KIND_OPTIONS + 1] = { value = name, name = name }
end

local REMIND_OPTIONS = {
  { value = -1, name = "不提醒" },
  { value = 0, name = "当天提醒" },
  { value = 1, name = "提前 1 天" },
  { value = 3, name = "提前 3 天" },
  { value = 7, name = "提前 7 天" },
  { value = 30, name = "提前 30 天" },
}

function M.open(ctx, item, onSaved)
  local app = ctx.app
  local editing = item ~= nil
  return Form.open({
    title = editing and "编辑倒数日" or "新建倒数日",
    values = {
      title = editing and item.title or "",
      description = editing and (item.description or "") or "",
      target_date = editing and item.target_date or dateUtils.today(),
      repeat_yearly = editing and item.repeat_yearly == 1 or false,
      kind = editing and (item.kind or "自定义") or "自定义",
      reminder_days = editing and (tonumber(item.reminder_days) or 0) or 0,
      icon = editing and (item.icon or "star") or "star",
      color = editing and (item.color or constants.PALETTE[1]) or constants.PALETTE[1],
    },
    saveLabel = editing and "保存" or "创建",
    fields = {
      { type = "text", key = "title", label = "名称" },
      { type = "multiline", key = "description", label = "描述" },
      { type = "date", key = "target_date", label = "日期" },
      { type = "toggle", key = "repeat_yearly", label = "每年重复（生日、纪念日）" },
      { type = "choice", key = "kind", label = "类型", options = KIND_OPTIONS },
      { type = "choice", key = "reminder_days", label = "提醒", options = REMIND_OPTIONS },
      { type = "icon", key = "icon", label = "图标" },
      { type = "color", key = "color", label = "颜色" },
    },
    onSave = function(result)
      local id, err = M.persist(ctx, item, result)
      if not id then return false, err end
      if onSaved then onSaved(id) end
      return true
    end,
  })
end

-- 保存逻辑（与界面分离）：返回 id 或 nil, 错误
function M.persist(ctx, existingItem, result)
  local app = ctx.app
  local title = Form.trim(result.title)
  if title == "" then return nil, "请填写名称" end
  if not dateUtils.isValidDate(result.target_date) then return nil, "请选择日期" end

  local payload = {
    title = title,
    description = result.description or "",
    target_date = result.target_date,
    repeat_yearly = result.repeat_yearly == true,
    kind = result.kind,
    reminder_days = tonumber(result.reminder_days) or 0,
    icon = result.icon or "star",
    color = result.color,
  }

  local id, err
  if existingItem then
    local ok
    ok, err = app.countdowns:update(existingItem.id, payload)
    if ok then id = existingItem.id end
  else
    id, err = app.countdowns:create(payload)
  end
  if not id then return nil, err or "保存失败" end

  app:changed(eventBus.EVENTS.COUNTDOWNS_CHANGED)
  return id
end

return M
