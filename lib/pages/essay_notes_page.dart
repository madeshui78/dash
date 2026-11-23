// 批注本：把每篇文章里的单词批注按文章分组展示。
// 数据源是 word_notes，不同文章互不影响。

import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/essay.dart';
import '../models/word_note.dart';
import '../services/essay_focus.dart';
import '../theme/module_palette.dart';
import '../theme/ui.dart';
import '../widgets/app_toast.dart';

class EssayNotesPage extends StatefulWidget {
  const EssayNotesPage({super.key});

  @override
  State<EssayNotesPage> createState() => _EssayNotesPageState();
}

class _EssayNotesPageState extends State<EssayNotesPage> {
  bool _loading = true;
  List<WordNote> _notes = <WordNote>[];
  final Set<String> _open = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final List<WordNote> list = await DatabaseHelper.instance.getNoteOverview();
    if (!mounted) return;
    setState(() {
      _notes = list;
      _open.addAll(list.map((WordNote n) => n.essayId));
      _loading = false;
    });
  }

  /// 点一条批注：回到那篇文章，滚到这个词
  Future<void> _openAt(WordNote n) async {
    final Essay? essay = await DatabaseHelper.instance.getEssayById(n.essayId);
    if (!mounted) return;
    if (essay == null) {
      AppToast.show(context, '这篇文章已经不在了');
      return;
    }

    int para = 0;
    final List<String> paras = essay.text
        .split(RegExp(r'\n\s*\n'))
        .map((String s) => s.trim())
        .toList();
    for (int i = 0; i < paras.length; i++) {
      if (paras[i].toLowerCase().contains(n.word.toLowerCase())) {
        para = i;
        break;
      }
    }

    Navigator.of(context).pop();
    EssayFocus.switchToEssay.value = true;
    EssayFocus.go(
      EssayFocusRequest(
        essayId: n.essayId,
        word: n.word,
        para: para,
        markOnOpen: true,
      ),
    );
  }

  String _date(int ms) {
    final DateTime d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.month}月${d.day}日';
  }

  @override
  Widget build(BuildContext context) {
    final ModulePalette p = ModulePalette.of(context);

    // 按文章分组，保持最近更新的文章在前
    final Map<String, List<WordNote>> groups = <String, List<WordNote>>{};
    for (final WordNote n in _notes) {
      groups.putIfAbsent(n.essayId, () => <WordNote>[]).add(n);
    }

    return Scaffold(
      backgroundColor: p.canvas,
      appBar: AppBar(title: const Text('批注本')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notes.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.sticky_note_2_outlined,
                      size: 40,
                      color: p.muted,
                    ),
                    const SizedBox(height: 12),
                    Text('还没有批注', style: TextStyle(fontSize: 15, color: p.ink)),
                    const SizedBox(height: 6),
                    Text(
                      '在作文里点一个词，底部「写批注」\n写完会按文章归到这里',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.6,
                        color: p.muted,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: <Widget>[
                for (final MapEntry<String, List<WordNote>> g in groups.entries)
                  _group(p, g.value),
              ],
            ),
    );
  }

  Widget _group(ModulePalette p, List<WordNote> list) {
    final WordNote first = list.first;
    final String title = first.essayTitle.trim().isEmpty
        ? '未命名文章'
        : first.essayTitle.trim();
    final bool open = _open.contains(first.essayId);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InkWell(
            onTap: () => setState(() {
              if (open) {
                _open.remove(first.essayId);
              } else {
                _open.add(first.essayId);
              }
            }),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                            color: p.ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${first.essayDate.isEmpty ? '' : '${first.essayDate} · '}'
                          '${list.length} 条批注',
                          style: TextStyle(fontSize: 11, color: p.muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    open ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: p.muted,
                  ),
                ],
              ),
            ),
          ),
          if (open) ...<Widget>[
            Divider(height: 1, color: p.line),
            for (final WordNote n in list) ...<Widget>[
              InkWell(
                onTap: () => _openAt(n),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          SizedBox(
                            width: 96,
                            child: Row(
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    n.word,
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                      color: p.blue,
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.north_east,
                                  size: 11,
                                  color: p.blue.withValues(alpha: 0.5),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Text(
                              n.note,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.55,
                                color: p.ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (n.sentence.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 96, top: 3),
                          child: Text(
                            n.sentence,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.45,
                              color: p.muted,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (n != list.last) Divider(height: 1, indent: 96, color: p.line),
            ],
          ],
        ],
      ),
    );
  }
}
