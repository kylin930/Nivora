# 数据库说明

- 文件：应用私有目录 `nivora.db`
- 引擎：Android 内置 SQLite
- 版本：`DB_VERSION = 1`，由 `core/migrations.lua` 管理
- 外键：连接后执行 `PRAGMA foreign_keys=ON`
- 时间约定
  - 纯日期：`TEXT`，`YYYY-MM-DD`（本地时区）
  - 时刻：`INTEGER`，epoch 毫秒
  - 时长：`INTEGER` 秒
  - 布尔：`INTEGER` 0/1

## 表结构

### categories 分类
| 列 | 类型 | 说明 |
| --- | --- | --- |
| id | INTEGER PK | |
| name | TEXT NOT NULL | 名称 |
| color | TEXT NOT NULL | `#RRGGBB` |
| icon | TEXT | 图标名 |
| type | TEXT | `schedule` / `todo` / `both` |
| sort_order | INTEGER | |
| created_at | INTEGER | |

首次建库写入：工作、个人、学习（schedule）、健康（todo）。

### habits 习惯
| 列 | 类型 | 说明 |
| --- | --- | --- |
| id | INTEGER PK | |
| name | TEXT NOT NULL | |
| description | TEXT | |
| icon / color | TEXT | 图标名、颜色 |
| frequency_type | TEXT | `daily` / `weekly_days` / `weekly_count` |
| frequency_config | TEXT | JSON：`{"days":[1,3,5]}` 或 `{"times":3}` |
| target_count | INTEGER | 每周目标次数 |
| reminder_time | TEXT | `HH:MM` 或 NULL |
| is_active | INTEGER | 1 在用 / 0 暂停 |
| sort_order / created_at / updated_at | INTEGER | |

### habit_records 打卡记录
| 列 | 类型 | 说明 |
| --- | --- | --- |
| id | INTEGER PK | |
| habit_id | INTEGER NOT NULL | → habits(id) ON DELETE CASCADE |
| record_date | TEXT NOT NULL | `YYYY-MM-DD` |
| completed_at | INTEGER | |
| note | TEXT | |

`UNIQUE(habit_id, record_date)`：同一天只能有一条，打卡用 `INSERT OR IGNORE`，
冲突时 `executeInsert()` 返回 -1 即为「今天已打卡」。

### schedules 日程
| 列 | 类型 | 说明 |
| --- | --- | --- |
| id | INTEGER PK | |
| title | TEXT NOT NULL | |
| description | TEXT | |
| start_time | INTEGER NOT NULL | 毫秒 |
| end_time | INTEGER | 毫秒，可空 |
| is_all_day | INTEGER | |
| category_id | INTEGER | → categories(id) |
| color | TEXT | |
| reminder_minutes | INTEGER | -1 = 不提醒 |
| recurrence_rule | TEXT | JSON，见下 |
| series_id | INTEGER | 0 表示单次；重复系列指向自身 id |
| created_at / updated_at | INTEGER | |

`recurrence_rule` 示例：

```json
{"freq":"weekly","byWeekday":[1,3,5],"until":"2027-01-31"}
```

- `freq`：`none` / `daily` / `weekly` / `monthly` / `yearly`
- `byWeekday`：1 = 周一 … 7 = 周日
- `until`：可选，最后一天（含）

只存规则不存实例。查询时按区间展开；`monthly` 遇到短月自动回退到月末
（31 日规则在 2 月变 28 日），`yearly` 遇到 2 月 29 日在平年回退到 28 日。

### schedule_exceptions 重复日程例外
| 列 | 类型 | 说明 |
| --- | --- | --- |
| id | INTEGER PK | |
| series_id | INTEGER NOT NULL | 母记录 id |
| occurrence_date | TEXT NOT NULL | 被修改的那一天 |
| override_json | TEXT | 改期后的字段 |
| is_canceled | INTEGER | 1 = 这一次被取消 |

`UNIQUE(series_id, occurrence_date)`。这样「只改一次」不需要复制出无限实例。

### todos 待办
| 列 | 类型 | 说明 |
| --- | --- | --- |
| id | INTEGER PK | |
| title | TEXT NOT NULL | |
| description | TEXT | |
| due_date | TEXT | 截止日期，可空 |
| priority | INTEGER | 0 低 / 1 中 / 2 高 |
| category_id | INTEGER | |
| goal_id | INTEGER | 关联目标 |
| is_completed | INTEGER | |
| completed_at | INTEGER | 完成时间 |
| sort_order / created_at / updated_at | INTEGER | |

过期不落库，由 `due_date < 今天 且未完成` 动态判断。

### todo_subtasks 子任务
| 列 | 类型 |
| --- | --- |
| id | INTEGER PK |
| todo_id | INTEGER NOT NULL → todos(id) ON DELETE CASCADE |
| title | TEXT NOT NULL |
| is_completed | INTEGER |
| sort_order | INTEGER |

