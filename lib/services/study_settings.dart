// 学习设置：每天抽多少个、默写用列表还是卡片、学习流程用四步还是连续小循环。
// 存在 settings 表里，设置页改，学习流程页读。

import '../db/database_helper.dart';

class StudySettings {
  StudySettings._();

  static const int defaultCount = 20;

  static const String keyCount = 'daily_draw_count';
  static const String keyMode = 'dictation_mode'; // list | card
  static const String keyFlow = 'study_flow'; // steps | loop
  static const String keyClearedDay = 'today_cleared_day'; // YYYY-MM-DD
  static const String keyRate = 'speech_rate';

  /// 默认语速：比正常说话慢一档。背单词要听清音节，
  /// 1.0 是正常速度，太快跟不上；低于 0.25 会拖成怪腔。
  static const double defaultRate = 0.3;
  static const double minRate = 0.15;
  static const double maxRate = 1.0;

  /// 今天这批被手动清空了：记个日期，当天就不再自动重抽。
  /// 不然清空完一重启 App，词又自己回来了，等于没清。
  static Future<String> _today() async {
    final DateTime now = DateTime.now();
    final String m = '${now.month}'.padLeft(2, '0');
    final String d = '${now.day}'.padLeft(2, '0');
    return '${now.year}-$m-$d';
  }

  static Future<bool> clearedToday() async {
    final String? v =
        await DatabaseHelper.instance.getSetting(keyClearedDay);
    return v != null && v == await _today();
  }

  static Future<void> markClearedToday() async {
    await DatabaseHelper.instance.setSetting(keyClearedDay, await _today());
  }

  /// 手动「抽 N 个」时要把清空标记抹掉，否则当天再也抽不出来
  static Future<void> clearClearedMark() async {
    await DatabaseHelper.instance.setSetting(keyClearedDay, '');
  }

  /// 两种学习流程
  /// steps：四步（看英想中 → 看中想英 → 写中文 → 写英文），一批词过一遍
  /// loop ：连续小循环（拼第 N 个 → 闪中文 → 拼第 N+1 个 → 回头考第 N 个）
  ///        复刻「抄两个回头回忆前面」的机制，每一步都带发音
  static Future<String> studyFlow() async {
    final String? v = await DatabaseHelper.instance.getSetting(keyFlow);
    return v == 'loop' ? 'loop' : 'steps';
  }

  static Future<void> setStudyFlow(String flow) async {
    await DatabaseHelper.instance.setSetting(
      keyFlow,
      flow == 'loop' ? 'loop' : 'steps',
    );
  }

  static Future<bool> isLoop() async => await studyFlow() == 'loop';

  static Future<int> dailyCount() async {
    final String? v = await DatabaseHelper.instance.getSetting(keyCount);
    final int? n = int.tryParse(v ?? '');
    if (n == null || n < 1) return defaultCount;
    return n > 200 ? 200 : n;
  }

  static Future<void> setDailyCount(int n) async {
    final int v = n < 1 ? 1 : (n > 200 ? 200 : n);
    await DatabaseHelper.instance.setSetting(keyCount, '$v');
  }

  /// 朗读语速。每个人耳朵不一样，这个必须能自己调。
  static Future<double> speechRate() async {
    final String? v = await DatabaseHelper.instance.getSetting(keyRate);
    final double? r = double.tryParse(v ?? '');
    if (r == null) return defaultRate;
    return r.clamp(minRate, maxRate);
  }

  static Future<void> setSpeechRate(double r) async {
    final double v = r < minRate
        ? minRate
        : (r > maxRate ? maxRate : r);
    await DatabaseHelper.instance.setSetting(keyRate, v.toStringAsFixed(2));
  }

  /// 'list' = 一屏列出来一起填；'card' = 逐个来
  static Future<String> dictationMode() async {
    final String? v = await DatabaseHelper.instance.getSetting(keyMode);
    return v == 'card' ? 'card' : 'list';
  }

  static Future<void> setDictationMode(String mode) async {
    await DatabaseHelper.instance.setSetting(
      keyMode,
      mode == 'card' ? 'card' : 'list',
    );
  }
}
