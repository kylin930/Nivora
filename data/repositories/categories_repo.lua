-- 分类：日程与待办共用，type 区分适用场景
local M = {}

local Repo = {}
Repo.__index = Repo

function Repo:list(type)
  local sql = "SELECT * FROM categories"
  local args = {}
  if type and type ~= "" then
    sql = sql .. " WHERE type = ? OR type = 'both'"
    args[#args + 1] = type
  end
  sql = sql .. " ORDER BY sort_order ASC, id ASC"
  return self.db:query(sql, args) or {}
end

function Repo:get(id)
  return self.db:queryOne("SELECT * FROM categories WHERE id = ?", { id })
end

function Repo:create(data)
  local id = self.db:insert("categories", {
    name = data.name,
    color = data.color or "#6750A4",
    icon = data.icon,
    type = data.type or "schedule",
    sort_order = data.sort_order or 0,
    created_at = require("utils.date_utils").nowMs(),
  })
  if not id or id < 1 then return nil, "创建分类失败" end
  return id
end

function Repo:update(id, data)
  local row = {}
  for _, key in ipairs({ "name", "color", "icon", "type", "sort_order" }) do
    if data[key] ~= nil then row[key] = data[key] end
  end
  local affected = self.db:update("categories", row, "id = ?", { id })
  if not affected or affected < 1 then return nil, "更新分类失败" end
  return true
end

function Repo:remove(id)
  -- 解除引用后再删除，避免留下悬空 category_id
  local ok, err = self.db:transaction(function()
    self.db.db.execSQL("UPDATE schedules SET category_id = NULL WHERE category_id = ?", { id })
    self.db.db.execSQL("UPDATE todos SET category_id = NULL WHERE category_id = ?", { id })
    self.db:delete("categories", "id = ?", { id })
    return true
  end)
  if not ok then return nil, err end
  return true
end

function Repo:map()
  local rows = self:list(nil)
  local map = {}
  for _, row in ipairs(rows) do
    map[row.id] = row
  end
  return map
end

M.new = function(db) return setmetatable({ db = db }, Repo) end

return M
