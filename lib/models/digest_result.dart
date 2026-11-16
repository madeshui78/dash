// 错词复盘的结构化结果：分组、逐条纠错、学习路线
//
// AI 只输出 JSON，渲染成卡片，不再是一大段文字。
// 每个词有独立位置，右侧目录靠它精准定位。

import 'dart:convert';

class DigestItem {
  final String word;
  final String meaning;
  final String memory;
  final String group;

  const DigestItem({
    required this.word,
    required this.meaning,
    required this.memory,
    required this.group,
  });
}

class DigestGroup {
  final String title;
  final List<String> words;
  final String tip;

  const DigestGroup({
    required this.title,
    required this.words,
    required this.tip,
  });
}

class DigestResult {
  final List<DigestGroup> groups;
  final List<DigestItem> items;
  final List<String> path;

  const DigestResult({
    required this.groups,
    required this.items,
    required this.path,
  });

  bool get isEmpty => items.isEmpty && groups.isEmpty && path.isEmpty;

  static DigestResult? tryParse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    String s = raw.trim();
    s = s.replaceAll(RegExp(r'^```[a-zA-Z]*'), '').replaceAll('```', '');
    final int a = s.indexOf('{');
    final int b = s.lastIndexOf('}');
    if (a < 0 || b <= a) return null;
    try {
      final Object? data = jsonDecode(s.substring(a, b + 1));
      if (data is! Map) return null;

      final List<DigestGroup> groups = <DigestGroup>[];
      final Object? gs = data['groups'];
      if (gs is List) {
        for (final Object? g in gs) {
          if (g is! Map) continue;
          final List<String> ws = <String>[];
          final Object? rawWords = g['words'];
          if (rawWords is List) {
            for (final Object? w in rawWords) {
              final String t = w.toString().trim();
              if (t.isNotEmpty) ws.add(t);
            }
          }
          final String title = (g['title'] ?? '').toString().trim();
          if (title.isEmpty && ws.isEmpty) continue;
          groups.add(
            DigestGroup(
              title: title.isEmpty ? '一组' : title,
              words: ws,
              tip: (g['tip'] ?? '').toString().trim(),
            ),
          );
        }
      }

      final List<DigestItem> items = <DigestItem>[];
      final Object? rawItems = data['items'];
      if (rawItems is List) {
        for (final Object? it in rawItems) {
          if (it is! Map) continue;
          final String word = (it['word'] ?? '').toString().trim();
          if (word.isEmpty) continue;
          items.add(
            DigestItem(
              word: word,
              meaning: (it['meaning'] ?? '').toString().trim(),
              memory: (it['memory'] ?? '').toString().trim(),
              group: (it['group'] ?? '').toString().trim(),
            ),
          );
        }
      }

      final List<String> path = <String>[];
      final Object? ps = data['path'];
      if (ps is List) {
        for (final Object? p in ps) {
          final String t = p.toString().trim();
          if (t.isNotEmpty) path.add(t);
        }
      }

      final DigestResult r = DigestResult(
        groups: groups,
        items: items,
        path: path,
      );
      return r.isEmpty ? null : r;
    } catch (_) {
      return null;
    }
  }
}
