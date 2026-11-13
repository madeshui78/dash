// 错词本：两部分——作文里标红的词、以及做题时答错的词。
//
// 标红的词带着出处：点一下跳回那篇作文的对应段落，
// 而不是只看到一个孤零零的单词。

import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/essay.dart';
import '../models/word.dart';
import '../services/essay_focus.dart';
import '../services/track_store.dart';
import '../theme/module_palette.dart';
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
    final List<EssayMarkHit> marks =
        await DatabaseHelper.instance.getEssayMarkHits(track: track);
    final List<Word> all =
        await DatabaseHelper.instance.getWrongWords(track: track);
    // 作文带进来的词已经在上面单独列了，这里不重复
    final List<Word> words =
        all.where((Word w) => w.tag != '作文').toList();
    return _Data(marks, words);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _clearWrong(Word word) async {
    await DatabaseHelper.instance.markMastered(word);
    if (!mounted) return;
    _reload();
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已标记为掌握')));
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
    EssayFocus.go(
      EssayFocusRequest(
        essayId: h.mark.essayId,
        word: h.mark.word,
        para: h.mark.para,
      ),
    );
    widget.onOpenEssay?.call();
  }

  @override
  Widget build(BuildContext context) {
    final ModulePalette p = ModulePalette.of(context);

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

        final List<Object> items = <Object>[
          _Header(data),
          if (data.marks.isNotEmpty) const _Section('作文标记'),
          ...data.marks,
          if (data.words.isNotEmpty) const _Section('错题'),
          ...data.words,
        ];

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
          itemCount: items.length,
          itemBuilder: (BuildContext context, int i) {
            final Object item = items[i];
            if (item is _Header) {
              return _header(item.data, p);
            }
            if (item is _Section) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(8, 18, 8, 6),
                child: Text(
                  item.title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                    color: p.muted,
                  ),
                ),
              );
            }
            if (item is EssayMarkHit) {
              return _markTile(item, p);
            }
            final Word w = item as Word;
            return _wordTile(w, p);
          },
        );
      },
    );
  }

  Widget _header(_Data data, ModulePalette p) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 4, 2),
      child: Row(
        children: <Widget>[
          Text(
            '${data.marks.length + data.words.length} 条',
            style: TextStyle(fontSize: 12, color: p.muted),
          ),
          const Spacer(),
          if (data.words.isNotEmpty) ...<Widget>[
            MotionButton(
              label: '复测',
              icon: Icons.bolt,
              kind: MotionKind.pulse,
              filled: false,
              onPressed: () async {
                final Object? changed =
                    await Navigator.of(context).push<Object?>(
                  SmoothRoute<Object?>(
                    page: QuickQuizPage(
                      pool: data.words,
                      title: '错词复测',
                      count:
                          data.words.length > 20 ? 20 : data.words.length,
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
            onPressed: () => showExportSheet(
              context,
              initial: ExportScope.wrong,
            ),
          ),
        ],
      ),
    );
  }

  /// 作文里标红的一条：词 + 出处 + 原句
  Widget _markTile(EssayMarkHit h, ModulePalette p) {
    return InkWell(
      onTap: () => _openEssay(h),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Icon(Icons.bookmark, size: 16, color: p.wrong),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    h.mark.word,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: p.wrong,
                    ),
                  ),
                  if (h.mark.sentence.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 3),
                    Text(
                      h.mark.sentence,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: p.ink.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    '${h.essayDate} · ${h.essayTitle}',
                    style: TextStyle(fontSize: 10, color: p.muted),
                  ),
                ],
              ),
            ),
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
          child: Text(
            '已掌握',
            style: TextStyle(fontSize: 12, color: p.muted),
          ),
        ),
      ),
    );
  }
}

class _Header {
  final _Data data;
  const _Header(this.data);
}

class _Section {
  final String title;
  const _Section(this.title);
}
