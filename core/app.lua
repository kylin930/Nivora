-- 应用组装根：打开数据库、构建仓储与服务，供页面统一取用
local M = {}

local bindClass = luajava.bindClass
local File = bindClass "java.io.File"

local constants = require "config.constants"
local database = require "core.database"
local migrations = require "core.migrations"
local eventBus = require "core.event_bus"

local SettingsRepo = require "data.repositories.settings_repo"
local CategoriesRepo = require "data.repositories.categories_repo"
local HabitsRepo = require "data.repositories.habits_repo"
local SchedulesRepo = require "data.repositories.schedules_repo"
local TodosRepo = require "data.repositories.todos_repo"
local GoalsRepo = require "data.repositories.goals_repo"
local JournalsRepo = require "data.repositories.journals_repo"
local CountdownsRepo = require "data.repositories.countdowns_repo"
local FocusRepo = require "data.repositories.focus_repo"
local RemindersRepo = require "data.repositories.reminders_repo"

local Notifier = require "services.notification.notifier"
local ReminderService = require "services.reminder.reminder_service"
local FocusTimer = require "services.focus_timer.focus_timer"
local BackupService = require "services.backup.backup_service"

local App = {}
App.__index = App

function App:reloadRepositories()
  local weekStart = self.settings:weekStart()
  self.habits = HabitsRepo.new(self.db, weekStart)
  self.schedules = SchedulesRepo.new(self.db, weekStart)
  self.todos = TodosRepo.new(self.db)
  self.goals = GoalsRepo.new(self.db)
  self.journals = JournalsRepo.new(self.db)
  self.countdowns = CountdownsRepo.new(self.db)
  self.focusRepo = FocusRepo.new(self.db)
  self.categories = CategoriesRepo.new(self.db)
  self.reminders = RemindersRepo.new(self.db)
end

-- 数据变更通知：页面订阅后自行刷新
function App:changed(kind)
  eventBus.emit(kind or eventBus.EVENTS.DATA_CHANGED)
  eventBus.emit(eventBus.EVENTS.DATA_CHANGED)
end

function App:warn(message)
  self.warnings[#self.warnings + 1] = tostring(message)
end

function App:dispose()
  if self.remindersService then pcall(function() self.remindersService:unregister() end) end
  if self.db then pcall(function() self.db:close() end) end
  eventBus.clear()
end

function M.create()
  local dbFile = File(activity.getLuaDir(), constants.DB_NAME)
  local isNew = not dbFile.exists()
  local db = database.open(dbFile, migrations.DB_VERSION, migrations.create, migrations.upgrade)
  local app = setmetatable({
    db = db,
    warnings = {},
    isNew = isNew,
  }, App)

  -- 旧版本升级：getVersion 落后时逐级迁移（探针中验证过 onUpgrade 回调可用）
  local version = db.db.getVersion()
  if version == 0 and not isNew then
    migrations.create(db.db)
    db.db.setVersion(migrations.DB_VERSION)
  elseif version < migrations.DB_VERSION then
    local ok, err = pcall(function()
      migrations.upgrade(db.db, version, migrations.DB_VERSION)
      db.db.setVersion(migrations.DB_VERSION)
    end)
    if not ok then app:warn("数据库升级失败：" .. tostring(err)) end
  end

  app.settings = SettingsRepo.new(db)
  app:reloadRepositories()

  app.notifier = Notifier.new()
  app.remindersService = ReminderService.new(app)
  app.focusTimer = FocusTimer.new(app)
  app.backup = BackupService.new(app)

  return app
end

M.App = App

return M
