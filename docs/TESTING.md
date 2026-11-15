# 测试与验证记录

本文件记录**实际执行过**的验证，以及验证方式。未执行的项目不列为通过。

验证环境：HONOR ANN-AN00 / Android 15（API 35）/ LuaJ++ 1.0。

## 验证方法

开发期使用临时脚本（`probe_*.lua`）在 `run_project` 中执行，结果写入文本文件后读取。
脚本在交付前已删除，结论保留在此。复现方式：

1. 在工程根新建 `probe_xxx.lua`。
2. 用 `pcall` 包裹每项检查，把 `[OK]/[FAIL]` 与关键数值追加到数组。
3. 用 `LuaFileUtil.writeOrCreate` 写到工程目录下的 `.txt`。
4. `run_project` 运行该脚本，读取输出文件，再删除脚本。

先在脚本里删除 `nivora.db` 可保证每次都是干净数据（探针专用，正式应用不要这样做）。

要验证保存逻辑，用编辑器的 `M.persist(ctx, existing, values)`——
它把校验与落库从界面里拆了出来，不需要弹窗即可测。

## 一、环境能力探测

| 检查项 | 结果 | 备注 |
| --- | --- | --- |
| SQLite 打开/建表/事务/回滚 | 通过 | 回滚后无脏数据 |
| `SQLiteOpenHelper` 子类 + `onUpgrade` | 通过 | 实测回调触发，旧库升级到新版本，列数变化可见 |
| `PRAGMA foreign_keys` | 通过 | 返回 1 |
| 外键级联删除 | 通过 | 删习惯后打卡记录消失 |
| `INSERT OR IGNORE` 冲突 | 通过 | 冲突时 `executeInsert()` 返回 -1 |
| 大整数时间戳绑定 | 通过 | `1794718000000` 读写无损 |
| 文本参数与数值列比较 | 通过 | `ts > ?` / `id = ?` 结果正确 |
| SharedPreferences | 通过 | `commit()` 返回 true |
| 通知渠道创建 | 通过 | importance = 4 |
| 通知发送 | 通过 | 需运行时授权 `POST_NOTIFICATIONS`；授权后能进通知栏 |
| 通知小图标 | 通过 | 用 `activity.getApplicationInfo().icon`（`android.R.drawable` 字段不能按名反射） |
| 运行时注册广播接收器 | 通过 | `BroadcastReceiver.override` + `registerReceiver` 能收到 `sendBroadcast` |
| `AlarmManager.setAndAllowWhileIdle` | 通过 | 2 秒后广播实测送达（进程存活） |
| `canScheduleExactAlarms()` | 返回 false | 因此不使用精确闹钟，只用 `setAndAllowWhileIdle` |
| `PendingIntent.getBroadcast` | 通过 | |
| 通知点击回到页面 | 通过 | `Intent(activity, activity.getClass())` + `file://` 数据 |
| MD3 控件绑定 | 通过 | 39 个类全部可 `bindClass`（Toolbar/Card/Button/Chip/DatePicker/TimePicker/Snackbar/BottomSheet 等） |
| `BottomNavigationView` 动态菜单 + 图标 | 通过 | `getMenu().add(...)` + `item.setIcon(Drawable)` |
| `MaterialDatePicker` / `MaterialTimePicker` | 通过 | `show(supportFragmentManager, tag)` 正常弹出 |
| 自定义 View（`View.override{onDraw}`） | 通过 | 用于图标与图表 |
| Canvas 绘制像素校验 | 通过 | 96×96 位图上采样到预期颜色 |
| `res.drawable` 读取内置矢量 | 通过 | `ic_dashboard`、`ic_article` 等 |
| `res.drawable("<lua图标>", color)` 着色 | **失败** | `.lua` 图标返回 Bitmap 时内部按 Drawable tint 而报错 → 改为自建 `BitmapDrawable` |
| `Paint.setColor(0xFF6750A4)` | **失败** | 绑定到 `setColor(long)` 抛 `IllegalArgumentException` → 统一用 `Color.parseColor` |
| 主题 `themeUtil` 取色 | 通过 | `primary.main`、`surface.containerLow` 等 |
| 夜间模式 | 通过 | `AppCompatDelegate.setDefaultNightMode` |
| 动态取色 | 通过 | `activity.dynamicColor(seed)` |

