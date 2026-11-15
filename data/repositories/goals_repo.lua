-- 目标数据访问：目标 → 里程碑 → 关联任务
-- 进度按里程碑与关联任务的完成比例计算，不采用手工百分比。
local M = {}

local dateUtils = require "utils.date_utils"

local Repo = {}
Repo.__index = Repo

function Repo:get(id)
  return self.db:queryOne("SELECT * FROM goals WHERE id = ?", { id })
end

function Repo:list(status)
  local sql = "SELECT * FROM goals"
  local args = {}
  if status and status ~= "" then
    sql = sql .. " WHERE status = ?"
    args[#args + 1] = status
  end
  sql = sql .. " ORDER BY CASE status WHEN 'active' THEN 0 WHEN 'done' THEN 1 ELSE 2 END, " ..
    "CASE WHEN end_date IS NULL OR end_date = '' THEN 1 ELSE 0 END, end_date ASC, id DESC"
  local rows = self.db:query(sql, args)
  local list = {}
  for _, row in ipairs(rows or {}) do
    list[#list + 1] = self:decorate(row)
  end
  return list
end

function Repo:milestones(goalId)
  return self.db:query(
    "SELECT * FROM goal_milestones WHERE goal_id = ? ORDER BY sort_order ASC, id ASC", { goalId })
end

-- 补全展示字段：进度、剩余天数、里程碑完成数
function Repo:decorate(goal)
  if not goal then return nil end
  local milestones = self:milestones(goal.id)
  local total, done = 0, 0
  for _, item in ipairs(milestones or {}) do
    total = total + 1
    if item.is_completed == 1 then done = done + 1 end
  end
  goal.milestoneTotal = total
  goal.milestoneDone = done
  goal.milestones = milestones

  local todoTotal, todoDone = 0, 0
  local todoRow = self.db:queryOne(
    "SELECT COUNT(*) AS total, SUM(CASE WHEN is_completed = 1 THEN 1 ELSE 0 END) AS done " ..
    "FROM todos WHERE goal_id = ?", { goal.id })
  if todoRow then
    todoTotal = tonumber(todoRow.total) or 0
    todoDone = tonumber(todoRow.done) or 0
  end
  goal.todoTotal = todoTotal
  goal.todoDone = todoDone

  local milestoneRatio = total > 0 and (done / total) or nil
  local todoRatio = todoTotal > 0 and (todoDone / todoTotal) or nil
  local progress = 0
  if milestoneRatio and todoRatio then
    progress = (milestoneRatio + todoRatio) / 2
  elseif milestoneRatio then
    progress = milestoneRatio
  elseif todoRatio then
    progress = todoRatio
  end
  goal.progress = math.floor(progress * 100 + 0.5)
  if goal.status == "done" then goal.progress = 100 end

  if goal.end_date and goal.end_date ~= "" then
    goal.daysLeft = dateUtils.diffDays(dateUtils.today(), goal.end_date)
  end
  if goal.start_date and goal.start_date ~= "" and goal.end_date and goal.end_date ~= "" then
    local span = dateUtils.diffDays(goal.start_date, goal.end_date)
    goal.spanDays = span
    local elapsed = dateUtils.diffDays(goal.start_date, dateUtils.today())
    goal.timeProgress = span > 0 and math.max(0, math.min(100, math.floor(elapsed / span * 100 + 0.5))) or 0
  end
  return goal
end

function Repo:create(data)
  local now = dateUtils.nowMs()
  local id = self.db:insert("goals", {
    title = data.title,
    description = data.description,
    start_date = data.start_date,
    end_date = data.end_date,
    status = data.status or "active",
    color = data.color,
    created_at = now,
    updated_at = now,
  })
  if not id or id < 1 then return nil, "创建目标失败" end
  return id
end

function Repo:update(id, data)
  local row = { updated_at = dateUtils.nowMs() }
  for _, key in ipairs({ "title", "description", "start_date", "end_date", "status", "color" }) do
    if data[key] ~= nil then row[key] = data[key] end
  end
  local affected = self.db:update("goals", row, "id = ?", { id })
  if not affected or affected < 1 then return nil, "更新目标失败" end
  return true
end

function Repo:remove(id)
  -- 先解除任务关联再删除目标；NULL 用字面量写，避免 Lua nil 不参与 UPDATE
  local ok, err = self.db:transaction(function()
    self.db.db.execSQL("UPDATE todos SET goal_id = NULL WHERE goal_id = ?", { id })
    self.db:delete("goal_milestones", "goal_id = ?", { id })
    self.db:delete("goals", "id = ?", { id })
    return true
  end)
  if not ok then return nil, err end
  return true
end

function Repo:setStatus(id, status)
  local affected = self.db:update("goals", {
    status = status,
    updated_at = dateUtils.nowMs(),
  }, "id = ?", { id })
  if not affected or affected < 1 then return nil, "更新目标状态失败" end
  return true
end

-- 里程碑
function Repo:addMilestone(goalId, title)
  local order = self.db:scalar(
    "SELECT COALESCE(MAX(sort_order), 0) + 1 FROM goal_milestones WHERE goal_id = ?", { goalId }, 1)
  local id = self.db:insert("goal_milestones", {
    goal_id = goalId,
    title = title,
    is_completed = 0,
    sort_order = order,
  })
  if not id or id < 1 then return nil, "添加里程碑失败" end
  return id
end

function Repo:setMilestoneCompleted(id, completed)
  local row = { is_completed = completed and 1 or 0 }
  local nulls = nil
  if completed then
    row.completed_at = dateUtils.nowMs()
  else
    nulls = { "completed_at" }
  end
  local affected = self.db:update("goal_milestones", row, "id = ?", { id }, nulls)
  if not affected or affected < 1 then return nil, "更新里程碑失败" end
  return true
end

function Repo:removeMilestone(id)
  local affected = self.db:delete("goal_milestones", "id = ?", { id })
  if not affected or affected < 1 then return nil, "删除里程碑失败" end
  return true
end

function Repo:milestoneCountBetween(fromMs, toMs)
  return self.db:scalar(
    "SELECT COUNT(*) FROM goal_milestones WHERE is_completed = 1 AND completed_at >= ? AND completed_at <= ?",
    { fromMs, toMs }, 0)
end

function Repo:activeCount()
  return self.db:scalar("SELECT COUNT(*) FROM goals WHERE status = 'active'", nil, 0)
end

function Repo:doneCount()
  return self.db:scalar("SELECT COUNT(*) FROM goals WHERE status = 'done'", nil, 0)
end

function M.new(db)
  return setmetatable({ db = db }, Repo)
end

return M
