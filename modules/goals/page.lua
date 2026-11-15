-- 目标页（子页面）：目标列表 + 里程碑 + 关联任务
local bindClass = luajava.bindClass
local LinearLayout = bindClass "android.widget.LinearLayout"
local ScrollView = bindClass "androidx.core.widget.NestedScrollView"
local BottomSheetDialog = bindClass "com.google.android.material.bottomsheet.BottomSheetDialog"

local ui = require "components.ui"
local theme = require "config.theme"
local constants = require "config.constants"
local dateUtils = require "utils.date_utils"
local eventBus = require "core.event_bus"
local Form = require "components.form_dialog"
local todosEditor = require "modules.todos.editor"

local M = {}

M.title = "目标"

local function openEditor(ctx, goal, onSaved)
  local app = ctx.app
  local editing = goal ~= nil
  return Form.open({
    title = editing and "编辑目标" or "新建目标",
    values = {
      title = editing and goal.title or "",
      description = editing and (goal.description or "") or "",
      start_date = editing and (goal.start_date or "") or dateUtils.today(),
      end_date = editing and (goal.end_date or "") or dateUtils.addDays(dateUtils.today(), 30),
    },
    saveLabel = editing and "保存" or "创建",
    fields = {
      { type = "text", key = "title", label = "目标名称" },
      { type = "multiline", key = "description", label = "描述" },
      { type = "date", key = "start_date", label = "开始日期" },
      { type = "date", key = "end_date", label = "截止日期" },
    },
    onSave = function(result)
      local id, err = M.persist(ctx, goal, result)
      if not id then return false, err end
      if onSaved then onSaved(id) end
      return true
    end,
  })
end

-- 保存逻辑（与界面分离，便于校验）：返回 id 或 nil, 错误
function M.persist(ctx, existingGoal, result)
  local app = ctx.app
  local title = Form.trim(result.title)
  if title == "" then return nil, "请填写目标名称" end
  if not dateUtils.isValidDate(result.start_date) then return nil, "请选择开始日期" end
  if not dateUtils.isValidDate(result.end_date) then return nil, "请选择截止日期" end
  if dateUtils.diffDays(result.start_date, result.end_date) < 0 then
    return nil, "截止日期不能早于开始日期"
  end

  local payload = {
    title = title,
    description = result.description or "",
    start_date = result.start_date,
    end_date = result.end_date,
  }

  local id, err
  if existingGoal then
    local ok
    ok, err = app.goals:update(existingGoal.id, payload)
    if ok then id = existingGoal.id end
  else
    id, err = app.goals:create(payload)
  end
  if not id then return nil, err or "保存失败" end

  app:changed(eventBus.EVENTS.GOALS_CHANGED)
  return id
end

