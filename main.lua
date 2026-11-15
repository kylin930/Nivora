-- Nivora 入口：初始化数据库与服务、应用主题、构建底部导航外壳
local bindClass = luajava.bindClass
local LinearLayout = bindClass "android.widget.LinearLayout"
local FrameLayout = bindClass "android.widget.FrameLayout"
local BottomNavigationView = bindClass "com.google.android.material.bottomnavigation.BottomNavigationView"

local ui = require "components.ui"
local theme = require "config.theme"
local constants = require "config.constants"
local AppModule = require "core.app"
local Navigation = require "core.navigation"
local eventBus = require "core.event_bus"

local app
local nav

local function boot()
  app = AppModule.create()

  -- 主题必须在 setContentView 之前应用
  theme.apply(app.settings)

  local views = {}
  local shell = loadlayout({
    LinearLayout,
    orientation = "vertical",
    layout_width = "match",
    layout_height = "match",
    BackgroundColor = theme.ATTR.surface,
    {
      FrameLayout,
      id = "content",
      layout_width = "match",
      layout_height = "0dp",
      layout_weight = 1,
    },
    {
      BottomNavigationView,
      id = "nav",
      layout_width = "match",
      layout_height = "wrap",
      BackgroundColor = theme.ATTR.surfaceContainer,
    },
  }, views)
  activity.setContentView(shell)

  nav = Navigation.new({
    app = app,
    container = views.content,
    navView = views.nav,
    tabs = {
      { id = 1, title = "首页", icon = "home", page = require "modules.dashboard.page" },
      { id = 2, title = "日程", icon = "calendar", page = require "modules.schedules.page" },
      { id = 3, title = "习惯", icon = "check", page = require "modules.habits.page" },
      { id = 4, title = "统计", icon = "chart", page = require "modules.statistics.page" },
      { id = 5, title = "我的", icon = "person", page = require "modules.profile.page" },
    },
  })

  -- 注册闹钟广播接收器并重排提醒
  app.remindersService:register()
  local okSync, syncErr = pcall(function() app.remindersService:resync() end)
  if not okSync then print("reminder resync failed: " .. tostring(syncErr)) end
  app.remindersService:flushDue()

  -- 专注会话跨进程恢复
  local finished = app.focusTimer:catchUp()
  if finished then
    print("恢复专注会话：" .. tostring(finished.phase) .. " " .. tostring(finished.elapsed))
  end

  -- 启动时提示数据库升级问题
  if #app.warnings > 0 then
    ui.alert("数据提示", table.concat(app.warnings, "\n"))
  end

  nav:setTab(1)
end

boot()

-- 返回键：先交给站内页面栈，其次留在首页时正常退出
activity.addOnBackPressedCallback(function()
  if nav and nav:handleBack() then return end
  activity.finish()
end)

function onResume()
  if not app then return end
  pcall(function()
    app.remindersService:resync()
    app.remindersService:flushDue()
  end)
  local finished = app.focusTimer and app.focusTimer:catchUp()
  if finished and nav then
    eventBus.emit(eventBus.EVENTS.FOCUS_CHANGED)
  end
  if nav then nav:refreshCurrent() end
end

function onDestroy()
  if app then
    if nav then pcall(function() nav:destroy() end) end
    pcall(function() app:dispose() end)
    app = nil
  end
end

function onError(error, message)
  print("Nivora 运行错误：" .. tostring(error) .. " " .. tostring(message))
  return "trace"
end
