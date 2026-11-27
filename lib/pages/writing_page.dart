// 写作练习：自己写一篇，AI 按 15 分制批改并给改写。

import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/writing.dart';
import '../services/track_store.dart';
import '../services/writing_service.dart';
import '../theme/module_palette.dart';
import '../theme/ui.dart';
import '../widgets/app_toast.dart';

class WritingPage extends StatefulWidget {
  const WritingPage({super.key, this.embedded = false});

  /// 作为常驻页签嵌在首页时，不要自己的 AppBar（外面已经有了）
  final bool embedded;

  @override
  State<WritingPage> createState() => _WritingPageState();
}

class _WritingPageState extends State<WritingPage> {
  final TextEditingController _topic = TextEditingController();
  final TextEditingController _body = TextEditingController();
  final ScrollController _bodyScroll = ScrollController();

  WritingFeedback? _feedback;
  bool _busy = false;
  String? _error;
  int? _savedId;
  WritingScale _scale = writingScaleById('cet4');

  @override
  void initState() {
    super.initState();
    _loadScale();
  }

  Future<void> _loadScale() async {
    final String? id = await DatabaseHelper.instance.getSetting(
      'writing_scale',
    );
    if (!mounted) return;
    setState(() => _scale = writingScaleById(id));
  }

  Future<void> _pickScale(WritingScale s) async {
    setState(() => _scale = s);
    await DatabaseHelper.instance.setSetting('writing_scale', s.id);
  }

  @override
  void dispose() {
    _topic.dispose();
    _body.dispose();
    _bodyScroll.dispose();
    super.dispose();
  }

  int get _words {
    final String t = _body.text.trim();
    if (t.isEmpty) return 0;
    return t.split(RegExp(r'\s+')).where((String e) => e.isNotEmpty).length;
  }

