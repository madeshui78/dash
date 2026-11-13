// 单词卡：词 + 音标 + 释义 + 词根词缀 / 词组搭配 / 例句。
//
// 学习页的浏览两步和复习页共用这一张卡；未揭晓时只显示正面，
// 点一下才展开释义和下面的三块内容。
// 配色沿用应用现有的中性底 + 品牌蓝，不照搬参考图的渐变。

import 'package:flutter/material.dart';

import '../models/word.dart';
import '../services/tts_service.dart';
import '../services/word_card_store.dart';
import '../theme/module_palette.dart';
import 'fx.dart';

class WordInsightCard extends StatefulWidget {
  final Word word;

  /// 是否已经揭晓（复习：翻面；学习：直接 true）
  final bool revealed;

  /// 未揭晓时显示的正面文字，默认英文
  final String? frontText;

  /// 未揭晓时的提示
  final String? frontHint;

  final VoidCallback? onTap;

  const WordInsightCard({
    super.key,
    required this.word,
    required this.revealed,
    this.frontText,
    this.frontHint,
    this.onTap,
  });

  @override
  State<WordInsightCard> createState() => _WordInsightCardState();
}

class _WordInsightCardState extends State<WordInsightCard> {
  int _tab = 0;
  WordCardData? _data;
  bool _loading = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (widget.revealed) _load();
  }

  @override
  void didUpdateWidget(covariant WordInsightCard old) {
    super.didUpdateWidget(old);
    if (old.word.id != widget.word.id) {
      _data = null;
      _failed = false;
      _loading = false;
      _tab = 0;
      if (widget.revealed) _load();
    } else if (!old.revealed && widget.revealed) {
      _load();
    }
  }

  Future<void> _load() async {
    if (_loading || _data != null) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    final WordCardData? data = await WordCardStore.load(widget.word);
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
      _failed = data == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ModulePalette p = ModulePalette.of(context);

    return Material(
      color: p.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          child: widget.revealed ? _revealed(p) : _front(p),
        ),
      ),
    );
  }

  Widget _front(ModulePalette p) {
    final String text = widget.frontText ?? widget.word.en;
    return SizedBox(
      width: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const SizedBox(height: 24),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 30,
              height: 1.3,
              fontWeight: FontWeight.w500,
              color: p.ink,
            ),
          ),
          if (widget.frontText == null && widget.word.phonetic != null) ...<Widget>[
            const SizedBox(height: 12),
            _Phonetic(text: widget.word.phonetic!),
          ],
          const SizedBox(height: 28),
          Text(
            widget.frontHint ?? '点一下看答案',
            style: TextStyle(fontSize: 12, color: p.muted),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _revealed(ModulePalette p) {
    final Word w = widget.word;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Text(
                w.en,
                style: TextStyle(
                  fontSize: 28,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  color: p.ink,
                ),
              ),
            ),
            IconButton.filledTonal(
              onPressed: () => TtsService.speak(w.en),
              icon: const Icon(Icons.volume_up_outlined, size: 19),
              tooltip: '读一遍',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        if (w.phonetic != null && w.phonetic!.isNotEmpty) ...<Widget>[
          const SizedBox(height: 6),
          _Phonetic(text: w.phonetic!),
        ],
        const SizedBox(height: 10),
        Text(
          w.zh.isEmpty ? '（这个词还没释义）' : w.zh,
          style: TextStyle(fontSize: 16, height: 1.4, color: p.ink),
        ),
        const SizedBox(height: 14),
        Divider(color: p.line, height: 1),
        const SizedBox(height: 6),
        _tabs(p),
        const SizedBox(height: 6),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 76),
            child: _content(p),
          ),
        ),
      ],
    );
  }

  Widget _tabs(ModulePalette p) {
    const List<String> labels = <String>['词根词缀', '词组搭配', '例句'];
    return Row(
      children: List<Widget>.generate(labels.length, (int i) {
        final bool on = i == _tab;
        return Expanded(
          child: InkWell(
            onTap: () => setState(() => _tab = i),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: <Widget>[
                  Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                      color: on ? p.blue : p.muted,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Container(
                    height: 2,
                    width: 22,
                    decoration: BoxDecoration(
                      color: on ? p.blue : Colors.transparent,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _content(ModulePalette p) {
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Row(
          children: <Widget>[
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text('正在整理…', style: TextStyle(fontSize: 12, color: p.muted)),
          ],
        ),
      );
    }

    final WordCardData? d = _data;
    if (d == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            _failed
                ? 'AI 内容没加载出来，可以先用词库里的例句。'
                : '还没有内容',
            style: TextStyle(fontSize: 12, color: p.muted),
          ),
          const SizedBox(height: 8),
          ...fallbackRows(p),
          if (_failed)
            TextButton(
              onPressed: () {
                setState(() => _loading = false);
                _load();
              },
              child: const Text('重试'),
            ),
        ],
      );
    }

    switch (_tab) {
      case 0:
        return Text(
          d.root.isEmpty ? '这个词没有明显的词根词缀，直接记整体意思。' : d.root,
          style: TextStyle(fontSize: 13.5, height: 1.7, color: p.ink),
        );
      case 1:
        if (d.collocations.isEmpty) {
          return Text('暂无搭配', style: TextStyle(fontSize: 12, color: p.muted));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: d.collocations
              .map(
                (String s) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('· ', style: TextStyle(color: p.blue)),
                      Expanded(
                        child: Text(
                          s,
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.5,
                            color: p.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        );
      default:
        final List<WordExample> list = d.examples.isEmpty
            ? WordCardStore.fallbackExamples(widget.word)
            : d.examples;
        if (list.isEmpty) {
          return Text('暂无例句', style: TextStyle(fontSize: 12, color: p.muted));
        }
        return Column(
          children: list
              .map(
                (WordExample e) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              e.en,
                              style: TextStyle(
                                fontSize: 13.5,
                                height: 1.5,
                                color: p.ink,
                              ),
                            ),
                            if (e.zh.isNotEmpty) ...<Widget>[
                              const SizedBox(height: 2),
                              Text(
                                e.zh,
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.5,
                                  color: p.muted,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      FxIconButton(
                        icon: Icons.volume_up_outlined,
                        fx: TapFx.wave,
                        size: 16,
                        color: p.blue,
                        onPressed: () => TtsService.speak(e.en),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        );
    }
  }

  List<Widget> fallbackRows(ModulePalette p) {
    final List<WordExample> list = WordCardStore.fallbackExamples(widget.word);
    if (list.isEmpty) return const <Widget>[];
    return list
        .map(
          (WordExample e) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              e.en,
              style: TextStyle(fontSize: 13, height: 1.5, color: p.ink),
            ),
          ),
        )
        .toList();
  }
}

class _Phonetic extends StatelessWidget {
  final String text;

  const _Phonetic({required this.text});

  @override
  Widget build(BuildContext context) {
    final ModulePalette p = ModulePalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: p.blue.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 13, color: p.blue, letterSpacing: 0.3),
      ),
    );
  }
}
