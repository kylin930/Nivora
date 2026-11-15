-- 我的页（底部标签 5）：功能入口汇总 + 数据概览
local bindClass = luajava.bindClass
local LinearLayout = bindClass "android.widget.LinearLayout"
local ScrollView = bindClass "androidx.core.widget.NestedScrollView"

local ui = require "components.ui"
local theme = require "config.theme"
local constants = require "config.constants"
local dateUtils = require "utils.date_utils"
local eventBus = require "core.event_bus"

local M = {}

M.title = "我的"

function M.create(ctx)
  local app = ctx.app
  local page = { alive = true }

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

  local function entryRow(icon, title, subtitle, onClick)
    return ui.listItem({
      icon = icon,
      title = title,
      subtitle = subtitle,
      trailingIcon = "chevron_right",
      onClick = onClick,
    })
  end

  local function summaryCard()
    local today = dateUtils.today()
    local habitCount = app.habits:allActiveCount()
    local done, pending = app.todos:countByStatus()
    local journalCount = app.journals:count()
    local goalActive = app.goals:activeCount()
    local focusSeconds = app.focusRepo:totalSeconds(nil, nil)

    return ui.card({
      ui.row({
        ui.metric("在用习惯", tostring(habitCount)),
        ui.metric("进行任务", tostring(pending)),
        ui.metric("完成目标", tostring(goalActive)),
      }),
      ui.row({
        ui.metric("已完成任务", tostring(done)),
        ui.metric("记录天数", tostring(journalCount)),
        ui.metric("累计专注", dateUtils.durationLabel(focusSeconds)),
      }, { layout_marginTop = 8 }),
    })
  end

  local function refresh()
    if not page.alive then return end
    local children = {
      ui.text("我的", {
        textSize = "22sp", textStyle = "bold",
        layout_width = "match", layout_height = "wrap", layout_marginBottom = 12,
      }),
      summaryCard(),
      ui.space(16),
      ui.card({
        entryRow("target", "目标", "目标、里程碑与关联任务", function()
          ctx.nav:push(require("modules.goals.page"), {})
        end),
        entryRow("pen", "每日记录", "按日期写一点东西", function()
          ctx.nav:push(require("modules.journal.page"), {})
        end),
        entryRow("star", "倒数日", "生日、纪念日与截止日", function()
          ctx.nav:push(require("modules.countdown.page"), {})
        end),
        entryRow("timer", "专注", "番茄钟与专注记录", function()
          ctx.nav:push(require("modules.focus.page"), {})
        end),
        entryRow("list", "待办", "全部任务与子任务", function()
          ctx.nav:push(require("modules.todos.page"), {})
        end),
      }, { padding = 4 }),
      ui.space(12),
      ui.card({
        entryRow("settings", "设置", "外观、提醒、数据与关于", function()
          ctx.nav:push(require("modules.settings.page"), {})
        end),
        entryRow("backup", "备份与恢复", "导出 / 导入 JSON 数据", function()
          ctx.nav:push(require("modules.settings.page"), {})
        end),
      }, { padding = 4 }),
      ui.column({
        ui.caption(constants.APP_NAME .. " " .. constants.VERSION, { layout_marginTop = 20 }),
        ui.caption("习惯、日程、待办、目标、记录与专注都在本地保存", { layout_marginTop = 2 }),
      }, { layout_width = "match", layout_height = "wrap", gravity = "center_horizontal" }),
    }
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
