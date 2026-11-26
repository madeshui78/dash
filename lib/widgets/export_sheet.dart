// 导出词表：把库里的词导成能直接用的笔记，而不是备份 JSON。
//
// 备份 JSON 是给机器读的，你打不出来也看不了。
// 这里导的三种格式是给你自己的：
//   纯文本  —— 对齐的清单，打印贴墙、抄进本子
//   CSV     —— 进 Excel / WPS / Anki，带 BOM 中文不乱码
//   Markdown—— 贴进笔记软件或思维导图工具
//
// 生成完调系统分享面板，想发微信、存网盘、发到电脑上打印都行。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app_toast.dart';

import 'package:share_plus/share_plus.dart';

import '../db/database_helper.dart';
import '../models/word.dart';
import '../services/backup_service.dart';
import '../services/export_format.dart';
import '../services/track_store.dart';

/// 导出哪些词
enum ExportScope {
  all('全部', Icons.list_alt),
  wrong('错词', Icons.error_outline),
  mastered('已掌握', Icons.check_circle_outline),
  due('今天该复习', Icons.history_edu),
  today('今天这批', Icons.today);

  const ExportScope(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// 弹出导出面板。调用方只要给个初始范围就行。
Future<void> showExportSheet(
  BuildContext context, {
  ExportScope initial = ExportScope.all,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext ctx) => _ExportSheet(initial: initial),
  );
}

class _ExportSheet extends StatefulWidget {
  final ExportScope initial;

  const _ExportSheet({required this.initial});

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  late ExportScope _scope;
  ExportFormat _format = ExportFormat.txt;
  bool _withStats = false;
  bool _busy = false;
  int? _count;

  @override
  void initState() {
    super.initState();
    _scope = widget.initial;
    _refreshCount();
  }

  Future<void> _refreshCount() async {
    final List<Word> words = await _load();
    if (!mounted) return;
    setState(() => _count = words.length);
  }

  Future<List<Word>> _load() async {
    final String track = TrackStore.current.value;
    final DatabaseHelper db = DatabaseHelper.instance;
    switch (_scope) {
      case ExportScope.all:
        return db.queryWords(track: track);
      case ExportScope.wrong:
        return db.getWrongWords(track: track);
      case ExportScope.mastered:
        return db.queryWords(track: track, filter: 'mastered');
      case ExportScope.due:
        return db.getDueWords(track: track, limit: 9999);
      case ExportScope.today:
        return db.getTodayDraw(track: track);
    }
  }

  Future<void> _doExport() async {
    setState(() => _busy = true);
    try {
      final List<Word> words = await _load();
      if (words.isEmpty) {
        if (!mounted) return;
        setState(() => _busy = false);
        AppToast.show(context, '这个范围里没有词');
        return;
      }
      final String text = await BackupService.exportAs(
        words,
        format: _format,
        withStats: _withStats,
      );
      final Directory dir = await getTemporaryDirectory();
      final String stamp = _stamp();
      final String name = '单词_${_scope.label}_$stamp.${_format.ext}';
      final File file = File('${dir.path}${Platform.pathSeparator}$name');
      await file.writeAsString(text);

      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile(file.path)],
          subject: name,
          text: '${_scope.label} ${words.length} 个词',
        ),
      );
      if (!mounted) return;
      setState(() => _busy = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      AppToast.show(context, '导出失败：$e', duration: const Duration(seconds: 3));
    }
  }

  String _stamp() {
    final DateTime n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${two(n.month)}${two(n.day)}_${two(n.hour)}${two(n.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              '导出词表',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            Text(
              '导成能直接用的笔记，不是备份 JSON',
              style: TextStyle(fontSize: 12, color: cs.outline),
            ),
            const SizedBox(height: 16),
            const Text('范围', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ExportScope.values
                  .map(
                    (ExportScope s) => ChoiceChip(
                      avatar: Icon(s.icon, size: 16),
                      label: Text(s.label),
                      selected: _scope == s,
                      onSelected: (_) {
                        setState(() => _scope = s);
                        _refreshCount();
                      },
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 16),
            const Text('格式', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ExportFormat.values
                  .map(
                    (ExportFormat f) => ChoiceChip(
                      label: Text(f.label),
                      selected: _format == f,
                      onSelected: (_) => setState(() => _format = f),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('带上答对/答错次数', style: TextStyle(fontSize: 14)),
              subtitle: Text(
                '想知道哪些词错得多，勾上这个',
                style: TextStyle(fontSize: 12, color: cs.outline),
              ),
              value: _withStats,
              onChanged: (bool v) => setState(() => _withStats = v),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _doExport,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.ios_share),
                label: Text(_count == null ? '导出' : '导出 $_count 个词'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
