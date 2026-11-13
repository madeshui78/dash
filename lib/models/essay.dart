// 作文与标记的数据模型。
//
// 一篇作文存一行；用户标红的词/短语另存一行，
// 错词本靠 essay_marks 反向找到「这个词是在哪篇作文的哪一段标的」。

/// 一篇作文
class Essay {
  final String id;

  /// 哪一天推的，YYYY-MM-DD
  final String date;

  /// 用户选的类型：议论文 / 书信 / 图表 / 记叙 / 说明
  final String topic;

  final String title;
  final String text;
  final String track;

  /// 毫秒时间戳
  final int createdAt;

  const Essay({
    required this.id,
    required this.date,
    required this.topic,
    required this.title,
    required this.text,
    required this.track,
    required this.createdAt,
  });

  int get wordCount =>
      RegExp(r"[A-Za-z]+(?:['’\-][A-Za-z]+)*").allMatches(text).length;

  factory Essay.fromMap(Map<String, dynamic> m) {
    return Essay(
      id: m['id'] as String? ?? '',
      date: m['date'] as String? ?? '',
      topic: m['topic'] as String? ?? '',
      title: m['title'] as String? ?? '',
      text: m['text'] as String? ?? '',
      track: m['track'] as String? ?? 'CET4',
      createdAt: m['created_at'] as int? ?? 0,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'date': date,
      'topic': topic,
      'title': title,
      'text': text,
      'track': track,
      'created_at': createdAt,
    };
  }
}

/// 用户在作文里标红的一处：可能是一个词，也可能是连着标的几个词（短语）
class EssayMark {
  final int? id;
  final String essayId;

  /// 标红的内容。短语是几个词用空格连起来
  final String word;

  /// 它所在的那句英文，错词本里显示这一句当语境
  final String sentence;

  /// 第几段（从 0 开始），点错词本回来时滚到这里
  final int para;

  /// 段落内的起始 token 下标，用来精确定位
  final int start;

  final int createdAt;

  const EssayMark({
    this.id,
    required this.essayId,
    required this.word,
    required this.sentence,
    required this.para,
    required this.start,
    required this.createdAt,
  });

  factory EssayMark.fromMap(Map<String, dynamic> m) {
    return EssayMark(
      id: m['id'] as int?,
      essayId: m['essay_id'] as String? ?? '',
      word: m['word'] as String? ?? '',
      sentence: m['sentence'] as String? ?? '',
      para: m['para'] as int? ?? 0,
      start: m['start_index'] as int? ?? 0,
      createdAt: m['created_at'] as int? ?? 0,
    );
  }
}

/// 错词本里展示的一条作文标记，带上出处
class EssayMarkHit {
  final EssayMark mark;
  final String essayTitle;
  final String essayDate;

  const EssayMarkHit({
    required this.mark,
    required this.essayTitle,
    required this.essayDate,
  });
}
