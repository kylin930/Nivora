app_name = "Nivora"
package_name = "com.xiaolin.nivora"
ver_name = "1.0.2"
ver_code = "3"
min_sdk = "26"
target_sdk = "33"
debug_mode = false
NeLuaJ_Theme = "Theme_NeLuaJ_Material3_NoActionBar_ActionOverlay"
-- POST_NOTIFICATIONS：Android 13+ 发送提醒通知
-- SCHEDULE_EXACT_ALARM：声明精确闹钟能力（本机 canScheduleExactAlarms 为 false，运行时会退化为 setAndAllowWhileIdle）
-- VIBRATE：提醒通知震动
user_permission = {
  "POST_NOTIFICATIONS",
  "SCHEDULE_EXACT_ALARM",
  "VIBRATE",
}
