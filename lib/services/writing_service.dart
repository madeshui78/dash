// 写作批改：把用户写的作文发给模型，按评分标准返回结构化结果。

import 'dart:convert';

import '../models/chat_session.dart';
import 'ai_service.dart';

class WritingIssue {
  final String quote;
  final String fix;
  final String why;

  const WritingIssue({
    required this.quote,
    required this.fix,
    required this.why,
  });

  factory WritingIssue.fromMap(Map<String, dynamic> m) => WritingIssue(
    quote: (m['quote'] ?? '').toString(),
    fix: (m['fix'] ?? '').toString(),
    why: (m['why'] ?? '').toString(),
  );

  Map<String, dynamic> toMap() => <String, dynamic>{
    'quote': quote,
    'fix': fix,
    'why': why,
  };
}

class WritingFeedback {
  final double score; // 15 分制
  final String level;
  final List<String> good;
  final List<WritingIssue> issues;
  final String rewrite;
  final String advice;

  const WritingFeedback({
    required this.score,
    required this.level,
    required this.good,
    required this.issues,
    required this.rewrite,
    required this.advice,
  });

  factory WritingFeedback.fromMap(Map<String, dynamic> m) => WritingFeedback(
    score: ((m['score'] as num?) ?? 0).toDouble(),
    level: (m['level'] ?? '').toString(),
    good: ((m['good'] as List?) ?? <dynamic>[])
        .map((dynamic e) => e.toString())
        .toList(),
    issues: ((m['issues'] as List?) ?? <dynamic>[])
        .whereType<Map>()
        .map((Map e) => WritingIssue.fromMap(e.cast<String, dynamic>()))
        .toList(),
    rewrite: (m['rewrite'] ?? '').toString(),
    advice: (m['advice'] ?? '').toString(),
  );

  Map<String, dynamic> toMap() => <String, dynamic>{
    'score': score,
    'level': level,
    'good': good,
    'issues': issues.map((WritingIssue e) => e.toMap()).toList(),
    'rewrite': rewrite,
    'advice': advice,
  };

  String encode() => jsonEncode(toMap());

  static WritingFeedback? tryDecode(String raw) {
    try {
      final Map<String, dynamic> m = jsonDecode(raw) as Map<String, dynamic>;
      return WritingFeedback.fromMap(m);
    } catch (_) {
      return null;
    }
  }
}

class WritingScale {
  final String id;
  final String label;
  final double maxScore;
  final String standard;

  /// 分数依据，写在选择面板里，不让人以为分数是随手编的
  final String note;

  const WritingScale({
    required this.id,
    required this.label,
    required this.maxScore,
    required this.standard,
    this.note = '',
  });
}

/// 只放有公开依据的评分标准；各省自命题的差异写在 note 里
const List<WritingScale> writingScales = <WritingScale>[
  WritingScale(
    id: 'zhongkao',
    label: '中考',
    maxScore: 15,
    standard: '中考英语作文',
    note: '多数地区满分 15；部分省市 20 或 25，以本地卷面为准',
  ),
  WritingScale(
    id: 'gaokao',
    label: '高考',
    maxScore: 25,
    standard: '高考英语作文（全国卷）',
    note: '全国卷写作 25 分；新高考为应用文 15 + 读后续写 25',
  ),
  WritingScale(
    id: 'cet4',
    label: '四级',
    maxScore: 15,
    standard: '大学英语四级写作',
    note: '卷面 15 分，占 15%，折合总分 106.5',
  ),
  WritingScale(
    id: 'cet6',
    label: '六级',
    maxScore: 15,
    standard: '大学英语六级写作',
    note: '卷面 15 分，占 15%，折合总分 106.5',
  ),
  WritingScale(
    id: 'kaoyan1',
    label: '考研一',
    maxScore: 20,
    standard: '考研英语（一）大作文',
    note: '英语一写作共 30：小作文 10 + 大作文 20',
  ),
  WritingScale(
    id: 'kaoyan2',
    label: '考研二',
    maxScore: 15,
    standard: '考研英语（二）大作文',
    note: '英语二写作共 25：小作文 10 + 大作文 15',
  ),
  WritingScale(
    id: 'upgrade',
    label: '专升本',
    maxScore: 15,
    standard: '专升本英语写作',
    note: '各省不同（15 / 20 / 25），这里按 15 算，以本省考纲为准',
  ),
];

WritingScale writingScaleById(String? id) {
  // 兼容旧版本存下的 id
  const Map<String, String> legacy = <String, String>{
    'primary': 'zhongkao',
    'junior': 'zhongkao',
    'senior': 'gaokao',
    'postgrad': 'kaoyan1',
  };
  final String key = legacy[id] ?? id ?? '';
  for (final WritingScale s in writingScales) {
    if (s.id == key) return s;
  }
  return writingScales[2]; // 默认四级
}

class WritingService {
  WritingService._();

  static const String _system =
      '你是英语写作阅卷老师，熟悉中考、高考、四六级、考研和专升本的评分标准。'
      '只输出一个合法的 JSON 对象，不要输出解释、Markdown 或代码块。'
      'JSON 结构：'
      '{"score": 按题目给定满分的数字, "level": "档次说明", '
      '"good": ["写得好的地方"], '
      '"issues": [{"quote": "原文片段", "fix": "建议改法", "why": "原因"}], '
      '"rewrite": "改写后的全文", "advice": "下一步怎么练"}';

  static Future<WritingFeedback> correct({
    required String topic,
    required String content,
    required WritingScale scale,
  }) async {
    final AiConfig cfg = await AiService.loadConfig();
    if (cfg.deepseekKey.trim().isEmpty) {
      throw Exception('还没填 DeepSeek Key，去设置里填一下');
    }

    final String ask =
        '评分标准：${scale.standard}，满分 ${scale.maxScore.toStringAsFixed(0)} 分。\n'
        '${scale.note.isEmpty ? '' : '评分依据：${scale.note}\n'}'
        '题目/要求：${topic.trim().isEmpty ? '未提供，按通用议论文评分' : topic.trim()}\n'
        '作文正文：\n$content\n\n'
        '请严格按该标准的满分打分，指出 3-6 处具体问题（引用原文片段），'
        '并给出改写全文。只输出 JSON。';

    final String raw = await AiService.chat(cfg, <ChatMessage>[
      ChatMessage(role: 'user', content: ask),
    ], systemPrompt: _system);

    final String json = _extractJson(raw);
    final WritingFeedback? fb = WritingFeedback.tryDecode(json);
    if (fb == null) {
      throw Exception('模型返回的格式看不懂，再试一次');
    }
    return fb;
  }

  /// 模型偶尔会包 ```json，或前后带一句话，这里截出第一个完整对象
  static String _extractJson(String s) {
    String t = s.trim();
    if (t.startsWith('```')) {
      t = t.replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '');
      t = t.replaceFirst(RegExp(r'\s*```$'), '');
    }
    final int start = t.indexOf('{');
    final int end = t.lastIndexOf('}');
    if (start >= 0 && end > start) return t.substring(start, end + 1);
    return t;
  }
}
