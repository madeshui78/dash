// 探针：拿真实作文文本试分词和词形还原。
// 纯 Dart，不涉及 sqflite / dart:ui，可以直接 flutter run 这个文件。

import 'dart:convert';
import 'dart:io';

import 'package:english_agent/services/essay_service.dart';

const String sample = '''
Learning a new language is never easy, but it is worth the effort.
When I started studying English, I could not even remember simple words.
My teacher told me that reviewing regularly matters more than studying for hours.
So I began to review the words every morning, and slowly they stuck.

There were times when I wanted to give up. The children in my class seemed
to learn faster than me. But I kept going, and now I can read short stories
without looking up every unknown word. That feeling is better than any grade.
''';

void main() {
  final List<EssayToken> tokens = tokenizeEssay(sample);
  final int words = tokens.where((EssayToken t) => t.isWord).length;
  final String rebuilt =
      tokens.map((EssayToken t) => t.text).join();
  stdout.writeln('token 数：${tokens.length}，其中单词：$words');
  stdout.writeln('还原后与原文一致：${rebuilt == sample}');
  stdout.writeln('');

  // 词形还原抽查：这些形态必须能还原到词库里可能存在的原形
  const Map<String, String> expect = <String, String>{
    'learning': 'learn',
    'studying': 'study',
    'words': 'word',
    'hours': 'hour',
    'children': 'child',
    'stories': 'story',
    'classes': 'class',
    'studies': 'study',
    'went': 'go',
    'bigger': 'big',
    'happily': 'happy',
    'stopped': 'stop',
    'making': 'make',
    "don't": 'do',
    'well-known': 'well-known',
  };
  int pass = 0;
  for (final MapEntry<String, String> e in expect.entries) {
    final List<String> c = lemmaCandidates(e.key);
    final bool ok = c.contains(e.value);
    if (ok) {
      pass++;
    } else {
      stdout.writeln('  ✗ ${e.key} -> 期望 ${e.value}，实际候选 $c');
    }
  }
  stdout.writeln('词形还原：${expect.length} 个里对了 $pass 个');
  stdout.writeln('');

  stdout.writeln('几个候选链：');
  for (final String w in <String>[
    'studies',
    'running',
    'bigger',
    'carried',
    "children's",
  ]) {
    stdout.writeln('  $w -> ${lemmaCandidates(w)}');
  }

  // 顺带看看去重后要查多少次词典
  final Set<String> lookups = <String>{};
  for (final EssayToken t in tokens) {
    if (t.word != null) lookups.addAll(lemmaCandidates(t.word!));
  }
  stdout.writeln('');
  stdout.writeln('需要查词典的形态数：${lookups.length}（原始词数 $words）');
  stdout.writeln(jsonEncode(lookups.toList()..sort()));
}
