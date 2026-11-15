-- 公共 UI 组件：所有页面只从这里取卡片、文本、按钮、空状态、对话框、Snackbar。
-- 布局表用 ?attr/… 取色；需要在 Canvas 上绘制时读 theme.colors()。
local bindClass = luajava.bindClass
local ui = {}

local LinearLayout = bindClass "android.widget.LinearLayout"
local FrameLayout = bindClass "android.widget.FrameLayout"
local View = bindClass "android.view.View"
local ScrollView = bindClass "androidx.core.widget.NestedScrollView"
local MaterialTextView = bindClass "com.google.android.material.textview.MaterialTextView"
local MaterialCardView = bindClass "com.google.android.material.card.MaterialCardView"
local MaterialButton = bindClass "com.google.android.material.button.MaterialButton"
local MaterialCheckBox = bindClass "com.google.android.material.checkbox.MaterialCheckBox"
local MaterialDivider = bindClass "com.google.android.material.divider.MaterialDivider"
local LinearProgressIndicator = bindClass "com.google.android.material.progressindicator.LinearProgressIndicator"
local AppCompatImageView = bindClass "androidx.appcompat.widget.AppCompatImageView"
local FloatingActionButton = bindClass "com.google.android.material.floatingactionbutton.FloatingActionButton"
local Chip = bindClass "com.google.android.material.chip.Chip"
local TextInputLayout = bindClass "com.google.android.material.textfield.TextInputLayout"
local TextInputEditText = bindClass "com.google.android.material.textfield.TextInputEditText"
local MaterialAlertDialogBuilder = bindClass "com.google.android.material.dialog.MaterialAlertDialogBuilder"
local Snackbar = bindClass "com.google.android.material.snackbar.Snackbar"

local icons = require "components.icons"
local theme = require "config.theme"

ui.ATTR = theme.ATTR

-- MaterialAlertDialogBuilder.setItems 需要 Java String[]
local function stringArray(list)
  local String = bindClass "java.lang.String"
  local values = {}
  for i = 1, #list do values[i] = tostring(list[i]) end
  return String.array(values)
end

ui.stringArray = stringArray

-- ---------- 基础构造 ----------

function ui.dp(value) return tostring(math.floor(value)) .. "dp" end
function ui.sp(value) return tostring(math.floor(value)) .. "sp" end

