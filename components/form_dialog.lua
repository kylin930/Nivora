-- 编辑表单：底部弹出，字段由声明式 spec 生成，所有模块共用同一套编辑体验。
-- 字段类型：text / multiline / choice / date / time / toggle / number / priority /
--           weekdays / color / icon
--
-- 关键约定：这里返回的都是**布局声明表**，不是 View。
-- 读取用户输入必须给控件设 id，等 loadlayout 通过绑定表拿到真实 View 后再读，
-- 直接在声明表上调用 getText()/isChecked()/setText() 都是错的（会静默失败）。
local bindClass = luajava.bindClass
local BottomSheetDialog = bindClass "com.google.android.material.bottomsheet.BottomSheetDialog"
local LinearLayout = bindClass "android.widget.LinearLayout"
local MaterialTextView = bindClass "com.google.android.material.textview.MaterialTextView"
local SwitchMaterial = bindClass "com.google.android.material.switchmaterial.SwitchMaterial"
local Chip = bindClass "com.google.android.material.chip.Chip"
local ChipGroup = bindClass "com.google.android.material.chip.ChipGroup"
local MaterialDatePicker = bindClass "com.google.android.material.datepicker.MaterialDatePicker"
local MaterialTimePicker = bindClass "com.google.android.material.timepicker.MaterialTimePicker"
local ScrollView = bindClass "androidx.core.widget.NestedScrollView"
local LinearLayoutParams = bindClass "android.widget.LinearLayout$LayoutParams"

local ui = require "components.ui"
local icons = require "components.icons"
local theme = require "config.theme"
local constants = require "config.constants"
local dateUtils = require "utils.date_utils"
local colorUtils = require "utils.color_utils"

local M = {}

local function trim(text)
  return tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

M.trim = trim

-- 日期选择器：onPick("YYYY-MM-DD")，allowEmpty 时清除按钮回传 ""
function M.pickDate(current, onPick, allowEmpty)
  local builder = MaterialDatePicker.Builder.datePicker()
  builder.setTitleText("选择日期")
  if current and current ~= "" and dateUtils.isValidDate(current) then
    local ms = dateUtils.msOf(current, 12, 0)
    if ms then pcall(function() builder.setSelection(ms) end) end
  end
  local picker = builder.build()
  picker.addOnPositiveButtonClickListener(function(selection)
    local ms = tonumber(tostring(selection))
    if ms then onPick(dateUtils.dateOf(ms)) end
  end)
  if allowEmpty then
    picker.addOnNegativeButtonClickListener(function() onPick("") end)
  end
  picker.show(activity.getSupportFragmentManager(), "nivora_date")
  return picker
end

function M.pickTime(hour, minute, onPick)
  local builder = MaterialTimePicker.Builder()
  builder.setTitleText("选择时间")
  builder.setHour(hour or 9)
  builder.setMinute(minute or 0)
  builder.setTimeFormat(MaterialTimePicker.TIME_FORMAT_24H)
  local picker = builder.build()
  picker.addOnPositiveButtonClickListener(function()
    onPick(picker.getHour(), picker.getMinute())
  end)
  picker.show(activity.getSupportFragmentManager(), "nivora_time")
  return picker
end

local INITIAL_BY_TYPE = {
  text = "",
  multiline = "",
  choice = "",
  date = "",
  time = "",
  toggle = false,
  number = 0,
  priority = 1,
  weekdays = {},
  color = "#6750A4",
  icon = "check",
}

local function optionLabel(field, value)
  for _, option in ipairs(field.options or {}) do
    if option.value == value then return option.name end
  end
  return tostring(value)
end

