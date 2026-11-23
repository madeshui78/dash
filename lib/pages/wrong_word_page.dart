// 错词本：两部分——作文里标红的词、以及做题时答错的词。
//
// 标红的词带着出处：点一下跳回那篇作文的对应段落，
// 而不是只看到一个孤零零的单词。

import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/essay.dart';
import '../models/word.dart';
import '../services/essay_focus.dart';
import '../services/chat_focus.dart';
import '../services/digest_queue.dart';
import '../services/track_store.dart';
import '../theme/module_palette.dart';
import '../widgets/app_toast.dart';
import '../widgets/empty_view.dart';
import '../widgets/export_sheet.dart';
import '../widgets/fx.dart';
import '../widgets/motion_button.dart';
import '../widgets/smooth_route.dart';
import '../widgets/word_detail_sheet.dart';
import 'quick_quiz_page.dart';

class WrongWordPage extends StatefulWidget {
  final ValueNotifier<int>? refreshTick;

  /// 点标记后切到作文页签
  final VoidCallback? onOpenEssay;

  const WrongWordPage({super.key, this.refreshTick, this.onOpenEssay});

  @override
  State<WrongWordPage> createState() => _WrongWordPageState();
}

/// 一屏要显示的东西：作文标记 + 错词
class _Data {
  final List<EssayMarkHit> marks;
  final List<Word> words;

  const _Data(this.marks, this.words);

  bool get isEmpty => marks.isEmpty && words.isEmpty;
}

class _WrongWordPageState extends State<WrongWordPage> {
  late Future<_Data> _future;
  bool _submitting = false;

  /// 0 = 标记词，1 = 错题。默认落在错题，每天要清的是这里
  int _tab = 1;
  final Set<String> _openMarks = <String>{};

  @override
  void initState() {
    super.initState();
    _future = _load();
    widget.refreshTick?.addListener(_reload);
  }

  @override
  void dispose() {
    widget.refreshTick?.removeListener(_reload);
    super.dispose();
  }

