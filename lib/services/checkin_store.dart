// 打卡记录：只存一串日期（YYYY-MM-DD），放在 settings 表里。
// 不建表是因为它实在太小——一个月 30 个字符串，没必要单开一张表。

import '../db/database_helper.dart';

class CheckInStore {
  CheckInStore._();

  static const String key = 'checkin_days';

  static String dayKey(DateTime d) {
    final String m = '${d.month}'.padLeft(2, '0');
    final String day = '${d.day}'.padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  static String todayKey() => dayKey(DateTime.now());

  static Future<Set<String>> all() async {
    final String? raw =
        await DatabaseHelper.instance.getSetting(key);
    if (raw == null || raw.trim().isEmpty) return <String>{};
    return raw
        .split(',')
        .map((String s) => s.trim())
        .where((String s) => s.length == 10)
        .toSet();
  }

  static Future<bool> doneToday() async {
    return (await all()).contains(todayKey());
  }

  /// 打卡。重复打卡不会写两遍。
  static Future<void> checkIn() async {
    final Set<String> days = await all();
    if (!days.add(todayKey())) return;
    final List<String> sorted = days.toList()..sort();
    await DatabaseHelper.instance.setSetting(key, sorted.join(','));
  }

  /// 连续天数：从今天往回数，断一天就停。
  /// 今天还没打卡时从昨天开始数，这样白天看一眼不会显示 0。
  static Future<int> streak() async {
    final Set<String> days = await all();
    DateTime cursor = DateTime.now();
    if (!days.contains(dayKey(cursor))) {
      cursor = cursor.subtract(const Duration(days: 1));
      if (!days.contains(dayKey(cursor))) return 0;
    }
    int n = 0;
    while (days.contains(dayKey(cursor))) {
      n++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return n;
  }

  /// 本月打过卡的日期号，日历上用来画点
  static Future<Set<int>> monthDays(DateTime month) async {
    final Set<String> days = await all();
    final String prefix =
        '${month.year}-${month.month.toString().padLeft(2, '0')}-';
    return days
        .where((String s) => s.startsWith(prefix))
        .map((String s) => int.tryParse(s.substring(8)) ?? -1)
        .where((int d) => d > 0)
        .toSet();
  }
}
