// 学习流程页：今天抽到的这批词，走四步
//   第 1 步  看英文想中文，翻面对答案（浏览）
//   第 2 步  看中文想英文，翻面对答案（浏览）
//   第 3 步  给英文写中文 → 自己对答案，自己点对了/错了
//   第 4 步  给中文写英文 → 机器判（忽略大小写），拼错当场给正确拼写
// 走完：记住了的进已掌握，忘了的进错词本。
//
// 默写那两步支持两种形式（设置里切）：list 一屏列完、card 逐个来。

import 'dart:async';

import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/word.dart';
import '../services/session_draft.dart';
import '../services/study_settings.dart';
import '../services/tts_service.dart';
import '../widgets/word_insight_card.dart';

class StudySessionPage extends StatefulWidget {
  final List<Word> words;

  /// true = 今日抽词（要写回抽词池，标记这批学完）
  /// false = 复习已掌握的词（只更新对错统计）
  final bool isDaily;

  const StudySessionPage({super.key, required this.words, this.isDaily = true});

  @override
  State<StudySessionPage> createState() => _StudySessionPageState();
}

class _StudySessionPageState extends State<StudySessionPage> {
  /// 0 浏览英→中 / 1 浏览中→英 / 2 默写中 / 3 默写英 / 4 完成
  int _step = 0;

  /// 浏览步骤的当前词下标
  int _browseIndex = 0;
  bool _flipped = false;

  /// 默写：逐个模式下的当前题号
  int _cardIndex = 0;

  /// 默写处于"作答"还是"批改"
  bool _grading = false;

  /// wordId → 用户填的答案
  final Map<int, String> _answers = <int, String>{};

  /// wordId → 这一步判定的对错
  final Map<int, bool> _results = <int, bool>{};

  final Map<int, TextEditingController> _controllers =
      <int, TextEditingController>{};

  String _mode = 'list';
  bool _saving = false;

  /// 这次是不是从上次没学完的草稿恢复过来的（用于顶部提示条）
  bool _restored = false;

  static const List<String> _steps = <String>[
    '看英文想中文',
    '看中文想英文',
    '写中文释义',
    '写英文单词',
  ];

