# 开发指南

## 环境

| 项 | 值 |
| --- | --- |
| NeLuaJ+ | LuaJ++ 1.0 |
| 验证机型 | HONOR ANN-AN00，Android 15（API 35） |
| 屏幕 | 360dp 宽，density 3 |
| 工程根 | 包含 `init.lua` 的目录 |

运行：在 NeLuaJ+ 中打开工程根目录，运行 `main.lua`。
打包：使用 NeLuaJ-Builder，`init.lua` 决定名称、包名、版本、主题与权限。

`init.lua` 当前配置：

```lua
app_name = "Nivora"
package_name = "com.xiaolin.nivora"
ver_name = "1.0.0"
ver_code = "1"
min_sdk = "26"
target_sdk = "33"
NeLuaJ_Theme = "Theme_NeLuaJ_Material3_NoActionBar_ActionOverlay"
user_permission = { "POST_NOTIFICATIONS", "SCHEDULE_EXACT_ALARM", "VIBRATE" }
```

无 ActionBar 主题，界面自己用底部导航 + 页内标题栏，不依赖系统 ActionBar。

## 目录职责

```
main.lua                 入口与生命周期
config/constants.lua     枚举、选项表、色板
config/theme.lua         夜间模式、动态取色、运行时颜色 token
core/app.lua             组装根
core/database.lua        SQL 封装
core/migrations.lua      建表与迁移
core/navigation.lua      底部标签 + 页面栈
core/event_bus.lua       数据变更事件
data/repositories/       仓储（唯一写 SQL 的地方）
services/notification    通知渠道与发送
services/reminder        闹钟排期与补发
services/focus_timer     番茄钟状态机
services/backup          JSON 备份与恢复
components/ui.lua        卡片、列表项、空状态、对话框、Snackbar
components/form_dialog   声明式编辑表单
components/icons.lua     Canvas 图标
components/charts.lua    Canvas 图表
modules/<模块>/page.lua  页面
modules/<模块>/editor.lua 编辑表单 + 持久化
utils/                   日期、颜色、JSON
```

## 硬性规则

1. **页面不写 SQL**。需要新查询就在对应 repo 加方法。
2. **跳转只走 `ctx.nav`**（`setTab` / `push` / `pop`），不直接换 ContentView。
3. **日期计算只走 `utils/date_utils.lua`**。跨天、跨月、闰年、每周起始都在那里。
4. **颜色不硬编码**。布局用 `?attr/…`；需要 int 时用 `config/theme.lua` 的 `colors()`
   或 `utils/color_utils.lua` 的 `C("#RRGGBB")`。
5. **公共结构不重复实现**。卡片、列表项、空状态、确认框一律用 `components/ui.lua`。
6. **写操作失败必须有可见反馈**，不允许静默失败。
7. **定时器回调先检查 `page.alive`**。

## LuaJ++ / LuaJava 注意事项

完整清单见 `AGENTS.md` 第 3 节，最容易踩的几条：

- `try`、`switch`、`default`、`module` 是保留字，不能当变量/函数名/字段名
  （`local try = ...` 直接语法错误）。用 `attempt`、`toggle` 等替代。
- 颜色必须是**有符号 32 位整数**。`0xFF6750A4` 会被当成 long 并绑定到
  `Paint.setColor(long)` 抛异常，必须写 `Color.parseColor("#6750A4")`。
- 内部类用 `$`：`android.app.Notification$Builder`、`R$drawable`。
- Java 方法用点调用：`view.setText("x")`。
- `loadlayout(tbl, binding)` 第二参传局部表，id 才写到里面，不污染 `_G`。
- **布局表不是 View**。`{ MaterialButton, id = "x" }` 是声明，下标 1 是控件类；
  要操作控件必须有 `id` 并通过绑定表取，或者用构造函数返回的引用。
- `rawQuery` 的 selectionArgs 只能是字符串：`String.array({tostring(v)})`。
- **Lua 表里值为 `nil` 的键不存在**，`{ goal_id = nil }` 是空表，
  不能用来表达「把 goal_id 设为 NULL」。用 `db:update(..., nullColumns)` 或直接写 SQL 字面量。

## 新增一个模块

以「记体重」为例：

1. **建表**：`core/migrations.lua` 的 `V1`（或新版本）加 `CREATE TABLE weights(...)`，
   加索引，必要时 `M.UPGRADE`。
2. **仓储**：`data/repositories/weights_repo.lua`，导出 `M.new(db)`，
   返回 `{ create, update, remove, list, ... }` 表，方法返回 `result, err`。
3. **注册**：`core/app.lua` 的 `App:reloadRepositories()` 里 `self.weights = WeightsRepo.new(self.db)`。
4. **常量**：若需枚举/选项，放 `config/constants.lua`。
5. **页面**：`modules/weights/page.lua` 导出 `M.create(ctx)`，返回
   `{ view, refresh, onShow, destroy }`，内容区用 `ui.fill` 局部刷新。
6. **入口**：主标签在 `main.lua` 的 `tabs` 里注册；子页面在「我的」页 `entryRow` 里加一项，
   用 `ctx.nav:push(require "modules.weights.page", {})`。
7. **备份**：`services/backup/backup_service.lua` 的 `TABLES` 加上表名，否则不会导出。
8. **验证**：写一个临时脚本按 `docs/TESTING.md` 的方式跑一遍，确认无崩溃且数据正确。

## 调试

- `main.lua` 的 `onError` 返回 `"trace"`，堆栈会进日志；`activity.showLogs()` 可看日志。
- 页面错误会被导航层 `pcall` 捕获并 `print`，注意看日志而不是只看界面是否白屏。
- 想看某个仓储的行为，写一个临时脚本 `probe_xxx.lua`，`run_project` 跑它，
  把结果写文件再读取。验证完删掉（打包会带上所有文件）。

## 常见问题

**界面空白，日志无报错**
页面 `create` 返回的 `view` 为空，或内容容器 id 拼错导致 `ui.fill` 拿到 nil。
在 `ui.fill` 调用处确认绑定表里存在该 id。

**`Expected receiver of type View, but got Class<...>`**
把布局表当 View 用了。检查是否写了 `row[1].setOnClickListener` 之类。
`row[1]` 是控件类本身，不是子控件。

**填了内容点保存却提示「请填写名称」**
同源问题：字段读的是布局声明表而不是真实 View。给控件设 `id`，
在 `loadlayout(tbl, bound)` 之后用 `bound.<id>.getText()` 读取。
`components/form_dialog.lua` 的 renderers 就是按这个模式写的：
每个字段先登记 `pending[key] = function(bound) return reader end`，
加载完成后再统一建立读取器。

**水平一行被竖着排、或某个文字被压得看不见**
`ui.fill` 把子视图包进了一层垂直容器。它必须是逐个子视图 `addView`
并用与父容器匹配的 LayoutParams，否则 `layout_weight` 会按错误轴向分配。

**`no matching overload found for method 'setColor'`**
颜色字面量溢出成 long。改用 `Color.parseColor` / `color_utils.C`。

**改了权限但没生效**
权限写在 APK 的清单里，必须重新打包；IDE 内运行用的是 NeLuaJ+ 自己的清单。

**提醒不到点**
见 README「已知限制」：进程被杀后闹钟无人接收，这是打包能力限制。
