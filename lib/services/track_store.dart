// 分区：每个分区一套独立的词、复习进度、错词和统计。
//
// 现在是自由分区：名字、数量都能改，存在 sections 表里。
// 默认给四个（四级 / 六级 / 专升本 / 考研），用户可以改名或删掉。

import 'package:flutter/foundation.dart';

import '../db/database_helper.dart';

/// 一个分区
class Track {
  final String id; // 存库用的标识
  final String label; // 完整名称
  final String short; // 顶部显示的短名

  const Track({required this.id, required this.label, required this.short});
}

class TrackStore {
  TrackStore._();

  // 默认四个分区的标识。已有数据都挂在这四个 id 上，不能随便改。
  static const String cet4 = 'CET4';
  static const String cet6 = 'CET6';
  static const String upgrade = 'UPGRADE';
  static const String kaoyan = 'KAOYAN';

  static const List<Track> defaults = <Track>[
    Track(id: cet4, label: '英语四级', short: '四级'),
    Track(id: cet6, label: '英语六级', short: '六级'),
    Track(id: upgrade, label: '专升本英语', short: '专升本'),
    Track(id: kaoyan, label: '考研英语', short: '考研'),
  ];

  static List<Track> _tracks = defaults;

  /// 当前的分区列表（每次改完会换一个新 list）
  static List<Track> get tracks => _tracks;

  /// 列表变更信号，抽屉之类常驻的界面靠它重建
  static final ValueNotifier<int> version = ValueNotifier<int>(0);

  /// 当前选中的分区。页面切数据、主界面刷新都靠它。
  static final ValueNotifier<String> current = ValueNotifier<String>(cet4);

  /// 启动时从库里读回分区和上次选的那个
  static Future<void> load() async {
    final List<Map<String, Object?>> rows = await DatabaseHelper.instance
        .getSections();
    if (rows.isEmpty) {
      _tracks = defaults;
    } else {
      _tracks = rows
          .map(
            (Map<String, Object?> r) => Track(
              id: r['id'] as String,
              label: (r['name'] as String?) ?? '分区',
              short: _short((r['name'] as String?) ?? '分区'),
            ),
          )
          .toList();
    }
    version.value++;

    final String? saved = await DatabaseHelper.instance.getSetting(
      'current_track',
    );
    final bool ok = saved != null && _tracks.any((Track t) => t.id == saved);
    current.value = ok ? saved! : _tracks.first.id;
  }

  static String _short(String name) {
    if (name.length <= 4) return name;
    // 「英语四级」这类去掉前面的「英语」更好看
    if (name.startsWith('英语') && name.length > 4) {
      return name.substring(2);
    }
    return name.substring(0, 4);
  }

  /// 切换分区：写库 + 通知所有页面
  static Future<void> setCurrent(String id) async {
    if (!_valid(id)) return;
    await DatabaseHelper.instance.setSetting('current_track', id);
    current.value = id;
  }

  static Future<Track?> add(String name) async {
    final String n = name.trim();
    if (n.isEmpty) return null;
    if (_tracks.any((Track t) => t.label == n)) return null;
    final String id = 'S${DateTime.now().millisecondsSinceEpoch}';
    await DatabaseHelper.instance.insertSection(
      id: id,
      name: n,
      sort: _tracks.length,
    );
    await load();
    return _tracks.firstWhere((Track t) => t.id == id);
  }

  static Future<bool> rename(String id, String name) async {
    final String n = name.trim();
    if (n.isEmpty) return false;
    await DatabaseHelper.instance.renameSection(id, n);
    await load();
    return true;
  }

  /// 删除分区。只剩一个、或者分区里还有词，都不让删。
  static Future<String?> remove(String id) async {
    if (_tracks.length <= 1) return '至少要留一个分区';
    final int n = await DatabaseHelper.instance.countWords(track: id);
    if (n > 0) return '这个分区里还有 $n 个词，先移走或删掉';
    final bool wasCurrent = current.value == id;
    await DatabaseHelper.instance.deleteSection(id);
    await load();
    if (wasCurrent && _tracks.isNotEmpty) {
      await setCurrent(_tracks.first.id);
    }
    return null;
  }

  /// 取完整名称（用于 AI 提示词、统计页标题等）
  static String labelOf(String id) {
    for (final Track t in _tracks) {
      if (t.id == id) return t.label;
    }
    return _tracks.isEmpty ? '分区' : _tracks.first.label;
  }

  static String shortOf(String id) {
    for (final Track t in _tracks) {
      if (t.id == id) return t.short;
    }
    return _tracks.isEmpty ? '分区' : _tracks.first.short;
  }

  static bool _valid(String? id) =>
      id != null && _tracks.any((Track t) => t.id == id);
}
