// 错词提交记录：后台发给 AI 的原文都留在这里，按时间倒序。

import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/chat_session.dart';
import '../services/ai_service.dart';
import '../theme/module_palette.dart';

class DigestRecordsPage extends StatefulWidget {
  const DigestRecordsPage({super.key});

  @override
  State<DigestRecordsPage> createState() => _DigestRecordsPageState();
}

class _DigestRecordsPageState extends State<DigestRecordsPage> {
  bool _loading = true;
  List<DigestRecord> _items = <DigestRecord>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final List<DigestRecord> list =
        await DatabaseHelper.instance.getDigestRecords();
    if (!mounted) return;
    setState(() {
      _items = list;
      _loading = false;
    });
  }

  String _time(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.month} 月 ${t.day} 日 ${two(t.hour)}:${two(t.minute)}';
  }

  Future<void> _open(DigestRecord r) async {
    final List<ChatMessage> qa = r.messageId == null
        ? <ChatMessage>[]
        : await DatabaseHelper.instance.getDigestQa(r.messageId!);
    if (!mounted) return;
    final ModulePalette p = ModulePalette.of(context);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (BuildContext c, ScrollController sc) => ListView(
          controller: sc,
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
          children: <Widget>[
            Text(
              '${_time(r.createdAt)} · ${r.itemCount} 条',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            SelectableText(
              r.payload,
              style: const TextStyle(fontSize: 13, height: 1.6),
            ),
            if (qa.isNotEmpty) ...<Widget>[
              const SizedBox(height: 20),
              Divider(color: p.line),
              const SizedBox(height: 10),
              Text(
                '追问记录',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: p.muted,
                ),
              ),
              const SizedBox(height: 8),
              for (final ChatMessage m in qa)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        m.isUser ? '我' : 'AI',
                        style: TextStyle(
                          fontSize: 10,
                          color: m.isUser ? p.blue : p.muted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        m.content,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.55,
                          color: p.ink,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ModulePalette p = ModulePalette.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('错词记录')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Text(
                    '还没有提交记录',
                    style: TextStyle(fontSize: 13, color: p.muted),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: <Widget>[
                    Text(
                      '每次在错词本点「提交今日错词」，发给 AI 的原文都会留一份。',
                      style: TextStyle(fontSize: 12, color: p.muted),
                    ),
                    const SizedBox(height: 12),
                    for (final DigestRecord r in _items)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: p.surface,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: ListTile(
                          onTap: () => _open(r),
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
                            child:
                                Icon(Icons.psychology_outlined,
                                    size: 18, color: p.blue),
                          ),
                          title: Text(
                            '${_time(r.createdAt)} · ${r.itemCount} 条',
                            style: TextStyle(fontSize: 14, color: p.ink),
                          ),
                          subtitle: Text(
                            r.payload.replaceAll('\n', ' '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: p.muted),
                          ),
                          trailing: Icon(Icons.chevron_right,
                              size: 18, color: p.muted),
                        ),
                      ),
                  ],
                ),
    );
  }
}
