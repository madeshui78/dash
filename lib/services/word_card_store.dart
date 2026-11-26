// 单词学习卡的数据：词根词缀 / 词组搭配 / 例句。
//
// 一个词只向 AI 要一次，拿到就写库 + 进内存缓存。
// 学习页和复习页共用这份缓存，来回切不会重复请求。

import 'dart:convert';

import '../db/database_helper.dart';
import '../models/word.dart';
import 'ai_service.dart';

class WordCardData {
  final String root;
  final String pos;
  final List<String> collocations;
  final List<WordExample> examples;

  const WordCardData({
    required this.root,
    required this.pos,
    required this.collocations,
    required this.examples,
  });

  bool get isEmpty => root.isEmpty && collocations.isEmpty && examples.isEmpty;
}

class WordExample {
  final String en;
  final String zh;

  const WordExample({required this.en, required this.zh});
}

class WordCardStore {
  WordCardStore._();

  static final Map<int, WordCardData> _cache = <int, WordCardData>{};
  static final Map<int, Future<WordCardData?>> _inflight =
      <int, Future<WordCardData?>>{};

  static Future<WordCardData?> load(Word word) {
    final int? id = word.id;
    if (id == null) return Future<WordCardData?>.value(null);
    final WordCardData? hit = _cache[id];
    if (hit != null) return Future<WordCardData?>.value(hit);
    return _inflight.putIfAbsent(id, () => _load(word));
  }

  static Future<WordCardData?> _load(Word word) async {
    try {
      // 1) 本地缓存
      final Map<String, String>? row = await DatabaseHelper.instance
          .getWordCard(word.id!);
      if (row != null && row['root']!.isNotEmpty) {
        final WordCardData data = _fromParts(
          row['root']!,
          row['collocations']!,
          row['examples']!,
        );
        _cache[word.id!] = data;
        return data;
      }

      // 2) 问 AI
      final AiConfig cfg = await AiService.loadConfig();
      final Map<String, dynamic>? map = await AiService.wordCard(cfg, word.en);
      if (map == null) return null;

      final String root = (map['root'] ?? '').toString().trim();
      final String pos = (map['pos'] ?? '').toString().trim();
      final List<String> collocations = <String>[];
      final Object? col = map['collocations'];
      if (col is List) {
        for (final Object? c in col) {
          final String s = c.toString().trim();
          if (s.isNotEmpty) collocations.add(s);
        }
      }
      final List<WordExample> examples = <WordExample>[];
      final Object? ex = map['examples'];
      if (ex is List) {
        for (final Object? e in ex) {
          if (e is Map) {
            final String en = (e['en'] ?? '').toString().trim();
            final String zh = (e['zh'] ?? '').toString().trim();
            if (en.isNotEmpty) examples.add(WordExample(en: en, zh: zh));
          }
        }
      }

      final WordCardData data = WordCardData(
        root: root,
        pos: pos,
        collocations: collocations,
        examples: examples,
      );
      if (data.isEmpty) return null;

      await DatabaseHelper.instance.saveWordCard(
        wordId: word.id!,
        root: jsonEncode(<String, Object?>{'text': root, 'pos': pos}),
        collocations: jsonEncode(collocations),
        examples: jsonEncode(
          examples
              .map((WordExample e) => <String, String>{'en': e.en, 'zh': e.zh})
              .toList(),
        ),
      );
      _cache[word.id!] = data;
      return data;
    } catch (_) {
      return null;
    } finally {
      _inflight.remove(word.id);
    }
  }

  static WordCardData _fromParts(String rootRaw, String colRaw, String exRaw) {
    String root = rootRaw;
    String pos = '';
    try {
      final Object? r = jsonDecode(rootRaw);
      if (r is Map) {
        root = (r['text'] ?? '').toString();
        pos = (r['pos'] ?? '').toString();
      }
    } catch (_) {
      // 老格式：直接是文本
    }

    final List<String> collocations = <String>[];
    try {
      final Object? c = jsonDecode(colRaw);
      if (c is List) {
        for (final Object? item in c) {
          final String s = item.toString().trim();
          if (s.isNotEmpty) collocations.add(s);
        }
      }
    } catch (_) {}

    final List<WordExample> examples = <WordExample>[];
    try {
      final Object? e = jsonDecode(exRaw);
      if (e is List) {
        for (final Object? item in e) {
          if (item is Map) {
            final String en = (item['en'] ?? '').toString();
            final String zh = (item['zh'] ?? '').toString();
            if (en.isNotEmpty) examples.add(WordExample(en: en, zh: zh));
          }
        }
      }
    } catch (_) {}

    return WordCardData(
      root: root,
      pos: pos,
      collocations: collocations,
      examples: examples,
    );
  }

  /// 用词库里已有的例句先垫一下，AI 还没回来时不至于空白
  static List<WordExample> fallbackExamples(Word word) {
    if (word.example == null || word.example!.trim().isEmpty) {
      return const <WordExample>[];
    }
    return <WordExample>[WordExample(en: word.example!, zh: '')];
  }
}
