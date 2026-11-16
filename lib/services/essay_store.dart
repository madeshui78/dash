// 每天一篇作文：选类型 → 让 AI 写 → 存库。
//
// 为什么存库：错词本要能溯源回原文。只把文章放内存里，
// 换个页签再回来就没了，「这个词是在哪篇里标的」也就断了。

import 'package:flutter/foundation.dart';

import '../db/database_helper.dart';
import '../models/essay.dart';
import 'ai_service.dart';
import 'track_store.dart';
import 'web_article.dart';

/// 作文类型。和考试无关，是文章体裁。
class EssayTopic {
  final String id;
  final String label;
  const EssayTopic(this.id, this.label);
}

class EssayStore {
  EssayStore._();

  static const String keyTopic = 'essay_topic';
  static const String keyWords = 'essay_words';
  static const String keyLevel = 'essay_level';
  static const String keyRequirement = 'essay_requirement';
  static const String keyFontSize = 'essay_font_size';

  /// 篇幅可选值（词）
  static const List<int> wordOptions = <int>[120, 180, 250, 350];

  /// 难度档位
  static const List<String> levels = <String>['基础', '适中', '进阶'];

  /// 换一篇时换个切入角度，避免每次生成出来都差不多
  static const List<String> _angles = <String>[
    '校园生活',
    '科技与学习',
    '环境与责任',
    '家庭与成长',
    '城市与出行',
    '网络与沟通',
    '健康与习惯',
    '选择与坚持',
  ];

  static const List<EssayTopic> topics = <EssayTopic>[
    EssayTopic('argument', '议论文'),
    EssayTopic('letter', '书信'),
    EssayTopic('chart', '图表'),
    EssayTopic('narrative', '记叙'),
    EssayTopic('exposition', '说明'),
    EssayTopic('web', '网上摘录'),
  ];

  static String labelOf(String id) {
    if (id == 'custom') return 'AI 生成';
    if (id == 'web') return '联网摘录';
    for (final EssayTopic t in topics) {
      if (t.id == id) return t.label;
    }
    return topics.first.label;
  }

  static Future<String> topic() async {
    final String? v =
        await DatabaseHelper.instance.getSetting(keyTopic);
    for (final EssayTopic t in topics) {
      if (t.id == v) return t.id;
    }
    return topics.first.id;
  }

  static Future<void> setTopic(String id) async {
    await DatabaseHelper.instance.setSetting(keyTopic, id);
  }

  /// 读用户定下的篇幅 / 难度 / 内容要求
  static Future<EssayPrefs> prefs() async {
    final DatabaseHelper db = DatabaseHelper.instance;
    final String? w = await db.getSetting(keyWords);
    final String? lv = await db.getSetting(keyLevel);
    final String? req = await db.getSetting(keyRequirement);
    final int words = int.tryParse(w ?? '') ?? 180;
    return EssayPrefs(
      topic: await topic(),
      words: wordOptions.contains(words) ? words : 180,
      level: levels.contains(lv) ? lv! : '适中',
      requirement: (req ?? '').trim(),
    );
  }

  static Future<void> savePrefs(EssayPrefs p) async {
    final DatabaseHelper db = DatabaseHelper.instance;
    await db.setSetting(keyTopic, p.topic);
    await db.setSetting(keyWords, '${p.words}');
    await db.setSetting(keyLevel, p.level);
    await db.setSetting(keyRequirement, p.requirement);
  }

  /// 正文字号，14–24，默认 17
  static final ValueNotifier<double> fontNotifier =
      ValueNotifier<double>(17);

  static Future<double> fontSize() async {
    final String? v =
        await DatabaseHelper.instance.getSetting(keyFontSize);
    final double d = (double.tryParse(v ?? '') ?? 17).clamp(14.0, 24.0);
    fontNotifier.value = d;
    return d;
  }

  static Future<void> setFontSize(double size) async {
    final double v = size.clamp(14.0, 24.0);
    fontNotifier.value = v;
    await DatabaseHelper.instance
        .setSetting(keyFontSize, v.toStringAsFixed(1));
  }

