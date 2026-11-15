-- 专注页（子页面）：番茄钟，状态持久化，切后台/进程重建后按时间差恢复
local bindClass = luajava.bindClass
local LinearLayout = bindClass "android.widget.LinearLayout"
local ScrollView = bindClass "androidx.core.widget.NestedScrollView"
local MaterialTextView = bindClass "com.google.android.material.textview.MaterialTextView"

local ui = require "components.ui"
local charts = require "components.charts"
local theme = require "config.theme"
local dateUtils = require "utils.date_utils"
local eventBus = require "core.event_bus"

-- 注意：全局 timer(fn, ms, interval) 是本文件的定时器工厂，
-- 因此专注计时器变量命名为 focusTimer，避免遮蔽全局函数。
local startTicker = timer

local M = {}

M.title = "专注"

function M.create(ctx)
  local app = ctx.app
  local focusTimer = app.focusTimer
  local page = { alive = true }
  local state = {
    todoId = tonumber(focusTimer.state.todo_id) or 0,
    ticker = nil,
    lastRemaining = -1,
    lastPhase = nil,
  }
  local ringState = { percent = 0 }
  local refresh, pickTodo, confirmStop, connectTicker, stopTicker

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
        ui.text("专注", {
          textSize = "20sp", textStyle = "bold",
          layout_width = "0dp", layout_weight = 1, layout_height = "wrap",
          layout_marginStart = "4dp",
        }),
        ui.iconButton("settings", function()
          ui.choose("默认专注时长", { "15 分钟", "25 分钟", "45 分钟", "50 分钟" }, function(index)
            local presets = { 15, 25, 45, 50 }
            app.settings:set("focus_minutes", presets[index])
            app:changed(eventBus.EVENTS.SETTINGS_CHANGED)
            refresh()
          end)
        end),
      },
    },
    {
      ScrollView,
      layout_width = "match",
      layout_height = "0dp",
      layout_weight = 1,
      clipToPadding = false,
      {
        LinearLayout,
        orientation = "vertical",
        layout_width = "match",
        layout_height = "wrap",
        paddingStart = "16dp",
        paddingEnd = "16dp",
        paddingBottom = "32dp",
        {
          LinearLayout,
          id = "ringBox",
          orientation = "vertical",
          layout_width = "match",
          layout_height = "wrap",
          gravity = "center_horizontal",
          layout_marginTop = "16dp",
        },
        {
          MaterialTextView,
          id = "clock",
          text = "25:00",
          textSize = "32sp",
          textStyle = "bold",
          textColor = theme.ATTR.onSurface,
          layout_width = "match",
          layout_height = "wrap",
          gravity = "center",
          layout_marginTop = "12dp",
        },
        {
          MaterialTextView,
          id = "phaseLabel",
          text = "准备开始",
          textSize = "14sp",
          textColor = theme.ATTR.onSurfaceVariant,
          layout_width = "match",
          layout_height = "wrap",
          gravity = "center",
          layout_marginTop = "4dp",
        },
        {
          LinearLayout,
          id = "controls",
          orientation = "horizontal",
          layout_width = "match",
          layout_height = "wrap",
          gravity = "center_horizontal",
          layout_marginTop = "20dp",
        },
        {
          LinearLayout,
          id = "details",
          orientation = "vertical",
          layout_width = "match",
          layout_height = "wrap",
        },
      },
    },
  }, views)

  local ringView = charts.ring(0, { size = 200, state = ringState })
  views.ringBox.addView(ringView)

  local function updateClock()
    local remaining = focusTimer:remainingSeconds()
    if focusTimer.state.phase == "idle" then
      remaining = app.settings:focusMinutes() * 60
    end
    views.clock.setText(dateUtils.clockLabel(remaining))
    views.phaseLabel.setText(focusTimer:phaseLabel())

    local planned = focusTimer.state.duration_seconds
    if not planned or planned <= 0 then
      planned = (focusTimer.state.phase == "short" and app.settings:shortBreakMinutes()
        or focusTimer.state.phase == "long" and app.settings:longBreakMinutes()
        or app.settings:focusMinutes()) * 60
    end
    local percent = 0
    if focusTimer.state.phase ~= "idle" and planned > 0 then
      percent = math.max(0, math.min(100, (planned - remaining) / planned * 100))
    end
    ringState.percent = percent
    pcall(function() ringView.invalidate() end)
  end

  local function renderControls()
    local phase = focusTimer.state.phase
    local children = {}
    if phase == "idle" then
      children[#children + 1] = ui.button("开始专注", function()
        focusTimer:start("focus", state.todoId)
        connectTicker()
        refresh()
      end, { icon = "play" })
    elseif phase == "paused" then
      children[#children + 1] = ui.button("继续", function()
        focusTimer:resume()
        connectTicker()
        refresh()
      end, { icon = "play" })
      children[#children + 1] = ui.outlinedButton("结束", function()
        confirmStop()
      end, { marginStart = 8 })
    else
      children[#children + 1] = ui.button("暂停", function()
        focusTimer:pause()
        stopTicker()
        refresh()
      end, { icon = "pause" })
      children[#children + 1] = ui.outlinedButton("结束", function()
        confirmStop()
      end, { marginStart = 8 })
    end
    ui.fill(views.controls, children)
  end

  local function renderDetails()
    local children = {}

    local linkedTitle = "未关联任务"
    if state.todoId and state.todoId > 0 then
      local todo = app.todos:get(state.todoId)
      if todo then linkedTitle = todo.title else state.todoId = 0 end
    end
    children[#children + 1] = ui.card({
      ui.listItem({
        icon = "list",
        title = "关联任务",
        subtitle = linkedTitle,
        trailingIcon = "chevron_right",
        onClick = function() pickTodo() end,
      }),
    }, { marginTop = 20, padding = 0 })

    local todayStart = dateUtils.msOf(dateUtils.today(), 0, 0)
    local todayEnd = dateUtils.msOf(dateUtils.today(), 23, 59)
    local todaySeconds = app.focusRepo:totalSeconds(todayStart, todayEnd)
    local todayCount = app.focusRepo:countBetween(todayStart, todayEnd)
    children[#children + 1] = ui.card({
      ui.row({
        ui.metric("今日专注", dateUtils.durationLabel(todaySeconds)),
        ui.metric("完成次数", tostring(todayCount)),
        ui.metric("总轮数", tostring(focusTimer.state.completed_rounds or 0)),
      }),
    }, { marginTop = 12 })

    local recent = app.focusRepo:recent(5)
    if #recent > 0 then
      local rows = {}
      for _, item in ipairs(recent) do
        rows[#rows + 1] = ui.listItem({
          icon = "timer",
          title = dateUtils.durationLabel(item.duration_seconds or 0),
          subtitle = dateUtils.formatDateTime(item.start_time)
            .. (item.todo_title and (" · " .. item.todo_title) or ""),
          trailing = item.completed == 1 and "完成" or "中断",
        })
      end
      children[#children + 1] = ui.card(rows, { marginTop = 12, padding = 4 })
    end

    children[#children + 1] = ui.caption(
      "计时基于开始时刻与时长计算，切到后台或页面重建后会按真实时间恢复。", {
        layout_width = "match",
        layout_height = "wrap",
        layout_marginTop = 16,
      })

    ui.fill(views.details, children)
  end

  connectTicker = function()
    if state.ticker then return end
    state.ticker = startTicker(function()
      if not page.alive then return end
      local finished = focusTimer:catchUp()
      if finished then
        stopTicker()
        ui.snackbar(root, finished.phase == "focus" and "专注完成" or "休息结束")
        app:changed(eventBus.EVENTS.FOCUS_CHANGED)
        refresh()
        return
      end
      local remaining = focusTimer:remainingSeconds()
      if remaining ~= state.lastRemaining or focusTimer.state.phase ~= state.lastPhase then
        state.lastRemaining = remaining
        state.lastPhase = focusTimer.state.phase
        updateClock()
      end
    end, 0, 1000)
  end

  stopTicker = function()
    if state.ticker then
      pcall(function() state.ticker.stop() end)
      state.ticker = nil
    end
  end

  refresh = function()
    if not page.alive then return end
    state.lastPhase = focusTimer.state.phase
    state.lastRemaining = focusTimer:remainingSeconds()
    updateClock()
    renderControls()
    renderDetails()
  end

  pickTodo = function()
    local list = { "不关联任务" }
    local ids = { 0 }
    for _, todo in ipairs(app.todos:list({ status = "active" })) do
      list[#list + 1] = todo.title
      ids[#ids + 1] = todo.id
      if #list > 20 then break end
    end
    ui.choose("选择任务", list, function(index)
      state.todoId = ids[index] or 0
      focusTimer.state.todo_id = state.todoId
      focusTimer:save()
      refresh()
    end)
  end

  confirmStop = function()
    ui.confirm({
      title = "结束本次专注",
      message = "会保存已专注的时长，未完成部分不计入。",
      confirmText = "结束",
    }, function()
      local finished = focusTimer:finish(false)
      stopTicker()
      if finished and finished.elapsed >= 60 then
        ui.snackbar(root, "已保存 " .. dateUtils.durationLabel(finished.elapsed))
      end
      app:changed(eventBus.EVENTS.FOCUS_CHANGED)
      refresh()
    end)
  end

  page.view = root
  page.refresh = refresh
  page.onShow = function()
    focusTimer:catchUp()
    connectTicker()
    refresh()
  end
  local unsubscribe = eventBus.on(eventBus.EVENTS.DATA_CHANGED, function()
    if page.alive then refresh() end
  end)
  page.destroy = function()
    page.alive = false
    stopTicker()
    if unsubscribe then unsubscribe() end
  end

  connectTicker()
  refresh()
  return page
end

return M
