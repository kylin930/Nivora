-- 统计页（底部标签 4）：总览、习惯、任务、专注与每周回顾
local bindClass = luajava.bindClass
local LinearLayout = bindClass "android.widget.LinearLayout"
local ScrollView = bindClass "androidx.core.widget.NestedScrollView"

local ui = require "components.ui"
local charts = require "components.charts"
local theme = require "config.theme"
local dateUtils = require "utils.date_utils"
local eventBus = require "core.event_bus"

local M = {}

M.title = "统计"

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

  local function overviewCard()
    local today = dateUtils.today()
    local weekStart = dateUtils.startOfWeek(today, app.settings:weekStart())
    local weekEnd = dateUtils.addDays(weekStart, 6)
    local monthStart = dateUtils.startOfMonth(today)

    local weekDone = app.todos:completedCountBetween(
      dateUtils.msOf(weekStart, 0, 0), dateUtils.msOf(weekEnd, 23, 59))
    local monthDone = app.todos:completedCountBetween(
      dateUtils.msOf(monthStart, 0, 0), dateUtils.msOf(today, 23, 59))

    -- 习惯完成率：所有在用习惯在本月的完成率平均
    local habits = app.habits:list(true)
    local totalRate, habitCount = 0, 0
    for _, habit in ipairs(habits) do
      totalRate = totalRate + app.habits:completionRate(habit, monthStart, today)
      habitCount = habitCount + 1
    end
    local avgRate = habitCount > 0 and math.floor(totalRate / habitCount + 0.5) or 0

    local focusSeconds = app.focusRepo:totalSeconds(
      dateUtils.msOf(weekStart, 0, 0), dateUtils.msOf(weekEnd, 23, 59))
    local goalDone = app.goals:doneCount()

    return ui.card({
      ui.text("总览", { textSize = "16sp", textStyle = "bold", layout_width = "match" }),
      ui.row({
        ui.metric("本周完成", tostring(weekDone)),
        ui.metric("本月完成", tostring(monthDone)),
        ui.metric("目标达成", tostring(goalDone)),
      }, { layout_marginTop = 12 }),
      ui.row({
        ui.metric("本月习惯完成率", avgRate .. "%"),
        ui.metric("本周专注", dateUtils.durationLabel(focusSeconds)),
        ui.metric("在用习惯", tostring(habitCount)),
      }, { layout_marginTop = 8 }),
    })
  end

  local function taskTrendCard()
    local today = dateUtils.today()
    local values, labels = {}, {}
    for offset = -6, 0 do
      local date = dateUtils.addDays(today, offset)
      values[#values + 1] = app.todos:completedCountOn(date)
      local _, _, day = dateUtils.parts(date)
      labels[#labels + 1] = tostring(day)
    end

    local chart = charts.barChart(values, labels, { height = 130 })
    local wrapped = ui.column({ chart }, { layout_marginTop = 8 })
    return ui.card({
      ui.text("近 7 天完成任务", { textSize = "16sp", textStyle = "bold", layout_width = "match" }),
      wrapped,
    })
  end

  local function focusTrendCard()
    local today = dateUtils.today()
    local values, labels = {}, {}
    local byDay = app.focusRepo:secondsByDay(dateUtils.addDays(today, -6), today)
    for offset = -6, 0 do
      local date = dateUtils.addDays(today, offset)
      values[#values + 1] = math.floor((byDay[date] or 0) / 60)
      local _, _, day = dateUtils.parts(date)
      labels[#labels + 1] = tostring(day)
    end
    local chart = charts.lineChart(values, labels, { height = 120 })
    return ui.card({
      ui.text("近 7 天专注（分钟）", { textSize = "16sp", textStyle = "bold", layout_width = "match" }),
      ui.column({ chart }, { layout_marginTop = 8 }),
    })
  end

  local function habitStatsCard()
    local habits = app.habits:list(true)
    local children = {
      ui.text("习惯", { textSize = "16sp", textStyle = "bold", layout_width = "match" }),
    }
    if #habits == 0 then
      children[#children + 1] = ui.caption("还没有在用习惯", { layout_marginTop = 8 })
      return ui.card(children)
    end
    local today = dateUtils.today()
    local monthStart = dateUtils.startOfMonth(today)
    for _, habit in ipairs(habits) do
      local streak, unit = app.habits:currentStreak(habit, today)
      local longest = app.habits:longestStreak(habit)
      local rate = app.habits:completionRate(habit, monthStart, today)
      children[#children + 1] = ui.listItem({
        title = habit.name,
        subtitle = string.format("连续 %d %s · 最长 %d · 本月 %d%%", streak, unit, longest, rate),
        trailing = tostring(app.habits:monthCount(habit, today)) .. " 次",
      })
    end
    return ui.card(children)
  end

  local function todoStatsCard()
    local done, pending = app.todos:countByStatus()
    local overdue = #app.todos:overdueList()
    return ui.card({
      ui.text("任务", { textSize = "16sp", textStyle = "bold", layout_width = "match" }),
      ui.row({
        ui.metric("已完成", tostring(done)),
        ui.metric("进行中", tostring(pending)),
        ui.metric("已逾期", tostring(overdue)),
      }, { layout_marginTop = 12 }),
    })
  end

  local function weeklyReviewCard()
    local today = dateUtils.today()
    local weekStart = dateUtils.startOfWeek(today, app.settings:weekStart())
    local weekEnd = dateUtils.addDays(weekStart, 6)
    local weekStartMs = dateUtils.msOf(weekStart, 0, 0)
    local weekEndMs = dateUtils.msOf(weekEnd, 23, 59)

    local todoDone = app.todos:completedCountBetween(weekStartMs, weekEndMs)
    local habitChecks = app.habits:totalChecksBetween(weekStart, weekEnd)

    local focusSeconds = app.focusRepo:totalSeconds(weekStartMs, weekEndMs)
    local focusCount = app.focusRepo:countBetween(weekStartMs, weekEndMs)
    local milestoneDone = app.goals:milestoneCountBetween(weekStartMs, weekEndMs)

    local unfinished = app.todos:pendingCount()

    local lines = {
      string.format("· 完成 %d 项任务", todoDone),
      string.format("· 打卡 %d 次习惯", habitChecks),
      string.format("· 专注 %s，共 %d 次", dateUtils.durationLabel(focusSeconds), focusCount),
      string.format("· 达成 %d 个里程碑", milestoneDone),
      string.format("· 还有 %d 项任务待完成", unfinished),
    }

    local children = {
      ui.row({
        ui.text("本周回顾", { textSize = "16sp", textStyle = "bold",
          layout_width = "0dp", layout_weight = 1, layout_height = "wrap" }),
        ui.caption(dateUtils.formatShortCN(weekStart) .. " – " .. dateUtils.formatShortCN(weekEnd)),
      }),
    }
    for _, line in ipairs(lines) do
      children[#children + 1] = ui.text(line, {
        textSize = "14sp",
        textColor = theme.ATTR.onSurfaceVariant,
        layout_width = "match",
        layout_height = "wrap",
        layout_marginTop = "6dp",
      })
    end
    return ui.card(children)
  end

  refresh = function()
    if not page.alive then return end
    ui.fill(views.content, {
      ui.text("统计", { textSize = "22sp", textStyle = "bold", layout_width = "match",
        layout_height = "wrap", layout_marginBottom = 12 }),
      overviewCard(),
      ui.space(12),
      taskTrendCard(),
      ui.space(12),
      focusTrendCard(),
      ui.space(12),
      habitStatsCard(),
      ui.space(12),
      todoStatsCard(),
      ui.space(12),
      weeklyReviewCard(),
    })
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
