-- 简易图表：全部用 Canvas 自绘，不引入图表库
local bindClass = luajava.bindClass
local View = bindClass "android.view.View"
local Paint = bindClass "android.graphics.Paint"
local Path = bindClass "android.graphics.Path"
local RectF = bindClass "android.graphics.RectF"

local theme = require "config.theme"
local colorUtils = require "utils.color_utils"

local M = {}

local function newPaint(color, style, width)
  local paint = Paint()
  paint.setAntiAlias(true)
  paint.setColor(color)
  paint.setStyle(style or Paint.Style.FILL)
  if width then paint.setStrokeWidth(width) end
  return paint
end

-- 柱状图：values 与 labels 等长；返回可直接加入布局的 View
function M.barChart(values, labels, options)
  local opts = options or {}
  local heightDP = opts.height or 140
  local colors = theme.colors()
  local barColor = opts.color and colorUtils.parse(opts.color) or colors.primary
  local trackColor = colors.surfaceContainerHigh
  local textColor = colors.onSurfaceVariant
  local maxValue = 1
  for _, value in ipairs(values) do
    if value > maxValue then maxValue = value end
  end

  local holder = {}
  local ChartView = View.override {
    onDraw = function(superCall, canvas)
      superCall(canvas)
      local view = holder[1]
      if not view then return end
      local width = view.getWidth()
      local height = view.getHeight()
      if width <= 0 or height <= 0 then return end

      local count = #values
      if count == 0 then return end
      local labelHeight = activity.dpToPx(16)
      local chartHeight = height - labelHeight
      local slot = width / count
      local barWidth = math.min(slot * 0.5, activity.dpToPx(22))

      local trackPaint = newPaint(trackColor)
      local barPaint = newPaint(barColor)
      local cornerPaint = newPaint(barColor)

      local textPaint = newPaint(textColor)
      textPaint.setTextSize(activity.spToPx(9))
      textPaint.setTextAlign(Paint.Align.CENTER)

      for index = 1, count do
        local value = values[index] or 0
        local left = (index - 1) * slot + (slot - barWidth) / 2
        local right = left + barWidth
        local radius = barWidth / 2

        canvas.drawRoundRect(RectF(left, activity.dpToPx(2), right, chartHeight), radius, radius, trackPaint)

        local ratio = value / maxValue
        if ratio > 0 then
          local barHeight = math.max(barWidth, chartHeight * ratio)
          local top = chartHeight - barHeight
          canvas.drawRoundRect(RectF(left, top, right, chartHeight), radius, radius, barPaint)
        end

        local label = labels and labels[index]
        if label then
          canvas.drawText(tostring(label), (index - 1) * slot + slot / 2, height - activity.dpToPx(4), textPaint)
        end
      end
    end,
  }

  local view = ChartView(activity)
  holder[1] = view
  local params = bindClass("android.view.ViewGroup$LayoutParams")(
    -1, activity.dpToPx(heightDP))
  view.setLayoutParams(params)
  return view
end

-- 折线图：用于任务完成趋势
function M.lineChart(values, labels, options)
  local opts = options or {}
  local heightDP = opts.height or 120
  local colors = theme.colors()
  local lineColor = opts.color and colorUtils.parse(opts.color) or colors.primary
  local textColor = colors.onSurfaceVariant
  local maxValue = 1
  for _, value in ipairs(values) do
    if value > maxValue then maxValue = value end
  end

  local holder = {}
  local ChartView = View.override {
    onDraw = function(superCall, canvas)
      superCall(canvas)
      local view = holder[1]
      if not view then return end
      local width = view.getWidth()
      local height = view.getHeight()
      if width <= 0 or height <= 0 or #values == 0 then return end

      local labelHeight = activity.dpToPx(14)
      local chartHeight = height - labelHeight
      local step = width / math.max(1, #values - 1)

      local linePaint = newPaint(lineColor, Paint.Style.STROKE, activity.dpToPx(2))
      linePaint.setStrokeCap(Paint.Cap.ROUND)
      linePaint.setStrokeJoin(Paint.Join.ROUND)

      local dotPaint = newPaint(lineColor)
      local textPaint = newPaint(textColor)
      textPaint.setTextSize(activity.spToPx(9))
      textPaint.setTextAlign(Paint.Align.CENTER)

      local path = Path()
      for index, value in ipairs(values) do
        local x = (index - 1) * step
        local y = chartHeight - (chartHeight * (value / maxValue)) * 0.9 - activity.dpToPx(4)
        if index == 1 then
          path.moveTo(x, y)
        else
          path.lineTo(x, y)
        end
      end
      canvas.drawPath(path, linePaint)

      for index, value in ipairs(values) do
        local x = (index - 1) * step
        local y = chartHeight - (chartHeight * (value / maxValue)) * 0.9 - activity.dpToPx(4)
        canvas.drawCircle(x, y, activity.dpToPx(2.5), dotPaint)
        local label = labels and labels[index]
        if label then
          canvas.drawText(tostring(label), x, height - activity.dpToPx(2), textPaint)
        end
      end
    end,
  }

  local view = ChartView(activity)
  holder[1] = view
  local params = bindClass("android.view.ViewGroup$LayoutParams")(
    -1, activity.dpToPx(heightDP))
  view.setLayoutParams(params)
  return view
end

-- 进度环：用于专注完成度。
-- opts.state 传入 { percent = n } 后可通过修改该表 + view.invalidate() 实时刷新。
function M.ring(percent, options)
  local opts = options or {}
  local size = opts.size or 120
  local colors = theme.colors()
  local ringColor = opts.color and colorUtils.parse(opts.color) or colors.primary
  local trackColor = colors.surfaceContainerHigh
  local textColor = colors.onSurface
  local live = opts.state
  if live and live.percent == nil then live.percent = percent or 0 end

  local holder = {}
  local RingView = View.override {
    onDraw = function(superCall, canvas)
      superCall(canvas)
      local view = holder[1]
      if not view then return end
      local width = view.getWidth()
      local height = view.getHeight()
      local diameter = math.min(width, height)
      if diameter <= 0 then return end

      local value = live and live.percent or percent or 0
      local stroke = activity.dpToPx(10)
      local inset = stroke / 2 + activity.dpToPx(2)
      local box = RectF(inset, inset, diameter - inset, diameter - inset)

      local trackPaint = newPaint(trackColor, Paint.Style.STROKE, stroke)
      trackPaint.setStrokeCap(Paint.Cap.ROUND)
      canvas.drawArc(box, 0, 360, false, trackPaint)

      local arcPaint = newPaint(ringColor, Paint.Style.STROKE, stroke)
      arcPaint.setStrokeCap(Paint.Cap.ROUND)
      local sweep = math.max(0, math.min(100, value)) * 3.6
      if sweep > 0 then
        canvas.drawArc(box, -90, sweep, false, arcPaint)
      end

      local textPaint = newPaint(textColor)
      textPaint.setTextSize(activity.spToPx(22))
      textPaint.setTextAlign(Paint.Align.CENTER)
      local text = tostring(math.floor(value)) .. "%"
      local metrics = textPaint.getFontMetrics()
      canvas.drawText(text, diameter / 2, diameter / 2 - (metrics.ascent + metrics.descent) / 2, textPaint)
    end,
  }

  local view = RingView(activity)
  holder[1] = view
  local px = activity.dpToPx(size)
  view.setLayoutParams(bindClass("android.view.ViewGroup$LayoutParams")(px, px))
  return view
end

return M
