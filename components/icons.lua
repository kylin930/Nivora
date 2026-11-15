-- 图标引擎：用 Canvas 在 96×96 位图上绘制线性图标，返回已着色的 BitmapDrawable。
-- 为什么不用 res.drawable：内置资源只提供编辑器图标，且 .lua 图标返回 Bitmap 时
-- 两参着色形式会失败（见 AGENTS.md 第 3 节第 4 条）。这里自行构造 Drawable，完全可控。
local bindClass = luajava.bindClass
local Bitmap = bindClass "android.graphics.Bitmap"
local Canvas = bindClass "android.graphics.Canvas"
local Paint = bindClass "android.graphics.Paint"
local Path = bindClass "android.graphics.Path"
local RectF = bindClass "android.graphics.RectF"
local BitmapDrawable = bindClass "android.graphics.drawable.BitmapDrawable"

local M = {}

local BASE = 96
local cache = {}

-- ---------- 绘制辅助 ----------

local function movePath(path, points)
  path.moveTo(points[1], points[2])
  local i = 3
  while i < #points do
    path.lineTo(points[i], points[i + 1])
    i = i + 2
  end
end

local function stroke(canvas, paint, points)
  local path = Path()
  movePath(path, points)
  canvas.drawPath(path, paint)
end

local function polygon(canvas, paint, points)
  local path = Path()
  movePath(path, points)
  path.close()
  canvas.drawPath(path, paint)
end

local function line(canvas, paint, x1, y1, x2, y2)
  canvas.drawLine(x1, y1, x2, y2, paint)
end

local function roundRect(canvas, paint, left, top, right, bottom, radius)
  canvas.drawRoundRect(RectF(left, top, right, bottom), radius, radius, paint)
end

local function arc(canvas, paint, left, top, right, bottom, start, sweep)
  canvas.drawArc(RectF(left, top, right, bottom), start, sweep, false, paint)
end

-- ---------- 图标定义 ----------
-- 每个函数签名：(canvas, strokePaint, fillPaint, size)

local shapes = {}

shapes.home = function(c, p)
  stroke(c, p, { 20, 46, 48, 22, 76, 46 })
  stroke(c, p, { 30, 44, 30, 76, 66, 76, 66, 44 })
end

shapes.calendar = function(c, p)
  roundRect(c, p, 18, 26, 78, 78, 10)
  line(c, p, 18, 42, 78, 42)
  line(c, p, 34, 18, 34, 30)
  line(c, p, 62, 18, 62, 30)
  c.drawCircle(38, 58, 3, p)
  c.drawCircle(58, 58, 3, p)
end

shapes.today = function(c, p)
  roundRect(c, p, 18, 26, 78, 78, 10)
  line(c, p, 18, 42, 78, 42)
  line(c, p, 34, 18, 34, 30)
  line(c, p, 62, 18, 62, 30)
  c.drawCircle(48, 60, 8, p)
end

shapes.check = function(c, p)
  c.drawCircle(48, 48, 30, p)
  stroke(c, p, { 34, 49, 44, 60, 63, 37 })
end

shapes.check_bare = function(c, p)
  stroke(c, p, { 22, 50, 40, 68, 74, 30 })
end

shapes.chart = function(c, p)
  line(c, p, 20, 78, 78, 78)
  line(c, p, 32, 78, 32, 56)
  line(c, p, 48, 78, 48, 38)
  line(c, p, 64, 78, 64, 48)
end

shapes.person = function(c, p)
  c.drawCircle(48, 36, 14, p)
  arc(c, p, 24, 54, 72, 96, 180, 180)
end

shapes.plus = function(c, p)
  line(c, p, 48, 24, 48, 72)
  line(c, p, 24, 48, 72, 48)
end

shapes.minus = function(c, p)
  line(c, p, 24, 48, 72, 48)
end

shapes.chevron_left = function(c, p)
  stroke(c, p, { 58, 26, 34, 48, 58, 70 })
