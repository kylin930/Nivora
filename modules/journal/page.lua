-- 每日记录页（子页面）：按日期写一条记录，支持心情与标签
local bindClass = luajava.bindClass
local LinearLayout = bindClass "android.widget.LinearLayout"
local ScrollView = bindClass "androidx.core.widget.NestedScrollView"
local BottomSheetDialog = bindClass "com.google.android.material.bottomsheet.BottomSheetDialog"
local Chip = bindClass "com.google.android.material.chip.Chip"
local ChipGroup = bindClass "com.google.android.material.chip.ChipGroup"

local ui = require "components.ui"
local theme = require "config.theme"
local constants = require "config.constants"
local dateUtils = require "utils.date_utils"
local eventBus = require "core.event_bus"
local Form = require "components.form_dialog"

local M = {}

M.title = "每日记录"

-- 编辑面板：正文 + 心情 + 标签。
-- 独立成模块级函数，既方便页面复用，也便于自动化验证输入与提交。
-- 注意：布局表里的节点是声明而不是 View，读取内容必须按 id 取真实控件。
function M.openEditor(ctx, dateStr, onSaved)
  local app = ctx.app
  local existing = app.journals:getByDate(dateStr)
  local sheet = BottomSheetDialog(activity)
  local sheetViews = {}

  local sheetBody = {
    LinearLayout,
    orientation = "vertical",
    layout_width = "match",
    layout_height = "wrap",
    padding = "20dp",
    BackgroundColor = theme.ATTR.surface,
    ui.text(dateUtils.formatDateCN(dateStr), {
      textSize = "18sp", textStyle = "bold", layout_width = "match",
    }),
    ui.textField("journalEditor", "今天发生了什么", {
      multiline = true,
      minLines = 6,
      value = existing and (existing.content or "") or "",
      marginTop = 12,
    }),
    ui.caption("心情", { layout_marginTop = 12 }),
  }

  local moodGroup = {
    ChipGroup,
    id = "journalMood",
    layout_width = "match",
    layout_height = "wrap",
    layout_marginTop = "8dp",
    singleSelection = true,
  }
  for _, mood in ipairs(constants.MOODS) do
    moodGroup[#moodGroup + 1] = {
      Chip,
      text = mood.label,
      checkable = true,
      checked = existing and existing.mood == mood.value or false,
      layout_width = "wrap",
      layout_height = "wrap",
      layout_marginEnd = "6dp",
    }
  end
  sheetBody[#sheetBody + 1] = moodGroup

  sheetBody[#sheetBody + 1] = ui.textField("journalTags", "标签（用逗号分隔）", {
    textSize = 14,
    value = existing and (existing.tags or "") or "",
    marginTop = 12,
  })

  sheetBody[#sheetBody + 1] = ui.row({
    ui.textButton("取消", function() sheet.dismiss() end, { weight = 1 }),
    ui.button("保存", nil, { weight = 1, id = "journalSave" }),
  }, { layout_marginTop = 12 })

  sheet.setContentView(loadlayout({
    ScrollView,
    layout_width = "match",
    layout_height = "wrap",
    sheetBody,
  }, sheetViews))
  sheet.show()

  local editorView = sheetViews.journalEditor
  local moodView = sheetViews.journalMood
  local tagsView = sheetViews.journalTags
  local saveView = sheetViews.journalSave
  if not (editorView and saveView) then
    print("[journal] 编辑面板控件未绑定")
    return sheet
  end

  saveView.setOnClickListener(function()
    local text = Form.trim(tostring(editorView.getText()))
    if text == "" then
      ui.alert("内容为空", "写点什么再保存吧")
      return
    end

    -- 心情：按 MOODS 顺序读取 ChipGroup 的真实子视图
    local mood = 0
    if moodView then
      for index, item in ipairs(constants.MOODS) do
        local chip = moodView.getChildAt(index - 1)
        if chip and chip.isChecked() then mood = item.value end
      end
    end

    local tags = tagsView and Form.trim(tostring(tagsView.getText())) or ""
    local id, err = app.journals:save(dateStr, text, mood, tags)
    if not id then
      ui.alert("保存失败", tostring(err))
      return
    end
    sheet.dismiss()
    app:changed(eventBus.EVENTS.JOURNALS_CHANGED)
    if onSaved then onSaved(id) end
  end)

  return sheet
