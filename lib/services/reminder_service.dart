// 每日提醒：调用原生 AlarmManager + NotificationManager，不依赖第三方插件。
//
// 提醒是 inexactRepeating，不需要「精确闹钟」权限；系统省电策略下可能晚几分钟。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../db/database_helper.dart';

class ReminderService {
  ReminderService._();

  static const MethodChannel _channel = MethodChannel('app.reminder');
  static const String keyEnabled = 'reminder_enabled';
  static const String keyHour = 'reminder_hour';
  static const String keyMinute = 'reminder_minute';

  static Future<void> init() async {
    // 原生侧在 MainActivity 里建通道，这里不需要预热
  }

  /// 申请通知权限。系统弹窗是异步的，所以申请后轮询几次结果。
  static Future<bool> requestPermission() async {
    try {
      await _channel.invokeMethod<bool>('requestPermission');
      // 系统弹窗是异步的，给用户留出点「允许」的时间
      for (int i = 0; i < 24; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final bool ok =
            await _channel.invokeMethod<bool>('permission') ?? false;
        if (ok) return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> schedule(TimeOfDay time) async {
    try {
      await _channel.invokeMethod<bool>('schedule', <String, int>{
        'hour': time.hour,
        'minute': time.minute,
      });
    } catch (_) {}
  }

  static Future<void> cancel() async {
    try {
      await _channel.invokeMethod<bool>('cancel');
    } catch (_) {}
  }

  // ---------------- 偏好 ----------------

  static Future<bool> isEnabled() async {
    final String? v = await DatabaseHelper.instance.getSetting(keyEnabled);
    return v == '1';
  }

  static Future<TimeOfDay> savedTime() async {
    final String? h = await DatabaseHelper.instance.getSetting(keyHour);
    final String? m = await DatabaseHelper.instance.getSetting(keyMinute);
    final int hour = int.tryParse(h ?? '') ?? 20;
    final int minute = int.tryParse(m ?? '') ?? 0;
    return TimeOfDay(hour: hour.clamp(0, 23), minute: minute.clamp(0, 59));
  }

  static Future<void> save(TimeOfDay t) async {
    await DatabaseHelper.instance.setSetting(keyHour, '${t.hour}');
    await DatabaseHelper.instance.setSetting(keyMinute, '${t.minute}');
  }

  static Future<void> enable(TimeOfDay t) async {
    await save(t);
    await DatabaseHelper.instance.setSetting(keyEnabled, '1');
    await schedule(t);
  }

  static Future<void> disable() async {
    await DatabaseHelper.instance.setSetting(keyEnabled, '0');
    await cancel();
  }

  /// 冷启动时对一遍：开着就重排一次，系统清理过也能补回来
  static Future<void> resync() async {
    if (!await isEnabled()) return;
    final TimeOfDay t = await savedTime();
    await schedule(t);
  }
}