  Future<_Data> _load() async {
    final String track = TrackStore.current.value;
    final List<EssayMarkHit> marks = await DatabaseHelper.instance
        .getEssayMarkHits(track: track);
    final List<Word> all = await DatabaseHelper.instance.getWrongWords(
      track: track,
    );
    // 作文带进来的词已经在上面单独列了，这里不重复
    final List<Word> words = all.where((Word w) => w.tag != '作文').toList();
    return _Data(marks, words);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _clearWrong(Word word) async {
    await DatabaseHelper.instance.markMastered(word);
    if (!mounted) return;
    _reload();
    AppToast.show(context, '已标记为掌握');
  }

  Future<void> _removeMark(EssayMarkHit h) async {
    final int? id = h.mark.id;
    if (id != null) {
      await DatabaseHelper.instance.deleteEssayMark(id);
    }
    await DatabaseHelper.instance.deleteEssayWordIfUntouched(
      track: TrackStore.current.value,
      en: h.mark.word,
    );
    if (!mounted) return;
    _reload();
  }

  void _openEssay(EssayMarkHit h) {
    // 先切到作文页签，等这一帧完成再发定位请求，
    // 否则作文页在隐藏状态下算不出正确的滚动位置。
    widget.onOpenEssay?.call();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      EssayFocus.go(
        EssayFocusRequest(
          essayId: h.mark.essayId,
          word: h.mark.word,
          para: h.mark.para,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final ModulePalette p = ModulePalette.of(context);

    return Column(
      children: <Widget>[
        Expanded(child: _buildList(p)),
        _submitBar(p),
      ],
    );
  }

  /// 底部：把今天的错词交给 AI 复盘
  Widget _submitBar(ModulePalette p) {
    return Container(
      decoration: BoxDecoration(
        color: p.canvas,
        border: Border(top: BorderSide(color: p.line)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 46,
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _submitting ? null : _submitToday,
            icon: _submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.psychology_outlined, size: 18),
            label: const Text('提交今日错词'),
            style: FilledButton.styleFrom(
              backgroundColor: p.blue,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submitToday() async {
    setState(() => _submitting = true);
    try {
      final DigestTask? task = await DigestQueue.buildToday(
        TrackStore.current.value,
      );
      if (!mounted) return;
      if (task == null) {
        AppToast.show(context, '今天还没有新的错词');
        return;
      }
      DigestQueue.submit(task);
      ChatFocus.openDigest();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _buildList(ModulePalette p) {
    return FutureBuilder<_Data>(
      future: _future,
      builder: (BuildContext context, AsyncSnapshot<_Data> snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('出错了：${snap.error}'));
        }
        final _Data data = snap.data!;
        if (data.isEmpty) {
          return const EmptyView(
            icon: Icons.sentiment_satisfied_outlined,
            title: '还没有错词',
            subtitle: '作文标记和答错的词会到这里',
          );
        }

        final bool showMarks = _tab == 0;
        final int count = showMarks ? data.marks.length : data.words.length;

        return Column(
          children: <Widget>[
            _filterBar(data, p),
            Expanded(
              child: count == 0
                  ? Center(
                      child: Text(
                        showMarks ? '还没有标记词' : '还没有错题',
                        style: TextStyle(fontSize: 12.5, color: p.muted),
                      ),
                    )
                  : GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragEnd: (DragEndDetails d) {
                        final double v = d.primaryVelocity ?? 0;
                        if (v < -260 && _tab == 0) {
                          setState(() => _tab = 1);
                        } else if (v > 260 && _tab == 1) {
                          setState(() => _tab = 0);
                        }
                      },
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                        itemCount: count,
                        itemBuilder: (BuildContext context, int i) {
                          if (showMarks) return _markTile(data.marks[i], p);
                          return _wordTile(data.words[i], p);
                        },
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  /// 顶部两个横向分区：标记词 / 错题，点哪个下面筛哪个
  Widget _filterBar(_Data data, ModulePalette p) {
    Widget zone({
      required String label,
      required int count,
      required IconData icon,
      required Color color,
      required int value,
    }) {
      final bool on = _tab == value;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _tab = value),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: on ? color.withValues(alpha: 0.08) : p.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: on ? color.withValues(alpha: 0.45) : p.line,
                width: on ? 1.2 : 1,
              ),
            ),
            child: Row(
              children: <Widget>[
                Icon(icon, size: 17, color: on ? color : p.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          color: on ? color : p.muted,
                          fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 19,
                          height: 1.2,
                          fontWeight: FontWeight.w600,
                          color: on ? p.ink : p.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final int shown = _tab == 0 ? data.marks.length : data.words.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              zone(
                label: '标记词',
                count: data.marks.length,
                icon: Icons.bookmark_border,
                color: p.wrong,
                value: 0,
              ),
              const SizedBox(width: 8),
              zone(
                label: '错题',
                count: data.words.length,
                icon: Icons.error_outline,
                color: p.blue,
                value: 1,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: <Widget>[
              Text(
                '$shown 条',
                style: TextStyle(fontSize: 11.5, color: p.muted),
              ),
              const Spacer(),
              if (_tab == 1 && data.words.isNotEmpty) ...<Widget>[
                MotionButton(
                  label: '复测',
                  icon: Icons.bolt,
                  kind: MotionKind.pulse,
                  filled: false,
                  onPressed: () async {
                    final Object? changed = await Navigator.of(context)
                        .push<Object?>(
                          SmoothRoute<Object?>(
                            page: QuickQuizPage(
                              pool: data.words,
                              title: '错词复测',
                              count: data.words.length > 20
                                  ? 20
                                  : data.words.length,
                            ),
                          ),
                        );
                    if (changed == true && mounted) _reload();
                  },
                ),
                const SizedBox(width: 4),
              ],
              FxIconButton(
                icon: Icons.ios_share,
                fx: TapFx.lift,
                tooltip: '导出',
                size: 18,
                color: p.amber,
                onPressed: () =>
                    showExportSheet(context, initial: ExportScope.wrong),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 作文里标红的一条：默认收成一行，点开才看原句
  Widget _markTile(EssayMarkHit h, ModulePalette p) {
    final String key = '${h.mark.word}@${h.mark.createdAt}';
    final bool open = _openMarks.contains(key);

    return InkWell(
      onTap: () => setState(() {
        if (open) {
          _openMarks.remove(key);
        } else {
          _openMarks.add(key);
        }
      }),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(Icons.bookmark, size: 16, color: p.wrong),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          h.mark.word,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: p.wrong,
                          ),
                        ),
                      ),
                      Icon(
                        open ? Icons.expand_less : Icons.expand_more,
                        size: 18,
                        color: p.muted,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${h.essayDate} · ${h.essayTitle}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: p.muted),
                  ),
                  if (open) ...<Widget>[
                    if (h.mark.sentence.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                        decoration: BoxDecoration(
                          color: p.surfaceAlt,
                          borderRadius: BorderRadius.circular(8),
                          border: Border(
                            left: BorderSide(color: p.wrong, width: 2.5),
                          ),
                        ),
                        child: Text(
                          h.mark.sentence,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.55,
                            color: p.ink.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => _openEssay(h),
                        icon: const Icon(Icons.north_east, size: 14),
                        label: const Text(
                          '去原文',
                          style: TextStyle(fontSize: 11.5),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          minimumSize: const Size(0, 30),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 4),
            FxIconButton(
              icon: Icons.close,
              fx: TapFx.close,
              tooltip: '取消标记',
              size: 16,
              color: p.muted,
              onPressed: () => _removeMark(h),
            ),
          ],
        ),
      ),
    );
  }

  Widget _wordTile(Word w, ModulePalette p) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        onTap: () => showWordDetail(context, w),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        leading: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: p.wrong.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            '${w.wrong}',
            style: TextStyle(
              fontSize: 12,
              color: p.wrong,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        title: Text(
          w.en,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: p.ink,
          ),
        ),
        subtitle: Text(
          w.zh.isEmpty ? '暂无释义' : w.zh,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: p.muted),
        ),
        trailing: TextButton(
          onPressed: () => _clearWrong(w),
          child: Text('已掌握', style: TextStyle(fontSize: 12, color: p.muted)),
        ),
      ),
    );
  }
}
