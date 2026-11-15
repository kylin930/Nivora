-- 习惯页（底部标签 3）：今日打卡 + 全部习惯管理
-- 统计规则来自 habits_repo：连续天数按排期日计算，暂停习惯不计入。
local bindClass = luajava.bindClass
local LinearLayout = bindClass "android.widget.LinearLayout"
local ScrollView = bindClass "androidx.core.widget.NestedScrollView"
local BottomSheetDialog = bindClass "com.google.android.material.bottomsheet.BottomSheetDialog"
local MaterialButton = bindClass "com.google.android.material.button.MaterialButton"

local ui = require "components.ui"
local theme = require "config.theme"
local constants = require "config.constants"
local dateUtils = require "utils.date_utils"
local eventBus = require "core.event_bus"
local Editor = require "modules.habits.editor"

local M = {}

M.title = "习惯"

function M.create(ctx)
  local app = ctx.app
  local page = { alive = true }
  local refresh
  local state = { mode = "today" }

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
      paddingStart = "16dp",
      paddingEnd = "12dp",
      paddingTop = "12dp",
      gravity = "center_vertical",
      ui.text("习惯", {
        textSize = "22sp",
        textStyle = "bold",
        layout_width = "0dp",
        layout_weight = 1,
        layout_height = "wrap",
      }),
      ui.iconButton("plus", function()
        Editor.open(ctx, nil, function() refresh() end)
      end),
    },
    {
      LinearLayout,
      id = "modes",
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
        paddingBottom = "96dp",
      },
    },
  }, views)

  -- 打卡历史与统计详情
  local function openDetail(habitId)
    local habit = app.habits:get(habitId)
    if not habit then return end
    local sheet = BottomSheetDialog(activity)
    local today = dateUtils.today()
    local year, month = dateUtils.parts(today)
    local streak, unit = app.habits:currentStreak(habit, today)
    local longest = app.habits:longestStreak(habit)
    local weekCount = app.habits:weekCount(habit, today)
    local monthCount = app.habits:monthCount(habit, today)
    local monthStart = dateUtils.startOfMonth(today)
    local rate = app.habits:completionRate(habit, monthStart, today)
    local calendar = app.habits:monthCalendar(habit, year, month)
    local monthGrid = dateUtils.monthGrid(year, month, app.settings:weekStart())

    local body = {
      LinearLayout,
      orientation = "vertical",
      layout_width = "match",
      layout_height = "wrap",
      padding = "20dp",
      BackgroundColor = theme.ATTR.surface,
      ui.text(habit.name, { textSize = "18sp", textStyle = "bold", layout_width = "match" }),
      ui.caption(app.habits:frequencyLabel(habit), {
        layout_width = "match", layout_marginTop = "4dp",
      }),
      ui.row({
        ui.metric("连续" .. unit, tostring(streak)),
        ui.metric("最长" .. unit, tostring(longest)),
        ui.metric("本周", tostring(weekCount)),
      }, { layout_marginTop = 12 }),
      ui.row({
        ui.metric("本月打卡", tostring(monthCount)),
        ui.metric("本月完成率", rate .. "%"),
        ui.metric("状态", habit.is_active == 1 and "进行中" or "已暂停"),
      }, { layout_marginTop = 8 }),
      ui.divider(),
      ui.caption(dateUtils.monthLabel(year, month) .. " 打卡分布", { layout_marginBottom = 4 }),
    }

    -- 月历：每天一个圆点
    local weekHeader = ui.row({}, { layout_marginTop = 4 })
    for day = 1, 7 do
      local weekday = ((app.settings:weekStart() - 1 + day - 1) % 7) + 1
      weekHeader[#weekHeader + 1] = ui.text(dateUtils.WEEK_CN[weekday], {
        textSize = "11sp",
        textColor = theme.ATTR.onSurfaceVariant,
        layout_width = "0dp",
        layout_weight = 1,
        gravity = "center",
      })
    end
    body[#body + 1] = weekHeader

    local colors = theme.colors()
    for _, week in ipairs(monthGrid) do
      local row = ui.row({}, { layout_marginTop = 2 })
      for _, cell in ipairs(week) do
        local entry = calendar[cell.date]
        local background, textColor
        if not cell.inMonth then
          background, textColor = colors.surface, colors.outlineVariant
        elseif entry and entry.done then
          background, textColor = colors.primary, colors.onPrimary
        elseif entry and entry.scheduled then
          background, textColor = colors.surfaceVariant, colors.onSurfaceVariant
        else
          background, textColor = colors.surfaceContainerLow, colors.onSurfaceVariant
        end
        row[#row + 1] = ui.dayCell({
          text = tostring(cell.day),
          textColor = textColor,
          background = background,
          weight = 1,
          height = 32,
          radius = 8,
        })
      end
      body[#body + 1] = row
    end

    body[#body + 1] = ui.divider()
    body[#body + 1] = ui.row({
      ui.textButton(habit.is_active == 1 and "暂停习惯" or "恢复习惯", function()
        app.habits:setActive(habit.id, habit.is_active ~= 1)
        app:changed(eventBus.EVENTS.HABITS_CHANGED)
        sheet.dismiss()
        refresh()
      end, { weight = 1 }),
      ui.textButton("编辑", function()
        sheet.dismiss()
        Editor.open(ctx, habit, function() refresh() end)
      end, { weight = 1 }),
    })
    body[#body + 1] = ui.row({
      ui.textButton("删除", function()
        sheet.dismiss()
        ui.confirm({
          title = "删除习惯",
          message = "删除「" .. habit.name .. "」会同时删除它的全部打卡记录，且无法恢复。",
          confirmText = "删除",
        }, function()
          local ok, err = app.habits:remove(habit.id)
          if not ok then
            ui.alert("删除失败", tostring(err))
            return
          end
          app:changed(eventBus.EVENTS.HABITS_CHANGED)
          refresh()
        end)
      end, { weight = 1 }),
    })

    sheet.setContentView(loadlayout({
      ScrollView,
      layout_width = "match",
      layout_height = "wrap",
      body,
    }))
    sheet.show()
  end

  local function habitRow(habit)
    local isActive = habit.is_active == 1
    local subtitle = app.habits:frequencyLabel(habit)
    if habit.frequency_type == "weekly_count" then
      subtitle = subtitle .. "（本周 " .. habit.weekCount .. "/" .. habit.target .. "）"
    end
    local streak, unit = app.habits:currentStreak(habit, dateUtils.today())
    if isActive and streak > 0 then
      subtitle = subtitle .. " · 连续 " .. streak .. " " .. unit
    end
    if not isActive then subtitle = "已暂停 · " .. subtitle end

    local row, check, textStack = ui.checkRow({
      title = habit.name,
      subtitle = subtitle,
      checked = habit.doneToday == true,
    })

    check.clickable = true
    check.onClick = function()
      local ok, err = app.habits:toggle(habit.id, dateUtils.today())
      if not ok and err then
        ui.snackbar(root, tostring(err))
      end
      app:changed(eventBus.EVENTS.HABITS_CHANGED)
      refresh()
    end
    textStack.clickable = true
    textStack.onClick = function() openDetail(habit.id) end
    row.onLongClick = function()
      openDetail(habit.id)
      return true
    end
    return row
  end

  refresh = function()
    if not page.alive then return end

    ui.fill(views.modes, {
      (state.mode == "today" and ui.button or ui.outlinedButton)("今日", function()
        state.mode = "today"
        refresh()
      end, { marginEnd = 8 }),
      (state.mode == "all" and ui.button or ui.outlinedButton)("全部", function()
        state.mode = "all"
        refresh()
      end, { marginEnd = 8 }),
    })

    local children = {}
    local today = dateUtils.today()

    if state.mode == "today" then
      local completed, scheduled = app.habits:todaySummary(today)
      children[#children + 1] = ui.card({
        ui.row({
          ui.text("今天", { textSize = "16sp", textStyle = "bold", layout_width = "0dp",
            layout_weight = 1, layout_height = "wrap" }),
          ui.caption(string.format("%d/%d 已完成", completed, scheduled)),
        }),
        ui.progress(scheduled > 0 and (completed / scheduled * 100) or 0, { marginTop = 12 }),
      }, { marginTop = 8 })

      local list = app.habits:todayList(today)
      if #list == 0 then
        children[#children + 1] = ui.empty("check", "今天没有要打卡的习惯",
          "新建习惯，或调整已有习惯的周期", "新建习惯", function()
            Editor.open(ctx, nil, function() refresh() end)
          end)
      else
        local rows = {}
        for _, habit in ipairs(list) do rows[#rows + 1] = habitRow(habit) end
        children[#children + 1] = ui.card(rows, { marginTop = 12, padding = 8 })
      end
    else
      local list = app.habits:list(false)
      if #list == 0 then
        children[#children + 1] = ui.empty("check", "还没有习惯", "从一个小习惯开始",
          "新建习惯", function()
            Editor.open(ctx, nil, function() refresh() end)
          end)
      else
        for _, habit in ipairs(list) do
          local doneToday = app.habits:countOn(habit.id, today) > 0
          habit.doneToday = doneToday
          habit.weekCount = app.habits:weekCount(habit, today)
          habit.target = app.habits:targetCount(habit)
          children[#children + 1] = ui.card({ habitRow(habit) }, { marginTop = 8, padding = 4 })
        end
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