## 二、数据层端到端断言（20 项，全部通过）

| 断言 | 结果 |
| --- | --- |
| 习惯创建 + 首次打卡成功 | 通过 |
| 同一天重复打卡被拒绝 | 通过（返回 false） |
| 连续天数从 1 起算 | 通过 |
| `weekly_days`：周一非计划日、周六是计划日 | 通过 |
| 暂停习惯不计入计划日 | 通过 |
| 每周重复 14 天区间展开数量正确 | 通过（14 条） |
| 单次取消只影响当天，后续实例保留 | 通过（当天 0，次日 1） |
| `monthly` 每月 31 日在 2 月回退到 28 日 | 通过（`2026-02-28`） |
| 时间段冲突能识别；排除自身后为空 | 通过 |
| 子任务数量统计 | 通过（0/2） |
| 逾期判断（截止日已过） | 通过 |
| 勾选完成后 `overdue` 变 false 且记录 `completed_at` | 通过 |
| 目标进度按里程碑计算（1/2 → 50%） | 通过 |
| 里程碑 + 关联任务混合进度（1/2 + 1/1 → 75%） | 通过 |
| 删除目标保留任务并解除关联 | 通过（`goal_id` 变 NULL） |
| 每日记录同一天 upsert 复用同一条 | 通过 |
| 倒数日每年重复 + 闰日回退（2000-02-29 → 2027-02-28） | 通过 |
| 专注计时状态持久化并在新实例恢复 | 通过 |
| 导出 → 导入往返后数据条数不变 | 通过 |
| 非法 JSON / 非 Nivora 备份被拒绝且不破坏原数据 | 通过 |

## 三、编辑器保存路径（通过）

将保存逻辑从表单里拆出为 `M.persist`，逐个验证：

| 用例 | 结果 |
| --- | --- |
| 待办：创建、标题自动 trim、优先级保存、未分类写 NULL | 通过 |
| 待办：编辑时清空截止日期生效 | 通过 |
| 待办：空标题、超长标题被拒绝 | 通过 |
| 习惯：未选打卡日被拒绝 | 通过 |
| 习惯：创建后 `weekly_days` 排期正确、提醒时间保存 | 通过 |
| 日程：创建后重复规则与提醒分钟保存、展开正确 | 通过 |
| 日程：结束时间早于开始时间时自动修正 | 通过 |
| 日程：空标题、非法日期被拒绝 | 通过 |
| 倒数日：创建后剩余天数正确（12 天）、提醒天数保存 | 通过 |
| 倒数日：空日期被拒绝 | 通过 |
| 四个编辑器 `open()` 均返回可用对话框并可关闭 | 通过 |

## 四、对话框真实交互（第二轮，通过）

在真机上真实打开对话框、写入输入框、点击提交按钮，再回查数据库：

| 用例 | 结果 |
| --- | --- |
| 待办新建对话框：输入标题 → 点「创建」 | 通过，落库 id=1，对话框自动关闭 |
| 习惯新建对话框：输入名称 → 点「创建」 | 通过，`frequency_type=daily` |
| 日程新建对话框：输入标题 → 点「创建」 | 通过，默认日期为今天，开始时间正确 |
| 倒数日新建对话框：输入名称 → 点「创建」 | 通过，剩余天数计算正确 |
| 待办优先级选择「高」后提交 | 通过，`priority=2` |
| 习惯图标选择「book」后提交 | 通过，`icon=book`，颜色一并保存 |
| 编辑习惯：预填原名称 | 通过，输入框内容 = 原名称 |
| 编辑习惯：改名保存 | 通过，记录被更新而非新增（总数仍为 1） |
| 待办详情：输入子任务 → 点「+」 | 通过，子任务落库 |
| 目标详情：输入里程碑 → 点「+」 | 通过，里程碑落库 |
| 每日记录面板：输入正文+标签 → 点「保存」 | 通过，正文与 tags 均正确 |
| 每日记录面板：点「取消」 | 通过，数据库无记录 |
| 每日记录面板：只输入空白 → 点「保存」 | 通过，被拒绝且不落库 |

