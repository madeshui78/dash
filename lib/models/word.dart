// 单词数据模型：负责 Dart 对象 <-> 数据库行(Map) 的互相转换

/// 一条单词记录，对应 words 表的一行
class Word {
  final int? id;

  /// 全局唯一标识。多设备同步靠它对账：
  /// 自增 id 在两台手机上会从 1 开始重复，uuid 不会。
  /// 插入时由 DatabaseHelper 自动生成，页面不用管。
  final String? uuid;

  final String en;
  final String zh;
  final String? phonetic;
  final String? example;
  final String? source;
  final String? tag;

  final int correct;
  final int wrong;
  final DateTime? lastReview;
  final DateTime? nextReview;
  final int interval;
  final double ease;

  /// 所属考试赛道：CET4（四级）/ CET6（六级）/ UPGRADE（专升本）/ KAOYAN（考研）
  /// 四类考试的数据完全隔离：各自的单词、复习进度、错词、统计互不干扰。
  /// 同一个词在不同赛道里是两条独立记录，各自的掌握状态互不牵连。
  final String track;

  /// 是否已掌握。
  /// 这是一个「落库」的显式标记，来源只有三个：
  ///   1. 复习连对 3 次   → 自动置 true
  ///   2. 复习中途答错   → 置回 false
  ///   3. 错词本点「已掌握」→ 手动置 true
  /// 它是唯一决定「这个词还进不进复习队列」的依据，口径统一。
  final bool mastered;

  const Word({
    this.id,
    this.uuid,
    required this.en,
    required this.zh,
    this.phonetic,
    this.example,
    this.source,
    this.tag,
    this.correct = 0,
    this.wrong = 0,
    this.lastReview,
    this.nextReview,
    this.interval = 1,
    this.ease = 2.5,
    this.track = 'CET4',
    this.mastered = false,
  });

  static DateTime? _parseDate(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString());

  factory Word.fromMap(Map<String, dynamic> m) {
    return Word(
      id: m['id'] as int?,
      uuid: m['uuid'] as String?,
      en: m['en'] as String? ?? '',
      zh: m['zh'] as String? ?? '',
      phonetic: m['phonetic'] as String?,
      example: m['example'] as String?,
      source: m['source'] as String?,
      tag: m['tag'] as String?,
      correct: m['correct'] as int? ?? 0,
      wrong: m['wrong'] as int? ?? 0,
      lastReview: _parseDate(m['last_review']),
      nextReview: _parseDate(m['next_review']),
      interval: m['interval'] as int? ?? 1,
      ease: (m['ease'] as num?)?.toDouble() ?? 2.5,
      // 老数据没有这一列，统一归到四级，不会丢
      track: (m['track'] as String?) ?? 'CET4',
      // SQLite 没有布尔类型，用 0 / 1 存
      mastered: (m['mastered'] as int? ?? 0) == 1,
    );
  }

  /// 转成数据库行。id 为 null 时不写入，交给自增
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      if (id != null) 'id': id,
      if (uuid != null) 'uuid': uuid,
      'en': en,
      'zh': zh,
      'phonetic': phonetic,
      'example': example,
      'source': source,
      'tag': tag,
      'correct': correct,
      'wrong': wrong,
      'last_review': lastReview?.toIso8601String(),
      'next_review': nextReview?.toIso8601String(),
      'interval': interval,
      'ease': ease,
      'track': track,
      'mastered': mastered ? 1 : 0,
    };
  }

  Word copyWith({
    String? uuid,
    String? en,
    String? zh,
    String? phonetic,
    String? example,
    String? source,
    String? tag,
    int? correct,
    int? wrong,
    DateTime? lastReview,
    DateTime? nextReview,
    int? interval,
    double? ease,
    String? track,
    bool? mastered,
  }) {
    return Word(
      id: id,
      uuid: uuid ?? this.uuid,
      en: en ?? this.en,
      zh: zh ?? this.zh,
      phonetic: phonetic ?? this.phonetic,
      example: example ?? this.example,
      source: source ?? this.source,
      tag: tag ?? this.tag,
      correct: correct ?? this.correct,
      wrong: wrong ?? this.wrong,
      lastReview: lastReview ?? this.lastReview,
      nextReview: nextReview ?? this.nextReview,
      interval: interval ?? this.interval,
      ease: ease ?? this.ease,
      track: track ?? this.track,
      mastered: mastered ?? this.mastered,
    );
  }
}
