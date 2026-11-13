// 一段独立的 AI 对话（像 DeepSeek 左侧的会话列表）

class ChatSession {
  final int id;
  final String title;
  final DateTime updatedAt;

  const ChatSession({
    required this.id,
    required this.title,
    required this.updatedAt,
  });

  factory ChatSession.fromMap(Map<String, dynamic> m) {
    return ChatSession(
      id: m['id'] as int? ?? 0,
      title: m['title'] as String? ?? '对话',
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (m['updated_at'] as int?) ?? 0,
      ),
    );
  }
}
