// 探针：试导出格式，确认输出是能直接用的文本。
// 纯 Dart，不涉及 sqflite / dart:ui。

import 'package:english_agent/models/word.dart';
import "package:english_agent/services/export_format.dart";

void main() {
  final List<Word> words = <Word>[
    Word(
      id: 1,
      en: 'abandon',
      zh: '放弃，抛弃',
      phonetic: '/əˈbændən/',
      example: 'He abandoned his car.',
      correct: 3,
      wrong: 2,
      track: 'upgrade',
    ),
    Word(
      id: 2,
      en: 'absorb',
      zh: '吸收；理解',
      phonetic: '/əbˈsɔːb/',
      example: 'Plants absorb water.',
      correct: 5,
      wrong: 0,
      mastered: true,
      track: 'upgrade',
    ),
    Word(
      id: 3,
      en: 'a, comma "quoted"',
      zh: '含逗号和引号的释义，用来试转义',
      phonetic: '',
      example: '',
      correct: 0,
      wrong: 1,
      track: 'upgrade',
    ),
  ];

  print('=========== 纯文本（打印 / 抄写）===========');
  print(ExportFormatter.format(words, format: ExportFormat.txt));

  print('=========== CSV（Excel / Anki）===========');
  print(ExportFormatter.format(words, format: ExportFormat.csv, withStats: true));

  print('=========== Markdown（笔记软件）===========');
  print(ExportFormatter.format(words, format: ExportFormat.md, withStats: true));

  print('=========== 边界 ===========');
  print('空列表 txt -> 「${ExportFormatter.format(<Word>[], format: ExportFormat.txt)}」');
  print('空列表 csv 行数 -> ${ExportFormatter.format(<Word>[], format: ExportFormat.csv).trim().split("\n").length}');
}
