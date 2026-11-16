// 连续小循环：抄两个，回头回忆前面那个。
//
// 流程（i 从 0 开始）：
//   拼写 words[i] → 闪中文 + 发音 → 回头考 words[i-1] → 拼写 words[i+1] → …
// 跟四步流程的区别：四步是"一批词从头过到尾"，这里是"边写边回头"，
// 而且每一步都带发音——耳朵必须参与，不然还是看着字母抄。
//
// 这一套是复刻你记日语的办法：假名音形绑定、抄两个回忆前面。
// 英语垮就垮在只会看字母，这套正好补上。

import 'dart:async';

import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/word.dart';
import '../services/session_draft.dart';
import '../services/tts_service.dart';
import '../widgets/app_toast.dart';

class LoopSessionPage extends StatefulWidget {
  final List<Word> words;

  /// true = 今日抽词（要写回抽词池，标记这批学完）
  final bool isDaily;

  const LoopSessionPage({
    super.key,
    required this.words,
    this.isDaily = true,
  });

  @override
  State<LoopSessionPage> createState() => _LoopSessionPageState();
}

class _LoopSessionPageState extends State<LoopSessionPage> {
  final TextEditingController _input = TextEditingController();

  /// 当前要拼写的词的下标
  int _i = 0;

  /// true = 正在回头考上一个词；false = 正在拼写当前词
  bool _recalling = false;

  /// 当前这一问答完没有（答完显示答案和"下一个"）
  bool _answered = false;

  /// 这一问答对没有
  bool _lastOk = false;

  /// wordId → 这一轮整体算不算记住了（拼写和回顾都对才算）
  final Map<int, bool> _results = <int, bool>{};

  bool _saving = false;
  bool _done = false;

  /// 回顾阶段也答过之后，才算这个词真正过了一轮
  final Map<int, bool> _spellOk = <int, bool>{};
  final Map<int, bool> _recallOk = <int, bool>{};

  /// 已经写进数据库的词 id。中途退出会把答过的先记账，
  /// 恢复后收尾时必须跳过这些，不然同一个词会被记两次。
  final Set<int> _committed = <int>{};

  /// 这次是不是从上次没学完的草稿恢复过来的
  bool _restored = false;

