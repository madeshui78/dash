// 复习页：单词卡，先看英文想意思，翻面对答案，然后自评对错

import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/word.dart';
import '../services/track_store.dart';
import '../widgets/empty_view.dart';
import '../widgets/word_insight_card.dart';

class ReviewPage extends StatefulWidget {
  /// 外部刷新信号。复习页只在「还没开始答题」或「已经答完」时才响应它，
  /// 答题中途收到信号会忽略，避免打断当前这一轮。
  final ValueNotifier<int>? refreshTick;

  const ReviewPage({super.key, this.refreshTick});

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  List<Word> _queue = <Word>[];
  int _index = 0;
  bool _showAnswer = false;
  bool _loading = true;
  bool _finished = false;

  int _reviewed = 0;
  int _correct = 0;

  /// 本轮计划题数 = 队列的初始长度。
  /// 答错插回队尾会改变 _queue.length，拿它当分母会让进度条和计数跳来跳去，
  /// 所以分母固定用这个值。
  int _initialCount = 0;

  /// 同一个词本次答错重来的次数，防止无限循环
  final Map<int, int> _retried = <int, int>{};

  @override
  void initState() {
    super.initState();
    _load();
    widget.refreshTick?.addListener(_onTick);
  }

  @override
  void dispose() {
    widget.refreshTick?.removeListener(_onTick);
    super.dispose();
  }

  /// 收到刷新信号时：只有还没开始答（_index == 0）或者已经答完才重新拉队列，
  /// 正在答题就当作没听见，不然新词插进来会打乱进度。
  void _onTick() {
    if (_index == 0 || _finished) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _finished = false;
      _index = 0;
      _showAnswer = false;
      _reviewed = 0;
      _correct = 0;
      _retried.clear();
    });
    final List<Word> words = await DatabaseHelper.instance
        .getDueWords(track: TrackStore.current.value);
    if (!mounted) return;
    setState(() {
      _queue = words;
      _initialCount = words.length;
      _loading = false;
    });
  }

  Future<void> _answer(bool remembered) async {
    if (_index >= _queue.length) return;
    final Word word = _queue[_index];
    await DatabaseHelper.instance.recordReview(word, remembered);

    if (!mounted) return;
    setState(() {
      _reviewed++;
      if (remembered) _correct++;

      // 答错就插回队尾，趁热打铁再来一次（最多重来 2 次）
      if (!remembered) {
        final int times = (_retried[word.id!] ?? 0) + 1;
        _retried[word.id!] = times;
        if (times <= 2) _queue.add(word);
      }

      _index++;
      _showAnswer = false;
      if (_index >= _queue.length) _finished = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        await _exit();
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('复习'),
          actions: <Widget>[
            IconButton(
              tooltip: '退出复习',
              icon: const Icon(Icons.close),
              onPressed: _exit,
            ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  /// 退出：答到一半先问一句，答完直接走
  Future<void> _exit() async {
    if (_index > 0 && !_finished) {
      final bool? leave = await showDialog<bool>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          title: const Text('退出复习？'),
          content: const Text('这一轮的进度不会保留。'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('继续'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('退出'),
            ),
          ],
        ),
      );
      if (leave != true) return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_queue.isEmpty) {
      return EmptyView(
        icon: Icons.check_circle_outline,
        title: '今天没有要复习的单词',
        subtitle: '到复习时间会自动出现在这里',
      );
    }
    if (_finished) return _buildFinish();
    return _buildCard();
  }

  Widget _buildCard() {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final Word word = _queue[_index];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: <Widget>[
          LinearProgressIndicator(
            // 分母固定为计划题数；答错重做的部分只把进度条推到 100% 为止
            value: _initialCount == 0
                ? 0
                : (_reviewed / _initialCount).clamp(0.0, 1.0),
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              // 已答可能大于计划数（有答错重做的），这是正常的
              Text('已答 $_reviewed / 计划 $_initialCount',
                  style: TextStyle(fontSize: 12, color: cs.outline)),
              Text('本次答对 $_correct',
                  style: TextStyle(fontSize: 12, color: cs.outline)),
            ],
          ),
          Expanded(
            child: SingleChildScrollView(
              child: WordInsightCard(
                key: ValueKey<int>(word.id ?? _index),
                word: word,
                revealed: _showAnswer,
                frontText: word.en,
                frontHint: '点击卡片看答案',
                onTap: () => setState(() => _showAnswer = !_showAnswer),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _answer(false),
                  icon: const Icon(Icons.close),
                  label: const Text('忘了'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade600,
                    minimumSize: const Size.fromHeight(50),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _answer(true),
                  icon: const Icon(Icons.check),
                  label: const Text('记得'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFinish() {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final double rate = _reviewed == 0 ? 0 : _correct / _reviewed;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.flag_outlined, size: 72, color: cs.primary),
            const SizedBox(height: 20),
            const Text('这一轮复习完成',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500)),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: <Widget>[
                _statBox('复习', '$_reviewed'),
                _statBox('答对', '$_correct'),
                _statBox('正确率', '${(rate * 100).round()}%'),
              ],
            ),
            const SizedBox(height: 32),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('退出'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _load,
                    child: const Text('再来一轮'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statBox(String label, String value) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Column(
      children: <Widget>[
        Text(value,
            style: TextStyle(
                fontSize: 26, fontWeight: FontWeight.w500, color: cs.primary)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 12, color: cs.outline)),
      ],
    );
  }
}
