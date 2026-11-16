// 分区管理：新建、改名、删除。每个分区一套独立的词和进度。

import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../services/track_store.dart';
import '../theme/module_palette.dart';
import '../widgets/app_toast.dart';

class SectionsPage extends StatefulWidget {
  const SectionsPage({super.key});

  @override
  State<SectionsPage> createState() => _SectionsPageState();
}

class _SectionsPageState extends State<SectionsPage> {
  bool _loading = true;
  List<_Sec> _items = <_Sec>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final List<Map<String, Object?>> rows =
        await DatabaseHelper.instance.getSections();
    final List<_Sec> list = <_Sec>[];
    for (final Map<String, Object?> r in rows) {
      final String id = r['id'] as String;
      final int count =
          await DatabaseHelper.instance.countWords(track: id);
      list.add(
        _Sec(
          id: id,
          name: (r['name'] as String?) ?? '分区',
          count: count,
        ),
      );
    }
    if (!mounted) return;
    setState(() {
      _items = list;
      _loading = false;
    });
  }

  Future<void> _add() async {
    final String? name = await _askName('新建分区', '');
    if (name == null) return;
    final Track? t = await TrackStore.add(name);
    if (!mounted) return;
    if (t == null) {
      AppToast.show(context, '名字为空或已经有同名分区');
      return;
    }
    await _load();
  }

  Future<void> _rename(_Sec s) async {
    final String? name = await _askName('重命名分区', s.name);
    if (name == null) return;
    await TrackStore.rename(s.id, name);
    await _load();
  }

  Future<void> _delete(_Sec s) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text('删除「${s.name}」？'),
        content: Text(
          s.count == 0
              ? '这个分区里没有词，删除后不可恢复。'
              : '这个分区里还有 ${s.count} 个词，需要先移走或删掉才能删分区。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          if (s.count == 0)
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('删除'),
            ),
        ],
      ),
    );
    if (ok != true) return;
    final String? err = await TrackStore.remove(s.id);
    if (!mounted) return;
    if (err != null) {
      AppToast.show(context, err);
      return;
    }
    await _load();
  }

  Future<String?> _askName(String title, String initial) async {
    final TextEditingController c = TextEditingController(text: initial);
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLength: 12,
          decoration: const InputDecoration(
            hintText: '比如：四级、专业课、雅思',
            counterText: '',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(c.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    return (result == null || result.isEmpty) ? null : result;
  }

  @override
  Widget build(BuildContext context) {
    final ModulePalette p = ModulePalette.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('分区'),
        actions: <Widget>[
          IconButton(
            tooltip: '新建分区',
            icon: const Icon(Icons.add),
            onPressed: _add,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: <Widget>[
                Text(
                  '每个分区的单词、复习进度和统计互不影响。',
                  style: TextStyle(fontSize: 12, color: p.muted),
                ),
                const SizedBox(height: 12),
                for (final _Sec s in _items)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: p.surface,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: ListTile(
                      onTap: () async {
                        await TrackStore.setCurrent(s.id);
                        if (context.mounted) Navigator.of(context).pop(true);
                      },
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      leading: Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: p.blue.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.folder_outlined,
                            size: 18, color: p.blue),
                      ),
                      title: Text(
                        s.name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: s.id == TrackStore.current.value
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: p.ink,
                        ),
                      ),
                      subtitle: Text(
                        '${s.count} 个词',
                        style: TextStyle(fontSize: 11, color: p.muted),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          if (s.id == TrackStore.current.value)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Text(
                                '当前',
                                style: TextStyle(fontSize: 11, color: p.blue),
                              ),
                            ),
                          PopupMenuButton<String>(
                            icon: Icon(Icons.more_horiz,
                                size: 18, color: p.muted),
                            onSelected: (String v) {
                              if (v == 'rename') _rename(s);
                              if (v == 'delete') _delete(s);
                            },
                            itemBuilder: (BuildContext ctx) =>
                                const <PopupMenuEntry<String>>[
                              PopupMenuItem<String>(
                                value: 'rename',
                                child: Text('重命名'),
                              ),
                              PopupMenuItem<String>(
                                value: 'delete',
                                child: Text('删除'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _Sec {
  final String id;
  final String name;
  final int count;

  const _Sec({required this.id, required this.name, required this.count});
}