  @override
  void initState() {
    super.initState();
    _restoreDraft();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  /// 把"做到第几个词、哪些答对了"存下来，中途退出不用从头
  Future<void> _saveDraft() async {
    if (_done || widget.words.isEmpty) return;
    await SessionDraft.save(<String, Object?>{
      'kind': 'loop',
      'ids': SessionDraft.idsOf(widget.words),
      'i': _i,
      'recalling': _recalling ? 1 : 0,
      'answered': _answered ? 1 : 0,
      'lastOk': _lastOk ? 1 : 0,
      'spell': SessionDraft.writeBoolMap(_spellOk),
      'recall': SessionDraft.writeBoolMap(_recallOk),
      'results': SessionDraft.writeBoolMap(_results),
      // 已经写过库的词，恢复后收尾要跳过，避免同一个词记两次
      'committed': _committed.toList(),
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> _restoreDraft() async {
    if (widget.words.isEmpty) return;
    final Map<String, Object?>? d = await SessionDraft.load();
    if (!SessionDraft.sameBatch(d, widget.words)) return;
    if (d!['kind'] != 'loop') return;

    final int i = (d['i'] as num?)?.toInt() ?? 0;
    if (i <= 0) return; // 刚开头没必要恢复

    if (!mounted) return;
    setState(() {
      _i = i.clamp(0, _total);
      _recalling = (d['recalling'] as num?)?.toInt() == 1;
      _lastOk = (d['lastOk'] as num?)?.toInt() == 1;
      _spellOk.addAll(SessionDraft.readBoolMap(d['spell']));
      _recallOk.addAll(SessionDraft.readBoolMap(d['recall']));
      _results.addAll(SessionDraft.readBoolMap(d['results']));
      // 上次退出时已经记账的词，这次收尾必须跳过
      final Object? done = d['committed'];
      if (done is List) {
        for (final Object? v in done) {
          final int? id = v is int ? v : int.tryParse('$v');
          if (id != null) _committed.add(id);
        }
      }
      // 「已作答」不恢复：回来先让输入框是空的，自己再答一遍更踏实
      _answered = false;
      _restored = true;
    });
  }

  int get _total => widget.words.length;

  /// 当前这一问针对的是哪个词
  Word get _word =>
      widget.words[(_recalling ? _i - 1 : _i).clamp(0, _total - 1)];

  /// 发音：拼写的时��念英文；回顾时不念（念了等于把答案念出来了）
  /// ——但回顾可以点喇叭主动听，那是你自己选择要听
  Future<void> _speak() => TtsService.speak(_word.en);

  /// 交答案：把输入框的内容跟单词比对。
  /// 空着就提示一下，不静默吞掉——以前空输入直接 return，
  /// 用户点了没反应，还以为没判。
  void _submit() {
    final String typed = _input.text.trim();
    if (typed.isEmpty) {
      AppToast.show(context, '先写点什么，想不出来就点「想不起来」');
      return;
    }

    final bool ok =
        typed.toLowerCase() == _word.en.trim().toLowerCase();
    final int id = _word.id!;

    if (_recalling) {
      _recallOk[id] = ok;
    } else {
      _spellOk[id] = ok;
      // 拼对就念一遍，让耳朵把音和形对上
      if (ok) TtsService.speak(_word.en);
    }

    setState(() {
      _answered = true;
      _lastOk = ok;
    });
    unawaited(_saveDraft());
  }

  /// 想不起来：直接看答案，这一问答错，但也要记进结果里
  void _giveUp() {
    final int id = _word.id!;
    setState(() {
      _answered = true;
      _lastOk = false;
      if (_recalling) {
        _recallOk[id] = false;
      } else {
        _spellOk[id] = false;
      }
    });
    _speak();
    unawaited(_saveDraft());
  }

  /// 点"下一个"：拼写 → 回顾 → 下一个词，这么循环
  void _advance() {
    if (_recalling) {
      // 回顾答完了，这个词这一轮结束
      final int id = _word.id!;
      _results[id] = (_spellOk[id] ?? false) && (_recallOk[id] ?? false);
      setState(() {
        _recalling = false;
        _i++;
        _answered = false;
        _input.clear();
      });
    } else {
      final int id = _word.id!;
      // 第一个词没有"上一个"可回顾，直接进下一个
      if (_i == 0) {
        _results[id] = _spellOk[id] ?? false;
        setState(() {
          _i++;
          _answered = false;
          _input.clear();
        });
      } else {
        setState(() {
          _recalling = true;
          _answered = false;
          _input.clear();
        });
      }
    }

    // 全部走完就收尾
    if (!_recalling && _i >= _total) {
      _finish();
    }
  }

  /// 中途退出：把这一轮已经答过的词先写进数据库。
  ///
  /// 以前退出只是存草稿、一行都不写库，于是"背不完退出 = 白学"，
  /// 错词本当然是空的。答过的就算数，剩下没答的留给下次。
  Future<int> _commitPartial() async {
    final List<Word> done = <Word>[];
    for (final Word w in widget.words) {
      final int id = w.id!;
      if (_committed.contains(id)) continue;
      // 走完一整轮的（_results 里有）或者至少拼过的，都算答过
      if (_results.containsKey(id) || _spellOk.containsKey(id)) {
        done.add(w);
      }
    }
    if (done.isEmpty) return 0;

    for (final Word w in done) {
      final bool ok = _results[w.id!] ?? (_spellOk[w.id!] ?? false);
      await DatabaseHelper.instance.finishDrawnWord(w, ok);
      _committed.add(w.id!);
    }
    return done.length;
  }

  Future<void> _finish() async {
    // 最后一个词可能只走了拼写没走回顾，补记一下
    for (final Word w in widget.words) {
      _results.putIfAbsent(w.id!, () => _spellOk[w.id!] ?? false);
    }
    setState(() => _saving = true);
    for (final Word w in widget.words) {
      // 中途退出时已经记过的，别再记一遍
      if (_committed.contains(w.id!)) continue;
      await DatabaseHelper.instance
          .finishDrawnWord(w, _results[w.id!] ?? false);
      _committed.add(w.id!);
    }
    // 走完了，草稿作废
    await SessionDraft.clear();
    if (!mounted) return;
    setState(() {
      _saving = false;
      _done = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        if (_done) {
          if (context.mounted) Navigator.of(context).pop(true);
          return;
        }
        // 答过的先记账，剩下的存草稿 —— 退出不等于白学
        final int saved = await _commitPartial();
        await _saveDraft();
        if (!context.mounted) return;
        final bool leave = await showDialog<bool>(
              context: context,
              builder: (BuildContext ctx) => AlertDialog(
                title: const Text('先歇会儿？'),
                content: Text(saved > 0
                    ? '已经答过的 $saved 个词记下了，错的进了错词本。'
                        '剩下的存着，下次点「开始学」接着第 ${_i + 1} 个继续。'
                    : '进度存下来了，下次点「开始学」'
                        '会接着第 ${_i + 1} 个词继续。'),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('继续学'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('退出'),
                  ),
                ],
              ),
            ) ??
            false;
        if (leave && context.mounted) Navigator.of(context).pop(true);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('连续小循环'),
          centerTitle: true,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        body: _done ? _buildDone() : _buildTask(),
      ),
    );
  }

  /// 恢复提示：这是接着上次的，也给一个从头再来的出口
  Widget _restoreBanner() {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: cs.secondaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: <Widget>[
          Icon(Icons.restore, size: 16, color: cs.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '接着上次学，第 ${_i + 1} / $_total 个',
              style: TextStyle(fontSize: 13, color: cs.onSecondaryContainer),
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _restored = false;
                _i = 0;
                _recalling = false;
                _answered = false;
                _lastOk = false;
                _spellOk.clear();
                _recallOk.clear();
                _results.clear();
                _input.clear();
              });
              unawaited(SessionDraft.clear());
            },
            child: const Text('从头开始'),
          ),
        ],
      ),
    );
  }

  Widget _buildTask() {
    final ColorScheme cs = Theme.of(context).colorScheme;
    if (widget.words.isEmpty) {
      return const Center(child: Text('这批没有词'));
    }

    final Word w = _word;
    final bool isRecall = _recalling;

    return Column(
      children: <Widget>[
        if (_restored) _restoreBanner(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    '${_i + 1} / $_total',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                  const Spacer(),
                  Text(
                    isRecall ? '回头回忆' : '拼写',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: _total == 0 ? 0 : (_i + (isRecall ? 0.5 : 0)) / _total,
              ),
              const SizedBox(height: 32),

              // 题干
              if (!isRecall) ...<Widget>[
                Text(
                  w.zh.isEmpty ? '（这个词还没释义）' : w.zh,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (w.phonetic != null && w.phonetic!.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 10),
                  Center(
                    child: Text(
                      w.phonetic!,
                      style: TextStyle(
                        fontSize: 16,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Center(
                  child: IconButton.outlined(
                    onPressed: _speak,
                    icon: const Icon(Icons.volume_up_outlined),
                    tooltip: '听发音',
                  ),
                ),
              ] else ...<Widget>[
                const Text(
                  '上一个词怎么拼？',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                Text(
                  '提示：${w.zh.isEmpty ? '（缺释义）' : w.zh}',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
              ],

              const SizedBox(height: 28),

              if (!_answered) ...<Widget>[
                TextField(
                  controller: _input,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                    hintText: '在这里写英文',
                    border: OutlineInputBorder(),
                  ),
                ),
              ] else ...<Widget>[
                // 答完：给对错、正确答案、发音
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(
                      _lastOk ? Icons.check : Icons.close,
                      size: 20,
                      color: _lastOk ? cs.onSurface : cs.error,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _lastOk ? '对了' : '不对',
                      style: const TextStyle(fontSize: 15),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        w.en,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.outlined(
                      onPressed: _speak,
                      icon: const Icon(Icons.volume_up_outlined, size: 20),
                      tooltip: '读一遍',
                    ),
                  ],
                ),
                if (w.phonetic != null && w.phonetic!.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      w.phonetic!,
                      style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
                if (!isRecall) ...<Widget>[
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      w.zh.isEmpty ? '' : w.zh,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
        _buildBottomBar(),
      ],
    );
  }

  Widget _buildBottomBar() {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          top: BorderSide(color: cs.outlineVariant),
        ),
      ),
      child: SafeArea(
        top: false,
        child: _answered
            ? FilledButton(
                onPressed: _saving ? null : _advance,
                style:
                    FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                child: const Text('下一个'),
              )
            : Row(
                children: <Widget>[
                  // 以前这儿只有一个"想不起来，看答案"，写完单词没有任何
                  // 提交按钮——只能靠软键盘的完成键触发。输入法不给
                  // onSubmitted 的话，你写的东西根本没被拿去比对过。
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: _saving ? null : _submit,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: const Text('对答案'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : _giveUp,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: const Text('想不起来'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildDone() {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final int ok = _results.values.where((bool v) => v).length;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text('这一轮走完了', style: TextStyle(fontSize: 20)),
            const SizedBox(height: 12),
            Text(
              '$_total 个词里记住了 $ok 个',
              style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style:
                  FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              child: const Text('好'),
            ),
          ],
        ),
      ),
    );
  }
}
