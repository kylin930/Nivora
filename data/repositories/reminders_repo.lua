-- 提醒排期表：每个业务对象最多一条提醒，便于幂等重排与取消
local M = {}

local Repo = {}
Repo.__index = Repo

-- type + ref_id 唯一，重复排期时覆盖
function Repo:upsert(kind, refId, triggerAt, title, body)
  local existing = self.db:queryOne(
    "SELECT * FROM reminders WHERE type = ? AND ref_id = ?", { kind, refId })
  local requestCode
  if existing then
    requestCode = existing.request_code
    self.db:update("reminders", {
      trigger_at = triggerAt,
      title = title,
      body = body,
    }, "id = ?", { existing.id })
  else
    requestCode = self.db:scalar(
      "SELECT COALESCE(MAX(request_code), 1000) + 1 FROM reminders", nil, 1001)
    self.db:insert("reminders", {
      type = kind,
      ref_id = refId,
      trigger_at = triggerAt,
      title = title,
      body = body,
      request_code = requestCode,
      created_at = require("utils.date_utils").nowMs(),
    })
  end
  return requestCode
end

function Repo:removeFor(kind, refId)
  self.db:delete("reminders", "type = ? AND ref_id = ?", { kind, refId })
end

function Repo:get(kind, refId)
  return self.db:queryOne("SELECT * FROM reminders WHERE type = ? AND ref_id = ?", { kind, refId })
end

function Repo:all()
  return self.db:query("SELECT * FROM reminders ORDER BY trigger_at ASC") or {}
end

function Repo:dueNow(nowMs)
  return self.db:query("SELECT * FROM reminders WHERE trigger_at <= ?", { nowMs or 0 }) or {}
end

function Repo:clear()
  self.db:delete("reminders", "", nil)
end

M.new = function(db) return setmetatable({ db = db }, Repo) end

return M
