# AGENTS.md — Nivora 开发规范（基于真机验证）

本文件记录在本项目中**已实测确认**的 NeLuaJ+ 能力与代码约定。所有模块必须遵守。
每条“已验证”结论都来自 `probe*.lua` 真机运行结果，不是推测。

运行环境（实测）：Android 15 / API 35，HONOR ANN-AN00，LuaJ++ 1.0，屏幕宽 360dp，density 3。

---

## 1. 项目结构约定

```
main.lua                 仅做初始化与启动
init.lua                 打包配置（名称/包名/版本/权限/主题）
config/                  常量与主题
core/                    数据库、迁移、导航、事件总线、应用组装
data/repositories/       数据层；SQL 只允许出现在仓储层
modules/<模块>/          业务页面（渲染 + 交互），不写 SQL
components/              公共 UI 组件、图标、图表（图标在 icons.lua 用 Canvas 绘制）
services/                通知、提醒、备份、专注计时
utils/                   日期、格式化、校验
docs/                    架构、数据库、开发、测试文档
```

硬性规则：

- UI 层不得出现 SQL 字符串；一律经 `data/repositories`。
- 页面之间的跳转只走 `core/navigation.lua`。
- 日期/时间计算只走 `utils/date_utils.lua`，不在页面内手写日期数学。
- 颜色只来自 `config/theme.lua` 或主题属性 `?attr/…`；页面内不硬编码色值。
- 公共结构（卡片、空状态、对话框、Snackbar）只从 `components/ui.lua` 取，不重复实现。

---

## 2. 已验证的运行时能力

| 能力 | 结论 | 用法 |
| --- | --- | --- |
| SQLite | 可用 | `SQLiteDatabase.openOrCreateDatabase(File, nil)` |
| SQLiteOpenHelper 子类 | 可用 | `SQLiteOpenHelper.override{onCreate=…, onUpgrade=…}`，升级回调实测触发 |
| 事务/回滚 | 可用 | `beginTransaction/setTransactionSuccessful/endTransaction`；异常时不调用 successful 即回滚 |
| 外键 | 可用 | `PRAGMA foreign_keys=ON`，`rawQuery("PRAGMA foreign_keys")` 返回 1 |
| 数据库版本号 | 可用 | `db.getVersion()/setVersion(n)` |
| SharedPreferences | 可用 | `activity.getSharedPreferences(name, 0)`，`edit().commit()` 返回 true |
| 通知渠道 | 可用 | `NotificationChannel(id, name, IMPORTANCE_HIGH)` + `createNotificationChannel` |
| 发通知 | 可用（需权限） | `android.app.Notification$Builder`，`setSmallIcon(int)` |
| 通知权限 | 需显式申请 | `activity.permissionLauncher(fn).launch("android.permission.POST_NOTIFICATIONS")` |
| 精确闹钟 | **不可用** | `canScheduleExactAlarms()` 返回 false，只用 `setAndAllowWhileIdle` |
| 广播接收器 | 仅运行时注册有效 | `BroadcastReceiver.override{onReceive=…}` + `registerReceiver` |
| 闹钟 → 广播 | 进程存活时实测送达 | `PendingIntent.getBroadcast` + `AlarmManager.setAndAllowWhileIdle` |
| 清单接收器 / 开机自启 | **不支持** | `init.lua` 只能声明 `user_permission`，无法声明 receiver，因此无法 `BOOT_COMPLETED` |
| 通知点击回页面 | 可用 | `Intent(activity, activity.getClass()).setData(Uri.parse("file://"..luaPath))` |
| MD3 控件 | 全部可用 | 见第 5 节清单 |
| 自定义 View | 可用 | `View.override{onDraw=…}`，用于 Canvas 图表 |
| RecyclerView 适配器 | 可用 | `com.androlua.adapter.LuaRecyclerAdapter` + `dataBinder` |
| 日期/时间选择器 | 可用 | `MaterialDatePicker.Builder.datePicker()/MaterialTimePicker.Builder()` + `show(supportFragmentManager, tag)` |
| 动态取色 | 可用 | `activity.dynamicColor(seed)`，在 `setContentView` 之前调用 |

### 2.1 提醒系统的真实边界（必须如实说明）

App 被杀掉后，运行时注册的 `BroadcastReceiver` 随之消失，闹钟广播无人接收；`init.lua`
也无法声明清单广播接收器。因此：

- 已实现：应用存活或回到前台时，按 `reminders` 表重新排期并补发过期提醒。
- 未实现：进程被系统杀死/设备重启后的独立推送。这是**平台打包能力限制**，不是遗漏。
- 交互上不得向用户宣称“一定能准时推送”；设置页需如实说明。

---

## 3. LuaJ++ / LuaJava 实测坑位

