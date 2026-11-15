-- 极简事件总线：数据变更后通知各页面刷新，避免页面之间直接耦合
local M = {}
local listeners = {}

function M.on(event, handler)
  local bucket = listeners[event]
  if not bucket then
    bucket = {}
    listeners[event] = bucket
  end
  bucket[#bucket + 1] = handler
  return function()
    M.off(event, handler)
  end
end

function M.off(event, handler)
  local bucket = listeners[event]
  if not bucket then return end
  for i = #bucket, 1, -1 do
    if bucket[i] == handler then table.remove(bucket, i) end
  end
end

function M.emit(event, payload)
  local bucket = listeners[event]
  if not bucket then return end
  local snapshot = {}
  for i = 1, #bucket do snapshot[i] = bucket[i] end
  for i = 1, #snapshot do
    local ok, err = pcall(snapshot[i], payload)
    if not ok then
      print("event handler error [" .. tostring(event) .. "]: " .. tostring(err))
    end
  end
end

function M.clear()
  listeners = {}
end

M.EVENTS = {
  DATA_CHANGED = "data_changed",
  HABITS_CHANGED = "habits_changed",
  SCHEDULES_CHANGED = "schedules_changed",
  TODOS_CHANGED = "todos_changed",
  GOALS_CHANGED = "goals_changed",
  JOURNALS_CHANGED = "journals_changed",
  COUNTDOWNS_CHANGED = "countdowns_changed",
  FOCUS_CHANGED = "focus_changed",
  SETTINGS_CHANGED = "settings_changed",
  THEME_CHANGED = "theme_changed",
}

return M
