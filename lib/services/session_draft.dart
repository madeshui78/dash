// 学习进度的草稿：学一半退出，下次进来接着学。
//
// 背景：一批词默认 20 个，手滑能抽到七八十个。四个步骤走下来是场持久战，
// 中途退出以前等于白干——下次进来从第一个词重新开始，正好卡在"背不完"上。
// 这里把进度存成 JSON 塞进 settings 表，重进时按词 id 列表对上就恢复。
//
// 只存"这一批词"，不存历史：切换赛道、抽新一批、或者学完了，草稿就作废。

import 'dart:convert';

import '../db/database_helper.dart';
import '../models/word.dart';

class SessionDraft {
  SessionDraft._();

  static const String key = 'session_draft';

  static Future<void> save(Map<String, Object?> data) async {
    await DatabaseHelper.instance.setSetting(key, jsonEncode(data));
  }

  static Future<Map<String, Object?>?> load() async {
    final String? raw = await DatabaseHelper.instance.getSetting(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final Object? d = jsonDecode(raw);
      if (d is Map<String, Object?>) return d;
      return null;
    } catch (_) {
      // 草稿坏了就当没有，不该让 App 起不来
      return null;
    }
  }

  static Future<void> clear() async {
    await DatabaseHelper.instance.setSetting(key, '');
  }

  static List<int> idsOf(List<Word> words) =>
      words.map((Word w) => w.id!).toList();

  /// 草稿是不是这批词的：词 id 列表必须逐个对得上。
  /// 换了一批词、词序变了、或者词被删了，这份草稿就没有意义了。
  static bool sameBatch(Map<String, Object?>? d, List<Word> words) {
    if (d == null) return false;
    final Object? ids = d['ids'];
    if (ids is! List) return false;
    if (ids.length != words.length) return false;
    for (int i = 0; i < words.length; i++) {
      final Object? v = ids[i];
      if (v is int) {
        if (v != words[i].id) return false;
      } else if (v is num) {
        if (v.toInt() != words[i].id) return false;
      } else {
        return false;
      }
    }
    return true;
  }

  /// JSON 的 key 只能是字符串，取回来要转回 int 下标
  static Map<int, String> readTextMap(Object? raw) {
    final Map<int, String> out = <int, String>{};
    if (raw is! Map) return out;
    raw.forEach((Object? k, Object? v) {
      final int? id = int.tryParse('$k');
      if (id != null && v != null) out[id] = '$v';
    });
    return out;
  }

  /// 同样地，bool 在 JSON 里存成 1 / 0
  static Map<int, bool> readBoolMap(Object? raw) {
    final Map<int, bool> out = <int, bool>{};
    if (raw is! Map) return out;
    raw.forEach((Object? k, Object? v) {
      final int? id = int.tryParse('$k');
      if (id == null) return;
      out[id] = v == true || v == 1 || v == '1' || v == 'true';
    });
    return out;
  }

  static Map<String, String> writeTextMap(Map<int, String> src) =>
      src.map((int k, String v) => MapEntry<String, String>('$k', v));

  static Map<String, int> writeBoolMap(Map<int, bool> src) => src.map(
        (int k, bool v) => MapEntry<String, int>('$k', v ? 1 : 0),
      );
}
