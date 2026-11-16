// 一段独立的 AI 对话（像 DeepSeek 左侧的会话列表）

class ChatSession {
  final int id;
  final String title;
  final DateTime updatedAt;

  /// 'chat' 普通问答 / 'digest' 错词复盘固定会话
  final String kind;

  const ChatSession({
    required this.id,
    required this.title,
    required this.updatedAt,
    this.kind = 'chat',
  });

  bool get isDigest => kind == 'digest';

  factory ChatSession.fromMap(Map<String, dynamic> m) {
    return ChatSession(
      id: m['id'] as int? ?? 0,
      title: m['title'] as String? ?? '对话',
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (m['updated_at'] as int?) ?? 0,
      ),
      kind: (m['kind'] as String?) ?? 'chat',
    );
  }
}

/// 一次后台提交的错词原文
class DigestRecord {
  final int id;
  final int sessionId;
  final String payload;
  final int itemCount;
  final int? messageId;
  final DateTime createdAt;

  const DigestRecord({
    required this.id,
    required this.sessionId,
    required this.payload,
    required this.itemCount,
    required this.messageId,
    required this.createdAt,
  });

  factory DigestRecord.fromMap(Map<String, dynamic> m) {
    return DigestRecord(
      id: m['id'] as int? ?? 0,
      sessionId: m['session_id'] as int? ?? 0,
      payload: (m['payload'] as String?) ?? '',
      itemCount: m['item_count'] as int? ?? 0,
      messageId: m['message_id'] as int?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (m['created_at'] as int?) ?? 0,
      ),
    );
  }
}
