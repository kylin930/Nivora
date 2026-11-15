-- 数据库结构定义与版本迁移。
-- 新增版本时：DB_VERSION + 1，并在 MIGRATIONS[n] 中追加该版本要执行的 SQL。
local M = {}

M.DB_VERSION = 1

-- v1：初始结构
local V1 = {
  [[CREATE TABLE IF NOT EXISTS categories(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    color TEXT NOT NULL,
    icon TEXT,
    type TEXT NOT NULL DEFAULT 'schedule',
    sort_order INTEGER DEFAULT 0,
    created_at INTEGER
  )]],

  [[CREATE TABLE IF NOT EXISTS habits(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    description TEXT,
    icon TEXT,
    color TEXT,
    frequency_type TEXT NOT NULL DEFAULT 'daily',
    frequency_config TEXT,
    target_count INTEGER DEFAULT 1,
    reminder_time TEXT,
    is_active INTEGER DEFAULT 1,
    sort_order INTEGER DEFAULT 0,
    created_at INTEGER,
    updated_at INTEGER
  )]],

  [[CREATE TABLE IF NOT EXISTS habit_records(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    habit_id INTEGER NOT NULL REFERENCES habits(id) ON DELETE CASCADE,
    record_date TEXT NOT NULL,
    completed_at INTEGER,
    note TEXT,
    UNIQUE(habit_id, record_date)
  )]],

  [[CREATE TABLE IF NOT EXISTS schedules(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    description TEXT,
    start_time INTEGER NOT NULL,
    end_time INTEGER,
    is_all_day INTEGER DEFAULT 0,
    category_id INTEGER,
    color TEXT,
    reminder_minutes INTEGER DEFAULT -1,
    recurrence_rule TEXT,
    series_id INTEGER DEFAULT 0,
    created_at INTEGER,
    updated_at INTEGER
  )]],

  -- 重复日程的单次例外：取消或改期都不改系列本身
  [[CREATE TABLE IF NOT EXISTS schedule_exceptions(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    series_id INTEGER NOT NULL,
    occurrence_date TEXT NOT NULL,
    override_json TEXT,
    is_canceled INTEGER DEFAULT 0,
    UNIQUE(series_id, occurrence_date)
  )]],

  [[CREATE TABLE IF NOT EXISTS todos(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    description TEXT,
    due_date TEXT,
    priority INTEGER DEFAULT 1,
    category_id INTEGER,
    goal_id INTEGER,
    is_completed INTEGER DEFAULT 0,
    completed_at INTEGER,
    sort_order INTEGER DEFAULT 0,
    created_at INTEGER,
    updated_at INTEGER
  )]],

  [[CREATE TABLE IF NOT EXISTS todo_subtasks(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    todo_id INTEGER NOT NULL REFERENCES todos(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    is_completed INTEGER DEFAULT 0,
    sort_order INTEGER DEFAULT 0
  )]],

  [[CREATE TABLE IF NOT EXISTS goals(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    description TEXT,
    start_date TEXT,
    end_date TEXT,
    status TEXT NOT NULL DEFAULT 'active',
    color TEXT,
    created_at INTEGER,
    updated_at INTEGER
  )]],

  [[CREATE TABLE IF NOT EXISTS goal_milestones(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    goal_id INTEGER NOT NULL REFERENCES goals(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    is_completed INTEGER DEFAULT 0,
    completed_at INTEGER,
    sort_order INTEGER DEFAULT 0
  )]],

  [[CREATE TABLE IF NOT EXISTS journals(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    record_date TEXT NOT NULL UNIQUE,
    content TEXT,
    mood INTEGER DEFAULT 0,
    tags TEXT,
    created_at INTEGER,
    updated_at INTEGER
  )]],

  [[CREATE TABLE IF NOT EXISTS focus_records(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    todo_id INTEGER,
    start_time INTEGER NOT NULL,
    end_time INTEGER,
    duration_seconds INTEGER DEFAULT 0,
    completed INTEGER DEFAULT 0,
    note TEXT,
    created_at INTEGER
  )]],

  [[CREATE TABLE IF NOT EXISTS countdowns(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    description TEXT,
    target_date TEXT NOT NULL,
    repeat_yearly INTEGER DEFAULT 0,
    icon TEXT,
    color TEXT,
    kind TEXT,
    reminder_days INTEGER DEFAULT 0,
    created_at INTEGER,
    updated_at INTEGER
  )]],

  -- 提醒排期表：一条业务记录最多一条提醒，便于幂等重排/取消
  [[CREATE TABLE IF NOT EXISTS reminders(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    type TEXT NOT NULL,
    ref_id INTEGER NOT NULL,
    trigger_at INTEGER NOT NULL,
    title TEXT,
    body TEXT,
    request_code INTEGER NOT NULL,
    created_at INTEGER,
    UNIQUE(type, ref_id)
  )]],

  [[CREATE TABLE IF NOT EXISTS app_settings(
    key TEXT PRIMARY KEY,
    value TEXT
  )]],

  "CREATE INDEX IF NOT EXISTS idx_habit_records_habit ON habit_records(habit_id, record_date)",
  "CREATE INDEX IF NOT EXISTS idx_habit_records_date ON habit_records(record_date)",
  "CREATE INDEX IF NOT EXISTS idx_schedules_start ON schedules(start_time)",
  "CREATE INDEX IF NOT EXISTS idx_exceptions_series ON schedule_exceptions(series_id, occurrence_date)",
  "CREATE INDEX IF NOT EXISTS idx_todos_due ON todos(due_date)",
  "CREATE INDEX IF NOT EXISTS idx_todos_status ON todos(is_completed, completed_at)",
  "CREATE INDEX IF NOT EXISTS idx_todos_goal ON todos(goal_id)",
  "CREATE INDEX IF NOT EXISTS idx_subtasks_todo ON todo_subtasks(todo_id)",
  "CREATE INDEX IF NOT EXISTS idx_milestones_goal ON goal_milestones(goal_id)",
  "CREATE INDEX IF NOT EXISTS idx_focus_start ON focus_records(start_time)",
  "CREATE INDEX IF NOT EXISTS idx_journals_date ON journals(record_date)",
  "CREATE INDEX IF NOT EXISTS idx_countdowns_date ON countdowns(target_date)",
  "CREATE INDEX IF NOT EXISTS idx_reminders_trigger ON reminders(trigger_at)",
}

local function seed(db, now)
  local seeds = {
    { "工作", "#0061A4", "schedule" },
    { "个人", "#3F6834", "schedule" },
    { "学习", "#8B5000", "both" },
    { "健康", "#00696B", "todo" },
  }
  for _, item in ipairs(seeds) do
    db.execSQL("INSERT INTO categories(name, color, type, sort_order, created_at) VALUES(?,?,?,?,?)",
      { item[1], item[2], item[3], 0, now })
  end
end

local function runList(db, list)
  for _, sql in ipairs(list) do
    db.execSQL(sql)
  end
end

-- onCreate：从零建库
function M.create(db)
  runList(db, V1)
  seed(db, require("utils.date_utils").nowMs())
end

-- 每个版本要执行的增量（用 n-1 → n 描述）
M.UPGRADES = {
  -- [2] = { "ALTER TABLE ... " },
}

-- onUpgrade：逐级迁移
function M.upgrade(db, oldVersion, newVersion)
  local target = newVersion or M.DB_VERSION
  local current = oldVersion
  while current < target do
    current = current + 1
    local statements = M.UPGRADES[current]
    if statements then
      runList(db, statements)
    end
  end
end

return M
