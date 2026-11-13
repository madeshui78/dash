// 快刷自测：一题一词，点了立刻对错，随时能停。
//
// 原来只有四步流程：一批词先全浏览一遍、再一次性填几十个空，最后才判分。
// 一轮十几分钟起，课间十分钟根本用不上；错了也要等一轮走完才知道，
// 跟你"学 → 测 → 整理错题 → 复测"的闭环习惯是拧着的。
//
// 这一页解决三件事：
//   1. 碎片时间能刷（一题几秒，随时停）
//   2. 反馈即时（点完立刻对错 + 正确答案 + 释义）
//   3. 独立自测（不绑定"今天这批"，想测什么测什么）
//
// 中途退出会把答过的记账，不用怕白刷。

import 'dart:async';

import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/word.dart';
import '../services/quiz_service.dart';
import '../services/tts_service.dart';
import '../widgets/smooth_route.dart';

class QuickQuizPage extends StatefulWidget {
  /// 要测的词。调用方决定是今日新词、没学完的、到期复习还是错词
  final List<Word> pool;

  /// 标题，比如「今日这批」
  final String title;

  /// 出几题
  final int count;

  const QuickQuizPage({
    super.key,
    required this.pool,
    required this.title,
    this.count = 20,
  });

  @override
  State<QuickQuizPage> createState() => _QuickQuizPageState();
}

class _QuickQuizPageState extends State<QuickQuizPage> {
  List<QuizQuestion> _qs = <QuizQuestion>[];
  int _i = 0;

  /// 这一题选了哪个（null = 还没选）
  int? _picked;

  /// 每题对错，用于最后总结
  final Map<int, bool> _results = <int, bool>{};

  /// 已经写进数据库的题，退出时不重复记
  final Set<int> _saved = <int>{};

  bool _saving = false;

  QuizQuestion? get _q => _i < _qs.length ? _qs[_i] : null;

  @override
  void initState() {
    super.initState();
    _qs = buildQuiz(widget.pool, count: widget.count);
  }

  int get _right => _results.values.where((bool v) => v).length;

  void _pick(int index) {
    if (_picked != null) return; // 一题只判一次
    final QuizQuestion? q = _q;
    if (q == null) return;
    final bool ok = q.isRight(index);
    setState(() {
      _picked = index;
      _results[_i] = ok;
    });
    // 答完念一遍，耳朵跟着走；答错更要念，把音和形对上
    unawaited(TtsService.speak(q.word.en));
  }

  Future<void> _saveOne(int i) async {
    if (_saved.contains(i)) return;
    final QuizQuestion q = _qs[i];
    await DatabaseHelper.instance.recordReview(
      q.word,
      _results[i] ?? false,
      mode: 'quiz',
    );
    _saved.add(i);
  }

  /// 把已答的题写进数据库。中途退出也记账，不算白刷。
  Future<int> _saveAnswered() async {
    int n = 0;
    for (int i = 0; i < _qs.length; i++) {
      if (!_results.containsKey(i)) continue;
      await _saveOne(i);
      n++;
    }
    return n;
  }

  void _next() {
    if (_i + 1 >= _qs.length) {
      _finish();
      return;
    }
    setState(() {
      _i++;
      _picked = null;
    });
  }

  Future<void> _finish() async {
    setState(() => _saving = true);
    await _saveAnswered();
    if (!mounted) return;
    setState(() {
      _saving = false;
      _i = _qs.length; // 进总结页
    });
  }

  Future<void> _leave() async {
    if (_i >= _qs.length) {
      if (mounted) Navigator.of(context).pop(true);
      return;
    }
    final int answered = _results.length;
    if (answered > 0) {
      await _saveAnswered();
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        await _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          centerTitle: true,
          actions: <Widget>[
            IconButton(
              tooltip: '结束',
              icon: const Icon(Icons.close),
              onPressed: _leave,
            ),
          ],
        ),
        body: _qs.isEmpty
            ? const Center(child: Text('这批没有能出题的词'))
            : _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_i >= _qs.length) return _buildSummary();
    final ColorScheme cs = Theme.of(context).colorScheme;
    final QuizQuestion q = _qs[_i];

