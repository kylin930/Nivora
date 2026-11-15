-- 全局常量与枚举：所有模块共享，禁止在页面里重复定义
local M = {}

M.APP_NAME = "Nivora"
M.VERSION = "1.0.0"
M.DB_NAME = "nivora.db"
M.DB_VERSION = 1
M.BACKUP_FORMAT = 1
M.BACKUP_PREFIX = "nivora-backup"

-- 优先级：0 低 / 1 中 / 2 高
M.PRIORITIES = {
  { value = 0, name = "低" },
  { value = 1, name = "中" },
  { value = 2, name = "高" },
}

function M.priorityName(value)
  for _, item in ipairs(M.PRIORITIES) do
    if item.value == value then return item.name end
  end
  return "中"
end

-- 习惯周期
M.HABIT_FREQ = {
  daily = "每天",
  weekly_days = "每周指定日期",
  weekly_count = "每周完成次数",
}

-- 重复规则频率
M.RECURRENCE = {
  none = "不重复",
  daily = "每天",
  weekly = "每周",
  monthly = "每月",
  yearly = "每年",
}

M.RECURRENCE_ORDER = { "none", "daily", "weekly", "monthly", "yearly" }

-- 提醒提前量（分钟），-1 表示不提醒
M.REMINDER_OPTIONS = {
  { value = -1, name = "不提醒" },
  { value = 0, name = "准时" },
  { value = 5, name = "提前 5 分钟" },
  { value = 10, name = "提前 10 分钟" },
  { value = 15, name = "提前 15 分钟" },
  { value = 30, name = "提前 30 分钟" },
  { value = 60, name = "提前 1 小时" },
  { value = 1440, name = "提前 1 天" },
}

function M.reminderName(minutes)
  for _, item in ipairs(M.REMINDER_OPTIONS) do
    if item.value == minutes then return item.name end
  end
  return "提前 " .. tostring(minutes) .. " 分钟"
end

-- 目标状态
M.GOAL_STATUS = {
  active = "进行中",
  done = "已完成",
  archived = "已归档",
}

-- 心情 1..5，0 表示未标记
M.MOODS = {
  { value = 1, label = "很差" },
  { value = 2, label = "有点糟" },
  { value = 3, label = "一般" },
  { value = 4, label = "不错" },
  { value = 5, label = "很好" },
}

function M.moodLabel(value)
  for _, item in ipairs(M.MOODS) do
    if item.value == value then return item.label end
  end
  return "未标记"
end

-- 倒数日类型只是展示标签，统一存 countdowns 表
M.COUNTDOWN_KINDS = { "生日", "纪念日", "考试", "截止日", "自定义" }

-- 一周起始日
M.FIRST_DAY_OPTIONS = {
  { value = 1, name = "周一" },
  { value = 7, name = "周日" },
}

-- 分类默认色板（颜色字符串，统一经 color_utils 转 signed int）
M.PALETTE = {
  "#6750A4", "#0061A4", "#00696B", "#3F6834",
  "#8C4A60", "#8B5000", "#B3261E", "#4A5C92",
  "#6B5B00", "#7D5260", "#006874", "#3F6B3F",
}

-- 习惯图标名（由 components/icons.lua 提供）
M.HABIT_ICONS = {
  "check", "star", "heart", "book", "run", "water", "moon", "sun",
  "leaf", "pen", "music", "code",
}

M.CATEGORY_TYPES = {
  { value = "schedule", name = "日程" },
  { value = "todo", name = "待办" },
}

return M