  static String today() {
    final DateTime d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  /// 今天那篇。没有就生成一篇并落库；换一篇就是再生成一篇，旧文保留。
  static Future<Essay> todayEssay({
    bool forceNew = false,
    EssayPrefs? options,
  }) async {
    final String track = TrackStore.current.value;
    final String date = today();
    if (!forceNew) {
      final Essay? saved =
          await DatabaseHelper.instance.getEssayForDay(track: track, date: date);
      if (saved != null) return saved;
    }

    final EssayPrefs p = options ?? await prefs();
    final AiConfig cfg = await AiService.loadConfig();
    final String exam = TrackStore.labelOf(track);
    final int para = p.words <= 150 ? 2 : (p.words <= 250 ? 3 : 4);
    final String angle = p.requirement.isEmpty
        ? _angles[DateTime.now().millisecondsSinceEpoch ~/ 1000 % _angles.length]
        : '';

    final String raw = await AiService.chat(
      cfg,
      <ChatMessage>[
        ChatMessage(
          role: 'user',
          content: '写一篇英语作文，用于精读学习。\n'
              '考试水平：$exam\n'
              '体裁：${labelOf(p.topic)}\n'
              '篇幅：约 ${p.words} 词，分 $para 段。\n'
              '难度：${p.level}\n'
              '${p.requirement.isEmpty ? '' : '内容与主题要求：${p.requirement}\n'}'
              '${angle.isEmpty ? '' : '这次从「$angle」这个角度写，别和常见范文重复。\n'}'
              '要求：用词地道，句式有变化，别用太生僻的词。\n'
              '输出格式：第一行写 TITLE: 英文标题，空一行后写正文。'
              '只输出作文，不要解释、不要中文翻译。',
        ),
      ],
      systemPrompt: '你是一名英语写作老师，出的范文难度贴合中国学生的升学考试。'
          '每次都要写新的题目和内容，不要重复用烂大街的范文。',
    );

    final String title = _pickTitle(raw);
    final String body = _stripTitle(raw);

    final DateTime now = DateTime.now();
    final Essay essay = Essay(
      id: newUuid(),
      date: date,
      topic: p.topic,
      title: title,
      text: body,
      track: track,
      createdAt: now.millisecondsSinceEpoch,
    );
    await DatabaseHelper.instance.saveEssay(essay);
    return essay;
  }

  /// 一句话描述，直接让 AI 按描述写。例如：
  /// 「给我一篇关于人与自然的议论文，难度大概相当于高一水平」
  static Future<Essay> fromPrompt(String prompt) async {
    final AiConfig cfg = await AiService.loadConfig();
    final String track = TrackStore.current.value;
    final String exam = TrackStore.labelOf(track);

    // 最近几篇的标题给模型看一眼，明确要求别换汤不换药
    final List<Essay> recent =
        await DatabaseHelper.instance.getRecentEssays(track: track, limit: 8);
    final String avoid = recent
        .map((Essay e) => '- ${e.title}')
        .where((String s) => s.trim().length > 2)
        .join('\n');

    String build(String extra) => '按下面的要求写一篇英语精读文章：\n$prompt\n\n'
        '要求没写清楚的地方，按这些默认值补：约 400 词、3-4 段、'
        '议论文或说明文、难度相当于中国高中/CET4。\n'
        '用词地道，句式有变化，别用太生僻的词。\n'
        '${avoid.isEmpty ? '' : '不要和最近这些文章重复（标题和主题都要换）：\n$avoid\n'}'
        '如果题目没指定，换一个新的切入角度，不要套常见范文。\n'
        '$extra'
        '输出格式：第一行写 TITLE: 英文标题，空一行后写正文。'
        '只输出作文，不要解释、不要中文翻译。';

    String raw = await AiService.chat(
      cfg,
      <ChatMessage>[ChatMessage(role: 'user', content: build(''))],
      systemPrompt: '你是一名英语写作老师，正在为 $exam 水平的学习者选读文章。'
          '每次都要写新的标题和内容。',
    );

    final Set<String> used = recent
        .map((Essay e) => e.title.trim().toLowerCase())
        .where((String t) => t.isNotEmpty)
        .toSet();
    String title = _pickTitle(raw);
    if (used.contains(title.toLowerCase())) {
      raw = await AiService.chat(
        cfg,
        <ChatMessage>[
          ChatMessage(
            role: 'user',
            content: build('上一次的标题和已有文章重复了，必须换一个完全不同的标题和内容。\n'),
          ),
        ],
        systemPrompt: '你是一名英语写作老师，正在为 $exam 水平的学习者选读文章。',
      );
      title = _pickTitle(raw);
    }

    return _save(
      topic: 'custom',
      title: title,
      body: _stripTitle(raw),
      track: track,
    );
  }

  /// 从网上摘一篇：让 WebArticleService 抓正文，直接当精读材料
  static Future<Essay> fromWeb(String query) async {
    final String track = TrackStore.current.value;
    final List<Essay> recent =
        await DatabaseHelper.instance.getRecentEssays(track: track, limit: 8);
    final Set<String> avoid = recent
        .map((Essay e) => e.title.trim().toLowerCase())
        .where((String t) => t.isNotEmpty)
        .toSet();

    final WebArticle a =
        await WebArticleService.fetch(query, avoidTitles: avoid);
    return _save(
      topic: 'web',
      title: a.title.isEmpty ? 'From the Web' : a.title,
      body: a.text,
      track: track,
    );
  }

  static Future<Essay> _save({
    required String topic,
    required String title,
    required String body,
    required String track,
  }) async {
    final DateTime now = DateTime.now();
    final Essay essay = Essay(
      id: newUuid(),
      date: today(),
      topic: topic,
      title: title,
      text: body,
      track: track,
      createdAt: now.millisecondsSinceEpoch,
    );
    await DatabaseHelper.instance.saveEssay(essay);
    return essay;
  }

  static String _pickTitle(String raw) {
    for (final String line in raw.split('\n')) {
      final String t = line.trim();
      if (t.isEmpty) continue;
      final String up = t.toUpperCase();
      if (up.startsWith('TITLE:')) {
        final String v = t.substring(6).trim();
        if (v.isNotEmpty) return v;
      }
      // 有的模型直接给 # 标题
      if (t.startsWith('#')) return t.replaceAll('#', '').trim();
      return '';
    }
    return '';
  }

  static String _stripTitle(String raw) {
    final List<String> lines = raw.split('\n');
    final List<String> out = <String>[];
    bool seenFirst = false;
    for (final String line in lines) {
      final String t = line.trim();
      if (!seenFirst) {
        if (t.isEmpty) {
          out.add(line);
          continue;
        }
        seenFirst = true;
        final String up = t.toUpperCase();
        // 只有确实是标题行才丢掉；第一行就是正文时原样保留
        if (up.startsWith('TITLE:') || t.startsWith('#')) continue;
      }
      out.add(line);
    }
    return out.join('\n').trim();
  }
}

/// 用户在「自定义」里定下的一组生成条件
class EssayPrefs {
  final String topic;

  /// 目标词数
  final int words;

  /// 基础 / 适中 / 进阶
  final String level;

  /// 自然语言写的主题要求，可以空
  final String requirement;

  const EssayPrefs({
    required this.topic,
    required this.words,
    required this.level,
    required this.requirement,
  });
}