function M.open(spec)
  -- ---------- 初始值 ----------
  local values = {}
  for key, value in pairs(spec.values or {}) do values[key] = value end
  for _, field in ipairs(spec.fields) do
    if values[field.key] == nil then
      local initial = field.initial
      if initial == nil then initial = INITIAL_BY_TYPE[field.type or "text"] end
      if field.type == "weekdays" then
        local days = {}
        if type(initial) == "table" then
          for day = 1, 7 do days[day] = initial[day] == true end
        end
        initial = days
      end
      values[field.key] = initial
    end
  end

  local dialog = BottomSheetDialog(activity)
  local container = {
    LinearLayout,
    orientation = "vertical",
    layout_width = "match",
    layout_height = "wrap",
    paddingStart = "20dp",
    paddingEnd = "20dp",
    paddingTop = "16dp",
    paddingBottom = "16dp",
    BackgroundColor = theme.ATTR.surface,
    {
      MaterialTextView,
      text = spec.title or "编辑",
      textSize = "20sp",
      textStyle = "bold",
      textColor = theme.ATTR.onSurface,
      layout_width = "match",
      layout_height = "wrap",
      singleLine = true,
    },
  }

  if spec.subtitle then
    container[#container + 1] = ui.caption(spec.subtitle, {
      layout_width = "match",
      layout_height = "wrap",
      layout_marginTop = "4dp",
    })
  end

  -- pending[key] = function(bound) -> reader，在 loadlayout 之后执行
  local pending = {}
  local renderers = {}

  -- ---------- 文本 / 多行 ----------
  renderers.text = function(field)
    local id = "f_" .. field.key
    container[#container + 1] = ui.textField(id, field.label, {
      multiline = field.multiline == true,
      minLines = field.multiline and 3 or nil,
      value = tostring(values[field.key] or ""),
      marginTop = 12,
    })
    pending[field.key] = function(bound)
      local input = bound[id]
      return function()
        if not input then return "" end
        return trim(tostring(input.getText()))
      end
    end
  end

  renderers.multiline = function(field)
    field.multiline = true
    renderers.text(field)
  end

  -- ---------- 点选列表 ----------
  renderers.choice = function(field)
    local id = "f_" .. field.key
    container[#container + 1] = ui.textButton(
      field.label .. "：" .. optionLabel(field, values[field.key]), nil, {
        id = id,
        width = "match",
        gravity = "start|center_vertical",
        marginTop = 8,
      })
    pending[field.key] = function(bound)
      local button = bound[id]
      if button then
        button.setOnClickListener(function()
          local labels = {}
          for _, option in ipairs(field.options or {}) do labels[#labels + 1] = option.name end
          ui.choose(field.label, labels, function(index)
            local option = field.options[index]
            if not option then return end
            values[field.key] = option.value
            button.setText(field.label .. "：" .. option.name)
            if field.onChange then field.onChange(option.value, values) end
          end)
        end)
      end
      return function() return values[field.key] end
    end
  end

  -- ---------- 日期 / 时间 ----------
  renderers.date = function(field)
    local id = "f_" .. field.key
    local current = tostring(values[field.key] or "")
    container[#container + 1] = ui.textButton(
      field.label .. "：" .. (current ~= "" and dateUtils.formatDateCN(current) or "未设置"), nil, {
        id = id,
        width = "match",
        gravity = "start|center_vertical",
        marginTop = 8,
      })
    pending[field.key] = function(bound)
      local button = bound[id]
      if button then
        button.setOnClickListener(function()
          M.pickDate(values[field.key], function(dateStr)
            values[field.key] = dateStr
            button.setText(field.label .. "：" ..
              (dateStr ~= "" and dateUtils.formatDateCN(dateStr) or "未设置"))
          end, field.allowEmpty)
        end)
        if field.allowEmpty then
          button.setOnLongClickListener(function()
            values[field.key] = ""
            button.setText(field.label .. "：未设置")
            return true
          end)
        end
      end
      return function() return values[field.key] end
    end
  end

  renderers.time = function(field)
    local id = "f_" .. field.key
    local hour, minute = tostring(values[field.key] or ""):match("^(%d+):(%d+)$")
    container[#container + 1] = ui.textButton(
      field.label .. "：" ..
        (hour and dateUtils.timeLabel(tonumber(hour), tonumber(minute)) or "未设置"), nil, {
        id = id,
        width = "match",
        gravity = "start|center_vertical",
        marginTop = 8,
      })
    pending[field.key] = function(bound)
      local button = bound[id]
      if button then
        button.setOnClickListener(function()
          local h, mi = tostring(values[field.key] or ""):match("^(%d+):(%d+)$")
          M.pickTime(tonumber(h) or 9, tonumber(mi) or 0, function(newHour, newMinute)
            values[field.key] = dateUtils.timeLabel(newHour, newMinute)
            button.setText(field.label .. "：" .. values[field.key])
          end)
        end)
        if field.allowEmpty then
          button.setOnLongClickListener(function()
            values[field.key] = ""
            button.setText(field.label .. "：未设置")
            return true
          end)
        end
      end
      return function() return values[field.key] end
    end
  end

  -- ---------- 开关 ----------
  renderers.toggle = function(field)
    local id = "f_" .. field.key
    container[#container + 1] = {
      SwitchMaterial,
      id = id,
      text = field.label,
      textSize = "14sp",
      checked = values[field.key] == true,
      textColor = theme.ATTR.onSurface,
      layout_width = "match",
      layout_height = "wrap",
      layout_marginTop = "12dp",
      minHeight = "44dp",
    }
    pending[field.key] = function(bound)
      local control = bound[id]
      return function()
        if not control then return false end
        return control.isChecked() == true
      end
    end
  end

  -- ---------- Chip 组 ----------
  -- chip 必须作为 ChipGroup 的子节点写在同一布局表里，
  -- loadlayout 才会把它们 addView 进 ChipGroup（顺序与 entries 一致）。
  -- 读取时遍历 ChipGroup 的真实子视图 getChildAt(index-1)。
  --
  -- 注意（真机实测）：布局表里的 checked 对 Chip **不生效**。
  -- LuaLayout 应用属性时 checkable 晚于 checked，而未 checkable 的 Chip
  -- 会忽略 setChecked，于是「编辑时看不到当前图标/颜色/打卡日」。
  -- 因此所有 chip 的选中状态都在 loadlayout 之后由 pending 显式恢复。
  local function restoreChips(bound, groupId, entries)
    local groupView = bound[groupId]
    for index = 1, #entries do
      local entry = entries[index]
      local child = groupView and groupView.getChildAt(index - 1)
      if child then
        -- 顺序不能颠倒：先 checkable，再 setChecked
        pcall(function() child.setCheckable(true) end)
        pcall(function() child.setChecked(false) end)
        if entry.textColor then
          pcall(function() child.setTextColor(colorUtils.parse(entry.textColor)) end)
        end
        if entry.iconName then
          pcall(function()
            child.setChipIcon(icons.get(entry.iconName, theme.colors().onSurfaceVariant, 96))
            child.setChipIconVisible(true)
          end)
        end
      end
    end
    for index = 1, #entries do
      if entries[index].checked then
        local child = groupView and groupView.getChildAt(index - 1)
        if child then pcall(function() child.setChecked(true) end) end
      end
    end
    return groupView
  end

  -- 单选组：返回选中项的值（无选中时回落到第一项）
  local function readSingle(group, entries)
    for index = 1, #entries do
      local child = group and group.getChildAt(index - 1)
      if child and child.isChecked() then return entries[index].value end
    end
    return entries[1] and entries[1].value
  end

  -- 多选组：7 个布尔
  local function readWeekdaySet(group)
    local days = {}
    for day = 1, 7 do
      local child = group and group.getChildAt(day - 1)
      days[day] = child ~= nil and child.isChecked() == true
    end
    return days
  end

  local function addChipGroup(field, entries, singleSelection, read)
    local groupId = "g_" .. field.key
    local group = {
      ChipGroup,
      id = groupId,
      layout_width = "match",
      layout_height = "wrap",
      layout_marginTop = "8dp",
    }
    if singleSelection then group.singleSelection = true end

    container[#container + 1] = ui.caption(field.label, { layout_marginTop = 12 })
    for _, entry in ipairs(entries) do
      local chip = {
        Chip,
        text = entry.text,
        checkable = true,
        layout_width = "wrap",
        layout_height = "wrap",
        layout_marginEnd = "6dp",
      }
      group[#group + 1] = chip
    end
    container[#container + 1] = group

    pending[field.key] = function(bound)
      local groupView = restoreChips(bound, groupId, entries)
      return function() return read(groupView, entries) end
    end
  end

  renderers.priority = function(field)
    local entries = {}
    for _, item in ipairs(constants.PRIORITIES) do
      entries[#entries + 1] = {
        text = item.name,
        value = item.value,
        checked = values[field.key] == item.value,
      }
    end
    addChipGroup(field, entries, true, readSingle)
  end

  renderers.color = function(field)
    local entries = {}
    for _, hex in ipairs(constants.PALETTE) do
      entries[#entries + 1] = {
        text = "●",
        value = hex,
        textColor = hex,
        checked = values[field.key] == hex,
      }
    end
    addChipGroup(field, entries, true, readSingle)
  end

  -- 图标 chip：中文标签 + 图形，避免用户面对 check / leaf 这类英文键名
  renderers.icon = function(field)
    local entries = {}
    for _, name in ipairs(constants.HABIT_ICONS) do
      entries[#entries + 1] = {
        text = constants.iconLabel(name),
        value = name,
        iconName = name,
        checked = values[field.key] == name,
      }
    end
    addChipGroup(field, entries, true, readSingle)
  end

  renderers.weekdays = function(field)
    local current = values[field.key] or {}
    local entries = {}
    for day = 1, 7 do
      entries[#entries + 1] = {
        text = "周" .. dateUtils.WEEK_CN[day],
        value = day,
        checked = current[day] == true,
      }
    end
    addChipGroup(field, entries, false, readWeekdaySet)
  end

  -- ---------- 数字 ----------
  renderers.number = function(field)
    local id = "f_" .. field.key
    container[#container + 1] = ui.textField(id, field.label, {
      inputType = "number",
      value = tostring(values[field.key] or ""),
      marginTop = 12,
    })
    pending[field.key] = function(bound)
      local input = bound[id]
      return function()
        if not input then return 0 end
        return tonumber(tostring(input.getText())) or 0
      end
    end
  end

  -- ---------- 渲染字段 ----------
  for _, field in ipairs(spec.fields) do
    local renderer = renderers[field.type or "text"]
    if renderer then
      local ok, err = pcall(renderer, field)
      if not ok then print("[form] 字段 " .. tostring(field.key) .. " 渲染失败：" .. tostring(err)) end
    end
  end

  -- ---------- 底部按钮 ----------
  local cancelButton = ui.textButton("取消", nil, { weight = 1, id = "form_cancel" })
  local saveButton = ui.button(spec.saveLabel or "保存", nil, { weight = 1, id = "form_save" })
  container[#container + 1] = ui.row({ cancelButton, saveButton }, {
    layout_marginTop = 16,
    layout_width = "match",
  })

  -- ---------- 加载并绑定真实 View ----------
  local bound = {}
  local okLoad, loadResult = pcall(loadlayout, {
    ScrollView,
    layout_width = "match",
    layout_height = "wrap",
    container,
  }, bound, LinearLayoutParams)
  if not okLoad then
    print("[form] 布局加载失败：" .. tostring(loadResult))
    ui.alert("无法打开表单", tostring(loadResult))
    return nil
  end
  dialog.setContentView(loadResult)
  dialog.show()

  -- 建立字段读取器
  local readers = {}
  for _, field in ipairs(spec.fields) do
    local setup = pending[field.key]
    if setup then
      local okSetup, reader = pcall(setup, bound)
      if okSetup and reader then
        readers[field.key] = reader
      else
        print("[form] 字段 " .. tostring(field.key) .. " 绑定失败：" .. tostring(reader))
      end
    end
  end

  local cancelView = bound.form_cancel
  if cancelView then
    cancelView.setOnClickListener(function() dialog.dismiss() end)
  end

  local saveView = bound.form_save
  if not saveView then
    print("[form] 保存按钮未绑定")
    return dialog
  end

  saveView.setOnClickListener(function()
    local result = {}
    for key, value in pairs(values) do result[key] = value end
    for _, field in ipairs(spec.fields) do
      local reader = readers[field.key]
      if reader then
        local okRead, value = pcall(reader)
        if okRead then
          result[field.key] = value
        else
          print("[form] 读取字段 " .. tostring(field.key) .. " 失败：" .. tostring(value))
        end
      end
    end
    if spec.onSave then
      local okSave, saved, message = pcall(spec.onSave, result)
      if not okSave then
        ui.alert("保存失败", tostring(saved))
        return
      end
      if saved == false then
        if message then ui.alert("无法保存", tostring(message)) end
        return
      end
    end
    dialog.dismiss()
  end)

  return dialog
end

return M