-- 垂直容器
function ui.column(children, options)
  local node = {
    LinearLayout,
    orientation = "vertical",
    layout_width = "match",
    layout_height = "wrap",
  }
  for key, value in pairs(options or {}) do node[key] = value end
  for _, child in ipairs(children or {}) do node[#node + 1] = child end
  return node
end

-- 水平容器
function ui.row(children, options)
  local node = {
    LinearLayout,
    orientation = "horizontal",
    layout_width = "match",
    layout_height = "wrap",
    gravity = "center_vertical",
  }
  for key, value in pairs(options or {}) do node[key] = value end
  for _, child in ipairs(children or {}) do node[#node + 1] = child end
  return node
end

function ui.space(height)
  return { View, layout_width = "match", layout_height = ui.dp(height) }
end

function ui.hspace(width)
  return { View, layout_width = ui.dp(width), layout_height = "1dp" }
end

-- 圆角纯色背景（日历格子等）：GradientDrawable 作为 background 传入布局表
function ui.roundBg(color, radiusDp)
  local bindClass2 = luajava.bindClass
  local GradientDrawable = bindClass2 "android.graphics.drawable.GradientDrawable"
  local drawable = GradientDrawable()
  drawable.setShape(GradientDrawable.RECTANGLE)
  drawable.setColor(color)
  drawable.setCornerRadius(activity.dpToPx(radiusDp or 10))
  return drawable
end

-- 日历格子：固定尺寸、圆角背景、居中文字。
-- 传 weight 时按权重平分宽度，否则用 width（默认 match）。
function ui.dayCell(options)
  local opts = options or {}
  local node = {
    MaterialTextView,
    text = opts.text or "",
    textSize = opts.textSize or "12sp",
    textColor = opts.textColor or theme.ATTR.onSurface,
    gravity = "center",
    background = ui.roundBg(opts.background, opts.radius or 10),
    layout_height = ui.dp(opts.height or 44),
    layout_marginStart = "2dp",
    layout_marginEnd = "2dp",
  }
  if opts.weight then
    node.layout_width = "0dp"
    node.layout_weight = opts.weight
  else
    node.layout_width = opts.width or "match"
  end
  if opts.marginTop then node.layout_marginTop = ui.dp(opts.marginTop) end
  if opts.onClick then
    node.onClick = opts.onClick
    node.clickable = true
  end
  return node
end

function ui.text(value, options)
  local node = {
    MaterialTextView,
    text = tostring(value or ""),
    textSize = "14sp",
    textColor = theme.ATTR.onSurface,
    layout_width = "wrap",
    layout_height = "wrap",
  }
  for key, value2 in pairs(options or {}) do node[key] = value2 end
  return node
end

function ui.title(value, options)
  local node = ui.text(value, {
    textSize = "20sp",
    textColor = theme.ATTR.onSurface,
    textStyle = "bold",
  })
  for key, value2 in pairs(options or {}) do node[key] = value2 end
  return node
end

function ui.caption(value, options)
  local node = ui.text(value, {
    textSize = "12sp",
    textColor = theme.ATTR.onSurfaceVariant,
  })
  for key, value2 in pairs(options or {}) do node[key] = value2 end
  return node
end

function ui.icon(name, options)
  local opts = options or {}
  local size = opts.size or 24
  local node = {
    AppCompatImageView,
    src = icons.get(name, opts.color, 96),
    layout_width = ui.dp(size),
    layout_height = ui.dp(size),
    scaleType = "fitCenter",
  }
  if opts.id then node.id = opts.id end
  if opts.marginEnd then node.layout_marginEnd = ui.dp(opts.marginEnd) end
  if opts.marginStart then node.layout_marginStart = ui.dp(opts.marginStart) end
  if opts.marginTop then node.layout_marginTop = ui.dp(opts.marginTop) end
  if opts.layout_gravity then node.layout_gravity = opts.layout_gravity end
  if opts.weight then
    node.layout_width = "0dp"
    node.layout_weight = opts.weight
  end
  return node
end

function ui.divider(options)
  local node = {
    MaterialDivider,
    layout_width = "match",
    layout_height = "1dp",
    layout_marginTop = "12dp",
    layout_marginBottom = "12dp",
  }
  for key, value in pairs(options or {}) do node[key] = value end
  return node
end

-- ---------- 卡片与分组 ----------

function ui.card(children, options)
  local opts = options or {}
  local inner = ui.column(children, {
    layout_width = "match",
    layout_height = "wrap",
    padding = ui.dp(opts.padding or 16),
  })
  local node = {
    MaterialCardView,
    layout_width = "match",
    layout_height = "wrap",
    radius = ui.dp(opts.radius or 16),
    cardElevation = 0,
    strokeWidth = "1dp",
    strokeColor = theme.ATTR.outlineVariant,
    CardBackgroundColor = opts.background or theme.ATTR.surfaceContainerLow,
  }
  if opts.id then node.id = opts.id end
  if opts.marginTop then node.layout_marginTop = ui.dp(opts.marginTop) end
  if opts.marginBottom then node.layout_marginBottom = ui.dp(opts.marginBottom) end
  if opts.clickable then
    node.clickable = true
    node.focusable = true
  end
  node[1] = MaterialCardView
  node[#node + 1] = inner
  return node
end

-- 标题 + 可选右侧动作
function ui.sectionHeader(titleText, actionText, actionHandler, options)
  local opts = options or {}
  local children = {
    ui.text(titleText, {
      textSize = "16sp",
      textStyle = "bold",
      textColor = theme.ATTR.onSurface,
      layout_width = "0dp",
      layout_weight = 1,
      layout_height = "wrap",
    }),
  }
  if actionText then
    children[#children + 1] = ui.textButton(actionText, actionHandler, { textSize = 13 })
  end
  return ui.row(children, {
    layout_marginTop = ui.dp(opts.marginTop or 0),
    layout_marginBottom = ui.dp(8),
  })
end

-- ---------- 按钮 ----------
-- MD3 按钮：40dp 高、全圆角（药丸）、标签不转大写
local BUTTON_HEIGHT = 40
local BUTTON_RADIUS = 20

function ui.button(label, onClick, options)
  local opts = options or {}
  local node = {
    MaterialButton,
    text = label,
    textSize = ui.sp(opts.textSize or 14),
    -- MD2 会把按钮文字转成全大写，MD3 保持原样
    allCaps = false,
    layout_width = opts.width or "wrap",
    layout_height = "wrap",
    -- MaterialButton 默认 minWidth 为 88dp，水平筛选条里会溢出被裁掉
    minWidth = 0,
    minHeight = ui.dp(opts.height or BUTTON_HEIGHT),
    radius = ui.dp(opts.radius or BUTTON_RADIUS),
    paddingStart = "16dp",
    paddingEnd = "16dp",
    onClick = onClick,
  }
  if opts.style then node.style = opts.style end
  if opts.styleAttr then node.styleAttr = opts.styleAttr end
  if opts.gravity then node.gravity = opts.gravity end
  if opts.icon then
    node.icon = icons.get(opts.icon, theme.colors().primary, 96)
    node.iconGravity = 1
    node.iconPadding = ui.dp(8)
    node.iconTint = theme.ATTR.primary
  end
  if opts.marginTop then node.layout_marginTop = ui.dp(opts.marginTop) end
  if opts.marginEnd then node.layout_marginEnd = ui.dp(opts.marginEnd) end
  if opts.weight then
    node.layout_width = "0dp"
    node.layout_weight = opts.weight
  end
  if opts.id then node.id = opts.id end
  return node
end

-- MD3 文本按钮：无背景，样式由 styleAttr 的 attr 引用决定
function ui.textButton(label, onClick, options)
  local opts = options or {}
  opts.styleAttr = "?attr/borderlessButtonStyle"
  return ui.button(label, onClick, opts)
end

-- MD3 描边按钮
function ui.outlinedButton(label, onClick, options)
  local opts = options or {}
  opts.styleAttr = "?attr/materialButtonOutlinedStyle"
  return ui.button(label, onClick, opts)
end

-- MD3 图标按钮：正方形改圆形，靠全圆角实现
function ui.iconButton(name, onClick, options)
  local opts = options or {}
  local size = opts.size or 40
  local node = {
    MaterialButton,
    styleAttr = "?attr/borderlessButtonStyle",
    layout_width = ui.dp(size),
    layout_height = ui.dp(size),
    minWidth = 0,
    minHeight = 0,
    radius = ui.dp(math.floor(size / 2)),
    padding = "8dp",
    icon = icons.get(name, opts.color or theme.colors().onSurfaceVariant, 96),
    iconGravity = 1,
    iconPadding = 0,
    iconTint = opts.tint or theme.ATTR.onSurfaceVariant,
    onClick = onClick,
  }
  if opts.id then node.id = opts.id end
  if opts.marginStart then node.layout_marginStart = ui.dp(opts.marginStart) end
  return node
end

function ui.fab(name, onClick, options)
  local opts = options or {}
  local node = {
    FloatingActionButton,
    layout_width = "wrap",
    layout_height = "wrap",
    layout_gravity = opts.gravity or "bottom|end",
    layout_margin = "16dp",
    src = icons.get(name, theme.colors().onPrimaryContainer, 96),
    onClick = onClick,
  }
  if opts.id then node.id = opts.id end
  return node
end

-- ---------- 列表项 ----------

-- 带图标、主标题、副标题、右侧附加值/勾选的列表行
function ui.listItem(options)
  local opts = options or {}
  local left = {}
  if opts.icon then
    left[#left + 1] = ui.icon(opts.icon, {
      size = 20,
      color = opts.iconColor,
      marginEnd = 12,
    })
  end
  local textStack = ui.column({
    ui.text(opts.title or "", {
      textSize = "15sp",
      textColor = theme.ATTR.onSurface,
      layout_width = "match",
      layout_height = "wrap",
      maxLines = 2,
    }),
  }, { layout_width = "0dp", layout_weight = 1, layout_height = "wrap" })

  if opts.subtitle and opts.subtitle ~= "" then
    textStack[#textStack + 1] = ui.caption(opts.subtitle, {
      layout_width = "match",
      layout_height = "wrap",
      layout_marginTop = "2dp",
      maxLines = 2,
    })
  end
  left[#left + 1] = textStack

  if opts.trailing then
    left[#left + 1] = ui.text(opts.trailing, {
      textSize = "13sp",
      textColor = opts.trailingColor or theme.ATTR.onSurfaceVariant,
      layout_marginStart = "8dp",
      layout_height = "wrap",
    })
  end
  if opts.trailingIcon then
    left[#left + 1] = ui.icon(opts.trailingIcon, {
      size = 20,
      color = theme.colors().onSurfaceVariant,
      marginStart = 8,
    })
  end

  local node = ui.row(left, {
    layout_width = "match",
    layout_height = "wrap",
    paddingStart = "16dp",
    paddingEnd = "16dp",
    paddingTop = "12dp",
    paddingBottom = "12dp",
    gravity = "center_vertical",
  })
  if opts.id then node.id = opts.id end
  if opts.onClick then
    node.clickable = true
    node.focusable = true
    node.background = "?attr/selectableItemBackground"
    node.onClick = opts.onClick
  end
  return node
end

-- 带勾选框的列表行（待办、习惯）
function ui.checkRow(options)
  local opts = options or {}
  local check = {
    MaterialCheckBox,
    id = opts.checkId,
    checked = opts.checked == true,
    layout_width = "wrap",
    layout_height = "wrap",
    minWidth = 0,
    minHeight = 0,
    clickable = false,
  }
  local textStack = ui.column({
    ui.text(opts.title or "", {
      textSize = "15sp",
      textColor = opts.checked and theme.ATTR.onSurfaceVariant or theme.ATTR.onSurface,
      layout_width = "match",
      layout_height = "wrap",
      maxLines = 3,
    }),
  }, { layout_width = "0dp", layout_weight = 1, layout_height = "wrap", layout_marginStart = "4dp" })

  if opts.subtitle and opts.subtitle ~= "" then
    textStack[#textStack + 1] = ui.caption(opts.subtitle, {
      layout_width = "match",
      layout_height = "wrap",
      layout_marginTop = "2dp",
    })
  end

  local children = { check, textStack }
  if opts.trailing then
    children[#children + 1] = ui.text(opts.trailing, {
      textSize = "12sp",
      textColor = opts.trailingColor or theme.ATTR.onSurfaceVariant,
      layout_marginStart = "8dp",
    })
  end

  local node = ui.row(children, {
    layout_width = "match",
    layout_height = "wrap",
    paddingStart = "8dp",
    paddingEnd = "12dp",
    paddingTop = "4dp",
    paddingBottom = "4dp",
    gravity = "center_vertical",
    onClick = opts.onClick,
    clickable = opts.onClick ~= nil,
    focusable = opts.onClick ~= nil,
    background = opts.onClick ~= nil and "?attr/selectableItemBackground" or nil,
  })
  if opts.id then node.id = opts.id end
  -- 返回 (行容器, 勾选框, 文本区)：布局表 [1] 是控件类，不能靠下标取子控件
  return node, check, textStack
