// 把词表格式化成能直接用的笔记。纯 Dart，不碰数据库，方便单独试。
//
// 备份 JSON 是给机器读的，你打不出来也看不了。这里的三种格式是给人用的：
//   纯文本  —— 对齐的清单，打印贴墙、抄进本子
//   CSV     —— 进 Excel / WPS / Anki，带 BOM 所以中文不乱码
//   Markdown—— 贴进笔记软件或思维导图工具

import '../models/word.dart';

/// 导出成笔记的格式
enum ExportFormat {
  txt('纯文本清单', 'txt'),
  csv('CSV（Excel / Anki）', 'csv'),
  md('Markdown 表格', 'md');

  const ExportFormat(this.label, this.ext);

  final String label;
  final String ext;
}

class ExportFormatter {
  ExportFormatter._();

  /// [words] 调用方给什么就导什么，排序在这里做（按英文升序）
  /// [withStats] 要不要带上答对/答错次数和掌握标记
  static String format(
    List<Word> words, {
    required ExportFormat format,
    bool withStats = false,
  }) {
    final List<Word> list = List<Word>.of(words)
      ..sort(
        (Word a, Word b) => a.en.toLowerCase().compareTo(b.en.toLowerCase()),
      );

    switch (format) {
      case ExportFormat.txt:
        return asTxt(list);
      case ExportFormat.csv:
        return asCsv(list, withStats: withStats);
      case ExportFormat.md:
        return asMarkdown(list, withStats: withStats);
    }
  }

  /// 对齐的纯文本：单词一列、音标一列、释义一列
  static String asTxt(List<Word> list) {
    if (list.isEmpty) return '';
    // 先量最宽的单词，好把后面两列对齐
    int w = 0;
    for (final Word x in list) {
      if (x.en.length > w) w = x.en.length;
    }
    final StringBuffer sb = StringBuffer();
    for (final Word x in list) {
      final String en = x.en.padRight(w + 2);
      final String ph = (x.phonetic ?? '').isEmpty ? '' : '${x.phonetic}  ';
      sb.writeln('$en$ph${x.zh}');
    }
    return sb.toString();
  }

  static String asCsv(List<Word> list, {required bool withStats}) {
    // Excel 认 BOM，不然中文全是乱码——这个坑踩过
    final StringBuffer sb = StringBuffer('\uFEFF');
    sb.writeln(withStats
        ? '单词,音标,释义,例句,答对,答错,已掌握'
        : '单词,音标,释义,例句');
    for (final Word x in list) {
      sb.writeln(
        <String>[
          _csv(x.en),
          _csv(x.phonetic ?? ''),
          _csv(x.zh),
          _csv(x.example ?? ''),
          if (withStats) ...<String>[
            '${x.correct}',
            '${x.wrong}',
            x.mastered ? '是' : '否',
          ],
        ].join(','),
      );
    }
    return sb.toString();
  }

  static String asMarkdown(List<Word> list, {required bool withStats}) {
    final StringBuffer sb = StringBuffer();
    sb.writeln(withStats
        ? '| 单词 | 音标 | 释义 | 例句 | 对 | 错 | 已掌握 |'
        : '| 单词 | 音标 | 释义 | 例句 |');
    sb.writeln(withStats
        ? '| --- | --- | --- | --- | --- | --- | --- |'
        : '| --- | --- | --- | --- |');
    for (final Word x in list) {
      sb.writeln(
        '| ${_md(x.en)} | ${_md(x.phonetic ?? '')} | ${_md(x.zh)} | '
        '${_md(x.example ?? '')}'
        '${withStats ? ' | ${x.correct} | ${x.wrong} | ${x.mastered ? '是' : '否'} |' : ' |'}',
      );
    }
    return sb.toString();
  }

  /// CSV 转义：含逗号或引号就整体加引号，里面的引号写两遍
  static String _csv(String s) {
    final String v = s.replaceAll('\n', ' ').replaceAll('\r', ' ');
    if (v.contains(',') || v.contains('"')) {
      return '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }

  /// Markdown 表格里竖线要转义，不然会把列撑坏
  static String _md(String s) =>
      s.replaceAll('\n', ' ').replaceAll('\r', ' ').replaceAll('|', r'\|');
}