end

function M.create(ctx)
  local app = ctx.app
  local page = { alive = true }
  local state = { date = dateUtils.today() }
  local refresh
  local openEditor

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
        ui.text("每日记录", {
          textSize = "20sp", textStyle = "bold",
          layout_width = "0dp", layout_weight = 1, layout_height = "wrap",
          layout_marginStart = "4dp",
        }),
        ui.iconButton("edit", function() openEditor(state.date) end),
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

  openEditor = function(dateStr)
    return M.openEditor(ctx, dateStr, function() refresh() end)
  end

  refresh = function()
    if not page.alive then return end
    local dateStr = state.date
    local entry = app.journals:getByDate(dateStr)
    local content = {}

    content[#content + 1] = ui.row({
      ui.iconButton("chevron_left", function()
        state.date = dateUtils.addDays(state.date, -1)
        refresh()
      end),
      ui.text(dateUtils.formatDateCN(dateStr), {
        textSize = "16sp", textStyle = "bold",
        layout_width = "0dp", layout_weight = 1, gravity = "center", layout_height = "wrap",
      }),
      ui.iconButton("chevron_right", function()
        state.date = dateUtils.addDays(state.date, 1)
        refresh()
      end),
    })

    if not entry then
      content[#content + 1] = ui.empty("pen", "这一天还没有记录", "写下一点什么吧",
        "开始记录", function() openEditor(dateStr) end)
    else
      content[#content + 1] = ui.card({
        ui.row({
          ui.caption(constants.moodLabel(entry.mood or 0)),
          ui.text("", { layout_width = "0dp", layout_weight = 1 }),
          ui.caption(dateUtils.formatTime(entry.updated_at or entry.created_at or 0)),
        }),
        ui.text(entry.content or "", {
          textSize = "15sp",
          layout_width = "match",
          layout_height = "wrap",
          layout_marginTop = "8dp",
        }),
      }, { marginTop = 8 })

      if entry.tags and entry.tags ~= "" then
        local chips = {}
        for tag in tostring(entry.tags):gmatch("[^,，%s]+") do
          chips[#chips + 1] = ui.caption("#" .. tag, { layout_marginEnd = 8, marginTop = 6 })
        end
        if #chips > 0 then
          content[#content + 1] = ui.row(chips, { layout_marginTop = 8 })
        end
      end

      content[#content + 1] = ui.row({
        ui.textButton("编辑", function() openEditor(dateStr) end),
        ui.textButton("删除", function()
          ui.confirm({
            title = "删除记录",
            message = "删除 " .. dateUtils.formatDateCN(dateStr) .. " 的记录？",
            confirmText = "删除",
          }, function()
            app.journals:remove(entry.id)
            app:changed(eventBus.EVENTS.JOURNALS_CHANGED)
            refresh()
          end)
        end),
      }, { layout_marginTop = 8 })
    end

    content[#content + 1] = ui.divider()
    content[#content + 1] = ui.caption("最近记录")

    local recent = app.journals:list(8)
    local rows = {}
    for _, item in ipairs(recent) do
      rows[#rows + 1] = ui.listItem({
        title = dateUtils.formatDateCN(item.record_date),
        subtitle = item.content and (tostring(item.content):sub(1, 40)) or "",
        onClick = function()
          state.date = item.record_date
          refresh()
        end,
      })
    end
    if #rows == 0 then
      content[#content + 1] = ui.caption("还没有历史记录", { layout_marginTop = 6 })
    else
      content[#content + 1] = ui.card(rows, { padding = 4, marginTop = 8 })
    end

    ui.fill(views.content, content)
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
