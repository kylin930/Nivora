-- 备份与恢复：JSON 交换格式，导入前校验，导入使用事务并保留原数据副本
local bindClass = luajava.bindClass
local LuaFileUtil = luajava.kotlinObject("com.nekolaska.io.LuaFileUtil")
local File = bindClass "java.io.File"

local dateUtils = require "utils.date_utils"
local jsonUtils = require "utils.json_utils"

local M = {}

local TABLES = {
  "categories", "habits", "habit_records", "schedules", "schedule_exceptions",
  "todos", "todo_subtasks", "goals", "goal_milestones", "journals",
  "focus_records", "countdowns", "app_settings",
}

local Service = {}
Service.__index = Service

function Service:backupDir()
  local dir = File(activity.getLuaDir("backups"))
  if not dir.exists() then pcall(function() dir.mkdirs() end) end
  return dir
end

-- 导出为 Lua 表
function Service:collect()
  local data = {
    format_version = require("config.constants").BACKUP_FORMAT,
    app = require("config.constants").APP_NAME,
    app_version = require("config.constants").VERSION,
    exported_at = dateUtils.isoNow(),
    tables = {},
  }
  for _, name in ipairs(TABLES) do
    local rows = self.app.db:query("SELECT * FROM " .. name)
    data.tables[name] = rows or {}
  end
  return data
end

function Service:toJson()
  local data = self:collect()
  local ok, text = pcall(function() return json.encode(data) end)
  if not ok or not text then return nil, "生成备份 JSON 失败" end
  return tostring(text), data
end

function Service:defaultFileName()
  return require("config.constants").BACKUP_PREFIX .. "-" .. dateUtils.fileStamp() .. ".json"
end

-- 本地备份（应用私有目录），返回路径
function Service:saveLocal()
  local text, err = self:toJson()
  if not text then return nil, err end
  local file = File(self:backupDir(), self:defaultFileName())
  local ok, writeErr = pcall(function()
    LuaFileUtil.writeOrCreate(file.getAbsolutePath(), text)
  end)
  if not ok then return nil, tostring(writeErr) end
  return file.getAbsolutePath()
end

function Service:listLocal()
  local dir = self:backupDir()
  local list = {}
  local ok, meta = pcall(function() return LuaFileUtil.listMeta(dir.getAbsolutePath()) end)
  if not ok or not meta then return list end
  for i = 0, #meta - 1 do
    local item = meta[i]
    local name = item.name
    if name and name:match("%.json$") then
      list[#list + 1] = {
        name = name,
        path = File(dir, name).getAbsolutePath(),
        mtime = item.mtime,
        size = item.size,
      }
    end
  end
  table.sort(list, function(a, b) return (a.mtime or 0) > (b.mtime or 0) end)
  return list
end

function Service:readLocal(path)
  local text = LuaFileUtil.read(path)
  if not text or text == "" then return nil, "文件为空或无法读取" end
  return text
end

-- 校验备份内容结构
function Service:validate(text)
  if type(text) ~= "string" or text == "" then return nil, "备份内容为空" end
  local ok, data = pcall(function() return json.decode(text) end)
  if not ok or type(data) ~= "table" then return nil, "不是有效的 JSON 备份文件" end
  if data.app ~= require("config.constants").APP_NAME then
    return nil, "备份文件不属于 Nivora"
  end
  local version = tonumber(data.format_version)
  if not version then return nil, "备份文件缺少格式版本号" end
  if version > require("config.constants").BACKUP_FORMAT then
    return nil, "备份文件来自更高版本，请先升级应用"
  end
  if type(data.tables) ~= "table" then return nil, "备份文件缺少数据表" end
  return data
end

-- 导入：先对现有数据做一次本地快照，再事务化覆盖
function Service:import(text)
  local data, err = self:validate(text)
  if not data then return nil, err end

  local snapshotPath = self:saveLocal()
  local ok, importErr = self.app.db:transaction(function()
    self.app.settings:set("last_restore_snapshot", snapshotPath or "")
    for _, name in ipairs(TABLES) do
      self.app.db.db.execSQL("DELETE FROM " .. name)
      local rows = data.tables[name] or {}
      for _, row in ipairs(rows) do
        self.app.db:insert(name, row)
      end
    end
    return true
  end)
  if not ok then
    return nil, "导入失败，原有数据已回滚：" .. tostring(importErr)
  end

  self.app.settings:clearCache()
  self.app:reloadRepositories()
  return true, snapshotPath
end

-- 通过系统文件选择器导出
function Service:exportWithPicker(onDone)
  local text, err = self:toJson()
  if not text then
    if onDone then onDone(false, err) end
    return
  end
  local ok, pickErr = pcall(function()
    saf.save(self:defaultFileName(), text, function(result)
      if onDone then onDone(result == true, result == true and nil or "保存已取消") end
    end)
  end)
  if not ok then
    if onDone then onDone(false, tostring(pickErr)) end
  end
end

-- 通过系统文件选择器导入
function Service:importWithPicker(onDone)
  local ok, pickErr = pcall(function()
    saf.read(function(content)
      if not content then
        if onDone then onDone(false, "未选择文件") end
        return
      end
      local success, message = self:import(content)
      if onDone then onDone(success == true, message) end
    end)
  end)
  if not ok then
    if onDone then onDone(false, tostring(pickErr)) end
  end
end

function Service:importLocal(path, onDone)
  local text, err = self:readLocal(path)
  if not text then
    if onDone then onDone(false, err) end
    return
  end
  local success, message = self:import(text)
  if onDone then onDone(success == true, message) end
end

function Service:clearAll()
  local snapshotPath = self:saveLocal()
  local ok, err = self.app.db:transaction(function()
    for _, name in ipairs(TABLES) do
      self.app.db.db.execSQL("DELETE FROM " .. name)
    end
    return true
  end)
  if not ok then return nil, err end
  self.app.settings:clearCache()
  self.app:reloadRepositories()
  return true, snapshotPath
end

function M.new(app)
  return setmetatable({ app = app }, Service)
end

M.TABLES = TABLES

return M
