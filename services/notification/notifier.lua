-- 通知服务：渠道创建、权限申请、发送与取消。
-- 注意：NeLuaJ+ 的 init.lua 无法声明清单广播接收器，进程被杀后闹钟无人接收，
-- 因此这里只保证"应用存活时"的通知投递，详见 AGENTS.md 2.1。
local bindClass = luajava.bindClass
local Context = bindClass "android.content.Context"
local Intent = bindClass "android.content.Intent"
local PendingIntent = bindClass "android.app.PendingIntent"
local Uri = bindClass "android.net.Uri"
local NotificationManager = bindClass "android.app.NotificationManager"
local NotificationChannel = bindClass "android.app.NotificationChannel"
local NotificationBuilder = bindClass "android.app.Notification$Builder"

local M = {}

local CHANNEL_ID = "nivora_reminders"
local CHANNEL_NAME = "日程与提醒"

local Notifier = {}
Notifier.__index = Notifier

function Notifier:ensureChannel()
  local manager = activity.getSystemService(Context.NOTIFICATION_SERVICE)
  if not manager then return false end
  if manager.getNotificationChannel(CHANNEL_ID) then return true end
  local channel = NotificationChannel(CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_DEFAULT)
  channel.setDescription("习惯、日程、待办、倒数日与专注结束提醒")
  channel.enableVibration(true)
  manager.createNotificationChannel(channel)
  return true
end

function Notifier:hasPermission()
  local ok, granted = pcall(function()
    return activity.checkPermission("android.permission.POST_NOTIFICATIONS")
  end)
  return ok and granted == true
end

-- 申请通知权限；结果回调 granted
function Notifier:requestPermission(onResult)
  if self:hasPermission() then
    if onResult then onResult(true) end
    return true
  end
  local ok, launcher = pcall(function()
    return activity.permissionLauncher(function(granted)
      if onResult then onResult(granted == true) end
    end)
  end)
  if not ok or not launcher then return false end
  launcher.launch("android.permission.POST_NOTIFICATIONS")
  return true
end

-- 点按通知回到应用入口
local function contentIntent()
  local intent = Intent(activity, activity.getClass())
  intent.setData(Uri.parse("file://" .. activity.getLuaPath("main.lua")))
  intent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
  return PendingIntent.getActivity(activity, 0, intent, PendingIntent.FLAG_IMMUTABLE)
end

function Notifier:post(id, title, body)
  if not self:hasPermission() then return false, "没有通知权限" end
  local manager = activity.getSystemService(Context.NOTIFICATION_SERVICE)
  if not manager then return false, "通知服务不可用" end
  self:ensureChannel()

  local builder = NotificationBuilder(activity, CHANNEL_ID)
  builder.setContentTitle(title or "Nivora")
  builder.setContentText(body or "")
  builder.setSmallIcon(activity.getApplicationInfo().icon)
  builder.setAutoCancel(true)
  builder.setContentIntent(contentIntent())
  builder.setStyle(NotificationBuilder.BigTextStyle().bigText(body or ""))
  local ok, err = pcall(function()
    manager.notify(id, builder.build())
  end)
  if not ok then return false, err end
  return true
end

function Notifier:cancel(id)
  local manager = activity.getSystemService(Context.NOTIFICATION_SERVICE)
  if manager then pcall(function() manager.cancel(id) end) end
end

function Notifier:cancelAll()
  local manager = activity.getSystemService(Context.NOTIFICATION_SERVICE)
  if manager then pcall(function() manager.cancelAll() end) end
end

function M.new()
  local notifier = setmetatable({}, Notifier)
  pcall(function() notifier:ensureChannel() end)
  return notifier
end

M.CHANNEL_ID = CHANNEL_ID

return M