### goals 目标
| 列 | 类型 | 说明 |
| --- | --- | --- |
| id | INTEGER PK | |
| title | TEXT NOT NULL | |
| description | TEXT | |
| start_date / end_date | TEXT | `YYYY-MM-DD` |
| status | TEXT | `active` / `done` / `archived` |
| color | TEXT | |
| created_at / updated_at | INTEGER | |

### goal_milestones 里程碑
| 列 | 类型 |
| --- | --- |
| id | INTEGER PK |
| goal_id | INTEGER NOT NULL → goals(id) ON DELETE CASCADE |
| title | TEXT NOT NULL |
| is_completed | INTEGER |
| completed_at | INTEGER |
| sort_order | INTEGER |

### journals 每日记录
| 列 | 类型 | 说明 |
| --- | --- | --- |
| id | INTEGER PK | |
| record_date | TEXT NOT NULL UNIQUE | 每天一条 |
| content | TEXT | 正文 |
| mood | INTEGER | 1…5，0 = 未标记 |
| tags | TEXT | 逗号分隔 |
| created_at / updated_at | INTEGER | |

### focus_records 专注记录
| 列 | 类型 | 说明 |
| --- | --- | --- |
| id | INTEGER PK | |
| todo_id | INTEGER | 关联任务，可空 |
| start_time / end_time | INTEGER | 毫秒 |
| duration_seconds | INTEGER | 实际专注秒数 |
| completed | INTEGER | 自然完成 1 / 中途结束 0 |
| note | TEXT | |
| created_at | INTEGER | |

### countdowns 倒数日
| 列 | 类型 | 说明 |
| --- | --- | --- |
| id | INTEGER PK | |
| title | TEXT NOT NULL | |
| description | TEXT | |
| target_date | TEXT NOT NULL | 原始日期 |
| repeat_yearly | INTEGER | |
| icon / color | TEXT | |
| kind | TEXT | 生日 / 纪念日 / 考试 / 截止日 / 自定义 |
| reminder_days | INTEGER | 提前天数，-1 = 不提醒 |
| created_at / updated_at | INTEGER | |

每年重复时，`target_date` 保持原始年份（如 `1990-11-20`），展示时算出下一次发生的日期。

### reminders 提醒排期
| 列 | 类型 | 说明 |
| --- | --- | --- |
| id | INTEGER PK | |
| type | TEXT | `schedule` / `todo` / `countdown` / `habit` |
| ref_id | INTEGER | 业务对象 id |
| trigger_at | INTEGER | 触发时刻（毫秒） |
| title / body | TEXT | 通知文案 |
| request_code | INTEGER | PendingIntent 请求码，唯一 |
| created_at | INTEGER | |

`UNIQUE(type, ref_id)`：一个业务对象最多一条提醒，重排时覆盖而不是叠加，
避免同一事件重复安排通知。

### app_settings 设置
| 列 | 类型 |
| --- | --- |
| key | TEXT PRIMARY KEY |
| value | TEXT |

键：`theme_mode`、`theme_seed`、`week_start`、`default_calendar_view`、
`default_reminder_minutes`、`habit_reminder_enabled`、`habit_reminder_time`、
`focus_minutes`、`short_break_minutes`、`long_break_minutes`、`auto_start_break`、
`show_completed_in_today`、`focus_state`、`last_restore_snapshot`。

放在表里而不是 SharedPreferences，是为了让它随 JSON 备份一起导出。

## 索引

```
habit_records(habit_id, record_date)   -- 打卡查询与去重
habit_records(record_date)             -- 按天统计
schedules(start_time)                  -- 区间扫描
schedule_exceptions(series_id, occurrence_date)
todos(due_date)                        -- 今日/过期
todos(is_completed, completed_at)      -- 完成统计
todos(goal_id)                         -- 目标关联任务
todo_subtasks(todo_id)
goal_milestones(goal_id)
focus_records(start_time)              -- 专注趋势
journals(record_date)
countdowns(target_date)
reminders(trigger_at)                  -- 补发扫描
```

## 迁移机制

`core/migrations.lua`：

```lua
M.DB_VERSION = 1
M.create(db)                      -- 从零建表 + 默认分类
M.UPGRADES = {                    -- [新版本号] = { SQL... }
  -- [2] = { "ALTER TABLE todos ADD COLUMN ..." },
}
M.upgrade(db, oldVersion, new)    -- 逐级执行
```

升级流程：`SQLiteOpenHelper` 的 `onUpgrade` 会被调用（真机已验证）；
`core/app.lua` 另外检查 `db.getVersion()`，落后就逐级补迁移并 `setVersion`，
兼容 IDE 内运行与打包后路径差异。

新增版本时：
1. 在 `M.UPGRADES` 里追加该版本要执行的 SQL。
2. `DB_VERSION` 加 1。
3. 同步更新本文档。

## 删除与关联

- 删除习惯 → 级联删除其打卡记录。
- 删除待办 → 级联删除子任务。
- 删除目标 → 里程碑一并删除；关联任务保留，`goal_id` 置 NULL。
- 删除分类 → 引用它的日程/待办 `category_id` 置 NULL，不删业务数据。
- 删除日程 → 连带清理其例外记录与提醒。
