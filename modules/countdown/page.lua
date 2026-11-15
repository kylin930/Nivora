-- 倒数日页（子页面）：按剩余天数排序展示
local bindClass = luajava.bindClass
local LinearLayout = bindClass "android.widget.LinearLayout"
local ScrollView = bindClass "androidx.core.widget.NestedScrollView"

local ui = require "components.ui"
local theme = require "config.theme"
local dateUtils = require "utils.date_utils"
local eventBus = require "core.event_bus"
local Editor = require "modules.countdown.editor"
local colorUtils = require "utils.color_utils"

local M = {}

M.title = "倒数日"

function M.create(ctx)
  local app = ctx.app
  local page = { alive = true }
  local refresh
  local openCreate

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
        ui.text("倒数日", {
          textSize = "20sp", textStyle = "bold",
          layout_width = "0dp", layout_weight = 1, layout_height = "wrap",
          layout_marginStart = "4dp",
        }),
        ui.iconButton("plus", function() openCreate() end),
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

  openCreate = function()
    Editor.open(ctx, nil, function() refresh() end)
  end

  local function countdownCard(item)
    local color = colorUtils.parse(item.color or "#6750A4")
    local bigText = tostring(math.abs(item.daysLeft))
    local unitText = item.daysLeft >= 0 and "天" or "天前"
    if item.daysLeft == 0 then
      bigText = "今天"
      unitText = ""
    end

    local card = ui.card({
      ui.row({
        ui.icon(item.icon or "star", { size = 20, color = color, marginEnd = 10 }),
        ui.text(item.title, {
          textSize = "15sp",
          textStyle = "bold",
          layout_width = "0dp",
          layout_weight = 1,
          layout_height = "wrap",
        }),
        ui.text(bigText, {
          textSize = "22sp",
          textStyle = "bold",
          textColor = color,
          layout_height = "wrap",
        }),
        ui.caption(unitText, { layout_marginStart = 2 }),
      }),
      ui.caption(
        dateUtils.formatFullCN(item.effective_date)
          .. (item.isYearly and " · 每年重复" or "")
          .. (item.kind and (" · " .. item.kind) or ""), {
          layout_width = "match",
          layout_height = "wrap",
          layout_marginTop = "6dp",
        }),
    }, { marginTop = 10 })
    card.clickable = true
    card.focusable = true
    card.onClick = function()
      ui.choose(item.title, { "编辑", "删除" }, function(index)
        if index == 1 then
          Editor.open(ctx, app.countdowns:get(item.id), function() refresh() end)
        else
          ui.confirm({
            title = "删除倒数日",
            message = "确定删除「" .. item.title .. "」吗？",
            confirmText = "删除",
          }, function()
            local ok, err = app.countdowns:remove(item.id)
            if not ok then ui.alert("删除失败", tostring(err)) return end
            app:changed(eventBus.EVENTS.COUNTDOWNS_CHANGED)
            refresh()
          end)
        end
      end)
    end
    return card
  end

  refresh = function()
    if not page.alive then return end
    local list = app.countdowns:list()
    local children = {}
    if #list == 0 then
      children[#children + 1] = ui.empty("star", "还没有倒数日",
        "生日、纪念日、考试和截止日都可以记在这里", "新建倒数日", function() openCreate() end)
    else
      for _, item in ipairs(list) do
        children[#children + 1] = countdownCard(item)
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