end

-- ---------- 状态展示 ----------

function ui.empty(iconName, titleText, hintText, actionLabel, actionHandler)
  local children = {
    ui.icon(iconName or "info", { size = 40, color = theme.colors().outline }),
    ui.text(titleText or "暂无内容", {
      textSize = "15sp",
      textColor = theme.ATTR.onSurface,
      layout_width = "match",
      layout_height = "wrap",
      gravity = "center",
      layout_marginTop = "12dp",
    }),
  }
  if hintText and hintText ~= "" then
    children[#children + 1] = ui.caption(hintText, {
      layout_width = "match",
      layout_height = "wrap",
      gravity = "center",
      layout_marginTop = "4dp",
    })
  end
  if actionLabel then
    children[#children + 1] = ui.textButton(actionLabel, actionHandler, {
      layout_width = "wrap",
      layout_gravity = "center_horizontal",
      layout_marginTop = "8dp",
    })
  end
  return ui.column(children, {
    layout_width = "match",
    layout_height = "wrap",
    paddingTop = "28dp",
    paddingBottom = "28dp",
    paddingStart = "24dp",
    paddingEnd = "24dp",
    gravity = "center_horizontal",
  })
end

function ui.progress(value, options)
  local opts = options or {}
  local node = {
    LinearProgressIndicator,
    layout_width = "match",
    layout_height = "wrap",
    progress = math.max(0, math.min(100, math.floor(value or 0))),
    trackThickness = ui.dp(opts.thickness or 8),
    trackCornerRadius = ui.dp(4),
    max = 100,
  }
  if opts.id then node.id = opts.id end
  if opts.marginTop then node.layout_marginTop = ui.dp(opts.marginTop) end
  return node
