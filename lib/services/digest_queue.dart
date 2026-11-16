// 错词提交：错词本点按钮 → 把今日错词整理好 → 主界面切到问答 → 后台发给 AI。
// 不生成用户气泡，AI 直接输出结构化复盘。

import 'package:flutter/foundation.dart';

import '../db/database_helper.dart';
import '../models/essay.dart';
import '../models/word.dart';

class DigestTask {
  final String payload;
  final List<String> words;
  final int count;

  const DigestTask({
    required this.payload,
    required this.words,
    required this.count,
  });
}

class DigestQueue {
  DigestQueue._();

  /// 非空表示有一次待处理的提交，主界面看到就切到问答页
  static final ValueNotifier<DigestTask?> task = ValueNotifier<DigestTask?>(
    null,
  );

  static void submit(DigestTask t) => task.value = t;

  static DigestTask? take() {
    final DigestTask? t = task.value;
    task.value = null;
    return t;
  }

  static const Set<String> _stop = <String>{
    'a', 'an', 'the', 'that', 'this', 'these', 'those', 'and', 'or', 'but',
    'is', 'are', 'was', 'were', 'be', 'been', 'being', 'do', 'does', 'did',
    'on', 'in', 'at', 'to', 'of', 'for', 'with', 'when', 'while', 'as',
    'it', 'we', 'they', 'he', 'she', 'i', 'you', 'my', 'our', 'their',
    'his', 'her', 'not', 'so', 'if', 'than', 'then',
  };

  /// 标记短语常常带着 that / and / on 这类虚词，去掉首尾，
  /// 否则复盘里会出现「discussions and」这种没有意义的条目。
  static String cleanPhrase(String raw) {
    final List<String> parts = raw
        .trim()
        .split(RegExp(r'\s+'))
        .where((String s) => s.isNotEmpty)
        .toList();
    while (parts.length > 1 && _stop.contains(parts.first.toLowerCase())) {
      parts.removeAt(0);
    }
    while (parts.length > 1 && _stop.contains(parts.last.toLowerCase())) {
      parts.removeLast();
    }
    return parts.join(' ');
  }

  /// 收集「今日」的错词：今天标的作文词 + 今天复习错的词
  static Future<DigestTask?> buildToday(String track) async {
    final DatabaseHelper db = DatabaseHelper.instance;
    final DateTime now = DateTime.now();
    final int start = DateTime(now.year, now.month, now.day)
        .millisecondsSinceEpoch;

    final List<EssayMarkHit> marks = await db.getEssayMarkHits(track: track);
    final List<Word> words = await db.getWrongWords(track: track);

    final List<String> lines = <String>[];
    final List<String> all = <String>[];
    final Set<String> seen = <String>{};

    for (final EssayMarkHit h in marks) {
      if (h.mark.createdAt < start) continue;
      final String w = cleanPhrase(h.mark.word);
      if (w.isEmpty || !seen.add(w.toLowerCase())) continue;
      all.add(w);
      final String sent = h.mark.sentence.trim();
      lines.add(sent.isEmpty ? '· $w' : '· $w —— 原句：$sent');
      if (all.length >= 12) break;
    }

    final List<String> wordLines = <String>[];
    for (final Word w in words) {
      final int t = w.lastReview?.millisecondsSinceEpoch ?? 0;
      if (t < start) continue;
      if (!seen.add(w.en.toLowerCase())) continue;
      all.add(w.en);
      wordLines.add(
        '· ${w.en}  ${w.zh}${w.wrong > 0 ? '（错 ${w.wrong} 次）' : ''}',
      );
      if (all.length >= 30) break;
    }

    if (all.isEmpty) return null;
    final StringBuffer sb = StringBuffer();
    if (lines.isNotEmpty) {
      sb.writeln('【作文里标记的】');
      sb.writeln(lines.join('\n'));
      sb.writeln();
    }
    if (wordLines.isNotEmpty) {
      sb.writeln('【做题错的】');
      sb.writeln(wordLines.join('\n'));
    }

    return DigestTask(
      payload: sb.toString().trim(),
      words: all,
      count: all.length,
    );
  }
}
