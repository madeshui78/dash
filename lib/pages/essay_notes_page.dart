// 批注本：把每篇文章里的单词批注按文章分组展示。
// 数据源是 word_notes，不同文章互不影响。

import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/word_note.dart';
import '../theme/module_palette.dart';

class EssayNotesPage extends StatefulWidget {
  const EssayNotesPage({super.key});

  @override
  State<EssayNotesPage> createState() => _EssayNotesPageState();
}

class _EssayNotesPageState extends State<EssayNotesPage> {
  bool _loading = true;
  List<WordNote> _notes = <WordNote>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final List<WordNote> list =
        await DatabaseHelper.instance.getNoteOverview();
    if (!mounted) return;
    setState(() {
      _notes = list;
      _loading = false;
    });
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
                        Icon(Icons.sticky_note_2_outlined,
                            size: 40, color: p.muted),
                        const SizedBox(height: 12),
                        Text(
                          '还没有批注',
                          style: TextStyle(fontSize: 15, color: p.ink),
                        ),
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
                    for (final MapEntry<String, List<WordNote>> g
                        in groups.entries)
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

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.line),
      ),
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
          const SizedBox(height: 8),
          Divider(height: 1, color: p.line),
          for (final WordNote n in list) ...<Widget>[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 96,
                  child: Text(
                    n.word,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: p.blue,
                    ),
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
            if (n.sentence.isNotEmpty) ...<Widget>[
              const SizedBox(height: 3),
              Padding(
                padding: const EdgeInsets.only(left: 96),
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
            const SizedBox(height: 2),
          ],
        ],
      ),
    );
  }
}
