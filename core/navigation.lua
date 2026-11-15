-- 页面导航：底部五个主标签 + 站内页面栈（子页面覆盖内容区、隐藏底栏）
local bindClass = luajava.bindClass
local BottomNavigationView = bindClass "com.google.android.material.bottomnavigation.BottomNavigationView"

local icons = require "components.icons"
local theme = require "config.theme"

local M = {}

local Navigation = {}
Navigation.__index = Navigation

-- ---------- 过渡动效（MD3） ----------
-- 子页面推入 / 返回：shared axis X（位移 + 淡入淡出）
-- 切换底部标签：fade through（旧页缩退、新页浮入）
-- 系统把「动画时长缩放」设为 0 时，全部退化为直接切换

local DURATION = {
  axisIn = 300,
  axisOut = 200,
  tabOut = 90,
  tabIn = 210,
  nav = 200,
}

local AXIS_OFFSET_DP = 24
local SETTLE_MS = 40   -- 动画结束后留一点余量再清理旧视图

local interpolators = {}

local function interpolator(kind)
  local cached = interpolators[kind]
  if cached then return cached end
  local curves = {
    enter = { 0.05, 0.7, 0.1, 1 },   -- decelerate
    exit = { 0.3, 0, 0.8, 0.15 },    -- accelerate
    emphasized = { 0.2, 0, 0, 1 },
  }
  local curve = curves[kind] or curves.emphasized
  local ok, value = pcall(function()
    local PathInterpolator = bindClass "android.view.animation.PathInterpolator"
    return PathInterpolator(curve[1], curve[2], curve[3], curve[4])
  end)
  if not ok or not value then
    local DecelerateInterpolator = bindClass "android.view.animation.DecelerateInterpolator"
    value = DecelerateInterpolator()
  end
  interpolators[kind] = value
  return value
end

-- dp → px；dpToPx 不可用时按 density 3 兜底
local function dp(value)
  local ok, result = pcall(function() return activity.dpToPx(value) end)
  if ok then
    local number = tonumber(result)
    if number then return number end
  end
  return value * 3
end

-- 尊重系统的「移除动画」辅助设置
local function animationsDisabled()
  local ok, scale = pcall(function()
    local SettingsGlobal = bindClass "android.provider.Settings$Global"
    return SettingsGlobal.getFloat(activity.getContentResolver(), "animator_duration_scale", 1)
  end)
  return ok and tonumber(scale) == 0
end

-- LuaJ++ 的 Java 对象包装不能直接用 == 判断是否同一实例
local function sameView(a, b)
  if a == nil or b == nil then return a == nil and b == nil end
  local ok, eq = pcall(function() return a.equals(b) end)
  return ok and eq == true
end

-- 页面视图会被缓存复用，收尾时必须把动画属性复位
local function resetView(view)
  if not view then return end
  pcall(function() view.animate().cancel() end)
  pcall(function() view.setAlpha(1) end)
  pcall(function() view.setTranslationX(0) end)
  pcall(function() view.setTranslationY(0) end)
  pcall(function() view.setScaleX(1) end)
  pcall(function() view.setScaleY(1) end)
end

local function isAttached(view)
  local ok, parent = pcall(function() return view.getParent() end)
  return ok and parent ~= nil
end

-- 统一入口：先设起始状态再启动；失败只记录，不让导航崩溃
local function animate(view, duration, curve, apply)
  if not view then return end
  local ok, err = pcall(function()
    local animator = view.animate()
    animator.setDuration(duration)
    animator.setInterpolator(interpolator(curve))
    apply(animator)
    animator.start()
  end)
  if not ok then print("[Nivora] 过渡动画失败：" .. tostring(err)) end
end

-- tabs: { { id, title, icon, page }, ... }
function Navigation:buildMenu()
  local menu = self.navView.getMenu()
  menu.clear()
  for index, tab in ipairs(self.tabs) do
    local item = menu.add(0, tab.id, index - 1, tab.title)
    local icon = icons.get(tab.icon, theme.colors().onSurfaceVariant, 96)
    if icon then item.setIcon(icon) end
  end
end

