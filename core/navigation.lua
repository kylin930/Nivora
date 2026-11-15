-- 页面导航：底部五个主标签 + 站内页面栈（子页面覆盖内容区、隐藏底栏）
local bindClass = luajava.bindClass
local BottomNavigationView = bindClass "com.google.android.material.bottomnavigation.BottomNavigationView"

local icons = require "components.icons"
local theme = require "config.theme"

local M = {}

local Navigation = {}
Navigation.__index = Navigation

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

function Navigation:showPage(page)
  self.container.removeAllViews()
  if page and page.view then self.container.addView(page.view) end
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
  self:showPage(page)
  self.navView.setVisibility(0)
  safeCall(page, "onShow")
end

function Navigation:push(pageSpec, params)
  local page = self:createPage(pageSpec, params)
  self.stack[#self.stack + 1] = page
  self:showPage(page)
  self.navView.setVisibility(8)
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
    self:showPage(top)
    self.navView.setVisibility(8)
    safeCall(top, "onShow")
  else
    local rootPage = self.tabPages[self.currentTab]
    if rootPage then
      self:showPage(rootPage)
      self.navView.setVisibility(0)
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
