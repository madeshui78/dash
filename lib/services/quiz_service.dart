// 快刷自测的出题器。纯 Dart，不碰 Flutter，方便单独跑真实数据试。
//
// 为什么要有快刷：原来的四步流程要"整批浏览完再整批填写"，
// 一轮十几分钟起，课间十分钟根本打不开；而且写完才判分，错了也当场不知道。
// 快刷是一题一词、点了立刻对错、随时能停——碎片时间和自测都靠它。
//
// 干扰项是这套题的关键：随便抓三个来凑数，题目一眼就看穿，练不到东西。
// 给中文选英文时，干扰项取首字母相同或长度相近的词（形近才容易混）；
// 给英文选中文时，取释义长度相近的，至少别让长短一眼分出答案。

import 'dart:math';

import '../models/word.dart';

/// 题型
enum QuizKind {
  /// 给英文，选中文
  enToZh,

  /// 给中文，选英文
  zhToEn,

  /// 听发音，选英文
  listen,
}

String quizKindLabel(QuizKind k) {
  switch (k) {
    case QuizKind.enToZh:
      return '看英文选意思';
    case QuizKind.zhToEn:
      return '看意思选英文';
    case QuizKind.listen:
      return '听音选词';
  }
}

class QuizQuestion {
  final Word word;
  final QuizKind kind;

  /// 题干：英文单词、中文释义，听音题是空串（靠发音）
  final String prompt;

  /// 四个选项，已打乱
  final List<String> options;

  /// 正确选项下标
  final int answerIndex;

  const QuizQuestion({
    required this.word,
    required this.kind,
    required this.prompt,
    required this.options,
    required this.answerIndex,
  });

  bool isRight(int i) => i == answerIndex;
}

/// 出题。
///
/// [pool] 候选词（调用方决定是今日新词、到期复习还是错词）
/// [count] 出几题，超过 pool 大小就出 pool.length 题
/// [kinds] 允许出现哪些题型，默认三种混合
/// [rng] 传固定的 Random 可以让测试可复现
List<QuizQuestion> buildQuiz(
  List<Word> pool, {
  int count = 20,
  List<QuizKind>? kinds,
  Random? rng,
}) {
  final Random r = rng ?? Random();
  // 默认加权：听音只占五分之一。
  // 一是考试大头是阅读（英→中）和词汇语法，二是你在图书馆/自习室，
  // 外放发音不合适——听音题做成点喇叭才响，不该占太多。
  final List<QuizKind> allow =
      kinds ??
      <QuizKind>[
        QuizKind.enToZh,
        QuizKind.zhToEn,
        QuizKind.enToZh,
        QuizKind.zhToEn,
        QuizKind.listen,
      ];
  if (pool.isEmpty || count <= 0) return const <QuizQuestion>[];

  // 只留能出题的词：英文和中文都得有，不然题干是空的
  final List<Word> usable = pool
      .where((Word w) => w.en.trim().isNotEmpty && w.zh.trim().isNotEmpty)
      .toList();
  if (usable.isEmpty) return const <QuizQuestion>[];

  // 按首字母建索引，给"形近干扰项"用
  final Map<String, List<Word>> byInitial = <String, List<Word>>{};
  for (final Word w in usable) {
    final String k = _initial(w.en);
    byInitial.putIfAbsent(k, () => <Word>[]).add(w);
  }
  // 按长度分桶，首字母相同时用它兜底
  final Map<int, List<Word>> byLen = <int, List<Word>>{};
  for (final Word w in usable) {
    byLen.putIfAbsent(w.en.length, () => <Word>[]).add(w);
  }

  // 打乱后取前 count 个当"主角"
  final List<Word> picks = List<Word>.of(usable)..shuffle(r);
  final int n = count < picks.length ? count : picks.length;

  final List<QuizQuestion> out = <QuizQuestion>[];
  for (int i = 0; i < n; i++) {
    final Word w = picks[i];
    final QuizKind kind = allow[r.nextInt(allow.length)];
    final List<Word> distractors = _pickDistractors(
      w,
      usable,
      byInitial,
      byLen,
      3,
      r,
    );

    final List<String> options;
    final String prompt;
    final String correct;

    switch (kind) {
      case QuizKind.enToZh:
        prompt = w.en.trim();
        correct = w.zh.trim();
        options = <String>{
          correct,
          ...distractors.map((Word d) => d.zh.trim()),
        }.toList();
        break;
      case QuizKind.zhToEn:
      case QuizKind.listen:
        prompt = kind == QuizKind.zhToEn ? w.zh.trim() : '';
        correct = w.en.trim();
        options = <String>{
          correct,
          ...distractors.map((Word d) => d.en.trim()),
        }.toList();
        break;
    }

    // 去重后不足 4 个就从全库补，实在补不满就少几个选项
    if (options.length < 4) {
      for (final Word d in usable) {
        if (options.length >= 4) break;
        final String v = (kind == QuizKind.enToZh ? d.zh : d.en).trim();
        if (!options.contains(v)) options.add(v);
      }
    }

    options.shuffle(r);
    // 选项文本可能重复（两个词同一个释义），用内容定位而不是下标
    final int answerIndex = options.indexOf(correct);
    if (answerIndex < 0) continue;

    out.add(
      QuizQuestion(
        word: w,
        kind: kind,
        prompt: prompt,
        options: options,
        answerIndex: answerIndex,
      ),
    );
  }
  return out;
}

/// 挑 3 个干扰项：优先同首字母（最像），其次长度相近，最后随机
List<Word> _pickDistractors(
  Word target,
  List<Word> usable,
  Map<String, List<Word>> byInitial,
  Map<int, List<Word>> byLen,
  int need,
  Random r,
) {
  final List<Word> out = <Word>[];
  final Set<int> used = <int>{target.id ?? -1};

  void take(Word w) {
    if (out.length >= need) return;
    final int k = w.id ?? -1;
    if (used.contains(k)) return;
    used.add(k);
    out.add(w);
  }

  // 同首字母最容易混：abroad / aboard 这种
  final List<Word>? same = byInitial[_initial(target.en)];
  if (same != null) {
    final List<Word> shuffled = List<Word>.of(same)..shuffle(r);
    for (final Word w in shuffled) {
      take(w);
    }
  }

  // 长度相近兜底
  if (out.length < need) {
    for (int d = 1; d <= 3 && out.length < need; d++) {
      for (final int len in <int>[target.en.length - d, target.en.length + d]) {
        final List<Word>? bucket = byLen[len];
        if (bucket == null) continue;
        final List<Word> shuffled = List<Word>.of(bucket)..shuffle(r);
        for (final Word w in shuffled) {
          take(w);
        }
      }
    }
  }

  // 还不够就随机抓
  if (out.length < need && usable.length > need) {
    for (int i = 0; i < 40 && out.length < need; i++) {
      take(usable[r.nextInt(usable.length)]);
    }
  }
  return out;
}

String _initial(String en) {
  final String s = en.trim().toLowerCase();
  return s.isEmpty ? '' : s[0];
}