function Navigation:createPage(pageSpec, params)
  local page = pageSpec.create({
    app = self.app,
    nav = self,
    params = params or {},
    tabId = self.currentTab,
  })
  return page
end

-- 清掉既不是当前页也不是上一页的残留视图（快速连点时的中间态）
function Navigation:pruneViews(keepA, keepB)
  local container = self.container
  local count = 0
  pcall(function() count = container.getChildCount() end)
  for index = count - 1, 0, -1 do
    local ok, child = pcall(function() return container.getChildAt(index) end)
    if ok and child and not sameView(child, keepA) and not sameView(child, keepB) then
      resetView(child)
      pcall(function() container.removeViewAt(index) end)
    end
  end
end

function Navigation:detachView(view)
  if not view then return end
  if isAttached(view) then pcall(function() self.container.removeView(view) end) end
  resetView(view)
end

-- kind：nil / "none" 直接切换；"tab" 用 fade through；"push" / "pop" 用 shared axis X
function Navigation:showPage(page, kind)
  local container = self.container
  local newView = page and page.view or nil

  if not newView then
    self.motionSeq = (self.motionSeq or 0) + 1
    container.removeAllViews()
    self.activeView = nil
    return
  end

  local oldView = self.activeView
  self.motionSeq = (self.motionSeq or 0) + 1
  local seq = self.motionSeq

  if sameView(oldView, newView) then
    self:pruneViews(newView, nil)
    resetView(newView)
    if not isAttached(newView) then container.addView(newView) end
    return
  end

  self.activeView = newView
  self:pruneViews(oldView, newView)
  resetView(newView)
  if not isAttached(newView) then container.addView(newView) end

  if not oldView or not kind or kind == "none" or self.reduceMotion then
    if oldView then self:detachView(oldView) end
    return
  end

  if kind == "tab" then
    -- fade through：旧页 90ms 缩退，新页接着 210ms 浮入
    pcall(function()
      newView.setAlpha(0)
      newView.setScaleX(0.92)
      newView.setScaleY(0.92)
    end)
    animate(oldView, DURATION.tabOut, "exit", function(animator)
      animator.alpha(0)
      animator.scaleX(0.92)
      animator.scaleY(0.92)
    end)
    activity.delay(DURATION.tabOut, function()
      if self.motionSeq ~= seq then return end
      animate(newView, DURATION.tabIn, "enter", function(animator)
        animator.alpha(1)
        animator.scaleX(1)
        animator.scaleY(1)
      end)
      activity.delay(DURATION.tabIn + SETTLE_MS, function()
        if self.motionSeq ~= seq then return end
        self:detachView(oldView)
      end)
    end)
    return
  end

  -- push / pop：进入方向与退出方向相反
  local distance = dp(AXIS_OFFSET_DP)
  local enterFrom, exitTo = distance, -distance
  if kind == "pop" then enterFrom, exitTo = -distance, distance end

  pcall(function()
    newView.setAlpha(0)
    newView.setTranslationX(enterFrom)
  end)
  animate(newView, DURATION.axisIn, "enter", function(animator)
    animator.alpha(1)
    animator.translationX(0)
  end)
  animate(oldView, DURATION.axisOut, "exit", function(animator)
    animator.alpha(0)
    animator.translationX(exitTo)
  end)
  activity.delay(DURATION.axisIn + SETTLE_MS, function()
    if self.motionSeq ~= seq then return end
    self:detachView(oldView)
  end)
end

-- 底栏显隐与页面过渡同步，避免硬跳变
function Navigation:setNavVisible(visible)
  local navView = self.navView
  if not navView then return end
  self.navSeq = (self.navSeq or 0) + 1
  local seq = self.navSeq

  if visible then
    local shown = false
    pcall(function()
      shown = navView.getVisibility() == 0 and navView.getAlpha() >= 1
    end)
    if shown then return end
    pcall(function() navView.setVisibility(0) end)
    pcall(function() navView.setAlpha(0) end)
    animate(navView, DURATION.nav, "enter", function(animator)
      animator.alpha(1)
    end)
    return
  end

  animate(navView, DURATION.nav, "exit", function(animator)
    animator.alpha(0)
  end)
  activity.delay(DURATION.nav + SETTLE_MS, function()
    if self.navSeq ~= seq then return end
    pcall(function()
      navView.setVisibility(8)
      navView.setAlpha(1)
    end)
  end)