1. **`try` 是关键字**，不能用作变量或函数名（`local try = ...` 直接语法错误）。用 `attempt`。
2. **颜色必须是有符号 32 位整数**。`0xFF6750A4` 这种字面量会被解析为 long 并绑定到
   `Paint.setColor(long)` 而抛 `IllegalArgumentException: Invalid ID`。
   统一用 `utils/color_utils.lua` 的 `C("#6750A4")`（内部 `Color.parseColor`，返回 signed int）。
3. **`android.app.Notification.Builder` 是内部类**，类名写作 `android.app.Notification$Builder`。
   同理 `NotificationCompat$Builder`、`R$drawable`。
4. **`res.drawable("<name>.lua")` 返回值**：`.lua` 图标返回 Bitmap 时，两参着色形式
   `res.drawable(name, color)` 会失败（内部按 Drawable 调用 tint）。→ 本项目改用
   `components/icons.lua` 直接构造已着色的 `BitmapDrawable`，不依赖 `res.drawable` 着色。
5. **`INSERT OR IGNORE` 冲突时 `executeInsert()` 返回 -1**，据此判断“已存在”。
6. **`rawQuery` 的 selectionArgs 只能是字符串**：`String.array({tostring(v)})`。
   SQLite 列亲和性会把文本转成数值比较，实测 `ts > ?`、`id = ?` 均正确。
7. **绑定参数不可为 nil**：`ipairs` 遇 nil 截断，`String.array` 塞 nil 会丢位。
   约定：查询/更新参数永不为 nil；写 NULL 时在 SQL 里写字面量 `NULL`，
   插入时空值用 `compileStatement().bindNull(i)` 显式绑定。
8. **Java 方法用点调用**（`view.setText(...)`），不要用冒号。
9. **loadlayout 必须传绑定表**：`loadlayout(tbl, views)`，id 写入 `views`，避免污染 `_G`。
10. **布局里 `layout_*` 属于父容器**；LinearLayout 按比例分配用 `layout_width/height = "0dp"` + `layout_weight`。
11. **列表容器用 `addView` 重建**：本项目列表规模小（单页数十条），不使用 RecyclerView，
    以便状态可控；切换 Tab 时保留滚动位置由页面缓存负责。
12. **`activity.delay(ms, fn)`** 可用，用于防抖与延时刷新；页面销毁时用标志位防止回调操作已销毁视图。
13. **`until` 是保留字**：表构造器里不能写 `{ until = "..." }`（语法错误），
    但赋值形式 `rule.until = "..."` 与读取 `rule.until` 合法（实测 `check_lua_syntax` 通过）。
    `schedules_repo.lua` 的重复规则 `until` 字段正是用赋值形式写入的，勿改成构造器字面量。

### 3.1 布局表是「声明」，不是 View（最容易踩的坑）

`{ MaterialButton, id = "save" }` 是**描述**，不是控件实例。它上面没有 `getText()`、
`isChecked()`、`setText()`、`setOnClickListener()`。

在声明表上调用这些方法会静默失败或抛错，典型症状：

- 用户填了内容，点保存却提示「请填写名称」——读不到文本，字段被当成空；
- 点选择按钮没反应，Chip 的选中状态读出来永远是 false。

正确做法（二选一）：

1. **写回调属性**：`{ MaterialButton, onClick = function() ... end }`，loadlayout 会绑定监听器。
2. **设 id + 用绑定表取真实控件**：
   ```lua
   local bound = {}
   local root = loadlayout({ MaterialButton, id = "save", ... }, bound)
   bound.save.setOnClickListener(function() ... end)
   ```
   `ui.*` 组件返回的都是声明表；要操作它必须先加 `id`，再从绑定表取。
   `ui.checkRow` 因此直接返回 `(行, 勾选框, 文本区)`，避免调用方猜下标。

**布局表下标 1 是控件类**：`row[1]` 是 `LinearLayout` 这个 class，不是子 View。
`row[1].setClickable(...)` 会报
`Expected receiver of type android.view.View, but got java.lang.Class<...>`。

读取 Chip 组时，先拿 `ChipGroup` 的真实 View，再 `getChildAt(index-1)` 遍历，顺序与添加顺序一致。

### 3.2 `ui.fill` 必须逐个子视图 addView

`ui.fill(container, children)` 把每个 child 单独 `loadlayout` 后 `addView` 到容器本身，
**不能**包一层垂直容器。包一层的后果：

- 水平容器（筛选条、时段导航、按钮行）被强行竖排；
- `layout_width = "0dp"` + `layout_weight = 1` 按错误的轴向分配，
  在垂直容器里宽度被压成 0，文字几乎不可见（日程页日期标题就因此只剩约 1/3）。

根 LayoutParams 类型要与容器匹配（LinearLayout 用 `LinearLayout$LayoutParams`），否则 weight 会丢失。

---

## 4. 数据约定

### 4.1 时间字段

