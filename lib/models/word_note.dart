// 作文里某个词的批注。按 (essay_id, word) 唯一，不同文章互不干扰。

class WordNote {
  final int? id;
  final String essayId;
  final String word;
  final String sentence;
  final String note;
  final int updatedAt;

  /// 批注本列表用：来自 essays 表
  final String essayTitle;
  final String essayDate;

  const WordNote({
    this.id,
    required this.essayId,
    required this.word,
    required this.sentence,
    required this.note,
    required this.updatedAt,
    this.essayTitle = '',
    this.essayDate = '',
  });

  factory WordNote.fromMap(Map<String, dynamic> m) {
    return WordNote(
      id: m['id'] as int?,
      essayId: (m['essay_id'] as String?) ?? '',
      word: (m['word'] as String?) ?? '',
      sentence: (m['sentence'] as String?) ?? '',
      note: (m['note'] as String?) ?? '',
      updatedAt: (m['updated_at'] as int?) ?? 0,
      essayTitle: (m['essay_title'] as String?) ?? '',
      essayDate: (m['essay_date'] as String?) ?? '',
    );
  }
}