    return Column(
      children: <Widget>[
        LinearProgressIndicator(
          value: (_i + (_picked == null ? 0 : 1)) / _qs.length,
          minHeight: 4,
          backgroundColor: cs.surfaceContainerHighest,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    '${_i + 1} / ${_qs.length}',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                  const Spacer(),
                  Text(
                    quizKindLabel(q.kind),
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '对 $_right',
                    style: TextStyle(fontSize: 12, color: cs.outline),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildPrompt(q, cs),
              const SizedBox(height: 24),
              ...List<Widget>.generate(q.options.length, (int i) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _OptionButton(
                    text: q.options[i],
                    index: i,
                    state: _picked == null
                        ? _OptState.idle
                        : (q.isRight(i)
                            ? _OptState.right
                            : (i == _picked
                                ? _OptState.wrong
                                : _OptState.dim)),
                    onTap: () => _pick(i),
                  ),
                );
              }),
              if (_picked != null) ...<Widget>[
                const SizedBox(height: 6),
                _buildAnswerCard(q, cs),
              ],
            ],
          ),
        ),
        if (_picked != null) _buildBottomBar(),
      ],
    );
  }

  Widget _buildPrompt(QuizQuestion q, ColorScheme cs) {
    if (q.kind == QuizKind.listen) {
      // 听音题不自动念：你在图书馆/自习室，外放不合适，点一下才响
      return Center(
        child: Column(
          children: <Widget>[
            IconButton.filledTonal(
              onPressed: () => TtsService.speak(q.word.en),
              icon: const Icon(Icons.volume_up, size: 32),
              iconSize: 32,
              style: IconButton.styleFrom(
                minimumSize: const Size(88, 88),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '点一下听发音',
              style: TextStyle(fontSize: 13, color: cs.outline),
            ),
          ],
        ),
      );
    }
    return Center(
      child: Text(
        q.prompt,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: q.kind == QuizKind.zhToEn ? 24 : 32,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  /// 答完给的信息：对错、正确答案、释义、音标
  Widget _buildAnswerCard(QuizQuestion q, ColorScheme cs) {
    final bool ok = _results[_i] ?? false;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ok ? cs.primaryContainer : cs.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                ok ? Icons.check_circle : Icons.cancel,
                size: 18,
                color: ok ? cs.onPrimaryContainer : cs.onErrorContainer,
              ),
              const SizedBox(width: 8),
              Text(
                ok ? '对了' : '不对',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: ok ? cs.onPrimaryContainer : cs.onErrorContainer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  q.word.en,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              IconButton.outlined(
                onPressed: () => TtsService.speak(q.word.en),
                icon: const Icon(Icons.volume_up_outlined, size: 18),
                tooltip: '再听一遍',
              ),
            ],
          ),
          if (q.word.phonetic != null &&
              q.word.phonetic!.isNotEmpty) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              q.word.phonetic!,
              style: TextStyle(fontSize: 13, color: cs.primary),
            ),
          ],
          const SizedBox(height: 4),
          Text(q.word.zh, style: const TextStyle(fontSize: 15)),
          if (q.word.example != null &&
              q.word.example!.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              q.word.example!,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final bool last = _i + 1 >= _qs.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _saving ? null : _next,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: Text(last ? '看结果' : '下一题'),
          ),
        ),
      ),
    );
  }

  Widget _buildSummary() {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final int total = _qs.length;
    final int right = _right;
    final int wrong = total - right;
    final double rate = total == 0 ? 0 : right / total;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              '$total 题对了 $right 题',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              rate >= 0.9
                  ? '这批稳了，可以往下了'
                  : (rate >= 0.6 ? '还有 $wrong 个没记住，明天再来一轮' : '错得有点多，先把错词过一遍'),
              style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.check),
                label: const Text('好了'),
                style:
                    FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              ),
            ),
            if (wrong > 0) ...<Widget>[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    // 错题再来一轮：只拿刚才答错的词重新出题
                    final List<Word> wrongWords = <Word>[];
                    for (int i = 0; i < _qs.length; i++) {
                      if (_results[i] == false) wrongWords.add(_qs[i].word);
                    }
                    Navigator.of(context).pushReplacement(
                      SmoothRoute<Object?>(
                        page: QuickQuizPage(
                          pool: wrongWords,
                          title: '错题重刷',
                          count: wrongWords.length,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.replay),
                  label: Text('只刷这 $wrong 个错的'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum _OptState { idle, right, wrong, dim }

class _OptionButton extends StatelessWidget {
  final String text;
  final int index;
  final _OptState state;
  final VoidCallback onTap;

  const _OptionButton({
    required this.text,
    required this.index,
    required this.state,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final Color bg;
    final Color fg;
    final Color border;
    switch (state) {
      case _OptState.idle:
        bg = cs.surface;
        fg = cs.onSurface;
        border = cs.outlineVariant;
        break;
      case _OptState.right:
        bg = cs.primaryContainer;
        fg = cs.onPrimaryContainer;
        border = cs.primary;
        break;
      case _OptState.wrong:
        bg = cs.errorContainer;
        fg = cs.onErrorContainer;
        border = cs.error;
        break;
      case _OptState.dim:
        bg = cs.surfaceContainerHighest.withValues(alpha: 0.4);
        fg = cs.onSurfaceVariant;
        border = cs.outlineVariant;
        break;
    }
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: border, width: state == _OptState.idle ? 1 : 1.5),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: <Widget>[
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: border),
                ),
                child: Text(
                  'ABCD'[index],
                  style: TextStyle(fontSize: 12, color: fg),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(fontSize: 16, color: fg),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
