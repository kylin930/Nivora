-- 首页：今日进度、习惯打卡、待办、日程、倒数日、快捷操作
-- 进度口径：今日待办 + 今日应打卡习惯，两者不重复计入。
local bindClass = luajava.bindClass
local LinearLayout = bindClass "android.widget.LinearLayout"
local ScrollView = bindClass "androidx.core.widget.NestedScrollView"

local ui = require "components.ui"
local theme = require "config.theme"
local dateUtils = require "utils.date_utils"
local eventBus = require "core.event_bus"
local habitsEditor = require "modules.habits.editor"
local schedulesEditor = require "modules.schedules.editor"
local todosEditor = require "modules.todos.editor"
local TodosPage = require "modules.todos.page"
local CountdownPage = require "modules.countdown.page"

local M = {}

M.title = "首页"

local function greeting()
  local hour = dateUtils.timeParts(dateUtils.nowMs())
  if hour < 5 then return "夜深了" end
  if hour < 11 then return "早上好" end
  if hour < 14 then return "中午好" end
  if hour < 18 then return "下午好" end
  return "晚上好"
end

function M.create(ctx)
  local app = ctx.app
  local page = { alive = true }
  local refresh

  local views = {}
  local root = loadlayout({
    LinearLayout,
    orientation = "vertical",
    layout_width = "match",
    layout_height = "match",
    BackgroundColor = theme.ATTR.surface,
    {
      ScrollView,
      layout_width = "match",
      layout_height = "match",
      fillViewport = true,
      clipToPadding = false,
      {
        LinearLayout,
        id = "content",
        orientation = "vertical",
        layout_width = "match",
        layout_height = "wrap",
        paddingStart = "16dp",
        paddingEnd = "16dp",
        paddingTop = "16dp",
        paddingBottom = "32dp",
      },
    },
  }, views)

  local function header()
    local today = dateUtils.today()
    local _, month, day = dateUtils.parts(today)
    return ui.column({
      ui.text(greeting(), {
        textSize = "24sp",
        textStyle = "bold",
        layout_width = "match",
        layout_height = "wrap",
      }),
      ui.caption(string.format("%d 月 %d 日 · %s", month, day,
        dateUtils.WEEK_FULL_CN[dateUtils.weekday(today)]), {
        layout_width = "match",
        layout_height = "wrap",
        layout_marginTop = "4dp",
      }),
    }, { layout_marginBottom = 12 })
  end

  local function progressCard()
    local today = dateUtils.today()
    local habitDone, habitTotal = app.habits:todaySummary(today)
    local todoDone, todoTotal = app.todos:todaySummary(today)
    local total = habitTotal + todoTotal
    local done = habitDone + todoDone
    local percent = total > 0 and math.floor(done / total * 100 + 0.5) or 0

    return ui.card({
      ui.row({
        ui.text("今日进度", {
          textSize = "16sp", textStyle = "bold",
          layout_width = "0dp", layout_weight = 1, layout_height = "wrap",
        }),
        ui.text(percent .. "%", {
          textSize = "20sp",
          textStyle = "bold",
          textColor = theme.ATTR.primary,
          layout_height = "wrap",
        }),
      }),
      ui.progress(percent, { marginTop = 12 }),
      ui.row({
        ui.metric("任务", string.format("%d/%d", todoDone, todoTotal)),
        ui.metric("习惯", string.format("%d/%d", habitDone, habitTotal)),
        ui.metric("日程", tostring(#app.schedules:occurrencesOn(today))),
      }, { layout_marginTop = 16 }),
    })
  end

  local function habitSection()
    local list = app.habits:todayList(dateUtils.today())
    local children = {
      ui.sectionHeader("今日习惯", "管理", function() ctx.nav:setTab(3) end, { marginTop = 20 }),
    }
    if #list == 0 then
      children[#children + 1] = ui.card({
        ui.caption("还没有今天的习惯，先建一个吧", { layout_width = "match" }),
        ui.textButton("新建习惯", function()
          habitsEditor.open(ctx, nil, function() refresh() end)
        end),
      })
      return children
    end
    local rows = {}
    for _, habit in ipairs(list) do
      local row, check, textStack = ui.checkRow({
        title = habit.name,
        subtitle = habit.frequency_type == "weekly_count"
          and ("本周 " .. habit.weekCount .. "/" .. habit.target) or nil,
        checked = habit.doneToday,
      })
      check.clickable = true
      check.onClick = function()
        local ok, err = app.habits:toggle(habit.id, dateUtils.today())
        if not ok and err then
          ui.snackbar(root, tostring(err))
        else
          app:changed(eventBus.EVENTS.HABITS_CHANGED)
        end
      end
      textStack.clickable = true
      textStack.onClick = function() ctx.nav:setTab(3) end
      rows[#rows + 1] = row
    end
    children[#children + 1] = ui.card(rows, { padding = 4 })
    return children
  end

  local function todoSection()
    local today = dateUtils.today()
    local list = app.todos:todayList(today)
    local overdue = app.todos:overdueList()
    local children = {
      ui.sectionHeader("今日待办", "全部", function()
        ctx.nav:push(TodosPage, {})
      end, { marginTop = 20 }),
    }

    if #list == 0 and #overdue == 0 then
      children[#children + 1] = ui.card({
        ui.caption("今天没有待办任务", { layout_width = "match" }),
        ui.textButton("新建待办", function()
          todosEditor.open(ctx, nil, function() refresh() end)
        end),
      })
      return children
    end

    local rows = {}
    for _, todo in ipairs(list) do
      local row, check, textStack = ui.checkRow({
        title = todo.title,
        subtitle = todo.subtaskTotal > 0
          and string.format("子任务 %d/%d", todo.subtaskDone, todo.subtaskTotal) or nil,
        checked = false,
        trailing = require("config.constants").priorityName(todo.priority),
      })
      check.clickable = true
      check.onClick = function()
        local ok, err = app.todos:toggle(todo.id)
        if not ok then
          ui.snackbar(root, tostring(err))
        else
          app:changed(eventBus.EVENTS.TODOS_CHANGED)
        end
      end
      textStack.clickable = true
      textStack.onClick = function() ctx.nav:push(TodosPage, {}) end
      rows[#rows + 1] = row
      if #rows >= 4 then break end
    end

    if #overdue > 0 then
      rows[#rows + 1] = ui.listItem({
        icon = "info",
        title = "另有 " .. #overdue .. " 项已过期",
        subtitle = overdue[1].title,
        trailingIcon = "chevron_right",
        onClick = function() ctx.nav:push(TodosPage, {}) end,
      })
    end
    children[#children + 1] = ui.card(rows, { padding = 4 })
    return children
  end

  local function scheduleSection()
    local upcoming = app.schedules:upcoming(3)
    local children = {
      ui.sectionHeader("接下来", "日程", function() ctx.nav:setTab(2) end, { marginTop = 20 }),
    }
    if #upcoming == 0 then
      children[#children + 1] = ui.card({
        ui.caption("近期没有安排", { layout_width = "match" }),
        ui.textButton("新建日程", function()
          schedulesEditor.open(ctx, nil, function() refresh() end)
        end),
      })
      return children
    end
    local rows = {}
    for _, item in ipairs(upcoming) do
      local dateStr = dateUtils.dateOf(item.start_time)
      local timeLabel = item.is_all_day == 1 and "全天" or dateUtils.formatTime(item.start_time)
      rows[#rows + 1] = ui.listItem({
        icon = "calendar",
        title = item.title,
        subtitle = (dateStr == dateUtils.today() and "今天" or dateUtils.formatDateCN(dateStr))
          .. " · " .. timeLabel,
        onClick = function() ctx.nav:setTab(2) end,
      })
    end
    children[#children + 1] = ui.card(rows, { padding = 4 })
    return children
  end

  local function countdownSection()
    local list = app.countdowns:upcoming(2)
    local children = {
      ui.sectionHeader("倒数日", "全部", function()
        ctx.nav:push(CountdownPage, {})
      end, { marginTop = 20 }),
    }
    if #list == 0 then
      children[#children + 1] = ui.card({
        ui.caption("还没有倒数日", { layout_width = "match" }),
        ui.textButton("新建倒数日", function()
          require("modules.countdown.editor").open(ctx, nil, function() refresh() end)
        end),
      })
      return children
    end
    local rows = {}
    for _, item in ipairs(list) do
      rows[#rows + 1] = ui.listItem({
        icon = "star",
        iconColor = item.color and require("utils.color_utils").parse(item.color) or nil,
        title = item.title,
        subtitle = dateUtils.formatDateCN(item.effective_date) ..
          (item.isYearly and " · 每年" or ""),
        trailing = item.statusText,
        trailingColor = item.daysLeft >= 0 and theme.ATTR.primary or theme.ATTR.onSurfaceVariant,
        onClick = function() ctx.nav:push(CountdownPage, {}) end,
      })
    end
    children[#children + 1] = ui.card(rows, { padding = 4 })
    return children
  end

  local function quickActions()
    -- 两列等宽卡片：宽度 0dp + weight 1
    local function actionCard(icon, label, handler)
      local card = ui.card({
        ui.row({
          ui.icon(icon, { size = 20, color = theme.colors().primary, marginEnd = 8 }),
          ui.text(label, { textSize = "13sp", layout_height = "wrap" }),
        }),
      }, { padding = 12 })
      card.layout_width = "0dp"
      card.layout_weight = 1
      card.clickable = true
      card.focusable = true
      card.onClick = handler
      return card
    end

    local row1 = ui.row({
      actionCard("list", "新建待办", function()
        todosEditor.open(ctx, nil, function() refresh() end)
      end),
      ui.hspace(8),
      actionCard("calendar", "新建日程", function()
        schedulesEditor.open(ctx, nil, function() refresh() end)
      end),
    }, { marginTop = 8 })

    local row2 = ui.row({
      actionCard("check", "新建习惯", function()
        habitsEditor.open(ctx, nil, function() refresh() end)
      end),
      ui.hspace(8),
      actionCard("timer", "开始专注", function()
        ctx.nav:push(require("modules.focus.page"), {})
      end),
    }, { marginTop = 8 })

    return {
      ui.sectionHeader("快捷操作", nil, nil, { marginTop = 20 }),
      row1,
      row2,
    }
  end

  refresh = function()
    if not page.alive then return end
    local children = { header(), progressCard() }
    for _, node in ipairs(habitSection()) do children[#children + 1] = node end
    for _, node in ipairs(todoSection()) do children[#children + 1] = node end
    for _, node in ipairs(scheduleSection()) do children[#children + 1] = node end
    for _, node in ipairs(countdownSection()) do children[#children + 1] = node end
    for _, node in ipairs(quickActions()) do children[#children + 1] = node end
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