end

shapes.chevron_right = function(c, p)
  stroke(c, p, { 38, 26, 62, 48, 38, 70 })
end

shapes.chevron_down = function(c, p)
  stroke(c, p, { 28, 40, 48, 62, 68, 40 })
end

shapes.chevron_up = function(c, p)
  stroke(c, p, { 28, 58, 48, 36, 68, 58 })
end

shapes.close = function(c, p)
  line(c, p, 30, 30, 66, 66)
  line(c, p, 66, 30, 30, 66)
end

shapes.edit = function(c, p)
  stroke(c, p, { 26, 70, 30, 54, 62, 22, 74, 34, 42, 66, 26, 70 })
end

shapes.trash = function(c, p)
  line(c, p, 22, 32, 74, 32)
  line(c, p, 40, 32, 40, 22)
  line(c, p, 56, 32, 56, 22)
  stroke(c, p, { 30, 32, 34, 78, 62, 78, 66, 32 })
  line(c, p, 44, 46, 44, 66)
  line(c, p, 52, 46, 52, 66)
end

shapes.bell = function(c, p)
  stroke(c, p, { 30, 64, 34, 44, 48, 26, 62, 44, 66, 64 })
  line(c, p, 24, 64, 72, 64)
  arc(c, p, 40, 64, 56, 80, 0, 180)
  line(c, p, 48, 20, 48, 26)
end

shapes.clock = function(c, p)
  c.drawCircle(48, 48, 30, p)
  line(c, p, 48, 30, 48, 50)
  line(c, p, 48, 50, 62, 58)
end

shapes.timer = function(c, p)
  c.drawCircle(48, 54, 26, p)
  line(c, p, 48, 54, 48, 40)
  line(c, p, 48, 54, 58, 60)
  line(c, p, 36, 18, 60, 18)
  line(c, p, 48, 18, 48, 26)
end

shapes.play = function(c, p, fill)
  polygon(c, fill, { 38, 26, 72, 48, 38, 70 })
end

shapes.pause = function(c, p, fill)
  roundRect(c, fill, 32, 26, 44, 70, 4)
  roundRect(c, fill, 52, 26, 64, 70, 4)
end

shapes.stop = function(c, p, fill)
  roundRect(c, fill, 32, 32, 64, 64, 8)
end

shapes.book = function(c, p)
  stroke(c, p, { 24, 26, 24, 74, 46, 74, 48, 68, 50, 74, 72, 74, 72, 26 })
  line(c, p, 48, 32, 48, 68)
  line(c, p, 32, 40, 42, 40)
  line(c, p, 54, 40, 64, 40)
end

shapes.target = function(c, p)
  c.drawCircle(48, 48, 28, p)
  c.drawCircle(48, 48, 16, p)
  c.drawCircle(48, 48, 4, p)
end

shapes.flag = function(c, p)
  line(c, p, 30, 20, 30, 78)
  stroke(c, p, { 30, 26, 62, 34, 30, 46 })
end

shapes.star = function(c, p, fill)
  polygon(c, fill, { 48, 22, 57, 42, 78, 44, 62, 58, 67, 78, 48, 68, 29, 78, 34, 58, 18, 44, 39, 42 })
end

shapes.heart = function(c, p)
  local path = Path()
  path.moveTo(48, 74)
  path.cubicTo(18, 54, 22, 28, 40, 26)
  path.cubicTo(46, 26, 48, 32, 48, 36)
  path.cubicTo(48, 32, 50, 26, 56, 26)
  path.cubicTo(74, 28, 78, 54, 48, 74)
  c.drawPath(path, p)
end

shapes.sun = function(c, p)
  c.drawCircle(48, 48, 16, p)
  for i = 0, 7 do
    local angle = math.rad(i * 45)
    local x1 = 48 + math.cos(angle) * 26
    local y1 = 48 + math.sin(angle) * 26
    local x2 = 48 + math.cos(angle) * 34
    local y2 = 48 + math.sin(angle) * 34
    line(c, p, x1, y1, x2, y2)
  end