-- 详情面板：里程碑与关联任务。
-- 独立成模块级函数，便于复用与自动化验证输入、提交。
-- 布局表里的节点是声明而非 View，读取内容必须按 id 取真实控件。
function M.openDetail(ctx, goalId, onChanged)
  local app = ctx.app
  local goal = app.goals:get(goalId)
  if not goal then return nil end
  local decorated = app.goals:decorate(goal)

  local sheet = BottomSheetDialog(activity)
  local sheetViews = {}

  local body = {
    LinearLayout,
    orientation = "vertical",
    layout_width = "match",
    layout_height = "wrap",
    padding = "20dp",
    BackgroundColor = theme.ATTR.surface,
    ui.text(goal.title, { textSize = "18sp", textStyle = "bold", layout_width = "match" }),
    ui.caption(string.format("进度 %d%% · 剩余 %s", decorated.progress,
      decorated.daysLeft and (decorated.daysLeft .. " 天") or "未设置"), {
      layout_width = "match", layout_marginTop = "4dp",
    }),
    ui.progress(decorated.progress, { marginTop = 10 }),
    ui.divider(),
    ui.caption("里程碑", { layout_marginBottom = 4 }),
    ui.container("milestones"),
  }

  local renderMilestones
  local renderTodos

  local addInput = ui.textField("milestoneInput", "新里程碑", { weight = 1, textSize = 14 })
  -- 回调在点击时才执行，届时 renderMilestones 已赋值
  local addButton = ui.iconButton("plus", function()
    local text = Form.trim(tostring(sheetViews.milestoneInput.getText()))
    if text == "" then return end
    local ok, err = app.goals:addMilestone(goalId, text)
    if not ok then
      ui.alert("添加失败", tostring(err))
      return
    end
    sheetViews.milestoneInput.setText("")
    renderMilestones()
    app:changed(eventBus.EVENTS.GOALS_CHANGED)
    if onChanged then onChanged() end
  end, { marginStart = 8, size = 44 })
  body[#body + 1] = ui.row({ addInput, addButton })

  body[#body + 1] = ui.divider()
  body[#body + 1] = ui.caption("关联任务", { layout_marginBottom = 4 })
  body[#body + 1] = ui.container("todos")

  body[#body + 1] = ui.row({
    ui.textButton("新增关联任务", function()
      sheet.dismiss()
      todosEditor.open(ctx, nil, onChanged)
    end, { weight = 1 }),
    ui.textButton(decorated.status == "done" and "重新开始" or "标记完成", function()
      app.goals:setStatus(goal.id, decorated.status == "done" and "active" or "done")
      app:changed(eventBus.EVENTS.GOALS_CHANGED)
      sheet.dismiss()
      if onChanged then onChanged() end
    end, { weight = 1 }),
  }, { layout_marginTop = 8 })

  body[#body + 1] = ui.row({
    ui.textButton("编辑", function()
      sheet.dismiss()
      openEditor(ctx, goal, onChanged)
    end, { weight = 1 }),
    ui.textButton("删除", function()
      sheet.dismiss()
      ui.confirm({
        title = "删除目标",
        message = "删除「" .. goal.title .. "」会同时删除它的里程碑，关联任务会保留但解除关联。",
        confirmText = "删除",
      }, function()
        local ok, err = app.goals:remove(goal.id)
        if not ok then
          ui.alert("删除失败", tostring(err))
          return
        end
        app:changed(eventBus.EVENTS.GOALS_CHANGED)
        if onChanged then onChanged() end
      end)
    end, { weight = 1 }),
  })

  renderMilestones = function()
    local milestones = app.goals:milestones(goalId)
    local children = {}
    if #milestones == 0 then
      children[#children + 1] = ui.caption("还没有里程碑", { layout_width = "match" })
    else
      for _, item in ipairs(milestones) do
        local row, check = ui.checkRow({
          title = item.title,
          checked = item.is_completed == 1,
        })
        check.clickable = true
        check.onClick = function()
          app.goals:setMilestoneCompleted(item.id, item.is_completed ~= 1)
          app:changed(eventBus.EVENTS.GOALS_CHANGED)
          renderMilestones()
          if onChanged then onChanged() end
        end
        children[#children + 1] = row
      end
    end
    ui.fill(sheetViews.milestones, children)
  end

  renderTodos = function()
    local linked = app.todos:linkedToGoal(goalId)
    local children = {}
    if #linked == 0 then
      children[#children + 1] = ui.caption("还没有关联任务", { layout_width = "match" })
    else
      for _, todo in ipairs(linked) do
        local row, check = ui.checkRow({
          title = todo.title,
          checked = todo.done,
          subtitle = todo.due_date and todo.due_date ~= ""
            and dateUtils.relativeDay(todo.due_date) or nil,
        })
        check.clickable = true
        check.onClick = function()
          app.todos:toggle(todo.id)
          app:changed(eventBus.EVENTS.TODOS_CHANGED)
          renderTodos()
          if onChanged then onChanged() end
        end
        children[#children + 1] = row
      end
    end
    ui.fill(sheetViews.todos, children)
  end

  sheet.setContentView(loadlayout({
    ScrollView,
    layout_width = "match",
    layout_height = "wrap",
    body,
  }, sheetViews))
  sheet.show()
  renderMilestones()
  renderTodos()
  return sheet
end

function M.create(ctx)
  local app = ctx.app
  local page = { alive = true }
  local state = { filter = "active" }
  local refresh

  local views = {}
  local root = loadlayout({
    LinearLayout,
    orientation = "vertical",
    layout_width = "match",
    layout_height = "match",
    BackgroundColor = theme.ATTR.surface,
    {
      LinearLayout,
      orientation = "horizontal",
      layout_width = "match",
      layout_height = "wrap",
      paddingStart = "8dp",
      paddingEnd = "12dp",
      paddingTop = "8dp",
      gravity = "center_vertical",
      {
        ui.iconButton("chevron_left", function() ctx.nav:pop() end),
        ui.text("目标", {
          textSize = "20sp", textStyle = "bold",
          layout_width = "0dp", layout_weight = 1, layout_height = "wrap",
          layout_marginStart = "4dp",
        }),
        ui.iconButton("plus", function()
          openEditor(ctx, nil, function() refresh() end)
        end),
      },
    },
    {
      LinearLayout,
      id = "filters",
      orientation = "horizontal",
      layout_width = "match",
      layout_height = "wrap",
      paddingStart = "16dp",
      paddingEnd = "16dp",
      paddingBottom = "8dp",
    },
    {
      ScrollView,
      layout_width = "match",
      layout_height = "0dp",
      layout_weight = 1,
      clipToPadding = false,
      {
        LinearLayout,
        id = "content",
        orientation = "vertical",
        layout_width = "match",
        layout_height = "wrap",
        paddingStart = "16dp",
        paddingEnd = "16dp",
        paddingBottom = "32dp",
      },
    },
  }, views)

  local function openDetail(goalId)
    return M.openDetail(ctx, goalId, function() refresh() end)
  end

  local function goalCard(goal)
    local subtitle = {}
    if goal.end_date and goal.end_date ~= "" then
      subtitle[#subtitle + 1] = goal.daysLeft >= 0
        and ("剩 " .. goal.daysLeft .. " 天") or ("超期 " .. (-goal.daysLeft) .. " 天")
    end
    if goal.milestoneTotal > 0 then
      subtitle[#subtitle + 1] = string.format("里程碑 %d/%d", goal.milestoneDone, goal.milestoneTotal)
    end
    if goal.todoTotal > 0 then
      subtitle[#subtitle + 1] = string.format("任务 %d/%d", goal.todoDone, goal.todoTotal)
    end

    return ui.card({
      ui.row({
        ui.text(goal.title, {
          textSize = "16sp", textStyle = "bold",
          layout_width = "0dp", layout_weight = 1, layout_height = "wrap",
        }),
        ui.text(goal.progress .. "%", {
          textSize = "14sp",
          textColor = theme.ATTR.primary,
          layout_height = "wrap",
        }),
      }),
      ui.progress(goal.progress, { marginTop = 8, thickness = 6 }),
      ui.caption(table.concat(subtitle, " · "), {
        layout_width = "match",
        layout_height = "wrap",
        layout_marginTop = "8dp",
      }),
    }, { marginTop = 10, clickable = true })
  end

  refresh = function()
    if not page.alive then return end

    ui.fill(views.filters, {
      (state.filter == "active" and ui.button or ui.outlinedButton)("进行中", function()
        state.filter = "active"
        refresh()
      end, { marginEnd = 8 }),
      (state.filter == "done" and ui.button or ui.outlinedButton)("完成", function()
        state.filter = "done"
        refresh()
      end, { marginEnd = 8 }),
      (state.filter == "all" and ui.button or ui.outlinedButton)("全部", function()
        state.filter = "all"
        refresh()
      end),
    })

    local list
    if state.filter == "all" then
      list = app.goals:list(nil)
    else
      list = app.goals:list(state.filter)
    end

    local children = {}
    if #list == 0 then
      children[#children + 1] = ui.empty("target", "还没有目标",
        "为目标设定里程碑与任务，进度会自动计算", "新建目标", function()
          openEditor(ctx, nil, function() refresh() end)
        end)
    else
      for _, goal in ipairs(list) do
        local card = goalCard(goal)
        card.onClick = function() openDetail(goal.id) end
        card.clickable = true
        card.focusable = true
        children[#children + 1] = card
      end
    end
    ui.fill(views.content, children)
  end

  page.view = root
  page.refresh = refresh
  page.onShow = refresh
  local unsubscribe = eventBus.on(eventBus.EVENTS.DATA_CHANGED, function()
    if page.alive then refresh() end
  end)
  page.destroy = function()
    page.alive = false
    if unsubscribe then unsubscribe() end
  end

  refresh()
  return page
end

return M
