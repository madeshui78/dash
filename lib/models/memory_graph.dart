// 记忆图谱的数据结构：AI 返回的 JSON 解析成这里
//
// 形如：
// {"groups":[{"title":"词根 spect-","words":["inspect","respect"],"tip":"..."}],
//  "path":["先攻词根组","再对比易混词","最后用作文复现"]}

import 'dart:convert';

class MemoryGroup {
  final String title;
  final List<String> words;
  final String tip;

  const MemoryGroup({
    required this.title,
    required this.words,
    required this.tip,
  });
}

class MemoryGraph {
  final List<MemoryGroup> groups;
  final List<String> path;

  const MemoryGraph({required this.groups, required this.path});

  bool get isEmpty => groups.isEmpty && path.isEmpty;

  int get wordCount =>
      groups.fold<int>(0, (int n, MemoryGroup g) => n + g.words.length);

  /// 从 AI 回复末尾的 JSON 解析；解析不出来返回 null
  static MemoryGraph? tryParse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    String s = raw.trim();
    final int a = s.indexOf('{');
    final int b = s.lastIndexOf('}');
    if (a < 0 || b <= a) return null;
    try {
      final Object? data = jsonDecode(s.substring(a, b + 1));
      if (data is! Map) return null;
      final List<MemoryGroup> groups = <MemoryGroup>[];
      final Object? gs = data['groups'];
      if (gs is List) {
        for (final Object? g in gs) {
          if (g is! Map) continue;
          final List<String> words = <String>[];
          final Object? ws = g['words'];
          if (ws is List) {
            for (final Object? w in ws) {
              final String t = w.toString().trim();
              if (t.isNotEmpty) words.add(t);
            }
          }
          final String title = (g['title'] ?? '').toString().trim();
          if (title.isEmpty && words.isEmpty) continue;
          groups.add(
            MemoryGroup(
              title: title.isEmpty ? '一组' : title,
              words: words,
              tip: (g['tip'] ?? '').toString().trim(),
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
      final MemoryGraph graph = MemoryGraph(groups: groups, path: path);
      return graph.isEmpty ? null : graph;
    } catch (_) {
      return null;
    }
  }
}
