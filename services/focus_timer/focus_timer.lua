-- 专注计时器：状态持久化在 app_settings，用时间差恢复，不依赖 UI 刷新频率
local dateUtils = require "utils.date_utils"
local jsonUtils = require "utils.json_utils"

local M = {}

local STATE_KEY = "focus_state"

local Timer = {}
Timer.__index = Timer

local DEFAULT_STATE = {
  phase = "idle",       -- idle / focus / short / long / paused
  running = false,
  started_at = 0,
  ends_at = 0,
  paused_remaining = 0,
  paused_phase = nil,
  duration_seconds = 0,
  todo_id = 0,
  completed_rounds = 0,
}

function Timer:load()
  local raw = self.app.settings:get(STATE_KEY, "")
  local state = jsonUtils.decode(raw, nil)
  if not state or not state.phase then
    state = {}
    for key, value in pairs(DEFAULT_STATE) do state[key] = value end
  end
  for key, value in pairs(DEFAULT_STATE) do
    if state[key] == nil then state[key] = value end
  end
  state.todo_id = tonumber(state.todo_id) or 0
  state.ends_at = tonumber(state.ends_at) or 0
  state.started_at = tonumber(state.started_at) or 0
  state.paused_remaining = tonumber(state.paused_remaining) or 0
  state.duration_seconds = tonumber(state.duration_seconds) or 0
  state.completed_rounds = tonumber(state.completed_rounds) or 0
  self.state = state
  return state
end

function Timer:save()
  self.app.settings:set(STATE_KEY, jsonUtils.encode(self.state) or "")
end

function Timer:sessionMinutes(phase)
  if phase == "focus" then return self.app.settings:focusMinutes() end
  if phase == "short" then return self.app.settings:shortBreakMinutes() end
  if phase == "long" then return self.app.settings:longBreakMinutes() end
  return self.app.settings:focusMinutes()
end

function Timer:start(phase, todoId)
  local kind = phase or "focus"
  local minutes = self:sessionMinutes(kind)
  local now = dateUtils.nowMs()
  self.state.phase = kind
  self.state.running = true
  self.state.started_at = now
  self.state.ends_at = now + minutes * 60000
  self.state.duration_seconds = minutes * 60
  self.state.paused_remaining = 0
  self.state.paused_phase = nil
  if todoId ~= nil then self.state.todo_id = tonumber(todoId) or 0 end
  self:save()
  return self.state
end

function Timer:pause()
  if not self.state.running then return false end
  local now = dateUtils.nowMs()
  self.state.paused_remaining = math.max(0, self.state.ends_at - now)
  self.state.running = false
  self.state.paused_phase = self.state.phase
  self.state.phase = "paused"
  self:save()
  return true
end

function Timer:resume()
  if self.state.phase ~= "paused" then return false end
  local now = dateUtils.nowMs()
  self.state.ends_at = now + self.state.paused_remaining
  self.state.running = true
  self.state.phase = self.state.paused_phase or "focus"
  self.state.paused_phase = nil
  self.state.paused_remaining = 0
  self:save()
  return true
end

function Timer:remainingSeconds()
  local state = self.state
  if state.phase == "idle" then return 0 end
  if state.phase == "paused" then
    return math.floor(state.paused_remaining / 1000)
  end
  if not state.running then return 0 end
  local remaining = math.floor((state.ends_at - dateUtils.nowMs()) / 1000)
  if remaining < 0 then return 0 end
  return remaining
end

function Timer:isRunning()
  return self.state.running == true
end

-- 结束当前会话：completed 表示自然完成
function Timer:finish(completed)
  local state = self.state
  local phase = state.phase == "paused" and (state.paused_phase or "focus") or state.phase
  if phase == "idle" then return nil end

  local now = dateUtils.nowMs()
  local planned = state.duration_seconds or 0
  local elapsed
  if state.running then
    elapsed = math.floor((now - state.started_at) / 1000)
  else
    elapsed = math.floor((planned * 1000 - state.paused_remaining) / 1000)
  end
  elapsed = math.max(0, math.min(elapsed, planned))

  local recordId
  if phase == "focus" and elapsed >= 60 then
    recordId = self.app.focusRepo:create({
      todo_id = state.todo_id ~= 0 and state.todo_id or nil,
      start_time = state.started_at,
      end_time = now,
      duration_seconds = elapsed,
      completed = completed and true or false,
    })
  end

  if phase == "focus" then
    state.completed_rounds = (state.completed_rounds or 0) + (completed and 1 or 0)
  end

  state.phase = "idle"
  state.running = false
  state.started_at = 0
  state.ends_at = 0
  state.paused_remaining = 0
  state.paused_phase = nil
  state.duration_seconds = 0
  self:save()

  return {
    phase = phase,
    elapsed = elapsed,
    recordId = recordId,
    completed = completed and true or false,
  }
end

-- 应用回到前台时检查：会话是否已经到期
function Timer:catchUp()
  local state = self.state
  if state.phase == "idle" or state.phase == "paused" then return nil end
  if not state.running then return nil end
  if dateUtils.nowMs() < state.ends_at then return nil end

  local finished = self:finish(true)
  if finished and finished.phase == "focus" then
    self.app.notifier:post(
      math.floor(dateUtils.nowMs() / 1000) % 100000,
      "专注完成",
      "本次专注 " .. dateUtils.durationLabel(finished.elapsed) .. "，休息一下吧")
    return finished
  end
  if finished then
    self.app.notifier:post(
      math.floor(dateUtils.nowMs() / 1000) % 100000,
      "休息结束", "可以开始下一轮专注了")
  end
  return finished
end

function Timer:reset()
  self.state = {}
  for key, value in pairs(DEFAULT_STATE) do self.state[key] = value end
  self:save()
end

function Timer:phaseLabel()
  local phase = self.state.phase
  if phase == "focus" then return "专注中" end
  if phase == "short" then return "短休息" end
  if phase == "long" then return "长休息" end
  if phase == "paused" then return "已暂停" end
  return "准备开始"
end

function M.new(app)
  local timer = setmetatable({ app = app }, Timer)
  timer:load()
  return timer
end

return M
