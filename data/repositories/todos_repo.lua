-- 待办数据访问：任务、子任务、状态派生（过期不落库，由截止日期动态判断）
local M = {}

local dateUtils = require "utils.date_utils"

local Repo = {}
Repo.__index = Repo

local function int(value)
  if value == true then return 1 end
  if value == false or value == nil then return 0 end
  return tonumber(value) or 0
end

-- ---------- 查询 ----------

function Repo:get(id)
  return self.db:queryOne("SELECT * FROM todos WHERE id = ?", { id })
end

function Repo:subtasks(todoId)
  return self.db:query(
    "SELECT * FROM todo_subtasks WHERE todo_id = ? ORDER BY sort_order ASC, id ASC", { todoId })
end

function Repo:subtaskCounts(todoId)
  local row = self.db:queryOne(
    "SELECT COUNT(*) AS total, SUM(is_completed) AS done FROM todo_subtasks WHERE todo_id = ?", { todoId })
  if not row then return 0, 0 end
  return tonumber(row.done) or 0, tonumber(row.total) or 0
end

-- 装饰：优先级名、是否过期、子任务进度
function Repo:decorate(todo)
  if not todo then return nil end
  todo.is_completed = int(todo.is_completed)
  todo.priority = tonumber(todo.priority) or 1
  todo.done = todo.is_completed == 1
  todo.overdue = (not todo.done) and todo.due_date ~= nil and todo.due_date ~= ""
    and dateUtils.diffDays(dateUtils.today(), todo.due_date) < 0
  local done, total = self:subtaskCounts(todo.id)
  todo.subtaskDone = done
  todo.subtaskTotal = total
  return todo
end