end

-- 页面回调统一保护：出错只记录，不让整个界面崩溃
local function safeCall(page, method)
  if not page or not page[method] then return end
  local ok, err = pcall(page[method], page)
  if not ok then
    print("[Nivora] 页面 " .. tostring(method) .. " 失败：" .. tostring(err))
  end
end

function Navigation:setTab(tabId, force)
  if not tabId then return end
  if self.currentTab == tabId and not force and #self.stack == 0 then
    self:refreshCurrent()
    return
  end
  -- 切走时清理子页面
  while #self.stack > 0 do
    local page = table.remove(self.stack)
    if page and page.destroy then pcall(page.destroy, page) end
  end

  local previousTab = self.currentTab
  self.currentTab = tabId
  self.suppress = true
  pcall(function() self.navView.setSelectedItemId(tabId) end)
  self.suppress = false

  local page = self.tabPages[tabId]
  if not page then
    local spec = self.tabModules[tabId]
    if not spec then return end
    page = self:createPage(spec, {})
    self.tabPages[tabId] = page
  end
  self:showPage(page, previousTab and "tab" or "none")
  self:setNavVisible(true)
  safeCall(page, "onShow")
end

function Navigation:push(pageSpec, params)
  local page = self:createPage(pageSpec, params)
  self.stack[#self.stack + 1] = page
  self:showPage(page, "push")
  self:setNavVisible(false)
  safeCall(page, "onShow")
  return page
end

function Navigation:topPage()
  local top = self.stack[#self.stack]
  if top then return top end
  return self.tabPages[self.currentTab]
end

function Navigation:pop()
  if #self.stack == 0 then return false end
  local page = table.remove(self.stack)
  if page and page.destroy then pcall(page.destroy, page) end

  local top = self.stack[#self.stack]
  if top then
    self:showPage(top, "pop")
    self:setNavVisible(false)
    safeCall(top, "onShow")
  else
    local rootPage = self.tabPages[self.currentTab]
    if rootPage then
      self:showPage(rootPage, "pop")
      self:setNavVisible(true)
      safeCall(rootPage, "onShow")
    end
  end
  return true
end

-- 返回键：由 main.lua 的返回回调调用
function Navigation:handleBack()
  local top = self.stack[#self.stack]
  if top and top.onBack then
    local handled = top:onBack()
    if handled then return true end
  end
  if #self.stack > 0 then
    return self:pop()
  end
  if self.currentTab ~= self.tabs[1].id then
    self:setTab(self.tabs[1].id)
    return true
  end
  return false
end

function Navigation:refreshCurrent()
  safeCall(self:topPage(), "refresh")
end

function Navigation:refreshAllTabs()
  for _, page in pairs(self.tabPages) do
    safeCall(page, "refresh")
  end
end

function Navigation:destroy()
  for _, page in pairs(self.tabPages) do
    if page and page.destroy then pcall(page.destroy, page) end
  end
  self.tabPages = {}
  while #self.stack > 0 do
    local page = table.remove(self.stack)
    if page and page.destroy then pcall(page.destroy, page) end
  end
end

function M.new(options)
  local nav = setmetatable({
    app = options.app,
    container = options.container,
    navView = options.navView,
    tabs = options.tabs,
    tabModules = {},
    tabPages = {},
    stack = {},
    currentTab = nil,
    suppress = false,
    activeView = nil,
    motionSeq = 0,
    navSeq = 0,
    reduceMotion = animationsDisabled(),
  }, Navigation)

  for _, tab in ipairs(options.tabs) do
    nav.tabModules[tab.id] = tab.page
  end

  nav:buildMenu()
  nav.navView.setOnItemSelectedListener(BottomNavigationView.OnItemSelectedListener {
    onNavigationItemSelected = function(item)
      if nav.suppress then return true end
      nav:setTab(item.getItemId())
      return true
    end,
  })
  return nav
end

M.Navigation = Navigation

return M
