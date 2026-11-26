// 数据访问层：整个 App 只有这里写 SQL，页面一律调用这里的方法

import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_session.dart';
import '../models/essay.dart';
import '../models/word.dart';
import '../models/word_note.dart';
import '../services/ai_service.dart';

const Uuid _uuid = Uuid();

/// 给一条记录生成全局唯一标识。
/// 多设备同步全靠它对账——自增 id 在两台手机上会撞车，uuid 不会。
String newUuid() => _uuid.v4();

/// 批量导入的结果：新增多少、跳过多少（重复或空行）
class ImportResult {
  final int added;
  final int skipped;

  const ImportResult({required this.added, required this.skipped});
}

/// 一次学习/复习算出来的调度结果。
/// 三条写结果的路（每日学习、复习页、错词本标记）共用，保证算法只有一份。
class _Schedule {
  /// 新的复习间隔（天）
  final int interval;

  /// 下次到期时间
  final DateTime next;

  /// 是否达到「已掌握」
  final bool mastered;

  /// 本次结果的时间戳，顺带保证同一次事务里各处写入时间一致
  final DateTime at;

  const _Schedule({
    required this.interval,
    required this.next,
    required this.mastered,
    required this.at,
  });
}

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  DatabaseHelper._init();

  static const String _dbName = 'english_agent.db';

  /// 正在进行的打开操作。保证并发调用 database getter 时
  /// openDatabase 只跑一次（双开同一个库文件在一些机型上会卡死查询）。
  static Future<Database>? _opening;

  /// 数据库版本号。
  /// v2：words 表新增 mastered 列。
  /// v3：新增 settings 键值表（存 Ollama 服务器地址、模型名等配置）。
  /// v4：words / reviews 新增 track 列（四级、六级、专升本、考研四套数据互相隔离）。
  /// v5：新增 draw_pool（每日抽词池：抽过哪些词、学完没有）。
  /// v7：为云同步铺路。words / reviews / draw_pool / chat_messages 四张表
  ///   各加 uuid（全局唯一标识，多设备不再靠自增 id 对账，否则必撞车）、
  ///   updated_at（毫秒时间戳，冲突时谁新听谁的）、dirty（本地改过还没上传）。
  ///   另建 tombstones 表：本地删掉一条就记下它的 uuid，同步时告诉云端「这条删了」，
  ///   否则下次拉取云端会把它原样送回来，删了又活。
  ///   settings 表不动——里面存着 DeepSeek 的 API Key，是个人凭据，绝不上云。
  /// 改了建表/加列之后必须把这里 +1，否则老设备上不会触发 onUpgrade。
  /// v8：新增 essays（每天推的作文）和 essay_marks（标红的词/短语）。
  /// v9：新增 chat_sessions（多段对话），chat_messages 加 session_id。
  /// v10：新增 essay_translations（逐句译文落库）。
  /// v11：新增 word_cards（词根词缀 / 搭配 / 例句，AI 生成后缓存）。
  /// v12：新增 sections（分区可自定义名称和数量）。
  /// v13：新增 word_glosses（作文里补过的中文，缓存下来不重复请求）。
  /// v14：新增 chat_graphs（错词复盘生成的记忆图谱，挂在消息下面）。
  /// v15：对话分类型 + digest_records（后台提交的错词原文）。
  /// v16：digest_qa（复盘悬浮窗的追问，挂在某条复盘结果下）。
  /// v17：word_notes（作文里单词的批注，按文章独立）。
  static const int _dbVersion = 17;

  static const String tableWords = 'words';
  static const String tableReviews = 'reviews';
  static const String tableSettings = 'settings';
  static const String tableDrawPool = 'draw_pool';
  static const String tableChat = 'chat_messages';
  static const String tableChatSessions = 'chat_sessions';
  static const String tableTombstones = 'tombstones';
  static const String tableEssays = 'essays';
  static const String tableEssayMarks = 'essay_marks';
  static const String tableEssayTranslations = 'essay_translations';
  static const String tableWordCards = 'word_cards';
  static const String tableSections = 'sections';
  static const String tableWordGlosses = 'word_glosses';
  static const String tableChatGraphs = 'chat_graphs';
  static const String tableDigestRecords = 'digest_records';

  /// 需要上云的四张表。settings 不在里面——里面有 API Key，绝不同步。
  static const List<String> syncTables = <String>[
    tableWords,
    tableReviews,
    tableDrawPool,
    tableChat,
  ];

  Future<Database> get database {
    final Database? ready = _database;
    if (ready != null) return Future<Database>.value(ready);
    // 单飞：并发调用时 openDatabase 只跑一次。
    // 双开同一个库文件在一些机型上会把后续查询卡死。
    return _opening ??= _initDatabase()
        .then((Database db) {
          _database = db;
          _opening = null;
          return db;
        })
        .catchError((Object e) {
          _opening = null;
          throw e;
        });
  }

  Future<Database> _initDatabase() async {
    final Directory dir = await getApplicationDocumentsDirectory();
    final String path = '${dir.path}${Platform.pathSeparator}$_dbName';
    // 只在调试模式打印，方便手动检查 / 删库调试
    if (kDebugMode) {
      // ignore: avoid_print
      print('数据库路径: $path');
    }

    final Database db = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: (Database db) async {
        // SQLite 的外键默认是关的，不打开 ON DELETE CASCADE 无效
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
    if (kDebugMode) {
      // ignore: avoid_print
      print('[db] openDatabase 完成');
    }
    return db;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE words (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        en          TEXT    NOT NULL,
        zh          TEXT    NOT NULL,
        phonetic    TEXT,
        example     TEXT,
        source      TEXT,
        tag         TEXT,
        correct     INTEGER NOT NULL DEFAULT 0,
        wrong       INTEGER NOT NULL DEFAULT 0,
        last_review TEXT,
        next_review TEXT,
        interval    INTEGER NOT NULL DEFAULT 1,
        ease        REAL    NOT NULL DEFAULT 2.5,
        mastered    INTEGER NOT NULL DEFAULT 0,
        track       TEXT    NOT NULL DEFAULT 'CET4',
        uuid        TEXT,
        updated_at  INTEGER NOT NULL DEFAULT 0,
        dirty       INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_words_uuid ON words (uuid)',
    );

    await db.execute('''
      CREATE TABLE reviews (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        word_id     INTEGER NOT NULL,
        mode        TEXT    NOT NULL,
        result      INTEGER NOT NULL,
        review_time TEXT    NOT NULL,
        track       TEXT    NOT NULL DEFAULT 'CET4',
        uuid        TEXT,
        updated_at  INTEGER NOT NULL DEFAULT 0,
        dirty       INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY (word_id) REFERENCES words (id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_reviews_uuid ON reviews (uuid)',
    );

    await db.execute('''
      CREATE TABLE settings (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // 每日抽词池：抽过的词记一条，保证跨天不重复抽同一个词
    await db.execute('''
      CREATE TABLE draw_pool (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        word_id    INTEGER NOT NULL,
        track      TEXT    NOT NULL,
        draw_date  TEXT    NOT NULL,
        done       INTEGER NOT NULL DEFAULT 0,
        uuid       TEXT,
        updated_at INTEGER NOT NULL DEFAULT 0,
        dirty      INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY (word_id) REFERENCES words (id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_pool_uuid ON draw_pool (uuid)',
    );

    await db.execute('CREATE INDEX idx_words_tag ON words (tag)');
    await db.execute('CREATE INDEX idx_words_next ON words (next_review)');
    await db.execute('CREATE INDEX idx_words_mastered ON words (mastered)');
    // 所有查询都会带 track 条件，索引必须建
    await db.execute('CREATE INDEX idx_words_track ON words (track)');
    await db.execute('CREATE INDEX idx_reviews_track ON reviews (track)');
    await db.execute('CREATE INDEX idx_reviews_word ON reviews (word_id)');

    // AI 问答的历史：一条消息一行，按时间顺序读回来就是对话
    await db.execute('''
      CREATE TABLE chat_messages (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        role       TEXT    NOT NULL,
        content    TEXT    NOT NULL,
        created_at TEXT    NOT NULL,
        session_id INTEGER NOT NULL DEFAULT 1,
        uuid       TEXT,
        updated_at INTEGER NOT NULL DEFAULT 0,
        dirty      INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_chat_uuid ON chat_messages (uuid)',
    );

    // 多段对话：像 DeepSeek 那样，每段独立保存
    await db.execute('''
      CREATE TABLE chat_sessions (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        title      TEXT    NOT NULL,
        kind       TEXT    NOT NULL DEFAULT 'chat',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    // 删除墓碑：本地删掉一条记录时，把它的 uuid 记在这里。
    // 同步时靠这张表告诉云端「这条也删了」，否则云端会把它再送回来。
    await db.execute('''
      CREATE TABLE tombstones (
        uuid       TEXT PRIMARY KEY,
        tbl        TEXT    NOT NULL,
        deleted_at INTEGER NOT NULL
      )
    ''');

    // 每天推的作文。一天一篇，换一篇时直接替换当天的记录。
    await db.execute('''
      CREATE TABLE essays (
        id         TEXT PRIMARY KEY,
        date       TEXT NOT NULL,
        topic      TEXT NOT NULL,
        title      TEXT NOT NULL,
        text       TEXT NOT NULL,
        track      TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_essays_date ON essays (date)');

    // 标红的词/短语。错词本靠 essay_id 溯源回原文位置。
    await db.execute('''
      CREATE TABLE essay_marks (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        essay_id    TEXT    NOT NULL,
        word        TEXT    NOT NULL,
        sentence    TEXT    NOT NULL DEFAULT '',
        para        INTEGER NOT NULL DEFAULT 0,
        start_index INTEGER NOT NULL DEFAULT 0,
        created_at  INTEGER NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_marks_essay ON essay_marks (essay_id)');

    // 逐句译文：一篇作文一条，存 JSON 数组，关掉再打开直接读
    await db.execute('''
      CREATE TABLE essay_translations (
        essay_id   TEXT PRIMARY KEY,
        content    TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    // 单词学习卡：词根词缀 / 搭配 / 例句，AI 生成一次就存下来
    await db.execute('''
      CREATE TABLE word_cards (
        word_id      INTEGER PRIMARY KEY,
        root         TEXT NOT NULL DEFAULT '',
        collocations TEXT NOT NULL DEFAULT '',
        examples     TEXT NOT NULL DEFAULT '',
        created_at   INTEGER NOT NULL
      )
    ''');

    // 分区：可以自己加、改名、删
    await db.execute('''
      CREATE TABLE sections (
        id         TEXT PRIMARY KEY,
        name       TEXT NOT NULL,
        sort       INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');
    await _seedSections(db);

    // 作文补过的中文释义，按单词缓存
    await db.execute('''
      CREATE TABLE word_glosses (
        en         TEXT PRIMARY KEY,
        zh         TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    // 错词复盘的记忆图谱，挂在某条 AI 回复下面
    await db.execute('''
      CREATE TABLE chat_graphs (
        message_id INTEGER PRIMARY KEY,
        json       TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    // 后台提交给 AI 的错词原文，抽屉「记录」里能翻到
    await db.execute('''
      CREATE TABLE digest_records (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL,
        payload    TEXT NOT NULL,
        item_count INTEGER NOT NULL,
        message_id INTEGER,
        created_at INTEGER NOT NULL
      )
    ''');

    // 复盘悬浮窗的追问，按复盘结果（message_id）归档
    await db.execute('''
      CREATE TABLE digest_qa (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        message_id INTEGER NOT NULL,
        role       TEXT NOT NULL,
        content    TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    // 作文里单词的批注：同一篇里一个词一条，不同文章互不影响
    await db.execute('''
      CREATE TABLE word_notes (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        essay_id   TEXT NOT NULL,
        word       TEXT NOT NULL,
        sentence   TEXT NOT NULL DEFAULT '',
        note       TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        UNIQUE (essay_id, word)
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_word_notes_essay ON word_notes (essay_id)',
    );
  }

  /// 老版本升级：只会补上缺失的列/表，不会动已有数据
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE words ADD COLUMN mastered INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS settings (
          key   TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 4) {
      // 四个考试赛道共用一张表，靠 track 列区分。
      // 老数据统一归到四级，不会丢，之后可以在单词页里再改归属。
      await db.execute(
        "ALTER TABLE words ADD COLUMN track TEXT NOT NULL DEFAULT 'CET4'",
      );
      await db.execute(
        "ALTER TABLE reviews ADD COLUMN track TEXT NOT NULL DEFAULT 'CET4'",
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_words_track ON words (track)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_reviews_track ON reviews (track)',
      );
    }
    if (oldVersion < 5) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS draw_pool (
          id         INTEGER PRIMARY KEY AUTOINCREMENT,
          word_id    INTEGER NOT NULL,
          track      TEXT    NOT NULL,
          draw_date  TEXT    NOT NULL,
          done       INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (word_id) REFERENCES words (id) ON DELETE CASCADE
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_pool_track ON draw_pool (track)',
      );
    }
    if (oldVersion < 6) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS chat_messages (
          id         INTEGER PRIMARY KEY AUTOINCREMENT,
          role       TEXT    NOT NULL,
          content    TEXT    NOT NULL,
          created_at TEXT    NOT NULL
        )
      ''');
    }
    if (oldVersion < 7) {
      // 四张要上云的表各补四列。老行的 updated_at 给当前时间、dirty 给 1，
      // 保证升级后第一次同步会把存量数据都推上去。
      for (final String table in <String>[
        tableWords,
        tableReviews,
        tableDrawPool,
        tableChat,
      ]) {
        await db.execute('ALTER TABLE $table ADD COLUMN uuid TEXT');
        await db.execute(
          'ALTER TABLE $table ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0',
        );
        await db.execute(
          'ALTER TABLE $table ADD COLUMN dirty INTEGER NOT NULL DEFAULT 1',
        );
        // 存量行补 uuid，并标记为待上传
        await _backfillUuid(db, table);
      }
      await db.execute('''
        CREATE TABLE IF NOT EXISTS tombstones (
          uuid       TEXT PRIMARY KEY,
          tbl        TEXT    NOT NULL,
          deleted_at INTEGER NOT NULL
        )
      ''');
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_words_uuid ON words (uuid)',
      );
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_reviews_uuid ON reviews (uuid)',
      );
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_pool_uuid ON draw_pool (uuid)',
      );
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_chat_uuid ON chat_messages (uuid)',
      );
    }
    if (oldVersion < 8) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS essays (
          id         TEXT PRIMARY KEY,
          date       TEXT NOT NULL,
          topic      TEXT NOT NULL,
          title      TEXT NOT NULL,
          text       TEXT NOT NULL,
          track      TEXT NOT NULL,
          created_at INTEGER NOT NULL
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_essays_date ON essays (date)',
      );
      await db.execute('''
        CREATE TABLE IF NOT EXISTS essay_marks (
          id          INTEGER PRIMARY KEY AUTOINCREMENT,
          essay_id    TEXT    NOT NULL,
          word        TEXT    NOT NULL,
          sentence    TEXT    NOT NULL DEFAULT '',
          para        INTEGER NOT NULL DEFAULT 0,
          start_index INTEGER NOT NULL DEFAULT 0,
          created_at  INTEGER NOT NULL
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_marks_essay ON essay_marks (essay_id)',
      );
    }
    if (oldVersion < 9) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS chat_sessions (
          id         INTEGER PRIMARY KEY AUTOINCREMENT,
          title      TEXT    NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
      await db.execute(
        'ALTER TABLE chat_messages ADD COLUMN session_id INTEGER NOT NULL DEFAULT 1',
      );
      // 老对话全归到一段「历史对话」里，不丢
      final List<Map<String, Object?>> has = await db.rawQuery(
        'SELECT COUNT(*) AS n FROM chat_messages',
      );
      final int count = (has.first['n'] as int?) ?? 0;
      if (count > 0) {
        final int now = DateTime.now().millisecondsSinceEpoch;
        await db.insert(tableChatSessions, <String, Object?>{
          'id': 1,
          'title': '历史对话',
          'created_at': now,
          'updated_at': now,
        });
      }
    }
    if (oldVersion < 10) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS essay_translations (
          essay_id   TEXT PRIMARY KEY,
          content    TEXT NOT NULL,
          created_at INTEGER NOT NULL
        )
      ''');
    }
    if (oldVersion < 11) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS word_cards (
          word_id      INTEGER PRIMARY KEY,
          root         TEXT NOT NULL DEFAULT '',
          collocations TEXT NOT NULL DEFAULT '',
          examples     TEXT NOT NULL DEFAULT '',
          created_at   INTEGER NOT NULL
        )
      ''');
    }
    if (oldVersion < 12) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS sections (
          id         TEXT PRIMARY KEY,
          name       TEXT NOT NULL,
          sort       INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL
        )
      ''');
      await _seedSections(db);
    }
    if (oldVersion < 13) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS word_glosses (
          en         TEXT PRIMARY KEY,
          zh         TEXT NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
    }
    if (oldVersion < 14) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS chat_graphs (
          message_id INTEGER PRIMARY KEY,
          json       TEXT NOT NULL,
          created_at INTEGER NOT NULL
        )
      ''');
    }
    if (oldVersion < 15) {
      await db.execute(
        "ALTER TABLE chat_sessions ADD COLUMN kind TEXT NOT NULL DEFAULT 'chat'",
      );
      await db.execute('''
        CREATE TABLE IF NOT EXISTS digest_records (
          id         INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id INTEGER NOT NULL,
          payload    TEXT NOT NULL,
          item_count INTEGER NOT NULL,
          message_id INTEGER,
          created_at INTEGER NOT NULL
        )
      ''');
    }
    if (oldVersion < 16) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS digest_qa (
          id         INTEGER PRIMARY KEY AUTOINCREMENT,
          message_id INTEGER NOT NULL,
          role       TEXT NOT NULL,
          content    TEXT NOT NULL,
          created_at INTEGER NOT NULL
        )
      ''');
    }
    if (oldVersion < 17) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS word_notes (
          id         INTEGER PRIMARY KEY AUTOINCREMENT,
          essay_id   TEXT NOT NULL,
          word       TEXT NOT NULL,
          sentence   TEXT NOT NULL DEFAULT '',
          note       TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          UNIQUE (essay_id, word)
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_word_notes_essay ON word_notes (essay_id)',
      );
    }
  }

  /// 第一次建库 / 升级到 v12 时，把原来四个固定的分区写进表里
  Future<void> _seedSections(Database db) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM $tableSections',
    );
    if (((rows.first['n'] as int?) ?? 0) > 0) return;
    const List<List<String>> defaults = <List<String>>[
      <String>['CET4', '英语四级'],
      <String>['CET6', '英语六级'],
      <String>['UPGRADE', '专升本英语'],
      <String>['KAOYAN', '考研英语'],
    ];
    final int now = DateTime.now().millisecondsSinceEpoch;
    for (int i = 0; i < defaults.length; i++) {
      await db.insert(tableSections, <String, Object?>{
        'id': defaults[i][0],
        'name': defaults[i][1],
        'sort': i,
        'created_at': now,
      });
    }
  }

  /// 给表里所有 uuid 为空的行补一个 uuid，并标成待上传（dirty=1）。
  /// 升级到 v7 的老数据库会走这里，存量的几千个词不能丢。
  static Future<void> _backfillUuid(Database db, String table) async {
    final List<Map<String, dynamic>> rows = await db.query(
      table,
      columns: <String>['id'],
      where: 'uuid IS NULL',
    );
    final int now = DateTime.now().millisecondsSinceEpoch;
    for (final Map<String, dynamic> r in rows) {
      await db.update(
        table,
        <String, Object?>{'uuid': newUuid(), 'updated_at': now, 'dirty': 1},
        where: 'id = ?',
        whereArgs: <Object?>[r['id']],
      );
    }
  }

  // ---------------- words ----------------

  /// 插入一条单词。uuid / updated_at / dirty 由这里统一维护，页面不用管。
  Future<int> insertWord(Word word) async {
    final Database db = await database;
    final Map<String, dynamic> m = word.toMap()
      ..['uuid'] = word.uuid ?? newUuid()
      ..['updated_at'] = DateTime.now().millisecondsSinceEpoch
      ..['dirty'] = 1;
    return db.insert(tableWords, m);
  }

  Future<int> updateWord(Word word) async {
    final Database db = await database;
    final Map<String, dynamic> m = word.toMap()
      ..['uuid'] = word.uuid ?? newUuid()
      ..['updated_at'] = DateTime.now().millisecondsSinceEpoch
      ..['dirty'] = 1;
    return db.update(
      tableWords,
      m,
      where: 'id = ?',
      whereArgs: <Object?>[word.id],
    );
  }

  /// 删除一个词。同步用的墓碑在这一起写：不记的话，下次拉云端数据
  /// 这个词会被原样送回来，删了又活。
  Future<int> deleteWord(int id) async {
    final Database db = await database;
    await _markDeleted(db, tableWords, id);
    return db.delete(tableWords, where: 'id = ?', whereArgs: <Object?>[id]);
  }

  /// 删一条记录前把它的 uuid 记进墓碑表。
  /// 同步时把这张表交给云端，云端才知道该删哪一条。
  Future<void> _markDeleted(Database db, String table, int id) async {
    final List<Map<String, dynamic>> rows = await db.query(
      table,
      columns: <String>['uuid'],
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final String? uuid = rows.first['uuid'] as String?;
    if (uuid == null || uuid.isEmpty) return;
    await db.insert(tableTombstones, <String, Object?>{
      'uuid': uuid,
      'tbl': table,
      'deleted_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 某个赛道下的全部单词；tag 传 null 表示该赛道全部课次
  Future<List<Word>> getWords({required String track, String? tag}) async {
    final Database db = await database;
    final List<Map<String, dynamic>> rows = await db.query(
      tableWords,
      where: tag == null ? 'track = ?' : 'track = ? AND tag = ?',
      whereArgs: tag == null ? [track] : [track, tag],
      orderBy: 'id DESC',
    );
    return rows.map(Word.fromMap).toList();
  }

  /// 单词页的筛选口径
  /// all 全部 / fresh 没抽过的新词 / today 今天抽的 / wrong 错词 / mastered 已掌握
  Future<List<Word>> queryWords({
    required String track,
    String prefix = '',
    String search = '',
    String filter = 'all',
  }) async {
    final Database db = await database;
    final List<String> where = <String>['track = ?'];
    final List<Object?> args = <Object?>[track];

    if (prefix.isNotEmpty) {
      // 字典式下钻：a → ap → app，只匹配开头
      where.add('LOWER(en) LIKE ?');
      args.add('${prefix.toLowerCase()}%');
    }
    if (search.isNotEmpty) {
      // 既能搜英文也能搜中文释义
      where.add('(LOWER(en) LIKE ? OR zh LIKE ?)');
      args.add('%${search.toLowerCase()}%');
      args.add('%$search%');
    }

    switch (filter) {
      case 'fresh':
        where.add(
          'mastered = 0 AND id NOT IN '
          '(SELECT word_id FROM $tableDrawPool WHERE track = ?)',
        );
        args.add(track);
        break;
      case 'today':
        where.add(
          'id IN (SELECT word_id FROM $tableDrawPool '
          'WHERE track = ? AND draw_date = ?)',
        );
        args.add(track);
        args.add(_today());
        break;
      case 'wrong':
        where.add('wrong > 0');
        break;
      case 'mastered':
        where.add('mastered = 1');
        break;
    }

    final List<Map<String, dynamic>> rows = await db.query(
      tableWords,
      where: where.join(' AND '),
      whereArgs: args,
      // 字典序：忽略大小写，同词不同大写也能挨在一起
      orderBy: 'en COLLATE NOCASE ASC',
    );
    return rows.map(Word.fromMap).toList();
  }

  /// 字母索引：depth=1 出首字母（a、b、c…），depth=2 出前两位（ap、ar…）
  /// 只统计当前筛选范围内的词，点了哪个字母就出那个字母下的分组
  Future<List<String>> getLetterGroups({
    required String track,
    required int depth,
    String prefix = '',
    String filter = 'all',
  }) async {
    final Database db = await database;
    final List<String> where = <String>['track = ?', "en LIKE '[a-zA-Z]%'"];
    final List<Object?> args = <Object?>[track];
    if (prefix.isNotEmpty) {
      where.add('LOWER(en) LIKE ?');
      args.add('${prefix.toLowerCase()}%');
    }
    if (filter == 'fresh') {
      where.add(
        'mastered = 0 AND id NOT IN '
        '(SELECT word_id FROM $tableDrawPool WHERE track = ?)',
      );
      args.add(track);
    } else if (filter == 'wrong') {
      where.add('wrong > 0');
    } else if (filter == 'mastered') {
      where.add('mastered = 1');
    }

    final List<Map<String, dynamic>> rows = await db.rawQuery(
      'SELECT DISTINCT LOWER(SUBSTR(en, 1, $depth)) AS g FROM $tableWords '
      'WHERE ${where.join(' AND ')} ORDER BY g ASC',
      args,
    );
    return rows
        .map((Map<String, dynamic> m) => (m['g'] as String?) ?? '')
        .where((String s) => s.isNotEmpty)
        .toList();
  }

  /// 批量导入：整批塞进事务里，几百上千个词也是一瞬间。
  /// 按「赛道 + 英文小写」跳过重复，返回 (新增, 跳过)。
  Future<ImportResult> insertWordsBatch(List<Word> words) async {
    final Database db = await database;
    int added = 0;
    int skipped = 0;

    await db.transaction((Transaction txn) async {
      for (final Word w in words) {
        final String en = w.en.trim().toLowerCase();
        if (en.isEmpty) {
          skipped++;
          continue;
        }
        final List<Map<String, dynamic>> exists = await txn.query(
          tableWords,
          columns: <String>['id'],
          where: 'track = ? AND LOWER(en) = ?',
          whereArgs: <Object?>[w.track, en],
          limit: 1,
        );
        if (exists.isNotEmpty) {
          skipped++;
          continue;
        }
        await txn.insert(tableWords, <String, Object?>{
          ...w.toMap(),
          'uuid': newUuid(),
          'updated_at': DateTime.now().millisecondsSinceEpoch,
          'dirty': 1,
        });
        added++;
      }
    });

    return ImportResult(added: added, skipped: skipped);
  }

  // ---------------- 每日抽词 ----------------

  /// 今天还能抽多少个：未掌握、且从没抽过的
  Future<int> countDrawable({required String track}) async {
    final Database db = await database;
    final List<Map<String, dynamic>> r = await db.rawQuery(
      'SELECT COUNT(*) FROM $tableWords WHERE track = ? AND mastered = 0 '
      'AND id NOT IN (SELECT word_id FROM $tableDrawPool WHERE track = ?)',
      <Object?>[track, track],
    );
    return Sqflite.firstIntValue(r) ?? 0;
  }

  /// 按英文精确查一个词（忽略大小写），查不到返回 null。
  /// 作文逐词翻译用：先查本地词库，命中就不用花 AI 的钱。
  Future<Word?> findByEn({required String track, required String en}) async {
    final String key = en.trim().toLowerCase();
    if (key.isEmpty) return null;
    final Database db = await database;
    final List<Map<String, dynamic>> rows = await db.query(
      tableWords,
      where: 'track = ? AND LOWER(en) = ?',
      whereArgs: <Object?>[track, key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Word.fromMap(rows.first);
  }

  /// 某个赛道一共有多少词（新用户判断要不要灌起步词表）
  Future<int> countWords({required String track}) async {
    final Database db = await database;
    final List<Map<String, Object?>> r = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM $tableWords WHERE track = ?',
      <Object?>[track],
    );
    return (r.first['n'] as int?) ?? 0;
  }

  /// 一次查一批英文（作文里去重后的词表），返回 小写英文 → 词条。
  /// 一条 SQL 搞定，避免几百个词逐个查。
  Future<Map<String, Word>> findByEnBatch({
    required String track,
    required Iterable<String> words,
  }) async {
    final List<String> keys = words
        .map((String w) => w.trim().toLowerCase())
        .where((String w) => w.isNotEmpty)
        .toSet()
        .toList();
    final Map<String, Word> out = <String, Word>{};
    if (keys.isEmpty) return out;

    final Database db = await database;
    // SQLite 的 IN 列表别太长，分批查
    for (int i = 0; i < keys.length; i += 400) {
      final List<String> part = i + 400 > keys.length
          ? keys.sublist(i)
          : keys.sublist(i, i + 400);
      final String marks = List<String>.filled(part.length, '?').join(',');
      final List<Map<String, dynamic>> rows = await db.query(
        tableWords,
        where: 'track = ? AND LOWER(en) IN ($marks)',
        whereArgs: <Object?>[track, ...part],
      );
      for (final Map<String, dynamic> m in rows) {
        final Word w = Word.fromMap(m);
        out[w.en.trim().toLowerCase()] = w;
      }
    }
    return out;
  }

  /// 今天已经抽到但还没学完的那批词
  Future<List<Word>> getTodayDraw({required String track}) async {
    final Database db = await database;
    final List<Map<String, dynamic>> rows = await db.rawQuery(
      'SELECT w.* FROM $tableWords w '
      'INNER JOIN $tableDrawPool p ON p.word_id = w.id '
      'WHERE p.track = ? AND p.draw_date = ? ORDER BY w.en COLLATE NOCASE ASC',
      <Object?>[track, _today()],
    );
    return rows.map(Word.fromMap).toList();
  }

  /// 自动抽：今天已经抽过就直接返回那批；没抽过才新抽 count 个。
  /// 只从「没掌握 + 没抽过」的词里随机取，所以跨天不会重复。
  Future<List<Word>> drawDaily({
    required String track,
    required int count,
  }) async {
    final List<Word> today = await getTodayDraw(track: track);
    if (today.isNotEmpty) return today;
    return drawMore(track: track, count: count);
  }

  /// 手动加抽：不管今天抽没抽过，再抽 count 个新的
  Future<List<Word>> drawMore({
    required String track,
    required int count,
  }) async {
    final Database db = await database;
    final List<Map<String, dynamic>> rows = await db.rawQuery(
      'SELECT * FROM $tableWords WHERE track = ? AND mastered = 0 '
      'AND id NOT IN (SELECT word_id FROM $tableDrawPool WHERE track = ?) '
      'ORDER BY RANDOM() LIMIT ?',
      <Object?>[track, track, count],
    );
    final List<Word> picked = rows.map(Word.fromMap).toList();

    final String date = _today();
    await db.transaction((Transaction txn) async {
      for (final Word w in picked) {
        await txn.insert(tableDrawPool, <String, Object?>{
          'word_id': w.id,
          'track': track,
          'draw_date': date,
          'done': 0,
          'uuid': newUuid(),
          'updated_at': DateTime.now().millisecondsSinceEpoch,
          'dirty': 1,
        });
      }
    });
    return picked;
  }

  /// 学完一个词：对了进已掌握，错了进错词本，同时把这条抽词记录标为已完成。
  /// 已掌握的词再复习时错了，会退回错词本（mastered 取消）。
  ///
  /// 调度跟复习页走同一套算法（见 _schedule）：答对 interval 翻倍，
  /// 答错立刻到期。以前这里不写 interval，导致学过的词永远明天再来。
  Future<void> finishDrawnWord(Word word, bool remembered) async {
    final Database db = await database;

    await db.transaction((Transaction txn) async {
      final _Schedule s = await _schedule(txn, word, remembered);

      await txn.update(
        tableWords,
        <String, Object?>{
          'correct': word.correct + (remembered ? 1 : 0),
          'wrong': word.wrong + (remembered ? 0 : 1),
          'mastered': s.mastered ? 1 : 0,
          'last_review': s.at.toIso8601String(),
          'next_review': s.next.toIso8601String(),
          'interval': s.interval,
          'updated_at': s.at.millisecondsSinceEpoch,
          'dirty': 1,
        },
        where: 'id = ?',
        whereArgs: <Object?>[word.id],
      );
      await txn.insert(tableReviews, <String, Object?>{
        'word_id': word.id,
        'mode': 'daily',
        'result': remembered ? 1 : 0,
        'review_time': s.at.toIso8601String(),
        'track': word.track,
        'uuid': newUuid(),
        'updated_at': s.at.millisecondsSinceEpoch,
        'dirty': 1,
      });
      await txn.update(
        tableDrawPool,
        <String, Object?>{
          'done': 1,
          'updated_at': s.at.millisecondsSinceEpoch,
          'dirty': 1,
        },
        where: 'word_id = ? AND track = ?',
        whereArgs: <Object?>[word.id, word.track],
      );
    });
  }

  // ---------------- AI 对话历史 ----------------

  /// 会话列表，最近更新的在前。kind 传 'chat' 只看普通对话。
  Future<List<ChatSession>> getChatSessions({String? kind}) async {
    final Database db = await database;
    String? where;
    List<Object?>? args;
    if (kind == 'chat') {
      // 早期的复盘会话没有 kind，按标题一并挡掉，避免混进普通历史
      where = "kind = 'chat' AND title NOT LIKE '错词复盘%'";
    } else if (kind != null) {
      where = 'kind = ?';
      args = <Object?>[kind];
    }
    final List<Map<String, dynamic>> rows = await db.query(
      tableChatSessions,
      where: where,
      whereArgs: args,
      orderBy: 'updated_at DESC, id DESC',
    );
    return rows.map(ChatSession.fromMap).toList();
  }

  Future<int> createChatSession(String title, {String kind = 'chat'}) async {
    final Database db = await database;
    final int now = DateTime.now().millisecondsSinceEpoch;
    return db.insert(tableChatSessions, <String, Object?>{
      'title': title.trim().isEmpty ? '新对话' : title.trim(),
      'kind': kind,
      'created_at': now,
      'updated_at': now,
    });
  }

  /// 固定的错词复盘会话，没有就建一条
  Future<ChatSession?> getDigestSession() async {
    final Database db = await database;
    final List<Map<String, dynamic>> rows = await db.query(
      tableChatSessions,
      where: "kind = 'digest'",
      orderBy: 'id ASC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ChatSession.fromMap(rows.first);
  }

  Future<int> ensureDigestSession() async {
    final ChatSession? s = await getDigestSession();
    if (s != null) return s.id;
    return createChatSession('错词复盘', kind: 'digest');
  }

  Future<int> addDigestRecord({
    required int sessionId,
    required String payload,
    required int itemCount,
  }) async {
    final Database db = await database;
    return db.insert(tableDigestRecords, <String, Object?>{
      'session_id': sessionId,
      'payload': payload,
      'item_count': itemCount,
      'message_id': null,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> setDigestRecordMessage(int recordId, int messageId) async {
    final Database db = await database;
    await db.update(
      tableDigestRecords,
      <String, Object?>{'message_id': messageId},
      where: 'id = ?',
      whereArgs: <Object?>[recordId],
    );
  }

  Future<List<DigestRecord>> getDigestRecords({int limit = 100}) async {
    final Database db = await database;
    final List<Map<String, dynamic>> rows = await db.query(
      tableDigestRecords,
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(DigestRecord.fromMap).toList();
  }

  Future<void> touchChatSession(int id) async {
    final Database db = await database;
    await db.update(
      tableChatSessions,
      <String, Object?>{'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> renameChatSession(int id, String title) async {
    final Database db = await database;
    await db.update(
      tableChatSessions,
      <String, Object?>{'title': title},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  /// 删掉一整段对话（连同里面的消息）
  Future<void> deleteChatSession(int id) async {
    final Database db = await database;
    await db.transaction((Transaction txn) async {
      final List<Map<String, dynamic>> rows = await txn.query(
        tableChat,
        columns: <String>['uuid'],
        where: 'session_id = ?',
        whereArgs: <Object?>[id],
      );
      final int now = DateTime.now().millisecondsSinceEpoch;
      for (final Map<String, dynamic> r in rows) {
        final String? uuid = r['uuid'] as String?;
        if (uuid == null || uuid.isEmpty) continue;
        await txn.insert(tableTombstones, <String, Object?>{
          'uuid': uuid,
          'tbl': tableChat,
          'deleted_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await txn.delete(
        tableChat,
        where: 'session_id = ?',
        whereArgs: <Object?>[id],
      );
      await txn.delete(
        tableChatSessions,
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
    });
  }

  /// 读某一段对话，按时间正序
  Future<List<ChatMessage>> getChatMessages({
    required int sessionId,
    int limit = 300,
  }) async {
    final Database db = await database;
    final List<Map<String, dynamic>> rows = await db.query(
      tableChat,
      where: 'session_id = ?',
      whereArgs: <Object?>[sessionId],
      orderBy: 'id ASC',
      limit: limit,
    );
    return rows.map(_chatFromMap).toList();
  }

  /// 存一条消息，返回自增 id
  Future<int> addChatMessage(ChatMessage m, {required int sessionId}) async {
    final Database db = await database;
    return db.insert(tableChat, <String, Object?>{
      'role': m.role,
      'content': m.content,
      'created_at': (m.createdAt ?? DateTime.now()).toIso8601String(),
      'session_id': sessionId,
      'uuid': newUuid(),
      'updated_at': DateTime.now().millisecondsSinceEpoch,
      'dirty': 1,
    });
  }

  Future<void> saveChatGraph(int messageId, String json) async {
    final Database db = await database;
    await db.insert(tableChatGraphs, <String, Object?>{
      'message_id': messageId,
      'json': json,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<int, String>> getChatGraphsForSession(int sessionId) async {
    final Database db = await database;
    final List<Map<String, dynamic>> rows = await db.rawQuery(
      'SELECT g.message_id, g.json FROM $tableChatGraphs g '
      'JOIN $tableChat m ON m.id = g.message_id '
      'WHERE m.session_id = ?',
      <Object?>[sessionId],
    );
    return <int, String>{
      for (final Map<String, dynamic> r in rows)
        (r['message_id'] as int): (r['json'] as String),
    };
  }

  /// 删掉指定的一句（用户长按选的那条）
  Future<void> deleteChatMessage(int id) async {
    final Database db = await database;
    await _markDeleted(db, tableChat, id);
    await db.delete(tableChat, where: 'id = ?', whereArgs: <Object?>[id]);
  }

  /// 清空某一段对话；不传就清空全部。
  Future<void> clearChat({int? sessionId}) async {
    final Database db = await database;
    await db.transaction((Transaction txn) async {
      final List<Map<String, dynamic>> rows = await txn.query(
        tableChat,
        columns: <String>['id', 'uuid'],
        where: sessionId == null ? null : 'session_id = ?',
        whereArgs: sessionId == null ? null : <Object?>[sessionId],
      );
      final int now = DateTime.now().millisecondsSinceEpoch;
      for (final Map<String, dynamic> r in rows) {
        final String? uuid = r['uuid'] as String?;
        if (uuid == null || uuid.isEmpty) continue;
        await txn.insert(tableTombstones, <String, Object?>{
          'uuid': uuid,
          'tbl': tableChat,
          'deleted_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await txn.delete(
        tableChat,
        where: sessionId == null ? null : 'session_id = ?',
        whereArgs: sessionId == null ? null : <Object?>[sessionId],
      );
    });
  }

  ChatMessage _chatFromMap(Map<String, dynamic> m) {
    return ChatMessage(
      id: m['id'] as int?,
      role: (m['role'] as String?) ?? 'user',
      content: (m['content'] as String?) ?? '',
      createdAt: DateTime.tryParse((m['created_at'] as String?) ?? ''),
    );
  }

  /// 清空今天这批抽词记录（"换一批"时用）
  Future<void> clearTodayDraw({required String track}) async {
    final Database db = await database;
    await db.delete(
      tableDrawPool,
      where: 'track = ? AND draw_date = ?',
      whereArgs: <Object?>[track, _today()],
    );
  }

  static String _today() {
    final DateTime n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  /// 全部赛道的全部单词（不分 track）。
  /// 只有备份/导出用——正常页面必须按赛道取数据，别用这个。
  Future<List<Word>> getAllWords() async {
    final Database db = await database;
    final List<Map<String, dynamic>> rows = await db.query(
      tableWords,
      orderBy: 'track, id',
    );
    return rows.map(Word.fromMap).toList();
  }

  /// 批量改归属：把一批词整批挪到另一条赛道，学习进度原样带走。
  /// 老数据升级后默认都归在四级，用这个整批挪到六级 / 专升本 / 考研。
  Future<int> moveWordsTo({
    required List<int> ids,
    required String track,
  }) async {
    final Database db = await database;
    int moved = 0;
    await db.transaction((Transaction txn) async {
      for (final int id in ids) {
        moved += await txn.update(
          tableWords,
          <String, Object?>{'track': track},
          where: 'id = ?',
          whereArgs: <Object?>[id],
        );
      }
    });
    return moved;
  }

  /// 某个赛道下的全部课次标签，用于筛选条
  Future<List<String>> getAllTags({required String track}) async {
    final Database db = await database;
    final List<Map<String, dynamic>> rows = await db.rawQuery(
      'SELECT DISTINCT tag FROM $tableWords '
      'WHERE track = ? AND tag IS NOT NULL AND tag != "" ORDER BY tag',
      [track],
    );
    return rows.map((m) => m['tag'] as String).toList();
  }

  /// 今日待复习：学过、到了复习时间、且还没被标记为已掌握。
  ///
  /// 关键：只认 next_review 非空的词。以前把 next_review IS NULL
  /// （= 从没在任何路径上学过）也算成"到期"，结果 3000 词的库里
  /// 绝大部分是生词，首页那个"该复习"数字直接等于词库总量，完全失真。
  /// 从没学过的词属于"抽新词"，不属于"复习"。
  Future<List<Word>> getDueWords({
    required String track,
    int limit = 30,
  }) async {
    final Database db = await database;
    final String now = DateTime.now().toIso8601String();
    final List<Map<String, dynamic>> rows = await db.query(
      tableWords,
      // 已掌握的直接排除（放在 SQL 里，避免先截断 limit 再过滤导致数量不准）
      where:
          'track = ? AND mastered = 0 '
          'AND next_review IS NOT NULL AND next_review <= ?',
      whereArgs: <Object?>[track, now],
      orderBy: 'next_review ASC',
      limit: limit,
    );
    return rows.map(Word.fromMap).toList();
  }

  /// 抽过但没学完的词：在抽词池里还挂着 done = 0，不限哪天抽的。
  ///
  /// 这个状态以前系统里没人认——抽词池按 draw_date 只认今天，
  /// "能不能再抽"又是 NOT IN (整张抽词池)，于是昨天抽多没背完的词
  /// 既不在今天这批、也永远抽不到，只能靠复习队列歪打正着露个脸。
  /// 现在单独拎出来，首页给一个"接着学"的入口。
  Future<List<Word>> getUnfinishedWords({
    required String track,
    int limit = 200,
  }) async {
    final Database db = await database;
    final List<Map<String, dynamic>> rows = await db.rawQuery(
      'SELECT w.* FROM $tableWords w '
      'INNER JOIN $tableDrawPool p ON p.word_id = w.id '
      'WHERE p.track = ? AND p.done = 0 AND w.mastered = 0 '
      'ORDER BY w.en COLLATE NOCASE ASC LIMIT ?',
      <Object?>[track, limit],
    );
    return rows.map(Word.fromMap).toList();
  }

  /// 放弃这批没学完的词：把它们从抽词池里摘掉，
  /// 词本身还在词库里，以后还能被抽到。
  Future<int> clearUnfinished({required String track}) async {
    final Database db = await database;
    return db.delete(
      tableDrawPool,
      where: 'track = ? AND done = 0',
      whereArgs: <Object?>[track],
    );
  }

  /// 错词本：只取当前赛道，错得多的排前面
  Future<List<Word>> getWrongWords({required String track}) async {
    final Database db = await database;
    final List<Map<String, dynamic>> rows = await db.query(
      tableWords,
      where: 'track = ? AND wrong > 0',
      whereArgs: [track],
      orderBy: 'wrong DESC, id DESC',
    );
    return rows.map(Word.fromMap).toList();
  }

  // ---------------- 复习 ----------------

  /// 复习调度的唯一算法。
  ///
  /// 以前三条写学习结果的路（每日学习 / 复习页 / 错词本标记）各写一套，
  /// 其中每日学习那条只算 next_review、从不把 interval 写回表里，
  /// 于是 interval 永远停在 1 —— 答对十次的词也是明天再来，词永不毕业。
  /// 现在统一从这里出结果，改算法只改这一处。
  ///
  /// 规则：答对 interval 翻倍（1→2→4→8…），答错打回 1 且立刻到期。
  /// 掌握：连对 3 次算掌握；中间错一次立刻取消。
  Future<_Schedule> _schedule(
    Transaction txn,
    Word word,
    bool remembered,
  ) async {
    final DateTime now = DateTime.now();

    final int newInterval = remembered
        ? (word.interval < 1 ? 1 : word.interval) * 2
        : 1;
    // 答错就地再来一次（next_review = 现在），答对按 interval 天后见
    final DateTime next = remembered
        ? now.add(Duration(days: newInterval))
        : now;

    // 只查这一个词最近 2 次记录，加上本次正好凑满 3 次判断。
    // 有 idx_reviews_word 索引，成本极低，不用扫全表。
    final List<Map<String, dynamic>> recent = await txn.query(
      tableReviews,
      columns: <String>['result'],
      where: 'word_id = ?',
      whereArgs: <Object?>[word.id],
      orderBy: 'id DESC',
      limit: 2,
    );
    final List<int> seq = <int>[
      remembered ? 1 : 0,
      ...recent.map((Map<String, dynamic> r) => r['result'] as int),
    ];
    final bool mastered = seq.length >= 3 && seq.every((int v) => v == 1);

    return _Schedule(
      interval: newInterval,
      next: next,
      mastered: mastered,
      at: now,
    );
  }

  /// 记录一次复习结果。
  /// result: 1 = 记住了，0 = 忘了
  Future<void> recordReview(
    Word word,
    bool remembered, {
    String mode = 'card',
  }) async {
    final Database db = await database;

    await db.transaction((Transaction txn) async {
      final _Schedule s = await _schedule(txn, word, remembered);

      await txn.update(
        tableWords,
        <String, dynamic>{
          'correct': word.correct + (remembered ? 1 : 0),
          'wrong': word.wrong + (remembered ? 0 : 1),
          'last_review': s.at.toIso8601String(),
          'next_review': s.next.toIso8601String(),
          'interval': s.interval,
          'mastered': s.mastered ? 1 : 0,
          'updated_at': s.at.millisecondsSinceEpoch,
          'dirty': 1,
        },
        where: 'id = ?',
        whereArgs: <Object?>[word.id],
      );
      await txn.insert(tableReviews, <String, dynamic>{
        'word_id': word.id,
        'mode': mode,
        'result': remembered ? 1 : 0,
        'review_time': s.at.toIso8601String(),
        // 复习记录也带上赛道，这样「今日复习数」能按赛道分开统计
        'track': word.track,
        'uuid': newUuid(),
        'updated_at': s.at.millisecondsSinceEpoch,
        'dirty': 1,
      });
    });
  }

  /// 错词本里点「已掌握」：
  /// 错误计数清零 + 标记掌握 + 补一条"答对"记录，
  /// 这样它不会继续赖在复习队列里，也不会再回到错词本。
  Future<void> markMastered(Word word) async {
    final Database db = await database;

    await db.transaction((Transaction txn) async {
      // 手动标记掌握：调度仍按"答对"推进（interval 翻倍），
      // 但掌握标记是用户自己拍的，不走"连对 3 次"那套判定。
      // 错误数清零 —— 不然它会一直赖在错词本里。
      final _Schedule s = await _schedule(txn, word, true);

      await txn.update(
        tableWords,
        <String, dynamic>{
          'wrong': 0,
          'mastered': 1,
          'last_review': s.at.toIso8601String(),
          'next_review': s.next.toIso8601String(),
          'interval': s.interval,
          'updated_at': s.at.millisecondsSinceEpoch,
          'dirty': 1,
        },
        where: 'id = ?',
        whereArgs: <Object?>[word.id],
      );
      await txn.insert(tableReviews, <String, dynamic>{
        'word_id': word.id,
        'mode': 'manual',
        'result': 1,
        'review_time': s.at.toIso8601String(),
        'track': word.track,
        'uuid': newUuid(),
        'updated_at': s.at.millisecondsSinceEpoch,
        'dirty': 1,
      });
    });
  }

  // ---------------- 统计 ----------------

  /// 统计：全部口径都限定在当前赛道内
  Future<Map<String, int>> getStats({required String track}) async {
    final Database db = await database;

    Future<int> count(String sql, [List<Object?>? args]) async {
      final List<Map<String, dynamic>> r = await db.rawQuery(sql, args);
      return Sqflite.firstIntValue(r) ?? 0;
    }

    final int total = await count(
      'SELECT COUNT(*) FROM $tableWords WHERE track = ?',
      [track],
    );
    final int wrongSum = await count(
      'SELECT COALESCE(SUM(wrong),0) FROM $tableWords WHERE track = ?',
      [track],
    );
    final int due = (await getDueWords(track: track, limit: 9999)).length;
    final int mastered = await count(
      'SELECT COUNT(*) FROM $tableWords WHERE track = ? AND mastered = 1',
      [track],
    );

    final String todayStart = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    ).toIso8601String();
    final int todayReviews = await count(
      'SELECT COUNT(*) FROM $tableReviews WHERE track = ? AND review_time >= ?',
      [track, todayStart],
    );
    final int todayCorrect = await count(
      'SELECT COUNT(*) FROM $tableReviews '
      'WHERE track = ? AND review_time >= ? AND result = 1',
      [track, todayStart],
    );

    return <String, int>{
      'total': total,
      'mastered': mastered,
      'due': due,
      'wrongSum': wrongSum,
      'todayReviews': todayReviews,
      'todayCorrect': todayCorrect,
    };
  }

  // ---------------- 设置（键值对） ----------------

  /// 读一个配置项，不存在返回 null
  Future<String?> getSetting(String key) async {
    final Database db = await database;
    final List<Map<String, dynamic>> rows = await db.query(
      tableSettings,
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  /// 写一个配置项，已存在就覆盖
  Future<void> setSetting(String key, String value) async {
    final Database db = await database;
    await db.insert(tableSettings, <String, dynamic>{
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---------------- 同步预留接口 ----------------
  // 等服务器搭好，SyncService 就调这几个方法。现在先不接网络，
  // 但字段和墓碑已经在写了，届时不用再做数据迁移。

  /// 取出某张表待上传的改动（dirty = 1）
  Future<List<Map<String, dynamic>>> getDirtyRows(
    String table, {
    int limit = 200,
  }) async {
    final Database db = await database;
    return db.query(
      table,
      where: 'dirty = 1',
      orderBy: 'updated_at ASC',
      limit: limit,
    );
  }

  /// 取出待上传的删除墓碑
  Future<List<Map<String, dynamic>>> getTombstones({int limit = 200}) async {
    final Database db = await database;
    return db.query(tableTombstones, orderBy: 'deleted_at ASC', limit: limit);
  }

  /// 一批记录上传成功后，清掉它们的 dirty 标记
  Future<void> markSynced(String table, List<String> uuids) async {
    if (uuids.isEmpty) return;
    final Database db = await database;
    final String placeholders = List<String>.filled(
      uuids.length,
      '?',
    ).join(',');
    await db.update(
      table,
      <String, Object?>{'dirty': 0},
      where: 'uuid IN ($placeholders)',
      whereArgs: uuids,
    );
  }

  /// 墓碑上传成功后删掉
  Future<void> clearTombstones(List<String> uuids) async {
    if (uuids.isEmpty) return;
    final Database db = await database;
    final String placeholders = List<String>.filled(
      uuids.length,
      '?',
    ).join(',');
    await db.delete(
      tableTombstones,
      where: 'uuid IN ($placeholders)',
      whereArgs: uuids,
    );
  }

  /// 上次同步到哪了（毫秒时间戳，0 = 从没同步过）
  Future<int> getLastSyncAt() async {
    final String? v = await getSetting('last_sync_at');
    return int.tryParse(v ?? '') ?? 0;
  }

  Future<void> setLastSyncAt(int millis) async {
    await setSetting('last_sync_at', millis.toString());
  }

  // ---------------- 作文 ----------------

  /// 存一篇作文。
  /// 现在不覆盖同一天的旧文：换一篇就是新增一篇，旧文和它的标记都留着，
  /// 错词本里指向旧文的标记才不会变成死链。
  Future<void> saveEssay(Essay e) async {
    final Database db = await database;
    await db.insert(
      tableEssays,
      e.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 某天推的那篇（没推过返回 null）
  Future<Essay?> getEssayForDay({
    required String track,
    required String date,
  }) async {
    final Database db = await database;
    final List<Map<String, dynamic>> rows = await db.query(
      tableEssays,
      where: 'track = ? AND date = ?',
      whereArgs: <Object?>[track, date],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Essay.fromMap(rows.first);
  }

  Future<Essay?> getEssayById(String id) async {
    final Database db = await database;
    final List<Map<String, dynamic>> rows = await db.query(
      tableEssays,
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Essay.fromMap(rows.first);
  }

  /// 最近几篇，用来在作文页翻旧文
  Future<List<Essay>> getRecentEssays({
    required String track,
    int limit = 20,
  }) async {
    final Database db = await database;
    final List<Map<String, dynamic>> rows = await db.query(
      tableEssays,
      where: 'track = ?',
      whereArgs: <Object?>[track],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(Essay.fromMap).toList();
  }

  // ---------------- 作文标记 ----------------

  /// 整篇的标记重写一遍。数量很小（十几个），全删重插最省事，
  /// 也不会出现「改了短语、旧的还留着」这种半截状态。
  Future<void> replaceEssayMarks(String essayId, List<EssayMark> marks) async {
    final Database db = await database;
    await db.transaction((Transaction txn) async {
      await txn.delete(
        tableEssayMarks,
        where: 'essay_id = ?',
        whereArgs: <Object?>[essayId],
      );
      for (final EssayMark m in marks) {
        await txn.insert(tableEssayMarks, <String, Object?>{
          'essay_id': essayId,
          'word': m.word,
          'sentence': m.sentence,
          'para': m.para,
          'start_index': m.start,
          'created_at': m.createdAt,
        });
      }
    });
  }

  Future<List<EssayMark>> getEssayMarks(String essayId) async {
    final Database db = await database;
    final List<Map<String, dynamic>> rows = await db.query(
      tableEssayMarks,
      where: 'essay_id = ?',
      whereArgs: <Object?>[essayId],
      orderBy: 'para ASC, start_index ASC',
    );
    return rows.map(EssayMark.fromMap).toList();
  }

  /// 错词本用：当前赛道所有作文标记，带出处标题和日期
  Future<List<EssayMarkHit>> getEssayMarkHits({required String track}) async {
    final Database db = await database;
    final List<Map<String, dynamic>> rows = await db.rawQuery(
      'SELECT m.*, e.title AS essay_title, e.date AS essay_date '
      'FROM $tableEssayMarks m JOIN $tableEssays e ON e.id = m.essay_id '
      'WHERE e.track = ? ORDER BY m.created_at DESC',
      <Object?>[track],
    );
    return rows
        .map(
          (Map<String, dynamic> r) => EssayMarkHit(
            mark: EssayMark.fromMap(r),
            essayTitle: r['essay_title'] as String? ?? '',
            essayDate: r['essay_date'] as String? ?? '',
          ),
        )
        .toList();
  }

  /// 某个词在别的作文里也被标过吗（错词本点进去时挑最近的一处）
  Future<EssayMarkHit?> findMarkForWord({
    required String track,
    required String word,
  }) async {
    final List<EssayMarkHit> all = await getEssayMarkHits(track: track);
    final String key = word.trim().toLowerCase();
    for (final EssayMarkHit h in all) {
      if (h.mark.word.trim().toLowerCase() == key) return h;
    }
    return null;
  }

  /// 删掉一条标记（错词本里点「取消标记」）
  Future<void> deleteEssayMark(int id) async {
    final Database db = await database;
    await db.delete(tableEssayMarks, where: 'id = ?', whereArgs: <Object?>[id]);
  }

  /// 取消标记时，如果这个词是作文带进错词本的，一并删掉。
  /// 只删「没复习过、tag 是作文」的行，别误伤你手动加的同类词。
  Future<void> deleteEssayWordIfUntouched({
    required String track,
    required String en,
  }) async {
    final Database db = await database;
    await db.delete(
      tableWords,
      where:
          "track = ? AND LOWER(en) = ? AND tag = '作文' "
          'AND correct = 0 AND wrong = 1',
      whereArgs: <Object?>[track, en.trim().toLowerCase()],
    );
  }

  /// 作文的逐句译文（JSON 字符串），没有就返回 null
  Future<String?> getEssayTranslation(String essayId) async {
    final Database db = await database;
    final List<Map<String, dynamic>> rows = await db.query(
      tableEssayTranslations,
      columns: <String>['content'],
      where: 'essay_id = ?',
      whereArgs: <Object?>[essayId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['content'] as String?;
  }

  Future<void> saveEssayTranslation(String essayId, String content) async {
    final Database db = await database;
    await db.insert(tableEssayTranslations, <String, Object?>{
      'essay_id': essayId,
      'content': content,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---------------- 单词学习卡 ----------------

  /// 取缓存的学习卡；没有返回 null
  Future<Map<String, String>?> getWordCard(int wordId) async {
    final Database db = await database;
    final List<Map<String, dynamic>> rows = await db.query(
      tableWordCards,
      where: 'word_id = ?',
      whereArgs: <Object?>[wordId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final Map<String, dynamic> r = rows.first;
    return <String, String>{
      'root': (r['root'] as String?) ?? '',
      'collocations': (r['collocations'] as String?) ?? '',
      'examples': (r['examples'] as String?) ?? '',
    };
  }

  Future<void> saveWordCard({
    required int wordId,
    required String root,
    required String collocations,
    required String examples,
  }) async {
    final Database db = await database;
    await db.insert(tableWordCards, <String, Object?>{
      'word_id': wordId,
      'root': root,
      'collocations': collocations,
      'examples': examples,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---------------- 作文释义缓存 ----------------

  Future<Map<String, String>> getGlosses(List<String> words) async {
    if (words.isEmpty) return <String, String>{};
    final Database db = await database;
    final String marks = List<String>.filled(words.length, '?').join(',');
    final List<Map<String, dynamic>> rows = await db.rawQuery(
      'SELECT en, zh FROM $tableWordGlosses WHERE en IN ($marks)',
      words,
    );
    return <String, String>{
      for (final Map<String, dynamic> r in rows)
        (r['en'] as String): (r['zh'] as String?) ?? '',
    };
  }

  Future<void> saveGlosses(Map<String, String> glosses) async {
    if (glosses.isEmpty) return;
    final Database db = await database;
    final int now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((Transaction txn) async {
      for (final MapEntry<String, String> e in glosses.entries) {
        if (e.value.trim().isEmpty) continue;
        await txn.insert(tableWordGlosses, <String, Object?>{
          'en': e.key,
          'zh': e.value.trim(),
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  // ---------------- 分区 ----------------

  Future<List<Map<String, Object?>>> getSections() async {
    final Database db = await database;
    return db.query(tableSections, orderBy: 'sort ASC, created_at ASC');
  }

  Future<void> insertSection({
    required String id,
    required String name,
    required int sort,
  }) async {
    final Database db = await database;
    await db.insert(tableSections, <String, Object?>{
      'id': id,
      'name': name,
      'sort': sort,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> renameSection(String id, String name) async {
    final Database db = await database;
    await db.update(
      tableSections,
      <String, Object?>{'name': name},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> deleteSection(String id) async {
    final Database db = await database;
    await db.delete(tableSections, where: 'id = ?', whereArgs: <Object?>[id]);
  }

  Future<WordNote?> getWordNote(String essayId, String word) async {
    final Database db = await database;
    final List<Map<String, dynamic>> rows = await db.query(
      'word_notes',
      where: 'essay_id = ? AND word = ?',
      whereArgs: <Object?>[essayId, word],
      limit: 1,
    );
    return rows.isEmpty ? null : WordNote.fromMap(rows.first);
  }

  Future<List<WordNote>> getWordNotes(String essayId) async {
    final Database db = await database;
    final List<Map<String, dynamic>> rows = await db.query(
      'word_notes',
      where: 'essay_id = ?',
      whereArgs: <Object?>[essayId],
      orderBy: 'updated_at DESC',
    );
    return rows.map(WordNote.fromMap).toList();
  }

  Future<void> saveWordNote({
    required String essayId,
    required String word,
    required String sentence,
    required String note,
  }) async {
    final Database db = await database;
    final int now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('word_notes', <String, Object?>{
      'essay_id': essayId,
      'word': word,
      'sentence': sentence,
      'note': note,
      'created_at': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteWordNote(String essayId, String word) async {
    final Database db = await database;
    await db.delete(
      'word_notes',
      where: 'essay_id = ? AND word = ?',
      whereArgs: <Object?>[essayId, word],
    );
  }

  /// 批注本：所有文章按最近更新排序，带标题和日期
  Future<List<WordNote>> getNoteOverview() async {
    final Database db = await database;
    final List<Map<String, dynamic>> rows = await db.rawQuery('''
      SELECT n.*, e.title AS essay_title, e.date AS essay_date
      FROM word_notes n
      LEFT JOIN essays e ON e.id = n.essay_id
      ORDER BY n.updated_at DESC
    ''');
    return rows.map(WordNote.fromMap).toList();
  }

  Future<List<ChatMessage>> getDigestQa(int messageId) async {
    final Database db = await database;
    final List<Map<String, dynamic>> rows = await db.query(
      'digest_qa',
      where: 'message_id = ?',
      whereArgs: <Object?>[messageId],
      orderBy: 'id ASC',
    );
    return rows
        .map(
          (Map<String, dynamic> r) => ChatMessage(
            id: r['id'] as int?,
            role: (r['role'] as String?) ?? 'user',
            content: (r['content'] as String?) ?? '',
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              (r['created_at'] as int?) ?? 0,
            ),
          ),
        )
        .toList();
  }

  Future<void> addDigestQa(int messageId, String role, String content) async {
    final Database db = await database;
    await db.insert('digest_qa', <String, Object?>{
      'message_id': messageId,
      'role': role,
      'content': content,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// 调试用：删库重建。改了建表 SQL 之后调它一次
  Future<void> resetDatabase() async {
    final Database db = await database;
    await db.close();
    _database = null;
    _opening = null;
    final Directory dir = await getApplicationDocumentsDirectory();
    await deleteDatabase('${dir.path}${Platform.pathSeparator}$_dbName');
  }
}