end

-- 圆点 + 文本的统计小块
function ui.metric(label, value, options)
  local opts = options or {}
  return ui.column({
    ui.text(value, {
      textSize = "20sp",
      textStyle = "bold",
      textColor = opts.valueColor and opts.valueColor or theme.ATTR.onSurface,
      layout_width = "match",
      layout_height = "wrap",
      gravity = opts.gravity or "start",
    }),
    ui.caption(label, {
      layout_width = "match",
      layout_height = "wrap",
      gravity = opts.gravity or "start",
      layout_marginTop = "2dp",
    }),
  }, { layout_width = "0dp", layout_weight = 1, layout_height = "wrap" })
end

-- ---------- 输入控件 ----------

-- MD3 描边输入框：1dp 描边、聚焦 2dp，圆角与颜色由 textInputOutlinedStyle 提供，
-- 因此必须用 styleAttr 传 attr 引用（style 键用于直接资源样式）。
function ui.textField(id, hintText, options)
  local opts = options or {}
  local edit = {
    TextInputEditText,
    id = id,
    layout_width = "match",
    layout_height = "wrap",
    textSize = ui.sp(opts.textSize or 15),
    inputType = opts.inputType or "text",
  }
  if opts.multiline then
    edit.inputType = "textMultiLine"
    edit.minLines = opts.minLines or 2
    edit.gravity = "top|start"
  elseif opts.minLines then
    edit.minLines = opts.minLines
  end
  if opts.maxLength then edit.maxLength = opts.maxLength end
  if opts.value then edit.text = tostring(opts.value) end

  local box = {
    TextInputLayout,
    id = id .. "Box",
    layout_width = opts.width or "match",
    layout_height = "wrap",
    Hint = hintText,
    styleAttr = "?attr/textInputOutlinedStyle",
    layout_marginTop = ui.dp(opts.marginTop or 8),
    edit,
  }
  if opts.weight then
    box.layout_width = "0dp"
    box.layout_weight = opts.weight
  end
  return box
