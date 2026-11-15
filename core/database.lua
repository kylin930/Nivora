-- SQLite 访问层：连接、参数绑定、查询、事务。
-- 约定（见 AGENTS.md）：
--   * 查询参数一律非 nil，用 String.array 传字符串，依靠列亲和性比较；
--   * 写 NULL 时在 SQL 里写字面量 NULL，或对 compileStatement 显式 bindNull。
local bindClass = luajava.bindClass
local SQLiteDatabase = bindClass "android.database.sqlite.SQLiteDatabase"
local SQLiteOpenHelper = bindClass "android.database.sqlite.SQLiteOpenHelper"
local String = bindClass "java.lang.String"
local File = bindClass "java.io.File"

local Database = {}
Database.__index = Database

local M = {}

local function bindValue(statement, index, value)
  local kind = type(value)
  if kind == "number" then
    if value % 1 == 0 then
      statement.bindLong(index, value)
    else
      statement.bindDouble(index, value)
    end
  elseif kind == "boolean" then
    statement.bindLong(index, value and 1 or 0)
  elseif value == nil then
    statement.bindNull(index)
  else
    statement.bindString(index, tostring(value))
  end
end

local function stringArray(args)
  if not args or #args == 0 then return nil end
  local list = {}
  for i = 1, #args do
    list[i] = tostring(args[i])
  end
  return String.array(list)
end

function Database:exec(sql, args)
  if args and #args > 0 then
    local Object = bindClass "java.lang.Object"
    local values = {}
    for i = 1, #args do values[i] = args[i] end
    self.db.execSQL(sql, Object.array(values))
  else
    self.db.execSQL(sql)
  end
end

-- 行插入：table 里 nil 值写成 SQL 字面量 NULL，其余走参数绑定。
-- ignore=true 时用 INSERT OR IGNORE：唯一约束冲突返回 -1 而不抛异常。
function Database:insert(tableName, row, ignore)
  local columns, marks, values = {}, {}, {}
  for column, value in pairs(row) do
    columns[#columns + 1] = column
    if value == nil then
      marks[#marks + 1] = "NULL"
    else
      marks[#marks + 1] = "?"
      values[#values + 1] = value
    end
  end
  local prefix = ignore and "INSERT OR IGNORE INTO " or "INSERT INTO "
  local sql = prefix .. tableName .. "(" .. table.concat(columns, ",") ..
    ") VALUES(" .. table.concat(marks, ",") .. ")"
  local statement = self.db.compileStatement(sql)
  for i = 1, #values do
    bindValue(statement, i, values[i])
  end
  local id = statement.executeInsert()
  statement.close()
  return id
end

-- 值为 nil 的键在 Lua 表里根本不存在（pairs 不遍历），
-- 因此要把某列清空成 NULL，必须用 nullColumns 显式声明。
function Database:update(tableName, row, whereSql, whereArgs, nullColumns)
  local sets, values = {}, {}
  for column, value in pairs(row) do
    sets[#sets + 1] = column .. " = ?"
    values[#values + 1] = value
  end
  for _, column in ipairs(nullColumns or {}) do
    sets[#sets + 1] = column .. " = NULL"
  end
  if #sets == 0 then return 0 end
  local sql = "UPDATE " .. tableName .. " SET " .. table.concat(sets, ",")
  if whereSql and whereSql ~= "" then sql = sql .. " WHERE " .. whereSql end
  local statement = self.db.compileStatement(sql)
  local index = 1
  for i = 1, #values do
    bindValue(statement, index, values[i])
    index = index + 1
  end
  if whereArgs then
    for i = 1, #whereArgs do
      bindValue(statement, index, whereArgs[i])
      index = index + 1
    end
  end
  local affected = statement.executeUpdateDelete()
  statement.close()
  return affected
end

function Database:delete(tableName, whereSql, whereArgs)
  local sql = "DELETE FROM " .. tableName
  if whereSql and whereSql ~= "" then sql = sql .. " WHERE " .. whereSql end
  if not whereArgs or #whereArgs == 0 then
    self.db.execSQL(sql)
    return true
  end
  local statement = self.db.compileStatement(sql)
  for i = 1, #whereArgs do
    bindValue(statement, i, whereArgs[i])
  end
  local affected = statement.executeUpdateDelete()
  statement.close()
  return affected
end

function Database:query(sql, args)
  local cursor = self.db.rawQuery(sql, stringArray(args))
  local rows = {}
  local ok, err = pcall(function()
    local names = cursor.getColumnNames()
    local count = #names
    while cursor.moveToNext() do
      local row = {}
      for i = 0, count - 1 do
        local name = names[i]
        local kind = cursor.getType(i)
        if kind == 1 then
          row[name] = cursor.getLong(i)
        elseif kind == 2 then
          row[name] = cursor.getDouble(i)
        elseif kind == 3 then
          row[name] = cursor.getString(i)
        elseif kind == 4 then
          row[name] = cursor.getBlob(i)
        end
      end
      rows[#rows + 1] = row
    end
  end)
  cursor.close()
  if not ok then return nil, err end
  return rows
end

function Database:queryOne(sql, args)
  local rows, err = self:query(sql, args)
  if not rows then return nil, err end
  return rows[1]
end

function Database:scalar(sql, args, fallback)
  local row, err = self:queryOne(sql, args)
  if not row then return fallback, err end
  for _, value in pairs(row) do
    if value ~= nil then return value end
  end
  return fallback
end

-- 事务：fn 抛错则回滚，返回 nil, err
function Database:transaction(fn, ...)
  self.db.beginTransaction()
  local ok, result, extra = pcall(fn, ...)
  if ok then
    self.db.setTransactionSuccessful()
    self.db.endTransaction()
    return result, extra
  end
  self.db.endTransaction()
  return nil, result
end

function Database:close()
  if self.db then
    pcall(function() self.db.close() end)
    self.db = nil
  end
end

-- 打开数据库：用 SQLiteOpenHelper 子类保证 onCreate/onUpgrade 可测
function M.open(dbFile, version, onCreate, onUpgrade)
  local Helper = SQLiteOpenHelper.override {
    onCreate = function(superCall, db) onCreate(db) end,
    onUpgrade = function(superCall, db, oldVersion, newVersion) onUpgrade(db, oldVersion, newVersion) end,
  }
  local helper = Helper(activity, dbFile.getAbsolutePath(), nil, version)
  local rawDb = helper.getWritableDatabase()
  rawDb.execSQL("PRAGMA foreign_keys=ON")
  return setmetatable({ db = rawDb, helper = helper }, Database)
end

return M
