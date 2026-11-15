-- 日程页（底部标签 2）：月 / 周 / 日视图 + 当日日程列表
local bindClass = luajava.bindClass
local LinearLayout = bindClass "android.widget.LinearLayout"
local ScrollView = bindClass "androidx.core.widget.NestedScrollView"
local MaterialButton = bindClass "com.google.android.material.button.MaterialButton"

local ui = require "components.ui"
local theme = require "config.theme"
local dateUtils = require "utils.date_utils"
local eventBus = require "core.event_bus"
local Editor = require "modules.schedules.editor"

local M = {}

M.title = "日程"

function M.create(ctx)
  local app = ctx.app
  local page = { alive = true }
  local today = dateUtils.today()
  local state = {
    view = app.settings:get("default_calendar_view", "month"),
    selected = today,
    anchor = today,
  }
  if state.view ~= "month" and state.view ~= "week" and state.view ~= "day" then
    state.view = "month"
  end

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
      ui.text("日程", {
        textSize = "22sp", textStyle = "bold",
        layout_width = "0dp", layout_weight = 1, layout_height = "wrap",
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
    },
    {
      LinearLayout,
      id = "periodNav",
      orientation = "horizontal",
      layout_width = "match",
      layout_height = "wrap",
      paddingStart = "8dp",
      paddingEnd = "12dp",
      paddingTop = "8dp",
      gravity = "center_vertical",
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

  local function openEvent(occurrence)
    local options = { "查看/编辑", "删除" }
    if occurrence.is_recurring then
      options = { "编辑整个系列", "仅修改这一次", "删除" }
    end
    ui.choose(occurrence.title, options, function(index)
      local row = app.schedules:get(occurrence.id)
      if not row then return end
      if index == 1 then
        Editor.open(ctx, row, function() refresh() end)
      elseif index == 2 and occurrence.is_recurring then
        Editor.open(ctx, row, function() refresh() end, { row = row, date = occurrence.occurrence_date })
      else
        Editor.confirmDelete(ctx, occurrence, function() refresh() end)
      end
    end)
  end

  local function eventRow(item)
    local startLabel = item.is_all_day == 1 and "全天" or dateUtils.formatTime(item.start_time)
    local subtitle = {}
    if item.end_time and item.end_time > item.start_time and item.is_all_day ~= 1 then
      subtitle[#subtitle + 1] = dateUtils.timeRange(item.start_time, item.end_time)
    end
    if item.is_recurring then subtitle[#subtitle + 1] = item.recurrence_label end
    if item.description and item.description ~= "" then
      subtitle[#subtitle + 1] = item.description
    end
    local colorHex = item.color or theme.colors().primary
    local row = ui.listItem({
      icon = "clock",
      iconColor = type(colorHex) == "string" and require("utils.color_utils").parse(colorHex) or nil,
      title = item.title,
      subtitle = table.concat(subtitle, " · "),
      trailing = startLabel,
      onClick = function() openEvent(item) end,
    })
    row.onLongClick = function()
      Editor.confirmDelete(ctx, item, function() refresh() end)
      return true
    end
    return row
  end

  local function renderMonth()
    local year, month = dateUtils.parts(state.anchor)
    local grid = dateUtils.monthGrid(year, month, app.settings:weekStart())
    local counts = app.schedules:dayCountMap(
      string.format("%04d-%02d-01", year, month), dateUtils.endOfMonth(state.anchor))

    local header = ui.row({}, { layout_marginTop = 4 })
    for index = 1, 7 do
      local weekday = ((app.settings:weekStart() - 1 + index - 1) % 7) + 1
      header[#header + 1] = ui.text(dateUtils.WEEK_CN[weekday], {
        textSize = "12sp",
        textColor = theme.ATTR.onSurfaceVariant,
        layout_width = "0dp",
        layout_weight = 1,
        gravity = "center",
        layout_height = "wrap",
      })
    end

    local colors = theme.colors()
    local cells = { header }
    for _, week in ipairs(grid) do
      local row = ui.row({}, { layout_marginTop = 4 })
      for _, cell in ipairs(week) do
        local isSelected = cell.date == state.selected
        local isToday = cell.date == today
        local background, textColor
        if isSelected then
          background, textColor = colors.primary, colors.onPrimary
        elseif isToday then
          background, textColor = colors.primaryContainer, colors.onPrimaryContainer
        elseif cell.inMonth then
          background, textColor = colors.surfaceContainerLow, colors.onSurface
        else
          background, textColor = colors.surface, colors.outlineVariant
        end
        local label = tostring(cell.day)
        if (counts[cell.date] or 0) > 0 and not isSelected then
          label = label .. "\n•"
        end
        row[#row + 1] = ui.dayCell({
          text = label,
          textColor = textColor,
          background = background,
          weight = 1,
          height = 44,
          onClick = function()
            state.selected = cell.date
            refresh()
          end,
        })
      end
      cells[#cells + 1] = row
    end
    return cells
  end

  local function renderWeek()
    local dates = dateUtils.weekDates(state.anchor, app.settings:weekStart())
    local counts = app.schedules:dayCountMap(dates[1], dates[7])
    local colors = theme.colors()
    local row = ui.row({}, { layout_marginTop = 8 })
    for _, date in ipairs(dates) do
      local isSelected = date == state.selected
      local isToday = date == today
      local _, _, day = dateUtils.parts(date)
      local background, textColor
      if isSelected then
        background, textColor = colors.primary, colors.onPrimary
      elseif isToday then
        background, textColor = colors.primaryContainer, colors.onPrimaryContainer
      else
        background, textColor = colors.surfaceContainerHigh, colors.onSurface
      end

      local cell = ui.dayCell({
        text = dateUtils.WEEK_CN[dateUtils.weekday(date)] .. "\n" .. day,
        textSize = "11sp",
        textColor = textColor,
        background = background,
        width = "match",
        height = 56,
        radius = 12,
        onClick = function()
          state.selected = date
          refresh()
        end,
      })

      local column = {
        LinearLayout,
        orientation = "vertical",
        layout_width = "0dp",
        layout_weight = 1,
        layout_height = "wrap",
        layout_marginStart = "3dp",
        layout_marginEnd = "3dp",
        gravity = "center_horizontal",
        cell,
        ui.caption((counts[date] or 0) > 0 and (counts[date] .. " 项") or " ", {
          layout_width = "match",
          gravity = "center",
          layout_marginTop = 2,
        }),
      }
      row[#row + 1] = column
    end
    return { row }
  end

  local function renderEventList(dateStr)
    local items = app.schedules:occurrencesOn(dateStr)
    local children = {}
    if #items == 0 then
      children[#children + 1] = ui.empty("calendar", dateUtils.relativeDay(dateStr) .. "没有日程",
        "点击右上角 + 添加一条安排", "新建日程", function()
          Editor.open(ctx, nil, function() refresh() end)
        end)
      return children
    end
    local rows = {}
    for _, item in ipairs(items) do rows[#rows + 1] = eventRow(item) end
    children[#children + 1] = ui.card(rows, { marginTop = 8, padding = 4 })
    return children
  end

  function refresh()
    if not page.alive then return end

    ui.fill(views.modes, {
      (state.view == "month" and ui.button or ui.outlinedButton)("月", function()
        state.view = "month"
        refresh()
      end, { weight = 1, marginEnd = 6 }),
      (state.view == "week" and ui.button or ui.outlinedButton)("周", function()
        state.view = "week"
        refresh()
      end, { weight = 1, marginEnd = 6 }),
      (state.view == "day" and ui.button or ui.outlinedButton)("日", function()
        state.view = "day"
        refresh()
      end, { weight = 1 }),
    })

    local titleText, stepPrev, stepNext
    if state.view == "month" then
      local year, month = dateUtils.parts(state.anchor)
      titleText = dateUtils.monthLabel(year, month)
      stepPrev = function() state.anchor = dateUtils.addMonths(state.anchor, -1) refresh() end
      stepNext = function() state.anchor = dateUtils.addMonths(state.anchor, 1) refresh() end
    elseif state.view == "week" then
      local dates = dateUtils.weekDates(state.anchor, app.settings:weekStart())
      titleText = dateUtils.formatShortCN(dates[1]) .. " – " .. dateUtils.formatShortCN(dates[7])
      stepPrev = function() state.anchor = dateUtils.addDays(state.anchor, -7) refresh() end
      stepNext = function() state.anchor = dateUtils.addDays(state.anchor, 7) refresh() end
    else
      titleText = dateUtils.formatDateCN(state.anchor)
      stepPrev = function() state.anchor = dateUtils.addDays(state.anchor, -1) ; state.selected = state.anchor ; refresh() end
      stepNext = function() state.anchor = dateUtils.addDays(state.anchor, 1) ; state.selected = state.anchor ; refresh() end
    end

    ui.fill(views.periodNav, {
      ui.iconButton("chevron_left", stepPrev),
      ui.text(titleText, {
        textSize = "15sp",
        textStyle = "bold",
        layout_width = "0dp",
        layout_weight = 1,
        gravity = "center",
        layout_height = "wrap",
      }),
      ui.iconButton("chevron_right", stepNext),
      ui.textButton("今天", function()
        state.anchor = today
        state.selected = today
        refresh()
      end),
    })

    local children = {}
    if state.view == "month" then
      for _, node in ipairs(renderMonth()) do children[#children + 1] = node end
      children[#children + 1] = ui.divider()
    elseif state.view == "week" then
      for _, node in ipairs(renderWeek()) do children[#children + 1] = node end
      children[#children + 1] = ui.divider()
    end

    children[#children + 1] = ui.sectionHeader(dateUtils.formatDateCN(state.selected))
    for _, node in ipairs(renderEventList(state.selected)) do children[#children + 1] = node end

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