end

shapes.moon = function(c, p)
  arc(c, p, 24, 20, 76, 76, 60, 240)
  arc(c, p, 44, 22, 88, 74, 120, 150)
end

shapes.settings = function(c, p)
  c.drawCircle(48, 48, 12, p)
  c.drawCircle(48, 48, 26, p)
  for i = 0, 5 do
    local angle = math.rad(i * 60 + 30)
    line(c, p,
      48 + math.cos(angle) * 26, 48 + math.sin(angle) * 26,
      48 + math.cos(angle) * 34, 48 + math.sin(angle) * 34)
  end
end

shapes.repeat = function(c, p)
  arc(c, p, 24, 28, 72, 68, 200, 220)
  stroke(c, p, { 62, 20, 72, 30, 62, 38 })
  arc(c, p, 24, 28, 72, 68, 20, 220)
  stroke(c, p, { 34, 76, 24, 66, 34, 58 })
end

shapes.water = function(c, p)
  local path = Path()
  path.moveTo(48, 22)
  path.cubicTo(30, 46, 28, 58, 34, 68)
  path.cubicTo(40, 78, 56, 78, 62, 68)
  path.cubicTo(68, 58, 66, 46, 48, 22)
  c.drawPath(path, p)
end

shapes.leaf = function(c, p)
  local path = Path()
  path.moveTo(28, 70)
  path.cubicTo(30, 34, 56, 24, 74, 26)
  path.cubicTo(72, 56, 54, 74, 28, 70)
  c.drawPath(path, p)
  line(c, p, 30, 68, 56, 42)
end

shapes.pen = function(c, p)
  stroke(c, p, { 24, 72, 26, 60, 64, 22, 74, 32, 36, 70, 24, 72 })
end

shapes.music = function(c, p)
  line(c, p, 40, 66, 40, 30)
  line(c, p, 40, 30, 70, 24)
  line(c, p, 70, 24, 70, 58)
  c.drawCircle(33, 68, 8, p)
  c.drawCircle(63, 60, 8, p)
end

shapes.code = function(c, p)
  stroke(c, p, { 36, 32, 20, 48, 36, 64 })
  stroke(c, p, { 60, 32, 76, 48, 60, 64 })
  line(c, p, 54, 26, 42, 70)
end

shapes.run = function(c, p)
  c.drawCircle(58, 28, 7, p)
  stroke(c, p, { 52, 40, 40, 54, 46, 66 })
  stroke(c, p, { 52, 40, 64, 52, 60, 70 })
  stroke(c, p, { 46, 52, 30, 62 })
  stroke(c, p, { 46, 52, 58, 62 })
end

shapes.fire = function(c, p)
  local path = Path()
  path.moveTo(48, 66)
  path.cubicTo(30, 66, 30, 50, 40, 40)
  path.cubicTo(48, 32, 46, 24, 52, 22)
  path.cubicTo(58, 34, 70, 44, 64, 58)
  path.cubicTo(60, 66, 52, 66, 48, 66)
  c.drawPath(path, p)
end

shapes.more = function(c, p, fill)
  c.drawCircle(30, 48, 5, fill)
  c.drawCircle(48, 48, 5, fill)
  c.drawCircle(66, 48, 5, fill)
end

shapes.search = function(c, p)
  c.drawCircle(44, 44, 20, p)
  line(c, p, 58, 58, 74, 74)
end

shapes.info = function(c, p)
  c.drawCircle(48, 48, 30, p)
  line(c, p, 48, 44, 48, 66)
  c.drawCircle(48, 34, 2, p)
end

shapes.backup = function(c, p)
  arc(c, p, 24, 26, 72, 66, 200, 200)
  stroke(c, p, { 62, 22, 72, 32, 60, 40 })
  line(c, p, 48, 46, 48, 76)
  stroke(c, p, { 36, 62, 48, 76, 60, 62 })
