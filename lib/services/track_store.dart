// 考试赛道：四类考试各自独立，互不干扰。
//
// 说明：这里说的「不重合」= 每个赛道有自己的一套单词、复习进度、错词和统计。
// 同一个英文单词（比如 abandon）可以同时存在于四级和考研，
// 但它们是两条独立记录，各背各的、各算各的掌握度，互不牵连。

import 'package:flutter/foundation.dart';

import '../db/database_helper.dart';

/// 一个考试赛道
class Track {
  final String id; // 存库用的标识
  final String label; // 完整名称
  final String short; // AppBar 上显示的短名

  const Track({
    required this.id,
    required this.label,
    required this.short,
  });
}

class TrackStore {
  TrackStore._();

  // 四个赛道的标识。改这四个字符串会牵动数据库里的历史数据，不要随意改。
  static const String cet4 = 'CET4';
  static const String cet6 = 'CET6';
  static const String upgrade = 'UPGRADE';
  static const String kaoyan = 'KAOYAN';

  static const List<Track> tracks = <Track>[
    Track(id: cet4, label: '英语四级', short: '四级'),
    Track(id: cet6, label: '英语六级', short: '六级'),
    Track(id: upgrade, label: '专升本英语', short: '专升本'),
    Track(id: kaoyan, label: '考研英语', short: '考研'),
  ];

  /// 当前选中的赛道。页面切数据、主界面刷新都靠它。
  static final ValueNotifier<String> current = ValueNotifier<String>(cet4);

  /// 启动时从本地设置里读回上次选的赛道
  static Future<void> load() async {
    final String? saved = await DatabaseHelper.instance.getSetting('current_track');
    current.value = _valid(saved) ? saved! : cet4;
  }

  /// 切换赛道：写库 + 通知所有页面
  static Future<void> setCurrent(String id) async {
    if (!_valid(id)) return;
    await DatabaseHelper.instance.setSetting('current_track', id);
    current.value = id;
  }

  /// 取赛道的完整名称（用于 AI 提示词、统计页标题等）
  static String labelOf(String id) {
    for (final Track t in tracks) {
      if (t.id == id) return t.label;
    }
    return '英语四级';
  }

  static String shortOf(String id) {
    for (final Track t in tracks) {
      if (t.id == id) return t.short;
    }
    return '四级';
  }

  static bool _valid(String? id) =>
      id != null && tracks.any((Track t) => t.id == id);
}
