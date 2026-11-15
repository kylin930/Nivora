-- 待办编辑表单
local M = {}

local Form = require "components.form_dialog"

local function buildCategoryOptions(app)
  local list = { { value = 0, name = "未分类" } }
  for _, item in ipairs(app.categories:list("todo")) do
    list[#list + 1] = { value = item.id, name = item.name }
  end
  return list
end

local function buildGoalOptions(app, currentGoalId)
  local list = { { value = 0, name = "不关联目标" } }
  for _, goal in ipairs(app.goals:list("active")) do
    list[#list + 1] = { value = goal.id, name = goal.title }
  end
  if currentGoalId and currentGoalId > 0 then
    local exists = false
    for _, option in ipairs(list) do
      if option.value == currentGoalId then exists = true end
    end
    if not exists then
      local goal = app.goals:get(currentGoalId)
      if goal then list[#list + 1] = { value = goal.id, name = goal.title } end
    end
  end
  return list
end

-- ctx: { app, nav }；todo 为空表示新建；onSaved(新 id) 回调
function M.open(ctx, todo, onSaved)
  local app = ctx.app
  local editing = todo ~= nil
  local values = {
    title = editing and todo.title or "",
    description = editing and (todo.description or "") or "",
    due_date = editing and (todo.due_date or "") or "",
    priority = editing and (todo.priority or 1) or 1,
    category_id = editing and (todo.category_id or 0) or 0,
    goal_id = editing and (todo.goal_id or 0) or 0,
  }

  return Form.open({
    title = editing and "编辑待办" or "新建待办",
    values = values,
    saveLabel = editing and "保存" or "创建",
    fields = {
      { type = "text", key = "title", label = "任务标题" },
      { type = "multiline", key = "description", label = "备注" },
      { type = "date", key = "due_date", label = "截止日期", allowEmpty = true },
      { type = "priority", key = "priority", label = "优先级" },
      { type = "choice", key = "category_id", label = "分类", options = buildCategoryOptions(app) },
      {
        type = "choice",
        key = "goal_id",
        label = "关联目标",
        options = buildGoalOptions(app, values.goal_id > 0 and values.goal_id or nil),
      },
    },
    onSave = function(result)
      local id, err = M.persist(ctx, todo, result)
      if not id then return false, err end
      if onSaved then onSaved(id) end
      return true
    end,
  })
end

-- 保存逻辑与界面分离：便于校验与自动化测试，UI 只负责收集字段
-- 返回 新 id / nil, 错误信息
function M.persist(ctx, existingTodo, result)
  local app = ctx.app
  local title = Form.trim(result.title)
  if title == "" then return nil, "请填写任务标题" end
  if #title > 120 then return nil, "标题不要超过 120 个字符" end

  local categoryId = tonumber(result.category_id) or 0
  local goalId = tonumber(result.goal_id) or 0
  local payload = {
    title = title,
    description = result.description or "",
    due_date = result.due_date or "",
    priority = tonumber(result.priority) or 1,
    category_id = categoryId > 0 and categoryId or nil,
    goal_id = goalId > 0 and goalId or nil,
  }
  -- 编辑时允许把分类/目标/截止日期清空
  if existingTodo then
    payload.clear_category = categoryId <= 0
    payload.clear_goal = goalId <= 0
  end

  local id, err
  if existingTodo then
    local ok
    ok, err = app.todos:update(existingTodo.id, payload)
    if ok then id = existingTodo.id end
  else
    id, err = app.todos:create(payload)
  end
  if not id then return nil, err or "保存失败" end

  app:changed(require("core.event_bus").EVENTS.TODOS_CHANGED)
  return id
end

-- 删除确认
function M.confirmDelete(ctx, todo, onDeleted)
  local ui = require "components.ui"
  ui.confirm({
    title = "删除待办",
    message = "确定删除「" .. tostring(todo.title) .. "」吗？其子任务也会一并删除。",
    confirmText = "删除",
  }, function()
    local ok, err = ctx.app.todos:remove(todo.id)
    if not ok then
      ui.alert("删除失败", tostring(err))
      return
    end
    ctx.app:changed(require("core.event_bus").EVENTS.TODOS_CHANGED)
    if onDeleted then onDeleted() end
  end)
end

return M
