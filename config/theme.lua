-- 主题：应用夜间模式与动态取色，并集中提供颜色 token
-- 页面里的布局颜色写 ?attr/…；Canvas 与图标需要 int 时读 M.colors()
local bindClass = luajava.bindClass
local colorUtils = require "utils.color_utils"

local M = {}

M.ATTR = {
  surface = "?attr/colorSurface",
  onSurface = "?attr/colorOnSurface",
  surfaceContainer = "?attr/colorSurfaceContainer",
  surfaceContainerLow = "?attr/colorSurfaceContainerLow",
  surfaceContainerHigh = "?attr/colorSurfaceContainerHigh",
  surfaceVariant = "?attr/colorSurfaceVariant",
  onSurfaceVariant = "?attr/colorOnSurfaceVariant",
  primary = "?attr/colorPrimary",
  onPrimary = "?attr/colorOnPrimary",
  primaryContainer = "?attr/colorPrimaryContainer",
  onPrimaryContainer = "?attr/colorOnPrimaryContainer",
  secondaryContainer = "?attr/colorSecondaryContainer",
  onSecondaryContainer = "?attr/colorOnSecondaryContainer",
  tertiary = "?attr/colorTertiary",
  error = "?attr/colorError",
  outline = "?attr/colorOutline",
  outlineVariant = "?attr/colorOutlineVariant",
  background = "?attr/colorBackground",
}

-- 在 setContentView 之前调用
function M.apply(settings)
  local AppCompatDelegate = bindClass "androidx.appcompat.app.AppCompatDelegate"
  local mode = settings:get("theme_mode", "system")
  local target = AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM
  if mode == "light" then
    target = AppCompatDelegate.MODE_NIGHT_NO
  elseif mode == "dark" then
    target = AppCompatDelegate.MODE_NIGHT_YES
  end
  pcall(function() AppCompatDelegate.setDefaultNightMode(target) end)

  local seed = settings:get("theme_seed", "")
  if seed and seed ~= "" then
    pcall(function() activity.dynamicColor(colorUtils.parse(seed)) end)
  else
    pcall(function() activity.dynamicColor() end)
  end
end

local function readThemeUtil()
  local ok, util = pcall(function() return activity.themeUtil end)
  if ok and util then return util end
  return nil
end

-- 运行时颜色：Canvas、图标着色、动态背景都用它
function M.colors()
  local util = readThemeUtil()
  local function pick(path, fallbackHex)
    if not util then return colorUtils.parse(fallbackHex) end
    local ok, value = pcall(function()
      local node = util
      for part in path:gmatch("[^.]+") do
        node = node[part]
      end
      return node
    end)
    if ok and type(value) == "number" then return value end
    return colorUtils.parse(fallbackHex)
  end

  return {
    primary = pick("primary.main", "#6750A4"),
    onPrimary = pick("primary.on", "#FFFFFF"),
    primaryContainer = pick("primary.container", "#EADDFF"),
    onPrimaryContainer = pick("primary.onContainer", "#21005D"),
    secondaryContainer = pick("secondary.container", "#E8DEF8"),
    onSecondaryContainer = pick("secondary.onContainer", "#1D192B"),
    tertiary = pick("tertiary.main", "#7D5260"),
    tertiaryContainer = pick("tertiary.container", "#FFD8E4"),
    error = pick("error.main", "#B3261E"),
    surface = pick("surface.main", "#FEF7FF"),
    onSurface = pick("surface.on", "#1D1B20"),
    surfaceVariant = pick("surface.variant", "#E7E0EC"),
    onSurfaceVariant = pick("surface.onVariant", "#49454F"),
    surfaceContainer = pick("surface.container", "#F3EDF7"),
    surfaceContainerLow = pick("surface.containerLow", "#F7F2FA"),
    surfaceContainerHigh = pick("surface.containerHigh", "#ECE6F0"),
    outline = pick("outline.main", "#79747E"),
    outlineVariant = pick("outline.variant", "#CAC4D0"),
  }
end

function M.isNight()
  local ok, value = pcall(function() return activity.isNightMode() end)
  return ok and value == true
end

-- 主题色切换：写设置后重建 Activity（由调用方负责提示）
function M.setMode(settings, mode)
  settings:set("theme_mode", mode)
  local AppCompatDelegate = bindClass "androidx.appcompat.app.AppCompatDelegate"
  local target = AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM
  if mode == "light" then
    target = AppCompatDelegate.MODE_NIGHT_NO
  elseif mode == "dark" then
    target = AppCompatDelegate.MODE_NIGHT_YES
  end
  AppCompatDelegate.setDefaultNightMode(target)
end

function M.setSeed(settings, hex)
  settings:set("theme_seed", hex or "")
end

return M
