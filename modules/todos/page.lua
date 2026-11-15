-- 待办列表页（子页面）：筛选、勾选完成、详情与子任务
local bindClass = luajava.bindClass
local LinearLayout = bindClass "android.widget.LinearLayout"
local BottomSheetDialog = bindClass "com.google.android.material.bottomsheet.BottomSheetDialog"
local ScrollView = bindClass "androidx.core.widget.NestedScrollView"

local ui = require "components.ui"
local theme = require "config.theme"
local constants = require "config.constants"
local dateUtils = require "utils.date_utils"
local eventBus = require "core.event_bus"
local Editor = require "modules.todos.editor"
local Form = require "components.form_dialog"

local M = {}

local FILTERS = {
  { id = "today", name = "今天" },
  { id = "all", name = "全部" },
  { id = "overdue", name = "已过期" },
  { id = "completed", name = "完成" },
}

M.title = "待办"

-- 详情面板：子任务可独立完成。
-- 独立成模块级函数，便于复用与自动化验证输入、提交。
-- 布局表里的节点是声明而非 View，读取内容必须按 id 取真实控件。
function M.openDetail(ctx, todoId, onChanged)
  local app = ctx.app
  local todo = app.todos:get(todoId)
  if not todo then return nil end

  local sheet = BottomSheetDialog(activity)
  local sheetViews = {}

  local meta = {}
  if todo.due_date and todo.due_date ~= "" then
    meta[#meta + 1] = dateUtils.formatDateCN(todo.due_date)
  end
  meta[#meta + 1] = "优先级 " .. constants.priorityName(todo.priority)
  local isOverdue = todo.due_date and todo.due_date ~= ""
    and dateUtils.diffDays(dateUtils.today(), todo.due_date) < 0 and todo.is_completed == 0
  if isOverdue then meta[#meta + 1] = "已逾期" end

  local body = {
    LinearLayout,
    orientation = "vertical",
    layout_width = "match",
    layout_height = "wrap",
    padding = "20dp",
    BackgroundColor = theme.ATTR.surface,
    ui.text(todo.title, { textSize = "18sp", textStyle = "bold", layout_width = "match" }),
    ui.caption(table.concat(meta, " · "), {
      layout_width = "match", layout_height = "wrap", layout_marginTop = "6dp",
    }),
  }
  if todo.description and todo.description ~= "" then
    body[#body + 1] = ui.text(todo.description, {
      textSize = "14sp",
      layout_width = "match",
      layout_height = "wrap",
      layout_marginTop = "8dp",
    })
  end

  body[#body + 1] = ui.divider({ layout_marginTop = 12 })
  body[#body + 1] = ui.caption("子任务", { layout_marginBottom = 4 })
  body[#body + 1] = ui.container("subtasks")

  local renderSubtasks

  local addInput = ui.textField("subtaskInput", "新子任务", { weight = 1, textSize = 14 })
  -- 回调在点击时才执行，届时 renderSubtasks 已赋值
  local addButton = ui.iconButton("plus", function()
    local text = Form.trim(tostring(sheetViews.subtaskInput.getText()))
    if text == "" then return end
    local ok, err = app.todos:addSubtask(todoId, text)
    if not ok then
      ui.alert("添加失败", tostring(err))
      return
    end
    sheetViews.subtaskInput.setText("")
    renderSubtasks()
    app:changed(eventBus.EVENTS.TODOS_CHANGED)
    if onChanged then onChanged() end
  end, { marginStart = 8, size = 44 })
  body[#body + 1] = ui.row({ addInput, addButton }, { layout_marginTop = 8 })

  body[#body + 1] = ui.row({
    ui.textButton("编辑", function()
      sheet.dismiss()
      Editor.open(ctx, todo, onChanged)
    end),
    ui.textButton("删除", function()
      sheet.dismiss()
      Editor.confirmDelete(ctx, todo, onChanged)
    end),
  }, { layout_marginTop = 8 })

  renderSubtasks = function()
    local subtasks = app.todos:subtasks(todoId)
    local children = {}
    if #subtasks == 0 then
      children[#children + 1] = ui.caption("还没有子任务，可以在下方添加", {
        layout_width = "match", paddingTop = 4, paddingBottom = 4,
      })
    else
      for _, item in ipairs(subtasks) do
        children[#children + 1] = ui.checkRow({
          title = item.title,
          checked = item.is_completed == 1,
          onClick = function()
            app.todos:setSubtaskCompleted(item.id, item.is_completed ~= 1)
            renderSubtasks()
            app:changed(eventBus.EVENTS.TODOS_CHANGED)
            if onChanged then onChanged() end
          end,
        })
      end
    end
    ui.fill(sheetViews.subtasks, children)
  end

  sheet.setContentView(loadlayout({
    ScrollView,
    layout_width = "match",
    layout_height = "wrap",
    body,
  }, sheetViews))
  sheet.show()
  renderSubtasks()
  return sheet
end

function M.create(ctx)
  local app = ctx.app
  local page = { alive = true }
  local state = { filter = "today" }
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
        ui.text("待办", {
          textSize = "20sp",
          textStyle = "bold",
          layout_width = "0dp",
          layout_weight = 1,
          layout_height = "wrap",
          layout_marginStart = "4dp",
        }),
        ui.iconButton("plus", function() openCreate() end),
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
        id = "list",
        orientation = "vertical",
        layout_width = "match",
        layout_height = "wrap",
        paddingStart = "16dp",
        paddingEnd = "16dp",
        paddingBottom = "32dp",
      },
    },
  }, views)

  local function openCreate()
    Editor.open(ctx, nil, function() refresh() end)
  end

  local function openEditor(todo)
    Editor.open(ctx, todo, function() refresh() end)
  end

  local function openDetail(todoId)
    return M.openDetail(ctx, todoId, function() refresh() end)
  end

  local function todoRow(todo)
    local subtitle = {}
    if todo.due_date and todo.due_date ~= "" then
      subtitle[#subtitle + 1] = dateUtils.relativeDay(todo.due_date)
    end
    if todo.subtaskTotal > 0 then
      subtitle[#subtitle + 1] = string.format("子任务 %d/%d", todo.subtaskDone, todo.subtaskTotal)
    end
    local priorityText = constants.priorityName(todo.priority)
    local trailingColor = todo.overdue and theme.ATTR.error or theme.ATTR.onSurfaceVariant

    -- 勾选区域切换完成；标题区域进入详情
    local row, check, textStack = ui.checkRow({
      title = todo.title,
      subtitle = table.concat(subtitle, " · "),
      checked = todo.done,
      trailing = priorityText,
      trailingColor = trailingColor,
    })

    check.clickable = true
    check.onClick = function()
      local ok, err = app.todos:toggle(todo.id)
      if not ok then
        ui.alert("操作失败", tostring(err))
        return
      end
      refresh()
    end
    textStack.clickable = true
    textStack.onClick = function() openDetail(todo.id) end

    row.onLongClick = function()
      openDetail(todo.id)
      return true
    end
    return row
  end

  refresh = function()
    if not page.alive then return end

    local chips = {}
    for _, filter in ipairs(FILTERS) do
      local selected = state.filter == filter.id
      local builder = selected and ui.button or ui.outlinedButton
      chips[#chips + 1] = builder(filter.name, function()
        state.filter = filter.id
        refresh()
      end, { marginEnd = 8 })
    end
    ui.fill(views.filters, chips)

    local todos = {}
    if state.filter == "today" then
      local today = dateUtils.today()
      todos = app.todos:list({ status = "active", dueDate = today })
      local seen = {}
      for _, item in ipairs(todos) do seen[item.id] = true end
      for _, item in ipairs(app.todos:overdueList()) do
        if not seen[item.id] then todos[#todos + 1] = item end
      end
    elseif state.filter == "overdue" then
      todos = app.todos:overdueList()
    elseif state.filter == "completed" then
      todos = app.todos:completedList(80)
    else
      todos = app.todos:list({ status = "active" })
    end

    local children = {}
    if #todos == 0 then
      children[#children + 1] = ui.empty("list", "没有待办",
        state.filter == "completed" and "完成的任务会出现在这里" or "点击右上角 + 创建一条任务",
        "新建待办", function() openCreate() end)
    else
      for _, todo in ipairs(todos) do
        children[#children + 1] = todoRow(todo)
      end
    end
    ui.fill(views.list, children)
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
