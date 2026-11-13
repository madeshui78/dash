// 探针：用一批真实形态的词试快刷出题，检查干扰项是不是"太容易"。
// 纯 Dart，不涉及 sqflite / dart:ui。

import 'package:english_agent/models/word.dart';
import 'package:english_agent/services/quiz_service.dart';

void main() {
  // 手工造一批词，首字母/长度分布刻意做得像真实词表
  const List<String> raw = <String>[
    'abandon', 'aboard', 'abroad', 'absorb', 'abstract',
    'accept', 'access', 'accuse', 'achieve', 'acquire',
    'address', 'adjust', 'admire', 'admit', 'adopt',
    'advance', 'affect', 'afford', 'afraid', 'agency',
    'believe', 'benefit', 'brilliant', 'budget', 'burden',
    'capable', 'career', 'challenge', 'climate', 'combine',
    'decision', 'definite', 'deliver', 'demand', 'describe',
  ];
  final List<Word> pool = raw
      .asMap()
      .entries
      .map(
        (MapEntry<int, String> e) => Word(
          id: e.key + 1,
          en: e.value,
          zh: '释义${e.key}',
          track: 'upgrade',
        ),
      )
      .toList();

  final List<QuizQuestion> qs = buildQuiz(pool, count: 20, rng: null);

  final int n = qs.length;
  int four = 0;
  int dupOpt = 0;
  int selfInOpt = 0;
  int listen = 0;
  int enToZh = 0;
  int zhToEn = 0;

  for (final QuizQuestion q in qs) {
    if (q.options.length == 4) four++;
    if (q.options.toSet().length != q.options.length) dupOpt++;
    final String correct = q.kind == QuizKind.enToZh
        ? q.word.zh.trim()
        : q.word.en.trim();
    if (q.options[q.answerIndex] != correct) selfInOpt++;
    switch (q.kind) {
      case QuizKind.listen:
        listen++;
        break;
      case QuizKind.enToZh:
        enToZh++;
        break;
      case QuizKind.zhToEn:
        zhToEn++;
        break;
    }
  }

  print('出题数：$n');
  print('四选一：$four / $n');
  print('选项有重复：$dupOpt');
  print('答案下标错位：$selfInOpt');
  print('题型分布：英选中 $enToZh，中选英 $zhToEn，听音 $listen');
  print('');

  // 抽查干扰项质量：中选英的题，干扰项跟正确词的首字母/长度对比
  int sameInitial = 0;
  int totalDistractors = 0;
  for (final QuizQuestion q in qs) {
    if (q.kind == QuizKind.zhToEn) continue;
    final String correct = q.word.en.trim();
    for (int i = 0; i < q.options.length; i++) {
      if (i == q.answerIndex) continue;
      totalDistractors++;
      if (q.options[i].isNotEmpty &&
          q.options[i][0].toLowerCase() == correct[0].toLowerCase()) {
        sameInitial++;
      }
    }
  }
  print('中选英的干扰项里，首字母相同的：$sameInitial / $totalDistractors'
      '（越高越像，越有训练价值）');
  print('');

  print('前 5 题样例：');
  for (final QuizQuestion q in qs.take(5)) {
    print('  [${quizKindLabel(q.kind)}] 题干「${q.prompt.isEmpty ? '(听音)' : q.prompt}」');
    for (int i = 0; i < q.options.length; i++) {
      print('    ${q.isRight(i) ? '✓' : ' '} ${q.options[i]}');
    }
  }

  // 边界：空池、只有一个词、count 大于池子
  print('');
  print('边界：空池 -> ${buildQuiz(<Word>[], count: 10).length}');
  print('边界：1 个词 -> ${buildQuiz(pool.sublist(0, 1), count: 10).length}');
  print('边界：count 超池子 -> ${buildQuiz(pool, count: 999).length}');
}