  Future<void> _submit() async {
    final String text = _body.text.trim();
    if (_words < 30) {
      AppToast.show(context, '至少写到 30 个词再批改');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _feedback = null;
    });
    try {
      final WritingFeedback fb = await WritingService.correct(
        topic: _topic.text,
        content: text,
        scale: _scale,
      );
      final int id = await DatabaseHelper.instance.addWriting(
        Writing(
          track: TrackStore.current.value,
          topic: _topic.text.trim(),
          content: text,
          score: fb.score,
          feedback: fb.encode(),
          createdAt: DateTime.now(),
        ),
      );
      if (!mounted) return;
      setState(() {
        _feedback = fb;
        _savedId = id;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
        _busy = false;
      });
    }
  }

  /// 评分标准收进小窗，避免一屏都是选项
  void _openScaleSheet() {
    final ModulePalette p = ModulePalette.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                '评分标准',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: p.ink,
                ),
              ),
            ),
            for (final WritingScale s in writingScales)
              ListTile(
                title: Text('${s.label}写作'),
                subtitle: Text(
                  '满分 ${s.maxScore.toStringAsFixed(0)} 分'
                  '${s.note.isEmpty ? '' : ' · ${s.note}'}',
                  style: TextStyle(fontSize: 11, height: 1.5, color: p.muted),
                ),
                trailing: s.id == _scale.id
                    ? Icon(Icons.check, size: 18, color: p.essay)
                    : null,
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickScale(s);
                },
              ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Future<void> _openHistory() async {
    final List<Writing> list = await DatabaseHelper.instance.getWritings(
      track: TrackStore.current.value,
    );
    if (!mounted) return;
    if (list.isEmpty) {
      AppToast.show(context, '还没有写过的作文');
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext ctx) => SafeArea(
        child: ListView.separated(
          itemCount: list.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (BuildContext c, int i) {
            final Writing w = list[i];
            return ListTile(
              title: Text(
                w.topic.isEmpty ? '未命名题目' : w.topic,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${w.createdAt.month}月${w.createdAt.day}日 · ${w.content.split(RegExp(r"\s+")).length} 词',
                style: const TextStyle(fontSize: 11),
              ),
              trailing: Text(
                '${w.score.toStringAsFixed(1)} 分',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                setState(() {
                  _topic.text = w.topic;
                  _body.text = w.content;
                  _feedback = WritingFeedback.tryDecode(w.feedback);
                  _savedId = w.id;
                  _error = null;
                });
              },
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ModulePalette p = ModulePalette.of(context);
    final bool hasResult = _feedback != null;

    return Scaffold(
      backgroundColor: p.canvas,
      appBar: widget.embedded
          ? null
          : AppBar(
              title: const Text('写作练习'),
              actions: <Widget>[
                IconButton(
                  tooltip: '历史',
                  onPressed: _openHistory,
                  icon: const Icon(Icons.history, size: 20),
                ),
              ],
            ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, widget.embedded ? 4 : 12, 16, 28),
        children: <Widget>[
          if (widget.embedded)
            Row(
              children: <Widget>[
                Text(
                  '写作练习',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: p.ink,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _openHistory,
                  icon: const Icon(Icons.history, size: 16),
                  label: const Text('历史', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          // 一张“答题纸”：白底、细边、横线，尽量接近卷面
          Container(
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: p.line),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: p.ink.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      'WRITING',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 2.4,
                        fontWeight: FontWeight.w600,
                        color: p.muted,
                      ),
                    ),
                    const Spacer(),
                    InkWell(
                      onTap: _openScaleSheet,
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              '${_scale.label} · ${_scale.maxScore.toStringAsFixed(0)} 分',
                              style: TextStyle(fontSize: 11, color: p.muted),
                            ),
                            Icon(Icons.expand_more, size: 14, color: p.muted),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                Divider(height: 18, color: p.line),
                TextField(
                  controller: _topic,
                  decoration: InputDecoration(
                    hintText: '题目 / 要求（可留空）',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: p.muted,
                      fontWeight: FontWeight.w400,
                    ),
                    isCollapsed: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.4,
                    fontFamily: 'serif',
                    fontWeight: FontWeight.w600,
                    color: p.ink,
                  ),
                ),
                Divider(height: 16, color: p.line),
                SizedBox(
                  height: 330,
                  child: ListenableBuilder(
                    listenable: _bodyScroll,
                    builder: (BuildContext ctx, Widget? child) {
                      // 文本框自己滚动时，把横线按滚动距离一起平移，
                      // 否则字往上走了，线还钉在原处。
                      final double off = _bodyScroll.hasClients
                          ? _bodyScroll.offset
                          : 0;
                      return Stack(
                        children: <Widget>[
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _RuledPainter(p.line, off),
                            ),
                          ),
                          TextField(
                            controller: _body,
                            scrollController: _bodyScroll,
                            maxLines: null,
                            expands: true,
                            textAlignVertical: TextAlignVertical.top,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              hintText: '在这里写作文，至少 30 个词',
                              hintStyle: TextStyle(
                                fontSize: 13,
                                color: p.muted,
                              ),
                              isCollapsed: true,
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                            ),
                            style: TextStyle(
                              fontSize: 16,
                              height: 30 / 16,
                              fontFamily: 'serif',
                              color: p.ink,
                            ),
                            strutStyle: const StrutStyle(
                              fontSize: 16,
                              height: 30 / 16,
                              forceStrutHeight: true,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: <Widget>[
                    Text(
                      '$_words words',
                      style: TextStyle(
                        fontSize: 11,
                        color: _words >= 30 ? p.green : p.muted,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '最少 30 词',
                      style: TextStyle(fontSize: 11, color: p.muted),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 46,
            child: FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.rate_review_outlined, size: 18),
              label: Text(_busy ? '批改中…' : '提交批改'),
              style: FilledButton.styleFrom(
                backgroundColor: p.ink,
                foregroundColor: p.canvas,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(fontSize: UiText.secondary, color: p.wrong),
            ),
          ],
          if (hasResult) ...<Widget>[
            const SizedBox(height: 22),
            _ResultView(
              feedback: _feedback!,
              maxScore: _scale.maxScore,
              saved: _savedId != null,
              onDelete: _savedId == null
                  ? null
                  : () async {
                      await DatabaseHelper.instance.deleteWriting(_savedId!);
                      if (!mounted) return;
                      setState(() => _savedId = null);
                      AppToast.show(context, '已从历史里删除');
                    },
            ),
          ],
        ],
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  final WritingFeedback feedback;
  final double maxScore;
  final bool saved;
  final VoidCallback? onDelete;

  const _ResultView({
    required this.feedback,
    required this.maxScore,
    required this.saved,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final ModulePalette p = ModulePalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: p.line),
          ),
          child: Row(
            children: <Widget>[
              Text(
                feedback.score.toStringAsFixed(1),
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  color: p.essay,
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  '/ ${maxScore.toStringAsFixed(0)}',
                  style: TextStyle(fontSize: 12, color: p.muted),
                ),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  feedback.level,
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 12, color: p.muted),
                ),
              ),
            ],
          ),
        ),
        if (feedback.good.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          _title('写得好的', p),
          const SizedBox(height: 6),
          for (final String g in feedback.good)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(Icons.check, size: 14, color: p.green),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      g,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: p.ink.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
        if (feedback.issues.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          _title('需要改的地方', p),
          const SizedBox(height: 6),
          for (final WritingIssue issue in feedback.issues)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: p.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    issue.quote,
                    style: TextStyle(fontSize: 13, height: 1.5, color: p.wrong),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '→ ${issue.fix}',
                    style: TextStyle(fontSize: 13, height: 1.5, color: p.green),
                  ),
                  if (issue.why.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      issue.why,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.6,
                        color: p.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
        if (feedback.rewrite.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          _title('改写参考', p),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: p.surfaceAlt,
              borderRadius: BorderRadius.circular(10),
            ),
            child: SelectableText(
              feedback.rewrite,
              style: TextStyle(fontSize: 13, height: 1.75, color: p.ink),
            ),
          ),
        ],
        if (feedback.advice.isNotEmpty) ...<Widget>[
          const SizedBox(height: 14),
          Text(
            feedback.advice,
            style: TextStyle(fontSize: 12, height: 1.6, color: p.muted),
          ),
        ],
        const SizedBox(height: 14),
        Row(
          children: <Widget>[
            Text(
              saved ? '已存入历史' : '未保存',
              style: TextStyle(fontSize: 11, color: p.muted),
            ),
            const Spacer(),
            if (onDelete != null)
              TextButton(onPressed: onDelete, child: const Text('删除这篇')),
          ],
        ),
      ],
    );
  }

  Widget _title(String t, ModulePalette p) => Text(
    t,
    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.ink),
  );
}

/// 答题纸的横线：每隔 30px 一条，和正文的行高对齐
class _RuledPainter extends CustomPainter {
  final Color color;
  final double offset;

  const _RuledPainter(this.color, this.offset);

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..strokeWidth = 0.8;
    // 随正文滚动平移；按 30 取模，避免长文时偏移累积成小数
    double y = 38 - (offset % 30);
    for (; y < size.height; y += 30) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_RuledPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.offset != offset;
}
