# 架构说明

## 1. 分层

```
main.lua                 入口：建库、组装服务、应用主题、构建底部导航外壳
config/                  常量、主题（颜色 token 与夜间模式）
core/                    数据库、迁移、导航、事件总线、应用根对象
data/repositories/       仓储层：唯一允许写 SQL 的地方
services/                通知、提醒排期、专注计时器、备份
components/              公共 UI（ui / form_dialog / icons / charts）
modules/<模块>/          page.lua（渲染交互）+ editor.lua（编辑表单）
utils/                   日期、颜色、JSON 工具
```

依赖方向单向向下：`modules → components/services/repositories → core/utils`。
页面之间不互相引用，只通过 `core/navigation.lua` 跳转。

## 2. 关键对象

### core/app.lua
进程内单例，持有数据库连接、全部仓储、通知器、提醒服务、专注计时器、备份服务。
- `App.create()` 打开数据库并完成版本迁移。
- `App:reloadRepositories()` 在恢复/清空数据后重建仓储（设置缓存也会失效）。
- `App:changed(event)` 广播数据变更。
- `App:dispose()` 在 `onDestroy` 时注销广播接收器、关闭数据库。

### core/navigation.lua
底部五个标签 + 站内页面栈。
- 主标签页面按需创建并缓存（`tabPages`），切回来时复用视图，滚动位置自然保留。
- 子页面通过 `push(spec, params)` 压栈，覆盖内容区并隐藏底栏；`pop()` 返回。
- 返回键由 `handleBack()` 统一处理：子页面 → 主标签 → 首页 → 退出。
- 页面回调统一包 `pcall`，单个页面出错只记录日志，不会让整个界面崩溃。

### core/event_bus.lua
极简订阅表。事件：`DATA_CHANGED`、`HABITS_CHANGED`、`SCHEDULES_CHANGED`、`TODOS_CHANGED`、
`GOALS_CHANGED`、`JOURNALS_CHANGED`、`COUNTDOWNS_CHANGED`、`FOCUS_CHANGED`、`SETTINGS_CHANGED`。
页面订阅后在销毁时退订，避免回调操作已销毁的视图。

### core/database.lua
对 `SQLiteDatabase` 的薄封装：参数绑定、`query`（Cursor → Lua 表）、
`insert`（支持 `INSERT OR IGNORE`）、`update`（支持显式置 NULL 的列）、`transaction`（失败回滚）。

`update` 接收 `nullColumns` 参数：Lua 表里值为 `nil` 的键根本不存在，
无法用 `pairs` 表达「把这一列设为 NULL」，必须显式声明。

## 3. 页面结构约定

每个 `modules/<模块>/page.lua` 导出 `M.create(ctx)`，返回页面对象：

```lua
{
  view = <View>,        -- 页面根视图
  refresh = function() end,
  onShow = function() end,
  onBack = function() return false end,  -- 可选，返回 true 表示已处理
  destroy = function() end,
}
```

页面内部模式：
- 顶部固定（标题栏 / 筛选条）+ 可滚动内容区。
- 内容区用 `ui.fill(container, children)` 局部重建，只替换滚动区内的视图，不重建整页。
- 状态（当前筛选、选中日期、视图模式）放在页面闭包里的 `state` 表。
- 页面销毁用 `page.alive` 标志阻止 `timer` 回调操作已销毁视图。

## 4. 数据流

```
用户操作
  → modules 调用 app.<repo>:方法
    → repository 拼 SQL（参数化）→ core.database
  → app:changed(EVENT)
    → event_bus 通知订阅页面 → page.refresh()
```

读取路径同理：页面只拿仓储返回的 Lua 表，不接触 Cursor。

## 5. 重要业务规则

### 习惯连续天数
不能按记录条数算。规则：
1. 从今天往前推；若今天应打卡且未打卡，从昨天开始算（今天还没结束，不打断连续）。
2. 每退一天：有记录则 +1；没记录但该天是排期日则中断；没记录且非排期日则跳过。
3. 暂停中的习惯 `isScheduledOn` 恒为 `false`，因此暂停期不计入也不打断。
4. `weekly_count` 类型改为按「周达标」计算连续周数。

### 重复日程
- 表中只存一条母记录（`recurrence_rule` 为 JSON），按查询区间展开为实例。
- 单次改动/取消写入 `schedule_exceptions`（唯一约束 `series_id + occurrence_date`），不改母记录。
- 「本次及以后删除」= 把 `recurrence_rule.until` 截断到该日期的前一天，并清掉之后的例外。
- 展开上限 750 次，避免异常规则拖死界面。

### 目标进度
同时存在里程碑与关联任务时取两者完成比例的**平均**，只有一类时用该类比例；
状态为 `done` 时进度固定 100%。这样进度随任务勾选自动变化。

### 专注计时
状态整体序列化进 `app_settings.focus_state`：`phase / running / started_at / ends_at /
paused_remaining / duration_seconds / todo_id / completed_rounds`。
剩余时间 = `ends_at - now`，不累加 UI 的 tick 次数。回到前台或页面重建时
`catchUp()` 判断是否已到期并补记记录。

## 6. UI 约定

- 布局表原生写法，颜色一律 `?attr/…`；Canvas 与图标着色用 `config/theme.lua` 的 `colors()`。
- 尺寸显式 `dp`、字号显式 `sp`；间距走 8dp 网格；卡片圆角 16dp。
- 列表用 `addView` 重建（单页数十条以内），不引入适配器复杂度。
- 图标由 `components/icons.lua` 用 Canvas 画 96×96 位图后包装为 `BitmapDrawable`，
  因为内置资源不含所需图标，且 `.lua` 图标的着色形式不可用（见 AGENTS.md 3.4）。

## 7. 错误处理

- 仓储方法返回 `result, err`；页面拿到 `err` 必须给用户可见反馈（Snackbar / 对话框）。
- 多步写操作走事务，失败回滚并返回错误信息。
- `main.lua` 的 `onError` 返回 `"trace"`，完整堆栈进日志。
- 页面回调、事件回调、图标绘制均有兜底，单点失败不影响整体界面。