end

-- ---------- 对话框 ----------

function ui.snackbar(rootView, message, actionLabel, actionHandler)
  if not rootView then return end
  local bar = Snackbar.make(rootView, tostring(message), Snackbar.LENGTH_SHORT)
  if actionLabel then
    bar.setAction(actionLabel, actionHandler)
  end
  bar.show()
end

function ui.alert(titleText, messageText)
  local dialog = MaterialAlertDialogBuilder(activity)
    .setTitle(titleText)
    .setMessage(messageText)
    .setPositiveButton("知道了", nil)
    .create()
  dialog.show()
  return dialog
end

function ui.confirm(options, onConfirm)
  local opts = options or {}
  local dialog = MaterialAlertDialogBuilder(activity)
    .setTitle(opts.title or "确认操作")
    .setMessage(opts.message or "")
    .setNegativeButton(opts.cancelText or "取消", nil)
    .setPositiveButton(opts.confirmText or "确定", function(_, _)
      if onConfirm then onConfirm() end
    end)
    .create()
  dialog.show()
  return dialog
end

-- 从字符串选项中选择一项
function ui.choose(titleText, labels, onSelect)
  local dialog = MaterialAlertDialogBuilder(activity)
    .setTitle(titleText)
    .setItems(stringArray(labels), function(_, which)
      onSelect(which + 1)
    end)
    .create()
  dialog.show()
  return dialog