日程页时段导航的标题宽度实测为 **172 dp**（修复前被压到不可读），
`ui.fill` 改为逐个子视图 `addView` 后，水平容器不再被强行竖排。

## 五、界面冒烟（通过）

在同一 Activity 内构建完整外壳，逐个触发：

| 用例 | 结果 |
| --- | --- |
| 建库 + 应用主题 + 构建底部导航外壳 | 通过 |
| 标签 1 首页 渲染 | 通过 |
| 标签 2 日程 渲染 | 通过 |
| 标签 3 习惯 渲染 | 通过 |
| 标签 4 统计 渲染 | 通过 |
| 标签 5 我的 渲染 | 通过 |
| 切回首页、刷新全部标签 | 通过 |
| 推入/弹出：待办、目标、每日记录、倒数日、专注、设置 | 通过 |
| 49 个 Canvas 图标全部构建 | 通过 |
| 柱状图 / 折线图 / 进度环构建 | 通过 |
| 返回键：子页面 → 主标签 → 退出 | 通过 |

## 六、通知与提醒（部分通过）

| 用例 | 结果 |
| --- | --- |
| 通知渠道创建与投递 | 通过（授权后） |
| 通知权限申请流程 | 通过（`permissionLauncher` 返回 granted=true） |
| 提醒排期表写入/读取/移除 | 通过 |
| `resync()` 按当前数据重排（日程/待办/倒数日/习惯） | 通过（生成 6 条并按类型分布） |
| 应用存活时闹钟到点送达并弹通知 | 通过（2 秒闹钟实测） |
| **进程被系统杀死后独立推送** | **无法实现** |
| **设备重启后自动恢复提醒** | **无法实现** |

后两项原因是 NeLuaJ+ 的 `init.lua` 无法声明清单广播接收器，因此无法接收
`BOOT_COMPLETED`，也无法让标准闹钟广播在进程外唤醒。已实现的替代方案：
应用每次启动与回到前台时按 `reminders` 表重新排期，并补发最近一小时内过期的提醒。

## 七、未验证 / 已知缺口

1. **打包后 APK 的独立启动**：需重新打包安装后确认（权限、启动页、数据库路径）。
2. **每日记录图片附件**：未实现。
3. **横屏/大字体适配**：布局使用 `match/wrap` 与权重，理论上可自适应，但未逐一实测。
4. **主题种子色**：Android 12–13 受系统限制可能回退为跟随壁纸。
5. **日期/时间选择器弹窗内的确认**：`MaterialDatePicker` / `MaterialTimePicker` 能正常弹出，
   但自动化脚本没有在系统选择器里选日期再确认（选择器是独立 Fragment 窗口）。
   表单里非日期字段的读写均已验证。

## 八、复现清单

若要重跑核心断言，建议顺序：

1. 建库与升级：`App.create()` 后检查 `db.db.getVersion() == 1`，再看默认分类数。
2. 习惯：创建 → 打卡两次（第二次应失败）→ 查连续天数。
3. 日程：创建每周重复 → 展开 30 天 → 取消某一天 → 确认只有该天消失。
4. 待办：创建 → 加子任务 → 勾选 → 检查 `overdue` 与 `completed_at`。
5. 目标：加两个里程碑完成一个 → 进度应为 50%。
6. 备份：导出 JSON → 导入同一份 → 条数不变；再导入非法内容 → 报错且数据不变。
7. 专注：`start` → 新建计时器实例验证状态恢复 → `finish`。
8. 对话框：调用 `Editor.open(ctx, nil, cb)` 打开表单，遍历
   `dialog.findViewById(android.R.id.content)` 找到 `EditText` 用 `setText` 写入，
   再点文本为「创建」的按钮，延迟后回查数据库。详情面板用
   `modules/<模块>.page.openDetail(ctx, id, cb)`，每日记录用
   `modules.journal.page.openEditor(ctx, dateStr, cb)`。