function Repo:list(filter)
  local opts = filter or {}
  local sql = "SELECT * FROM todos WHERE 1 = 1"
  local args = {}

  if opts.status == "active" then
    sql = sql .. " AND is_completed = 0"
  elseif opts.status == "completed" then
    sql = sql .. " AND is_completed = 1"
  end
  if opts.goalId then
    sql = sql .. " AND goal_id = ?"
    args[#args + 1] = opts.goalId
  end
  if opts.priority then
    sql = sql .. " AND priority = ?"
    args[#args + 1] = opts.priority
  end
  if opts.categoryId then
    sql = sql .. " AND category_id = ?"
    args[#args + 1] = opts.categoryId
  end
  if opts.dueDate then
    sql = sql .. " AND due_date = ?"
    args[#args + 1] = opts.dueDate
  end

  sql = sql .. " ORDER BY is_completed ASC, priority DESC, " ..
    "CASE WHEN due_date IS NULL OR due_date = '' THEN 1 ELSE 0 END ASC, due_date ASC, id ASC"

  local rows = self.db:query(sql, args)
  local list = {}
  for _, row in ipairs(rows or {}) do
    local item = self:decorate(row)
    if opts.status ~= "overdue" or item.overdue or (item.done and item.completed_at) then
      if not opts.onlyOverdue or item.overdue then
        list[#list + 1] = item
      end
    end
  end
  return list
end

function Repo:todayList(dateStr)
  local today = dateStr or dateUtils.today()
  local rows = self.db:query(
    "SELECT * FROM todos WHERE is_completed = 0 AND due_date = ? " ..
    "ORDER BY priority DESC, id ASC", { today })
  local list = {}
  for _, row in ipairs(rows or {}) do list[#list + 1] = self:decorate(row) end
  return list
end

function Repo:overdueList()
  local today = dateUtils.today()
  local rows = self.db:query(
    "SELECT * FROM todos WHERE is_completed = 0 AND due_date IS NOT NULL AND due_date <> '' " ..
    "AND due_date < ? ORDER BY due_date ASC, priority DESC", { today })
  local list = {}
  for _, row in ipairs(rows or {}) do list[#list + 1] = self:decorate(row) end
  return list
end

function Repo:completedList(limit)
  local rows = self.db:query(
    "SELECT * FROM todos WHERE is_completed = 1 ORDER BY completed_at DESC LIMIT ?",
    { limit or 100 })
  local list = {}
  for _, row in ipairs(rows or {}) do list[#list + 1] = self:decorate(row) end
  return list
end

-- 今日应完成：今天到期 + 逾期未完成
function Repo:todaySummary(dateStr)
  local today = dateStr or dateUtils.today()
  local dueToday = self.db:scalar(
    "SELECT COUNT(*) FROM todos WHERE due_date = ?", { today }, 0)
  local completedToday = self.db:scalar(
    "SELECT COUNT(*) FROM todos WHERE is_completed = 1 AND due_date = ?", { today }, 0)
  return completedToday or 0, dueToday or 0
end

function Repo:countByStatus()
  local row = self.db:queryOne(
    "SELECT SUM(CASE WHEN is_completed = 1 THEN 1 ELSE 0 END) AS done, " ..
    "SUM(CASE WHEN is_completed = 0 THEN 1 ELSE 0 END) AS pending FROM todos")
  if not row then return 0, 0 end
  return tonumber(row.done) or 0, tonumber(row.pending) or 0
end

-- ---------- 写入 ----------

function Repo:create(data)
  local now = dateUtils.nowMs()
  local id = self.db:insert("todos", {
    title = data.title,
    description = data.description,
    due_date = (data.due_date and data.due_date ~= "") and data.due_date or nil,
    priority = data.priority or 1,
    category_id = data.category_id,
    goal_id = data.goal_id,
    is_completed = 0,
    sort_order = data.sort_order or 0,
    created_at = now,
    updated_at = now,
  })
  if not id or id < 1 then return nil, "创建任务失败" end
  return id
end

function Repo:update(id, data)
  local row = { updated_at = dateUtils.nowMs() }
  local nulls = {}
  -- 用显式标记表示"清空"：nil 在 Lua 表里不会出现，无法作为 UPDATE 的赋值
  for _, key in ipairs({ "title", "description", "priority", "goal_id", "sort_order",
    "category_id" }) do
    if data[key] ~= nil then row[key] = data[key] end
  end
  if data.clear_goal then nulls[#nulls + 1] = "goal_id" end
  if data.clear_category then nulls[#nulls + 1] = "category_id" end
  if data.due_date ~= nil then
    if data.due_date == "" then
      nulls[#nulls + 1] = "due_date"
    else
      row.due_date = data.due_date
    end
  end
  local affected = self.db:update("todos", row, "id = ?", { id }, nulls)
  if not affected or affected < 1 then return nil, "更新任务失败" end
  return true
end

function Repo:setCompleted(id, completed)
  local now = dateUtils.nowMs()
  local row = {
    is_completed = completed and 1 or 0,
    updated_at = now,
  }
  local nulls = nil
  if completed then
    row.completed_at = now
  else
    nulls = { "completed_at" }
  end
  local affected = self.db:update("todos", row, "id = ?", { id }, nulls)
  if not affected or affected < 1 then return nil, "更新任务状态失败" end
  return true
end

function Repo:toggle(id)
  local todo = self:get(id)
  if not todo then return nil, "任务不存在" end
  return self:setCompleted(id, int(todo.is_completed) == 0)
end

function Repo:remove(id)
  local affected = self.db:delete("todos", "id = ?", { id })
  if not affected or affected < 1 then return nil, "删除任务失败" end
  return true
end

-- 子任务
function Repo:addSubtask(todoId, title)
  local order = self.db:scalar(
    "SELECT COALESCE(MAX(sort_order), 0) + 1 FROM todo_subtasks WHERE todo_id = ?", { todoId }, 1)
  local id = self.db:insert("todo_subtasks", {
    todo_id = todoId,
    title = title,
    is_completed = 0,
    sort_order = order,
  })
  if not id or id < 1 then return nil, "添加子任务失败" end
  return id
end

function Repo:setSubtaskCompleted(id, completed)
  local affected = self.db:update("todo_subtasks", {
    is_completed = completed and 1 or 0,
  }, "id = ?", { id })
  if not affected or affected < 1 then return nil, "更新子任务失败" end
  return true
end

function Repo:removeSubtask(id)
  local affected = self.db:delete("todo_subtasks", "id = ?", { id })
  if not affected or affected < 1 then return nil, "删除子任务失败" end
  return true
end

function Repo:replaceSubtasks(todoId, titles)
  local ok, err = self.db:transaction(function()
    self.db:delete("todo_subtasks", "todo_id = ?", { todoId })
    for index, title in ipairs(titles or {}) do
      local text = tostring(title or ""):gsub("^%s+", ""):gsub("%s+$", "")
      if text ~= "" then
        self.db:insert("todo_subtasks", {
          todo_id = todoId,
          title = text,
          is_completed = 0,
          sort_order = index,
        })
      end
    end
  end)
  if not ok then return nil, err end
  return true
end

-- 统计：某天完成数量（用于趋势图）
function Repo:completedCountBetween(fromMs, toMs)
  return self.db:scalar(
    "SELECT COUNT(*) FROM todos WHERE is_completed = 1 AND completed_at >= ? AND completed_at <= ?",
    { fromMs, toMs }, 0)
end

-- 统计：某天完成的任务数（供趋势图逐日取数）
function Repo:completedCountOn(dateStr)
  local rel = self._dateUtils
  return self:completedCountBetween(rel.msOf(dateStr, 0, 0), rel.msOf(dateStr, 23, 59))
end

-- 统计：待完成数量（含未设置日期的任务）
function Repo:pendingCount()
  return self.db:scalar("SELECT COUNT(*) FROM todos WHERE is_completed = 0", nil, 0)
end

function Repo:completedByDay(fromDate, toDate)
  local rows = self.db:query(
    "SELECT date(completed_at/1000, 'unixepoch', 'localtime') AS day, COUNT(*) AS total " ..
    "FROM todos WHERE is_completed = 1 AND completed_at IS NOT NULL GROUP BY day")
  local map = {}
  for _, row in ipairs(rows or {}) do
    map[row.day] = tonumber(row.total) or 0
  end
  return map
end

function Repo:linkedToGoal(goalId)
  local rows = self.db:query(
    "SELECT * FROM todos WHERE goal_id = ? ORDER BY is_completed ASC, id ASC", { goalId })
  local list = {}
  for _, row in ipairs(rows or {}) do list[#list + 1] = self:decorate(row) end
  return list
end

function Repo:unlinkGoal(goalId)
  -- 用 SQL 直接置空，避免依赖 Lua 表的 nil 语义
  self.db.db.execSQL("UPDATE todos SET goal_id = NULL WHERE goal_id = ?", { goalId })
end

function M.new(db)
  return setmetatable({ db = db, _dateUtils = dateUtils }, Repo)
end

return M
