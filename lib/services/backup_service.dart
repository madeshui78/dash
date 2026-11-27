// 备份服务：把单词表导出成 JSON，以及把 JSON 导回数据库。
// 只备份 words（单词本身和它的学习进度），不备份 reviews 的历史流水——
// 那样文件会大很多，而且对"换手机能继续用"来说不重要。

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../db/database_helper.dart';
import '../models/word.dart';
import 'export_format.dart' show ExportFormat, ExportFormatter;

class BackupService {
  BackupService._(); // 纯静态工具类

  /// 备份文件的格式版本号。以后字段变了，用它判断怎么兼容老文件。
  /// v2：单词带 track（四级/六级/专升本/考研），判重改成「赛道 + 英文」。
  /// v3：整包备份，除单词外还带作文、批注、错词记录、对话、设置。
  static const int formatVersion = 3;

  /// 整包包含的表。顺序不重要，但都必须是用户数据，不能放 sqlite 内部表。
  static const List<String> _tables = <String>[
    'words',
    'reviews',
    'draw_pool',
    'tombstones',
    'essays',
    'essay_marks',
    'essay_translations',
    'word_cards',
    'sections',
    'word_glosses',
    'word_notes',
    'chat_sessions',
    'chat_messages',
    'chat_graphs',
    'digest_records',
    'digest_qa',
    'settings',
  ];

  /// 这些设置里含密钥，不进备份文件，免得备份流出去把 Key 也带出去
  static const List<String> _secretKeys = <String>[
    'deepseek_key',
    'deepseek_model',
  ];

  /// 判断备份文件是整包还是老版本（只有单词）
  static bool isFullBackup(String jsonText) {
    try {
      final dynamic d = jsonDecode(jsonText);
      if (d is! Map<String, dynamic>) return false;
      return d['tables'] is Map;
    } catch (_) {
      return false;
    }
  }