end

-- 可滚动的内容容器（页面主体）
function ui.scroll(children, options)
  local opts = options or {}
  local inner = ui.column(children, {
    layout_width = "match",
    layout_height = "wrap",
    paddingStart = ui.dp(opts.paddingH or 16),
    paddingEnd = ui.dp(opts.paddingH or 16),
    paddingTop = ui.dp(opts.paddingTop or 8),
    paddingBottom = ui.dp(opts.paddingBottom or 96),
  })
  local node = {
    ScrollView,
    layout_width = "match",
    layout_height = "match",
    fillViewport = true,
    clipToPadding = false,
    inner,
  }
  if opts.id then node.id = opts.id end
  return node
end

-- 用新内容替换容器内的子视图（局部刷新，保留页面滚动位置）。
-- 必须逐个 addView 到容器本身，不能包一层垂直容器：
-- 否则水平容器（筛选条、时段导航、按钮行）会被强行竖排，
-- 且 layout_width="0dp" + layout_weight 会按错误的轴向分配而被压成 0 宽。
local LinearLayoutParams = luajava.bindClass "android.widget.LinearLayout$LayoutParams"

function ui.fill(container, children)
  if not container then return end
  container.removeAllViews()
  if type(children) ~= "table" then return end

  local isLinear = luajava.instanceof(container, LinearLayout)
  for index = 1, #children do
    local child = children[index]
    if type(child) == "table" and child[1] ~= nil then
      local bound = {}
      local ok, view
      if isLinear then
        ok, view = pcall(loadlayout, child, bound, LinearLayoutParams)
      else
        ok, view = pcall(loadlayout, child, bound)
      end
      if ok and view ~= nil then
        container.addView(view)
      else
        print("[ui.fill] 第 " .. index .. " 个子视图加载失败：" .. tostring(view))
      end
    end
  end
end

-- 动态容器：先占位，刷新时用 ui.fill 填充
function ui.container(id, options)
  local opts = options or {}
  return {
    LinearLayout,
    id = id,
    orientation = "vertical",
    layout_width = "match",
    layout_height = "wrap",
    layout_marginTop = opts.marginTop and ui.dp(opts.marginTop) or nil,
  }
end

-- 页面骨架：内容 + 右下角 FAB（可选）
function ui.page(children, options)
  local opts = options or {}
  local frame = {
    FrameLayout,
    layout_width = "match",
    layout_height = "match",
    BackgroundColor = theme.ATTR.surface,
  }
  frame[#frame + 1] = ui.scroll(children, opts)
  if opts.fab then
    frame[#frame + 1] = opts.fab
  end
  return frame
end

return ui
