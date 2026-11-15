-- 颜色工具：Android 的颜色是有符号 32 位 int。
-- 直接写 0xFF6750A4 会被 LuaJ++ 当作 long 并绑定到 setColor(long) 而抛异常，
-- 因此统一用本模块把 #RRGGBB / #AARRGGBB 转换为 signed int。
local bindClass = luajava.bindClass
local Color = bindClass "android.graphics.Color"

local M = {}
local cache = {}

local function parse(hex)
  local value = cache[hex]
  if value then return value end
  local text = hex
  if text:sub(1, 1) ~= "#" then text = "#" .. text end
  local color = Color.parseColor(text)
  cache[hex] = color
  return color
end

M.parse = parse
M.C = parse

-- 取主题色的整数形式（供 Canvas / setTint 使用）
function M.themeColor(path)
  local ok, value = pcall(function()
    local node = activity.themeUtil
    for part in path:gmatch("[^.]+") do
      node = node[part]
    end
    return node
  end)
  if ok and type(value) == "number" then return value end
  return parse("#6750A4")
end

-- 在给定颜色上叠加透明度（0..255）
function M.withAlpha(color, alpha)
  local a = math.max(0, math.min(255, math.floor(alpha)))
  local rgb = color & 0x00FFFFFF
  return a * 0x1000000 + rgb
end

function M.mix(colorA, colorB, ratio)
  local r = math.floor(Color.red(colorA) * (1 - ratio) + Color.red(colorB) * ratio)
  local g = math.floor(Color.green(colorA) * (1 - ratio) + Color.green(colorB) * ratio)
  local b = math.floor(Color.blue(colorA) * (1 - ratio) + Color.blue(colorB) * ratio)
  return Color.rgb(r, g, b)
end

-- 返回适合放在该颜色上的文字颜色（主题无关的黑/白）
function M.onColor(color)
  if activity.isColorLight(color) then
    return parse("#1A1A1A")
  end
  return parse("#FFFFFF")
end

function M.toHex(color)
  return string.format("#%02X%02X%02X", Color.red(color), Color.green(color), Color.blue(color))
end

return M