  /// 导出：把所有赛道的单词打包成一段带缩进的 JSON 文本。
  /// 备份是跨赛道的整体备份——换手机时四条赛道一起回来。
  static Future<String> exportJson() async {
    final List<Word> words = await DatabaseHelper.instance.getAllWords();
    final Map<String, int> perTrack = <String, int>{};
    for (final Word w in words) {
      perTrack[w.track] = (perTrack[w.track] ?? 0) + 1;
    }

    // 整包：把用户数据表整张带走，恢复时按原 id 放回去，关联不会断
    final Database db = await DatabaseHelper.instance.database;
    final Map<String, dynamic> tables = <String, dynamic>{};
    for (final String t in _tables) {
      List<Map<String, Object?>> rows = await db.query(t);
      if (t == 'settings') {
        rows = rows
            .where((Map<String, Object?> r) => !_secretKeys.contains(r['key']))
            .toList();
      }
      tables[t] = rows;
    }

    final Map<String, dynamic> data = <String, dynamic>{
      'format': formatVersion,
      'app': 'english_agent',
      'exportedAt': DateTime.now().toIso8601String(),
      'count': words.length,
      'byTrack': perTrack,
      'tables': tables,
      'words': words.map((Word w) => w.toMap()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// 整包恢复：会清空当前用户数据再写回，调用前必须让用户确认。
  /// 设置表不清空，只覆盖备份里有的键，避免把本机 Key 一起抹掉。
  static Future<int> restoreAll(String jsonText) async {
    final dynamic decoded;
    try {
      decoded = jsonDecode(jsonText);
    } catch (_) {
      throw Exception('这不是一个合法的 JSON 文件');
    }
    if (decoded is! Map<String, dynamic> || decoded['app'] != 'english_agent') {
      throw Exception('这不是本 App 导出的备份文件');
    }
    final dynamic rawTables = decoded['tables'];
    if (rawTables is! Map) {
      throw Exception('这不是整包备份，只能用「导入单词」的方式合并');
    }

    final Database db = await DatabaseHelper.instance.database;
    int restored = 0;

    await db.transaction((Transaction txn) async {
      for (final String t in _tables) {
        if (!rawTables.containsKey(t)) continue;
        final dynamic rows = rawTables[t];
        if (rows is! List) continue;

        if (t != 'settings') {
          await txn.delete(t);
        }
        for (final dynamic r in rows) {
          if (r is! Map) continue;
          final Map<String, Object?> row = r.map(
            (dynamic k, dynamic v) => MapEntry<String, Object?>('$k', v),
          );
          if (t == 'settings' && _secretKeys.contains(row['key'])) continue;
          try {
            await txn.insert(
              t,
              row,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            restored++;
          } catch (_) {
            // 老版本缺列之类的情况跳过这一行，别让整包恢复失败
          }
        }
      }
    });
    return restored;
  }

  /// 导入：解析 JSON 文本并写回数据库。
  /// 规则：按「赛道 + 英文（忽略大小写）」判重 —— 已存在的更新，不存在的插入。
  /// 同一个词允许同时存在于四级和考研，互不覆盖，这正是赛道隔离要保证的。
  /// 返回实际处理的条数。
  static Future<int> importJson(String jsonText) async {
    final Map<String, dynamic> data;
    try {
      data = jsonDecode(jsonText) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('这不是一个合法的 JSON 文件');
    }

    if (data['app'] != 'english_agent') {
      throw Exception('这不是本 App 导出的备份文件');
    }
    final List<dynamic> raw = data['words'] as List<dynamic>? ?? <dynamic>[];
    if (raw.isEmpty) {
      throw Exception('备份文件里没有单词');
    }

    // 先把库里现有的单词按「赛道 + 英文小写」建索引，用来判重
    final List<Word> existing = await DatabaseHelper.instance.getAllWords();
    final Map<String, Word> byKey = <String, Word>{};
    for (final Word w in existing) {
      byKey[_key(w.track, w.en)] = w;
    }

    int handled = 0;
    for (final dynamic item in raw) {
      if (item is! Map<String, dynamic>) continue;
      final Map<String, dynamic> m = item;

      final String en = (m['en'] as String? ?? '').trim();
      final String zh = (m['zh'] as String? ?? '').trim();
      if (en.isEmpty || zh.isEmpty) continue; // 脏数据跳过

      final Word incoming = Word.fromMap(m);
      final String key = _key(incoming.track, en);
      final Word? old = byKey[key];

      if (old == null) {
        // 新词：不能用备份里的 id（本地库的自增序列不一样，会主键冲突），
        // 所以重新构造一个不带 id 的对象，让数据库自己分配。
        await DatabaseHelper.instance.insertWord(
          Word(
            en: incoming.en,
            zh: incoming.zh,
            phonetic: incoming.phonetic,
            example: incoming.example,
            source: incoming.source,
            tag: incoming.tag,
            correct: incoming.correct,
            wrong: incoming.wrong,
            lastReview: incoming.lastReview,
            nextReview: incoming.nextReview,
            interval: incoming.interval,
            ease: incoming.ease,
            mastered: incoming.mastered,
            track: incoming.track,
          ),
        );
        byKey[key] = incoming;
      } else {
        // 老词：只更新内容字段，学习进度保留本地的（本地的更准）
        await DatabaseHelper.instance.updateWord(
          old.copyWith(
            zh: zh,
            phonetic: incoming.phonetic,
            example: incoming.example,
            source: incoming.source,
            tag: incoming.tag,
          ),
        );
      }
      handled++;
    }
    return handled;
  }

  /// 判重键：赛道 + 英文小写。老备份没有 track 字段时会默认 CET4。
  static String _key(String track, String en) =>
      '$track::${en.trim().toLowerCase()}';

  // ---------------- 导出成能看的笔记 ----------------

  /// 导出成笔记/清单，而不是备份用的 JSON。
  ///
  /// 备份 JSON 是给机器读的；这里导出的三种格式是给你自己用的：
  ///   txt  —— 对齐的纯文本，打印出来贴墙、或者抄进本子
  ///   csv  —— 能进 Excel / WPS / Anki，带 BOM 所以中文不乱码
  ///   md   —— Markdown 表格，贴进笔记软件或思维导图工具
  static Future<String> exportAs(
    List<Word> words, {
    required ExportFormat format,
    bool withStats = false,
  }) async {
    return ExportFormatter.format(words, format: format, withStats: withStats);
  }
}
