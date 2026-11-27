class Writing {
  final int? id;
  final String track;
  final String topic;
  final String content;
  final double score;
  final String feedback;
  final DateTime createdAt;

  const Writing({
    this.id,
    required this.track,
    required this.topic,
    required this.content,
    required this.score,
    required this.feedback,
    required this.createdAt,
  });

  factory Writing.fromMap(Map<String, Object?> m) => Writing(
    id: m['id'] as int?,
    track: m['track'] as String? ?? 'cet4',
    topic: m['topic'] as String? ?? '',
    content: m['content'] as String? ?? '',
    score: (m['score'] as num?)?.toDouble() ?? 0,
    feedback: m['feedback'] as String? ?? '',
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (m['created_at'] as int?) ?? 0,
    ),
  );
}