end

shapes.export = function(c, p)
  line(c, p, 48, 22, 48, 62)
  stroke(c, p, { 34, 36, 48, 22, 62, 36 })
  stroke(c, p, { 28, 62, 28, 76, 68, 76, 68, 62 })
end

shapes.download = function(c, p)
  line(c, p, 48, 24, 48, 62)
  stroke(c, p, { 34, 50, 48, 64, 62, 50 })
  stroke(c, p, { 28, 68, 28, 78, 68, 78, 68, 68 })
end

shapes.filter = function(c, p)
  stroke(c, p, { 22, 28, 74, 28, 54, 52, 54, 74, 42, 66, 42, 52, 22, 28 })
end

shapes.arrow_forward = function(c, p)
  line(c, p, 26, 48, 68, 48)
  stroke(c, p, { 54, 34, 68, 48, 54, 62 })
end

shapes.dot = function(c, p, fill)
  c.drawCircle(48, 48, 12, fill)
end

shapes.square = function(c, p, fill)
  roundRect(c, fill, 30, 30, 66, 66, 8)
end

shapes.list = function(c, p)
  line(c, p, 34, 32, 76, 32)
  line(c, p, 34, 48, 76, 48)
  line(c, p, 34, 64, 76, 64)
  c.drawCircle(24, 32, 3, p)
  c.drawCircle(24, 48, 3, p)
  c.drawCircle(24, 64, 3, p)
end

-- ---------- 公共接口 ----------

local function build(name, color, size)
  local bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
  local canvas = Canvas(bitmap)
  local scale = size / BASE

  local strokePaint = Paint()
  strokePaint.setAntiAlias(true)
  strokePaint.setColor(color)
  strokePaint.setStyle(Paint.Style.STROKE)
  strokePaint.setStrokeWidth(7 * scale)
  strokePaint.setStrokeCap(Paint.Cap.ROUND)
  strokePaint.setStrokeJoin(Paint.Join.ROUND)

  local fillPaint = Paint()
  fillPaint.setAntiAlias(true)
  fillPaint.setColor(color)
  fillPaint.setStyle(Paint.Style.FILL)

  canvas.scale(scale, scale)

  local shape = shapes[name] or shapes.dot
  local ok, err = pcall(shape, canvas, strokePaint, fillPaint, BASE)
  if not ok then
    print("icon draw failed: " .. tostring(name) .. " " .. tostring(err))
    canvas.drawCircle(BASE / 2, BASE / 2, BASE / 4, fillPaint)
  end

  local drawable = BitmapDrawable(activity.getResources(), bitmap)
  drawable.setBounds(0, 0, size, size)
  return drawable
end

-- 获取图标 Drawable。color 省略时使用主题 onSurfaceVariant。
function M.get(name, color, size)
  local tint = color
  if not tint then
    tint = require("config.theme").colors().onSurfaceVariant
  end
  local actualSize = size or 96
  local key = tostring(name) .. "|" .. tostring(tint) .. "|" .. actualSize
  local cached = cache[key]
  if cached then return cached end
  local drawable = build(name, tint, actualSize)
  cache[key] = drawable
  return drawable
end

function M.has(name)
  return shapes[name] ~= nil
end

-- 清除缓存（主题色变化后调用）
function M.clearCache()
  cache = {}
end

M.names = {
  "home", "calendar", "today", "check", "check_bare", "chart", "person", "plus", "minus",
  "chevron_left", "chevron_right", "chevron_down", "chevron_up", "close", "edit", "trash",
  "bell", "clock", "timer", "play", "pause", "stop", "book", "target", "flag", "star",
  "heart", "sun", "moon", "settings", "repeat", "water", "leaf", "pen", "music", "code",
  "run", "fire", "more", "search", "info", "backup", "export", "download", "filter",
  "arrow_forward", "list", "dot", "square",
}

return M
