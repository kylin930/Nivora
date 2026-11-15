-- 设置页（子页面）：外观、日程、习惯、专注、数据与关于
local bindClass = luajava.bindClass
local LinearLayout = bindClass "android.widget.LinearLayout"
local ScrollView = bindClass "androidx.core.widget.NestedScrollView"

local ui = require "components.ui"
local theme = require "config.theme"
local constants = require "config.constants"
local dateUtils = require "utils.date_utils"
local eventBus = require "core.event_bus"
local Form = require "components.form_dialog"

local M = {}

M.title = "设置"

local THEME_OPTIONS = {
  { value = "system", name = "跟随系统" },
  { value = "light", name = "浅色" },
  { value = "dark", name = "深色" },
}

local SEED_OPTIONS = {
  { value = "", name = "跟随壁纸" },
  { value = "#6750A4", name = "紫罗兰" },
  { value = "#0061A4", name = "海洋蓝" },
  { value = "#3F6834", name = "森林绿" },
  { value = "#8B5000", name = "赭石" },
  { value = "#8C4A60", name = "玫瑰" },
}

function M.create(ctx)
  local app = ctx.app
  local settings = app.settings
  local page = { alive = true }
  local refresh

  local views = {}
  local root = loadlayout({
    LinearLayout,
    orientation = "vertical",
    layout_width = "match",
    layout_height = "match",
    BackgroundColor = theme.ATTR.surface,
    {
      LinearLayout,
      orientation = "horizontal",
      layout_width = "match",
      layout_height = "wrap",
      paddingStart = "8dp",
      paddingEnd = "12dp",
      paddingTop = "8dp",
      gravity = "center_vertical",
      {
        ui.iconButton("chevron_left", function() ctx.nav:pop() end),
        ui.text("设置", {
          textSize = "20sp", textStyle = "bold",
          layout_width = "0dp", layout_weight = 1, layout_height = "wrap",
          layout_marginStart = "4dp",
        }),
      },
    },
    {
      ScrollView,
      layout_width = "match",
      layout_height = "0dp",
      layout_weight = 1,
      clipToPadding = false,
      {
        LinearLayout,
        id = "content",
        orientation = "vertical",
        layout_width = "match",
        layout_height = "wrap",
        paddingStart = "16dp",
        paddingEnd = "16dp",
        paddingBottom = "32dp",
      },
    },
  }, views)

  local function section(title, rows)
    return ui.card({
      ui.caption(title, { layout_marginBottom = 4 }),
      ui.column(rows, { layout_width = "match", layout_height = "wrap" }),
    }, { marginTop = 10 })
  end

  local function settingRow(title, value, onClick)
    return ui.listItem({
      title = title,
      trailing = value,
      trailingIcon = "chevron_right",
      onClick = onClick,
    })
  end

  local function notifyPermissionRow()
    local granted = app.notifier:hasPermission()
    return settingRow("通知权限", granted and "已开启" or "未开启", function()
      if granted then
        ui.alert("通知已开启", "可以在系统设置中关闭 Nivora 的通知。")
      else
        app.notifier:requestPermission(function(ok)
          if page.alive then
            if ok then
              ui.snackbar(root, "通知已开启")
            else
              ui.alert("未获得通知权限", "没有通知权限时，提醒不会显示。")
            end
            refresh()
          end
        end)
      end
    end)
  end

  local function themeRows()
    return {
      settingRow("主题模式", ({
        system = "跟随系统", light = "浅色", dark = "深色",
      })[settings:get("theme_mode", "system")] or "跟随系统", function()
        local labels = {}
        for _, item in ipairs(THEME_OPTIONS) do labels[#labels + 1] = item.name end
        ui.choose("主题模式", labels, function(index)
          local option = THEME_OPTIONS[index]
          if not option then return end
          theme.setMode(settings, option.value)
          ui.snackbar(root, "已切换外观，界面将重新加载")
        end)
      end),
      settingRow("主题色", (function()
        local seed = settings:get("theme_seed", "")
        if seed == "" then return "跟随壁纸" end
        for _, item in ipairs(SEED_OPTIONS) do
          if item.value == seed then return item.name end
        end
        return seed
      end)(), function()
        local labels = {}
        for _, item in ipairs(SEED_OPTIONS) do labels[#labels + 1] = item.name end
        ui.choose("主题色", labels, function(index)
          local option = SEED_OPTIONS[index]
          if not option then return end
          theme.setSeed(settings, option.value)
          ui.alert("主题色已保存", "重启应用后生效。")
          refresh()
        end)
      end),
    }
  end

  local function scheduleRows()
    return {
      settingRow("默认提醒时间",
        constants.reminderName(settings:defaultReminderMinutes()), function()
          local labels = {}
          for _, item in ipairs(constants.REMINDER_OPTIONS) do labels[#labels + 1] = item.name end
          ui.choose("默认提醒时间", labels, function(index)
            local option = constants.REMINDER_OPTIONS[index]
            if not option then return end
            settings:set("default_reminder_minutes", option.value)
            refresh()
          end)
        end),
      settingRow("一周起始日", settings:weekStart() == 7 and "周日" or "周一", function()
        ui.choose("一周起始日", { "周一", "周日" }, function(index)
          settings:set("week_start", index == 2 and 7 or 1)
          app:reloadRepositories()
          app:changed(eventBus.EVENTS.SETTINGS_CHANGED)
          refresh()
        end)
      end),
      settingRow("默认日历视图", ({
        month = "月", week = "周", day = "日",
      })[settings:get("default_calendar_view", "month")] or "月", function()
        ui.choose("默认日历视图", { "月", "周", "日" }, function(index)
          local values = { "month", "week", "day" }
          settings:set("default_calendar_view", values[index] or "month")
          refresh()
        end)
      end),
    }
  end

  local function habitRows()
    return {
      settingRow("每日提醒",
        settings:getBool("habit_reminder_enabled", false)
          and (settings:get("habit_reminder_time", "21:00")) or "关闭", function()
          ui.choose("习惯每日提醒", { "关闭", "开启" }, function(index)
            if index == 1 then
              settings:set("habit_reminder_enabled", false)
            else
              Form.pickTime(21, 0, function(hour, minute)
                settings:set("habit_reminder_enabled", true)
                settings:set("habit_reminder_time", dateUtils.timeLabel(hour, minute))
                app.remindersService:resync()
                refresh()
              end)
              return
            end
            app.remindersService:resync()
            refresh()
          end)
        end),
      settingRow("今日列表显示已完成", settings:getBool("show_completed_in_today", false) and "是" or "否",
        function()
          settings:set("show_completed_in_today", not settings:getBool("show_completed_in_today", false))
          refresh()
        end),
    }
  end

  local function focusRows()
    return {
      settingRow("专注时长", settings:focusMinutes() .. " 分钟", function()
        Form.pickTime(0, settings:focusMinutes(), function(hour, minute)
          local value = hour * 60 + minute
          if value < 1 then value = 25 end
          settings:set("focus_minutes", value)
          refresh()
        end)
      end),
      settingRow("短休息", settings:shortBreakMinutes() .. " 分钟", function()
        ui.choose("短休息", { "3 分钟", "5 分钟", "10 分钟" }, function(index)
          local values = { 3, 5, 10 }
          settings:set("short_break_minutes", values[index] or 5)
          refresh()
        end)
      end),
      settingRow("长休息", settings:longBreakMinutes() .. " 分钟", function()
        ui.choose("长休息", { "10 分钟", "15 分钟", "20 分钟", "30 分钟" }, function(index)
          local values = { 10, 15, 20, 30 }
          settings:set("long_break_minutes", values[index] or 15)
          refresh()
        end)
      end),
      settingRow("自动进入休息", settings:getBool("auto_start_break", false) and "开启" or "关闭",
        function()
          settings:set("auto_start_break", not settings:getBool("auto_start_break", false))
          refresh()
        end),
    }
  end

  local function dataRows()
    local BackupService = app.backup
    return {
      settingRow("导出数据（JSON）", "系统文件选择器", function()
        BackupService:exportWithPicker(function(ok, err)
          if not page.alive then return end
          if ok then
            ui.snackbar(root, "导出成功")
          elseif err then
            ui.alert("导出未完成", tostring(err))
          end
        end)
      end),
      settingRow("导入数据（JSON）", "先备份现有数据", function()
        ui.confirm({
          title = "导入数据",
          message = "导入会覆盖当前全部数据。系统会先自动备份一次到应用目录，仍建议你先手动导出一份。",
          confirmText = "选择文件",
        }, function()
          BackupService:importWithPicker(function(ok, err)
            if not page.alive then return end
            if ok then
              ui.snackbar(root, "导入成功")
              refresh()
            elseif err then
              ui.alert("导入失败", tostring(err))
            end
          end)
        end)
      end),
      settingRow("本地备份", "保存一份快照", function()
        local path = BackupService:saveLocal()
        if path then
          ui.snackbar(root, "已备份到应用目录")
        else
          ui.alert("备份失败", "无法写入备份文件")
        end
      end),
      settingRow("从本地备份恢复", "选择快照", function()
        local list = BackupService:listLocal()
        if #list == 0 then
          ui.alert("没有本地备份", "先执行一次「本地备份」。")
          return
        end
        local labels = {}
        for _, item in ipairs(list) do
          labels[#labels + 1] = item.name
        end
        ui.choose("选择备份文件", labels, function(index)
          local item = list[index]
          if not item then return end
          ui.confirm({
            title = "恢复数据",
            message = "将用「" .. item.name .. "」覆盖当前数据，确定继续？",
            confirmText = "恢复",
          }, function()
            BackupService:importLocal(item.path, function(ok, err)
              if not page.alive then return end
              if ok then
                ui.snackbar(root, "恢复成功")
                refresh()
              else
                ui.alert("恢复失败", tostring(err))
              end
            end)
          end)
        end)
      end),
      settingRow("清空全部数据", "不可撤销", function()
        ui.confirm({
          title = "清空全部数据",
          message = "这会删除所有习惯、日程、待办、目标、记录。操作前会自动生成一份本地备份。",
          confirmText = "清空",
        }, function()
          local ok, err = BackupService:clearAll()
          if not ok then
            ui.alert("清空失败", tostring(err))
            return
          end
          app:changed(eventBus.EVENTS.DATA_CHANGED)
          ui.snackbar(root, "已清空，可在本地备份中找回")
          refresh()
        end)
      end),
    }
  end

  local function aboutRows()
    return {
      settingRow("应用名称", constants.APP_NAME, function() end),
      settingRow("版本", constants.VERSION, function() end),
      settingRow("技术栈", "Lua + NeLuaJ+ + MD3", function() end),
      settingRow("运行环境", "Android " .. bindClass("android.os.Build").VERSION.RELEASE, function() end),
      settingRow("通知说明", "应用存活时提醒", function()
        ui.alert("关于提醒",
          "Nivora 的提醒依赖应用进程。应用被系统清理后，提醒不会独立送达，"
          .. "下次打开应用时会补发最近的提醒。这是打包能力的限制，不是遗漏。")
      end),
    }
  end

  refresh = function()
    if not page.alive then return end
    ui.fill(views.content, {
      section("外观", themeRows()),
      section("日程", scheduleRows()),
      section("习惯", habitRows()),
      section("专注", focusRows()),
      section("通知", { notifyPermissionRow() }),
      section("数据", dataRows()),
      section("关于", aboutRows()),
    })
  end

  page.view = root
  page.refresh = refresh
  page.onShow = refresh
  page.destroy = function() page.alive = false end

  refresh()
  return page
end

return M
