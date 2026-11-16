// 错词复盘：独立的一页，不和普通问答混在一起。
//
// 提交由错词本的按钮发起，这里只负责跑请求、展示结构化复盘和右侧目录。
// 没有输入框，交互是「看、点词、跳转」，和聊天页区分开。

import 'dart:convert';

import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/chat_session.dart';
import '../models/digest_result.dart';
import '../services/ai_service.dart';
import '../services/digest_queue.dart';
import '../services/tts_service.dart';
import '../theme/module_palette.dart';
import '../widgets/app_toast.dart';
import '../widgets/digest_answer_card.dart';

class DigestChatPage extends StatefulWidget {
  const DigestChatPage({super.key});

  @override
  State<DigestChatPage> createState() => _DigestChatPageState();
}

class _DigestChatPageState extends State<DigestChatPage> {
  static const String _prefix = 'DIGEST_JSON:';

  bool _loading = true;
  bool _running = false;
  int? _sid;
  String? _error;

  final List<ChatMessage> _messages = <ChatMessage>[];
  final Map<int, DigestResult> _results = <int, DigestResult>{};
  final Map<String, GlobalKey> _keys = <String, GlobalKey>{};
  final List<_Rail> _rail = <_Rail>[];
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    final DigestTask? task = DigestQueue.take();
    await _loadSession();
    if (task != null) await _run(task);
  }

  Future<void> _loadSession() async {
    final ChatSession? s =
        await DatabaseHelper.instance.getDigestSession();
    if (!mounted) return;
    if (s == null) {
      setState(() => _loading = false);
      return;
    }
    final List<ChatMessage> msgs =
        await DatabaseHelper.instance.getChatMessages(sessionId: s.id);
    if (!mounted) return;
    setState(() {
      _sid = s.id;
      _messages
        ..clear()
        ..addAll(msgs);
      _rebuild();
      _loading = false;
    });
    _scrollToEnd();
  }

  void _rebuild() {
    _results.clear();
    _keys.clear();
    _rail.clear();
    for (final ChatMessage m in _messages) {
      final int? mid = m.id;
      if (mid == null || !m.content.startsWith(_prefix)) continue;
      final DigestResult? r =
          DigestResult.tryParse(m.content.substring(_prefix.length));
      if (r == null) continue;
      _results[mid] = r;
      for (int i = 0; i < r.items.length; i++) {
        final String k = '$mid-$i';
        _keys[k] = GlobalKey();
        _rail.add(_Rail(word: r.items[i].word, keyId: k));
      }
    }
  }

  Future<void> _run(DigestTask task) async {
    setState(() {
      _running = true;
      _error = null;
      _loading = true;
    });
    try {
      final DatabaseHelper db = DatabaseHelper.instance;
      final int sid = await db.ensureDigestSession();
      _sid = sid;
      final int recId = await db.addDigestRecord(
        sessionId: sid,
        payload: task.payload,
        itemCount: task.count,
      );
      final AiConfig cfg = await AiService.loadConfig();
      final String raw = await AiService.digestWrongWords(cfg, task.payload);
      final DigestResult? result = DigestResult.tryParse(raw);
      if (result == null) throw Exception('复盘结果解析失败');

      final String content = '$_prefix$raw';
      final int mid = await db.addChatMessage(
        ChatMessage(role: 'assistant', content: content),
        sessionId: sid,
      );
      await db.setDigestRecordMessage(recId, mid);
      await db.touchChatSession(sid);

      if (!mounted) return;
      setState(() {
        _messages.add(
          ChatMessage(
            id: mid,
            role: 'assistant',
            content: content,
            createdAt: DateTime.now(),
          ),
        );
        _results[mid] = result;
        for (int i = 0; i < result.items.length; i++) {
          final String k = '$mid-$i';
          _keys[k] = GlobalKey();
          _rail.add(_Rail(word: result.items[i].word, keyId: k));
        }
        _running = false;
        _loading = false;
      });
      _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _loading = false;
        _error = '复盘失败：${e.toString().replaceFirst('Exception: ', '')}';
      });
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _jump(_Rail e) {
    final BuildContext? ctx = _keys[e.keyId]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        alignment: 0.05,
      );
    }
    AppToast.show(context, e.word);
  }

  void _openWord(DigestItem item) {
    TtsService.speak(item.word);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext ctx) {
        final ModulePalette p = ModulePalette.of(context);
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                item.word,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: p.ink,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                item.meaning,
                style: TextStyle(fontSize: 15, height: 1.5, color: p.ink),
              ),
              if (item.memory.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  item.memory,
                  style: TextStyle(fontSize: 13, height: 1.5, color: p.muted),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ModulePalette p = ModulePalette.of(context);
    final int words = _results.values
        .fold<int>(0, (int n, DigestResult r) => n + r.items.length);

    return Scaffold(
      backgroundColor: p.canvas,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('错词复盘'),
            Text(
              '专属记录 · 共 $words 个词',
              style: TextStyle(fontSize: 11, color: p.muted),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: '返回',
            icon: const Icon(Icons.edit_note),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _messages.isEmpty
              ? _empty(p)
              : Stack(
                  children: <Widget>[
                    ListView(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(14, 12, 46, 24),
                      children: <Widget>[
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text(
                              _error!,
                              style: TextStyle(fontSize: 12, color: p.wrong),
                            ),
                          ),
                        for (final ChatMessage m in _messages)
                          _resultCard(m),
                      ],
                    ),
                    if (_rail.isNotEmpty)
                      Positioned(
                        top: 12,
                        bottom: 12,
                        right: 0,
                        width: 32,
                        child: _DigestRail(entries: _rail, onTap: _jump),
                      ),
                  ],
                ),
    );
  }

  Widget _resultCard(ChatMessage m) {
    final int? mid = m.id;
    final DigestResult? r = mid == null ? null : _results[mid];
    if (r == null) return const SizedBox.shrink();
    return DigestAnswerCard(
      result: r,
      keyAt: (int i) => _keys['$mid-$i'] ?? GlobalKey(),
      onItemTap: _openWord,
    );
  }

  Widget _empty(ModulePalette p) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.psychology_outlined, size: 40, color: p.blue),
            const SizedBox(height: 14),
            Text(
              '还没有复盘记录',
              style: TextStyle(fontSize: 15, color: p.ink),
            ),
            const SizedBox(height: 6),
            Text(
              '去错词本点「提交今日错词」',
              style: TextStyle(fontSize: 12, color: p.muted),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('返回'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Rail {
  final String word;
  final String keyId;

  const _Rail({required this.word, required this.keyId});
}

class _DigestRail extends StatelessWidget {
  final List<_Rail> entries;
  final void Function(_Rail) onTap;

  const _DigestRail({required this.entries, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final ModulePalette p = ModulePalette.of(context);
    return LayoutBuilder(
      builder: (BuildContext ctx, BoxConstraints c) {
        final int n = entries.length;
        final double usable = c.maxHeight - 12;
        final double step = n <= 1 ? 0 : usable / (n - 1);
        return Stack(
          children: <Widget>[
            Positioned(
              left: 15,
              top: 6,
              bottom: 6,
              child: Container(width: 1, color: p.line),
            ),
            for (int i = 0; i < n; i++)
              Positioned(
                top: 6 + i * step - 6,
                left: 0,
                right: 0,
                height: 12,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onTap(entries[i]),
                  child: Center(
                    child: Container(
                      width: 16,
                      height: 2,
                      decoration: BoxDecoration(
                        color: p.blue.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