| 类型 | 存储 | 示例 |
| --- | --- | --- |
| 纯日期 | TEXT `YYYY-MM-DD` | `2026-11-15` |
| 时刻/时间戳 | INTEGER 毫秒（epoch） | `1794718000000` |
| 时长 | INTEGER 秒 | `1500` |
| 布尔 | INTEGER 0/1 | `1` |

日期字符串一律本地时区解释；跨时区不做转换（个人应用场景）。

### 4.2 枚举

- `habit.frequency_type`：`daily` / `weekly_days` / `weekly_count`
- `schedules.recurrence_rule`：JSON `{"freq":"none|daily|weekly|monthly|yearly","byWeekday":[1..7],"until":"YYYY-MM-DD"}`
  - `byWeekday` 1=周一 … 7=周日
- `todos.priority`：0 低 / 1 中 / 2 高
- `goals.status`：`active` / `done` / `archived`
- `reminders.type`：`schedule` / `todo` / `countdown` / `habit`
- `journals.mood`：1 很差 … 5 很好（0/空表示未标记）

### 4.3 数据库

- 文件名 `nivora.db`，位于 `activity.getLuaDir()`。
- 版本由 `core/migrations.lua` 统一管理，`DB_VERSION` 递增，`onUpgrade` 按版本逐级迁移。
- 从零建库与升级都必须可用（实测 `SQLiteOpenHelper` 路径）。

---

## 5. UI 规范

### 5.1 已验证可用的控件

`MaterialToolbar`、`AppBarLayout`、`BottomNavigationView`（= MD3 NavigationBar）、
`MaterialCardView`、`MaterialButton`、`MaterialButtonToggleGroup`、`TextInputLayout`、
`TextInputEditText`、`LinearProgressIndicator`、`CircularProgressIndicator`、
`FloatingActionButton`、`ExtendedFloatingActionButton`、`MaterialCheckBox`、`Chip`、
`ChipGroup`、`MaterialDatePicker`、`MaterialTimePicker`、`MaterialAlertDialogBuilder`、
`Snackbar`、`BottomSheetDialog`、`SwitchMaterial`、`MaterialDivider`、`TabLayout`、
`NestedScrollView`、`ViewPager2`、`AppCompatImageView`、`AppCompatTextView`、Canvas/Paint/Path。

### 5.2 尺寸与颜色

- 间距走 8dp 网格：4/8/12/16/24/32。
- 卡片圆角 16dp，对话框 28dp，Chip 8dp。
- 字号：标题 24sp、小标题 16sp、正文 14sp、说明 12sp；显式写 `sp`。
- 颜色写 `?attr/colorSurface`、`?attr/colorOnSurfaceVariant` 等；Canvas、图标着色用
  `activity.themeUtil.*`（`primary.main`、`surface.containerLow`、`outline.variant`…）。
- 页面根背景 `?attr/colorSurface`；卡片 `?attr/colorSurfaceContainerLow`；描边 `?attr/colorOutlineVariant`。

### 5.3 底部导航

`BottomNavigationView` 的菜单用 `nav.getMenu().add(groupId, itemId, order, title)` 动态创建，
图标用 `item.setIcon(Drawable)`。选中监听：
`BottomNavigationView.OnItemSelectedListener{ onNavigationItemSelected = function(item) … return true end }`。

### 5.4 自定义图标

`components/icons.lua` 用 Canvas 在 96×96 位图上绘制线性图标，返回带 bounds 的
`BitmapDrawable`。`Paint.setColor` 必须传 signed int；线宽 `size/12`，圆头圆角。
图标直接作为 `src`（布局）或 `setImageDrawable`（代码）使用。

---

## 6. 生命周期与资源释放

- `main.lua` 定义 `onDestroy`，调用 `App.dispose()`：停止定时器、注销广播接收器、关闭数据库。
- 页面切换不销毁 Activity，改为替换内容容器，避免频繁重建。
- 所有 `activity.delay`、`timer` 回调必须检查页面是否仍挂载（`page.alive`）。
- 数据库连接进程内单例，`onDestroy` 时关闭。

---

## 7. 错误处理

- 数据层方法返回 `result, err`；仓储层用 `pcall` 包裹事务，失败回滚并返回错误信息。
- 关键写操作失败必须给用户可见反馈（Snackbar 或对话框），不允许静默失败。
- `main.lua` 定义 `onError`，返回 `"trace"` 以便完整堆栈写日志。

---

## 8. 打包与验证

- `init.lua` 字段：`app_name`、`package_name`、`ver_name`、`ver_code`、`min_sdk`、`target_sdk`、
  `NeLuaJ_Theme`、`user_permission`。
- 权限变更必须重新打包才生效；IDE 内运行不等于 APK 权限已生效。
- 验证顺序：`check_lua_syntax` → `layout_check` → `run_project`（真机无崩溃）→ `build_project`。