  @override
  void initState() {
    super.initState();
    for (final Word w in widget.words) {
      _controllers[w.id!] = TextEditingController();
    }
    _loadMode();
    _restoreDraft();
    // 进页面先念第一个词，耳朵从一开始就跟着走
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoSpeak());
  }

  Future<void> _loadMode() async {
    final String m = await StudySettings.dictationMode();
    if (!mounted) return;
    setState(() => _mode = m);
  }

  @override
  void dispose() {
    for (final TextEditingController c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  int get _total => widget.words.length;

  Future<void> _nextStep() async {
    if (_step >= 3) {
      await _commit();
      return;
    }
    setState(() {
      _step++;
      _browseIndex = 0;
      _cardIndex = 0;
      _flipped = false;
      _grading = false;
      _answers.clear();
      for (final TextEditingController c in _controllers.values) {
        c.clear();
      }
    });
    await _saveDraft();
    _autoSpeak();
  }

  /// 第 3 步提交：不自动判，交给用户自己看标准答案
  void _submitZh() {
    for (final Word w in widget.words) {
      _answers[w.id!] = _controllers[w.id!]!.text.trim();
    }
    setState(() => _grading = true);
    unawaited(_saveDraft());
  }

  /// 第 4 步提交：忽略大小写和首尾空格，完全一致算对
  void _submitEn() {
    for (final Word w in widget.words) {
      final String input = _controllers[w.id!]!.text.trim().toLowerCase();
      _answers[w.id!] = _controllers[w.id!]!.text.trim();
      _results[w.id!] = input == w.en.trim().toLowerCase();
    }
    setState(() => _grading = true);
    unawaited(_saveDraft());
  }

  /// 全部走完，把结果写回数据库
  Future<void> _commit() async {
    setState(() => _saving = true);
    for (final Word w in widget.words) {
      final bool ok = _results[w.id!] ?? false;
      await DatabaseHelper.instance.finishDrawnWord(w, ok);
    }
    // 这批词学完了，草稿作废
    await SessionDraft.clear();
    if (!mounted) return;
    setState(() {
      _saving = false;
      _step = 4;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        final bool leave = await _confirmLeave() ?? false;
        if (leave && context.mounted) Navigator.of(context).pop(true);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _step >= 4 ? '学完了' : '第 ${_step + 1} 步 · ${_steps[_step]}',
          ),
          centerTitle: true,
          elevation: 0,
          scrolledUnderElevation: 0,
          actions: <Widget>[
            IconButton(
              tooltip: '结束',
              icon: const Icon(Icons.close),
              onPressed: () async {
                final bool leave = await _confirmLeave() ?? false;
                if (leave && context.mounted) Navigator.of(context).pop(true);
              },
            ),
          ],
        ),
        body: Column(
          children: <Widget>[
            _progressBar(),
            if (_step < 4) _stepDots(),
            if (_restored && _step < 4) _restoreBanner(),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                // 只有浏览词卡的两步支持左右滑，答题步骤不乱跳
                onHorizontalDragEnd: (DragEndDetails d) {
                  if (_step > 1) return;
                  final double v = d.primaryVelocity ?? 0;
                  if (v < -220) {
                    _next();
                  } else if (v > 220) {
                    _prev();
                  }
                },
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 320),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (Widget child, Animation<double> anim) {
                    final Animation<Offset> slide = Tween<Offset>(
                      begin: const Offset(0.06, 0),
                      end: Offset.zero,
                    ).animate(anim);
                    return FadeTransition(
                      opacity: anim,
                      child: SlideTransition(position: slide, child: child),
                    );
                  },
                  child: KeyedSubtree(
                    key: ValueKey<String>('$_step-$_browseIndex-$_cardIndex'),
                    child: _buildBody(),
                  ),
                ),
              ),
            ),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Future<bool?> _confirmLeave() async {
    if (_step >= 4) return true;
    // 退出前把进度落盘，下次进来接着学，不用从第一个词重来
    await _saveDraft();
    if (!mounted) return false;
    return showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('先歇会儿？'),
        content: const Text(
          '进度已经存下来了，下次点「开始学」'
          '会回到这一步接着来。',
        ),
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
    );
  }

  /// 把当前进度写进草稿。切换步骤、提交答案、以及退出时都会调。
  Future<void> _saveDraft() async {
    if (_step >= 4 || widget.words.isEmpty) return;
    await SessionDraft.save(<String, Object?>{
      'kind': 'steps',
      'ids': SessionDraft.idsOf(widget.words),
      'step': _step,
      'browse': _browseIndex,
      'card': _cardIndex,
      'grading': _grading ? 1 : 0,
      // 输入框里没提交的内容也存下来，回来时原样回填
      'drafts': SessionDraft.writeTextMap(
        widget.words.asMap().map(
          (int i, Word w) =>
              MapEntry<int, String>(w.id!, _controllers[w.id!]?.text ?? ''),
        ),
      ),
      'answers': SessionDraft.writeTextMap(_answers),
      'results': SessionDraft.writeBoolMap(_results),
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// 进来时先看有没有这批词的草稿，有就恢复到上次那一步
  Future<void> _restoreDraft() async {
    if (widget.words.isEmpty) return;
    final Map<String, Object?>? d = await SessionDraft.load();
    if (!SessionDraft.sameBatch(d, widget.words)) return;
    if (d!['kind'] != 'steps') return;

    final int step = (d['step'] as num?)?.toInt() ?? 0;
    if (step >= 4) return; // 已经走完了的草稿没意义

    final Map<int, String> drafts = SessionDraft.readTextMap(d['drafts']);
    for (final Word w in widget.words) {
      final String? t = drafts[w.id!];
      if (t != null && t.isNotEmpty) _controllers[w.id!]?.text = t;
    }

    if (!mounted) return;
    setState(() {
      _step = step;
      _browseIndex = (d['browse'] as num?)?.toInt() ?? 0;
      _cardIndex = (d['card'] as num?)?.toInt() ?? 0;
      _grading = (d['grading'] as num?)?.toInt() == 1;
      _answers.addAll(SessionDraft.readTextMap(d['answers']));
      _results.addAll(SessionDraft.readBoolMap(d['results']));
      _restored = true;
    });
  }

  /// 恢复提示：告诉用户这是接着上次的，并且给一个重来的出口
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
              '接着上次学，现在第 ${_step + 1} 步',
              style: TextStyle(fontSize: 13, color: cs.onSecondaryContainer),
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _restored = false;
                _step = 0;
                _browseIndex = 0;
                _cardIndex = 0;
                _flipped = false;
                _grading = false;
                _answers.clear();
                _results.clear();
                for (final TextEditingController c in _controllers.values) {
                  c.clear();
                }
              });
              unawaited(SessionDraft.clear());
            },
            child: const Text('从头开始'),
          ),
        ],
      ),
    );
  }

  Widget _progressBar() {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return LinearProgressIndicator(
      value: _step >= 4 ? 1 : (_step + 1) / 4,
      backgroundColor: cs.surfaceContainerHighest,
      minHeight: 4,
    );
  }

  /// 四个步骤：圆点 + 连接线，文字居中挂在圆点下面
  Widget _stepDots() {
    final ColorScheme cs = Theme.of(context).colorScheme;
    const List<String> labels = <String>['看词', '回想', '写中文', '写英文'];

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (int i = 0; i < 4; i++) ...<Widget>[
            if (i > 0)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    height: 2,
                    color: i <= _step ? cs.primary : cs.outlineVariant,
                  ),
                ),
              ),
            SizedBox(
              width: 44,
              child: Column(
                children: <Widget>[
                  Container(
                    width: 18,
                    height: 18,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == _step
                          ? cs.primary
                          : (i < _step
                                ? cs.primaryContainer
                                : cs.surfaceContainerHighest),
                    ),
                    child: i < _step
                        ? Icon(Icons.check, size: 11, color: cs.primary)
                        : Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontSize: 9,
                              color: i == _step
                                  ? cs.onPrimary
                                  : cs.onSurfaceVariant,
                            ),
                          ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    labels[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 9,
                      height: 1.1,
                      color: i == _step ? cs.primary : cs.outline,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_step >= 4) return _buildSummary();
    switch (_step) {
      case 0:
        return _buildBrowse(showEn: true);
      case 1:
        return _buildBrowse(showEn: false);
      case 2:
        return _buildDictation(enToZh: true);
      default:
        return _buildDictation(enToZh: false);
    }
  }

  // ---------------- 第 1/2 步：浏览 ----------------

  Widget _buildBrowse({required bool showEn}) {
    if (widget.words.isEmpty) return const SizedBox.shrink();
    final Word w = widget.words[_browseIndex];
    final ColorScheme cs = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text(
          showEn ? '心里想中文意思，想不起来也别急，点卡片看答案' : '看着中文，把英文单词拼出来，点卡片对答案',
          style: TextStyle(fontSize: 12, color: cs.outline),
        ),
        const SizedBox(height: 14),
        WordInsightCard(
          key: ValueKey<int>(w.id ?? _browseIndex),
          word: w,
          revealed: showEn || _flipped,
          frontText: showEn ? null : (w.zh.isEmpty ? '（缺释义）' : w.zh),
          frontHint: '点一下看英文',
          onTap: showEn
              ? null
              : () {
                  setState(() => _flipped = !_flipped);
                  // 第 2 步翻面出来的是英文，翻出来的同时念一遍
                  if (_flipped) TtsService.speak(w.en);
                },
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            IconButton.outlined(
              onPressed: _browseIndex > 0 ? _prev : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('${_browseIndex + 1} / $_total'),
            ),
            IconButton.outlined(
              onPressed: _browseIndex < _total - 1 ? _next : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ],
    );
  }

  void _prev() {
    setState(() {
      if (_browseIndex > 0) _browseIndex--;
      _flipped = false;
    });
    _autoSpeak();
  }

  void _next() {
    setState(() {
      if (_browseIndex < _total - 1) _browseIndex++;
      _flipped = false;
    });
    _autoSpeak();
  }

  /// 浏览这两步每换一个词 / 进新一步都自动念一遍。
  /// 音形不绑定的话，眼睛认得、耳朵不认得，背多少遍都是抄字母。
  void _autoSpeak() {
    if (_step > 1 || widget.words.isEmpty) return;
    if (_browseIndex < 0 || _browseIndex >= widget.words.length) return;
    // 第 1 步正面就是英文，直接念；第 2 步正面是中文，翻面才念英文
    if (_step == 0) {
      TtsService.speak(widget.words[_browseIndex].en);
    }
  }

  // ---------------- 第 3/4 步：默写 ----------------

  Widget _buildDictation({required bool enToZh}) {
    if (!_grading) {
      final Widget body = _mode == 'card'
          ? _cardAnswer(enToZh: enToZh)
          : _listAnswer(enToZh: enToZh);
      return body;
    }
    return _buildGrading(enToZh: enToZh);
  }

  Widget _listAnswer({required bool enToZh}) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: <Widget>[
        Text(
          enToZh ? '写出中文意思，写完点下面提交' : '写出英文单词，写完点下面提交',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
        const SizedBox(height: 12),
        ...widget.words.map(
          (Word w) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Expanded(
                  flex: 2,
                  child: Text(
                    enToZh ? w.en : (w.zh.isEmpty ? '（缺释义）' : w.zh),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _controllers[w.id],
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      hintText: '在这里写',
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _cardAnswer({required bool enToZh}) {
    if (widget.words.isEmpty) return const SizedBox.shrink();
    final Word w = widget.words[_cardIndex];
    final ColorScheme cs = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: <Widget>[
        Center(
          child: Text(
            '${_cardIndex + 1} / $_total',
            style: TextStyle(fontSize: 12, color: cs.outline),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          enToZh ? w.en : (w.zh.isEmpty ? '（缺释义）' : w.zh),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _controllers[w.id],
          autofocus: true,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: enToZh ? '中文意思' : '英文单词',
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            if (_cardIndex < _total - 1) {
              setState(() => _cardIndex++);
            }
          },
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            IconButton.outlined(
              onPressed: _cardIndex > 0
                  ? () => setState(() => _cardIndex--)
                  : null,
              icon: const Icon(Icons.chevron_left),
            ),
            const SizedBox(width: 20),
            IconButton.outlined(
              onPressed: _cardIndex < _total - 1
                  ? () => setState(() => _cardIndex++)
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ],
    );
  }

  /// 批改：第 3 步自己判，第 4 步机器已经判好（也可以手动改）
  Widget _buildGrading({required bool enToZh}) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: <Widget>[
        Text(
          enToZh ? '对照标准答案，自己判：写对了吗？' : '已经按拼写判好了，有争议的可以手动改',
          style: TextStyle(fontSize: 12, color: cs.outline),
        ),
        const SizedBox(height: 12),
        ...widget.words.map((Word w) {
          final String answer = _answers[w.id!] ?? '';
          final bool? ok = _results[w.id!];
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    enToZh ? w.en : (w.zh.isEmpty ? '（缺释义）' : w.zh),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    answer.isEmpty ? '（没写）' : '你写的：$answer',
                    style: TextStyle(
                      fontSize: 13,
                      color: answer.isEmpty ? cs.error : cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '标准答案：${enToZh ? w.zh : w.en}',
                    style: TextStyle(fontSize: 13, color: cs.primary),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      ChoiceChip(
                        label: const Text('对了'),
                        selected: ok == true,
                        onSelected: (_) =>
                            setState(() => _results[w.id!] = true),
                      ),
                      const SizedBox(width: 10),
                      ChoiceChip(
                        label: const Text('错了'),
                        selected: ok == false,
                        onSelected: (_) =>
                            setState(() => _results[w.id!] = false),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  // ---------------- 完成 ----------------

  Widget _buildSummary() {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final int ok = _results.values.where((bool v) => v).length;
    final int bad = _total - ok;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        const SizedBox(height: 20),
        Icon(Icons.check_circle_outline, size: 56, color: cs.primary),
        const SizedBox(height: 16),
        const Center(child: Text('这批词学完了', style: TextStyle(fontSize: 18))),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: <Widget>[
                _statRow('记住了', ok, Colors.green.shade600),
                const Divider(),
                _statRow('还要巩固', bad, Colors.red.shade600),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '记住了的进了「已掌握」，可以随时再复习；'
          '没记住的进了错词本，之后还会再抽到你。',
          style: TextStyle(fontSize: 12, height: 1.5, color: cs.outline),
        ),
      ],
    );
  }

  Widget _statRow(String label, int value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Text(label),
          const Spacer(),
          Text(
            '$value 个',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- 底部条 ----------------

  Widget _buildBottomBar() {
    final ColorScheme cs = Theme.of(context).colorScheme;
    if (_step >= 4) {
      return Container(
        padding: const EdgeInsets.all(16),
        child: SafeArea(
          top: false,
          child: FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.check),
            label: const Text('回到单词本'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ),
      );
    }

    final String text;
    IconData icon;
    VoidCallback? onPressed;
    if (_step <= 1) {
      text = '下一步：${_steps[_step + 1]}';
      icon = Icons.arrow_forward;
      onPressed = _nextStep;
    } else if (!_grading) {
      text = '提交';
      icon = Icons.check;
      onPressed = _step == 2 ? _submitZh : _submitEn;
    } else {
      text = _step == 3 ? '完成，记录结果' : '下一步：${_steps[_step + 1]}';
      icon = _step == 3 ? Icons.done_all : Icons.arrow_forward;
      onPressed = _nextStep;
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: _saving
            ? FilledButton(
                onPressed: null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : FilledButton.icon(
                onPressed: onPressed,
                icon: Icon(icon),
                label: Text(text, style: const TextStyle(fontSize: 16)),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
      ),
    );
  }
}
