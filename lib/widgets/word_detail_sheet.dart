// 单词详情：点列表里的任何一个词弹出来。
// 除了看音标释义例句，这里也是三个 AI 能力的入口：
//   AI 造句      —— 按你的背景造几个贴身例句
//   词根词缀拆解 —— 讲清楚这个词是怎么拼出来的
//   长难句分析   —— 贴一个看不懂的句子，拆主谓宾
// 这三个的接口都在 AiService 里，这里只是把它们摆到手边。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/word.dart';
import '../pages/study_session_page.dart';
import '../services/ai_service.dart';
import '../services/tts_service.dart';

Future<void> showWordDetail(BuildContext context, Word word) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext ctx) => _WordDetailSheet(word: word),
  );
}

class _WordDetailSheet extends StatefulWidget {
  const _WordDetailSheet({required this.word});

  final Word word;

  @override
  State<_WordDetailSheet> createState() => _WordDetailSheetState();
}

class _WordDetailSheetState extends State<_WordDetailSheet> {
  /// 当前在跑哪个能力，null 表示没在跑
  String? _busy;

  String? _resultTitle;
  String? _resultBody;
  String? _error;

  Future<void> _run(String kind) async {
    setState(() {
      _busy = kind;
      _resultTitle = null;
      _resultBody = null;
      _error = null;
    });

    try {
      final AiConfig cfg = await AiService.loadConfig();
      final String title;
      String body;

      switch (kind) {
        case 'example':
          final List<String> list = await AiService.makeExamples(
            cfg,
            widget.word.en,
          );
          title = 'AI 造句';
          body = list.isEmpty
              ? '（这次没造出来，换个词或者检查 AI 配置）'
              : list
                    .asMap()
                    .entries
                    .map((MapEntry<int, String> e) {
                      return '${e.key + 1}. ${e.value}';
                    })
                    .join('\n\n');
          break;
        case 'root':
          // 词根拆解复用批量补全那套提示词，只问一个词
          final List<WordEntry> got = await AiService.lookupWords(cfg, <String>[
            widget.word.en,
          ]);
          final WordEntry e = got.isEmpty
              ? WordEntry(
                  en: widget.word.en,
                  phonetic: '',
                  zh: '',
                  example: '',
                  root: '',
                )
              : got.first;
          title = '词根词缀';
          body = <String>[
            if (e.root.isNotEmpty) e.root,
            if (e.phonetic.isNotEmpty) '音标 ${e.phonetic}',
            if (e.zh.isNotEmpty) '释义 ${e.zh}',
            if (e.example.isNotEmpty) '例句 ${e.example}',
          ].join('\n\n');
          if (body.isEmpty) body = '（这次没拆出来，换个词或者检查 AI 配置）';
          break;
        default:
          title = '';
          body = '';
      }

      if (!mounted) return;
      setState(() {
        _busy = null;
        _resultTitle = title;
        _resultBody = body;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = null;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  /// 长按/点这里直接练这一个词：走四步卡片（英→中、中→英、默写中、默写英）。
  /// 不管设置里默认流程是哪种，这个入口固定走卡片四步。
  Future<void> _practice() async {
    final Word w = widget.word;
    final NavigatorState nav = Navigator.of(context);
    nav.pop();
    await nav.push<Object?>(
      MaterialPageRoute<Object?>(
        builder: (BuildContext _) =>
            StudySessionPage(words: <Word>[w], isDaily: false),
      ),
    );
  }

  /// 长难句要一个句子，先弹个输入框要过来
  Future<void> _askSentence() async {
    final TextEditingController c = TextEditingController();
    final String? sentence = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('分析长难句'),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: '把看不懂的英文句子贴进来',
            border: OutlineInputBorder(),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(c.text.trim()),
            child: const Text('分析'),
          ),
        ],
      ),
    );
    if (sentence == null || sentence.isEmpty) return;

    setState(() {
      _busy = 'sentence';
      _resultTitle = null;
      _resultBody = null;
      _error = null;
    });
    try {
      final AiConfig cfg = await AiService.loadConfig();
      final String text = await AiService.analyzeSentence(cfg, sentence);
      if (!mounted) return;
      setState(() {
        _busy = null;
        _resultTitle = '长难句拆解';
        _resultBody = text;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = null;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final Word w = widget.word;

    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      expand: false,
      builder: (BuildContext ctx, ScrollController scroll) {
        return ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: <Widget>[
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 单词 + 发音
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    w.en,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                IconButton.outlined(
                  onPressed: () => TtsService.speak(w.en),
                  icon: const Icon(Icons.volume_up_outlined),
                  tooltip: '读一遍',
                ),
              ],
            ),
            if (w.phonetic != null && w.phonetic!.isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                w.phonetic!,
                style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 14),
            Text(
              w.zh.isEmpty ? '（还没释义）' : w.zh,
              style: const TextStyle(fontSize: 16),
            ),
            if (w.example != null && w.example!.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                w.example!,
                style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
              ),
            ],

            const SizedBox(height: 20),

            // 练习入口：点一下就进四步卡片，不用先回列表找「开始学」
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _practice,
                icon: const Icon(Icons.style_outlined),
                label: const Text('练这个词（卡片四步）'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                ),
              ),
            ),

            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 16),

            // 三个 AI 入口
            const Text('让 AI 帮一下', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                _aiButton('AI 造句', Icons.auto_awesome, 'example'),
                _aiButton('词根词缀', Icons.account_tree_outlined, 'root'),
                _aiButton('长难句', Icons.segment_outlined, 'sentence'),
              ],
            ),

            const SizedBox(height: 20),

            if (_busy != null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Text(_error!, style: TextStyle(fontSize: 13, color: cs.error))
            else if (_resultBody != null) ...<Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      _resultTitle!,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: _resultBody!)),
                    icon: const Icon(Icons.copy_all_outlined, size: 18),
                    tooltip: '复制',
                  ),
                ],
              ),
              const SizedBox(height: 6),
              SelectableText(
                _resultBody!,
                style: const TextStyle(fontSize: 14, height: 1.6),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _aiButton(String label, IconData icon, String kind) {
    final bool loading = _busy == kind;
    return OutlinedButton.icon(
      onPressed: loading
          ? null
          : () {
              if (kind == 'sentence') {
                _askSentence();
              } else {
                _run(kind);
              }
            },
      icon: loading
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 17),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        minimumSize: Size.zero,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }
}
