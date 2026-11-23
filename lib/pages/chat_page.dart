// AI 问答页：跟 AI 直接聊英语——问单词、问语法、改句子、练作文。
// 整段对话都存在数据库的 chat_messages 表里，杀掉 App 再打开还在；
// 长按任意一句可以单独复制或删除。

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../db/database_helper.dart';
import '../models/chat_session.dart';
import '../models/digest_result.dart';
import '../models/essay.dart';
import '../models/memory_graph.dart';
import '../models/word.dart';
import '../services/ai_service.dart';
import '../services/chat_focus.dart';
import '../services/digest_queue.dart';
import '../services/track_store.dart';
import '../theme/module_palette.dart';
import '../widgets/app_toast.dart';
import '../widgets/digest_answer_card.dart';
import '../widgets/digest_view.dart';
import '../widgets/fx.dart';
import 'digest_records_page.dart';
import '../widgets/memory_graph_card.dart';
import 'settings_page.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  /// 当前这段对话的消息
  final List<ChatMessage> _messages = <ChatMessage>[];

  /// 所有对话（最近更新的在前）
  List<ChatSession> _sessions = <ChatSession>[];

  /// 当前对话 id。null = 还没落库的新对话
  int? _sessionId;
  String _title = '新对话';

  bool _busy = false;
  bool _loadingHistory = true;
  String? _error;

  /// 0 普通对话，1 错词复盘
  int _mode = 0;

  /// 每条 AI 回复下面挂的记忆图谱
  final Map<int, MemoryGraph> _graphs = <int, MemoryGraph>{};

  /// 固定复盘会话：解析后的结构化结果 + 每行的定位 key
  bool _isDigest = false;
  final Map<int, DigestResult> _digestResults = <int, DigestResult>{};
  final Map<String, GlobalKey> _digestKeys = <String, GlobalKey>{};
  final List<_RailEntry> _rail = <_RailEntry>[];
  bool _digestRunning = false;

  /// 每次发送时按当前考试赛道拼，切了赛道回答的侧重点也跟着变
  String get _systemPrompt {
    final String exam = TrackStore.labelOf(TrackStore.current.value);
    return '你是用户的英语应试辅导老师，用户正在准备「$exam」。\n'
        '要求：\n'
        '1. 讲解用中文，英文例句单独给出并标注难词；\n'
        '2. 讲单词要给音标、常考释义、常见搭配，例句尽量贴近考试场景；\n'
        '3. 改句子时先给修改后的版本，再逐条说明改了什么、为什么；\n'
        '4. 回答简洁，不啰嗦，不写客套话。';
  }

  /// 空态时给的快捷问题，点一下直接发出去
  static const List<String> _suggestions = <String>[
    '"abandon" 这个单词怎么记住？常考搭配有哪些？',
    '帮我改这句话：He suggested me to go there.',
    '虚拟语气在考研英语里常考哪几种？给我例句。',
    '用这三个词写一段四级作文开头：benefit, however, therefore',
  ];

  /// 启动：有历史就打开最近一段，没有就停在空白新对话
  Future<void> _loadHistory() async {
    final List<ChatSession> list = await DatabaseHelper.instance
        .getChatSessions(kind: 'chat');
    if (!mounted) return;
    setState(() => _sessions = list);
    if (list.isEmpty) {
      setState(() => _loadingHistory = false);
    } else {
      await _openSession(list.first.id);
    }
  }

  Future<void> _refreshSessions() async {
    final List<ChatSession> list = await DatabaseHelper.instance
        .getChatSessions(kind: 'chat');
    if (!mounted) return;
    setState(() => _sessions = list);
  }

  Future<void> _openSession(int id) async {
    final List<ChatMessage> history = await DatabaseHelper.instance
        .getChatMessages(sessionId: id);
    final Map<int, String> graphRows = await DatabaseHelper.instance
        .getChatGraphsForSession(id);
    if (!mounted) return;
    String title = '对话';
    bool digest = false;
    for (final ChatSession s in _sessions) {
      if (s.id == id) {
        title = s.title;
        digest = s.isDigest;
      }
    }

    // 解析结构化的复盘消息，顺便建好右侧目录的定位 key
    final Map<int, DigestResult> results = <int, DigestResult>{};
    final Map<String, GlobalKey> keys = <String, GlobalKey>{};
    final List<_RailEntry> rail = <_RailEntry>[];
    if (digest) {
      for (final ChatMessage m in history) {
        final int? mid = m.id;
        if (mid == null || !m.content.startsWith(_digestPrefix)) continue;
        final DigestResult? r = DigestResult.tryParse(
          m.content.substring(_digestPrefix.length),
        );
        if (r == null) continue;
        results[mid] = r;
        for (int i = 0; i < r.items.length; i++) {
          final String k = '$mid-$i';
          keys[k] = GlobalKey();
          rail.add(_RailEntry(word: r.items[i].word, keyId: k));
        }
      }
    }

    setState(() {
      _sessionId = id;
      _title = title;
      _isDigest = digest;
      _messages
        ..clear()
        ..addAll(history);
      _graphs.clear();
      graphRows.forEach((int mid, String json) {
        final MemoryGraph? g = MemoryGraph.tryParse(json);
        if (g != null) _graphs[mid] = g;
      });
      _digestResults
        ..clear()
        ..addAll(results);
      _digestKeys
        ..clear()
        ..addAll(keys);
      _rail
        ..clear()
        ..addAll(rail);
      _loadingHistory = false;
      _error = null;
    });
    _scrollToEnd();
  }

  /// 新对话：不立刻建库，发出第一条消息时再建，避免一堆空会话
  void _newChat() {
    setState(() {
      _sessionId = null;
      _title = '新对话';
      _messages.clear();
      _error = null;
    });
  }

  Future<void> _send([String? preset]) async {
    final String text = (preset ?? _input.text).trim();
    if (text.isEmpty || _busy) return;

    // 第一句发出时才创建会话
    int? sid = _sessionId;
    if (sid == null) {
      final String title = text.length > 18
          ? '${text.substring(0, 18)}…'
          : text;
      sid = await DatabaseHelper.instance.createChatSession(title);
      if (!mounted) return;
      setState(() {
        _sessionId = sid;
        _title = title;
      });
      await _refreshSessions();
    }

    // 用户的提问先落库，再显示在界面上
    final int myId = await DatabaseHelper.instance.addChatMessage(
      ChatMessage(role: 'user', content: text),
      sessionId: sid,
    );
    await DatabaseHelper.instance.touchChatSession(sid);
    setState(() {
      _messages.add(
        ChatMessage(
          id: myId,
          role: 'user',
          content: text,
          createdAt: DateTime.now(),
        ),
      );
      _busy = true;
      _error = null;
    });
    _input.clear();
    _scrollToEnd();

    final AiConfig cfg = await AiService.loadConfig();
    try {
      final String reply = await AiService.chat(
        cfg,
        _messages,
        systemPrompt: _systemPrompt,
      );
      if (!mounted) return;

      // 复盘回复末尾带一段 GRAPH_JSON，拆出来单独存，正文里不显示
      String visible = reply;
      String? graphJson;
      final int gi = reply.indexOf('GRAPH_JSON:');
      if (gi >= 0) {
        visible = reply.substring(0, gi).trim();
        graphJson = reply.substring(gi + 'GRAPH_JSON:'.length).trim();
      }

      final int replyId = await DatabaseHelper.instance.addChatMessage(
        ChatMessage(role: 'assistant', content: visible),
        sessionId: sid,
      );
      if (!mounted) return;
      final MemoryGraph? graph = MemoryGraph.tryParse(graphJson);
      if (graph != null && graphJson != null) {
        await DatabaseHelper.instance.saveChatGraph(replyId, graphJson);
      }
      setState(() {
        _messages.add(
          ChatMessage(
            id: replyId,
            role: 'assistant',
            content: visible,
            createdAt: DateTime.now(),
          ),
        );
        if (graph != null) _graphs[replyId] = graph;
        _busy = false;
      });
      _scrollToEnd();
      await DatabaseHelper.instance.touchChatSession(sid);
      await _refreshSessions();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _clean(e.toString());
      });
      _scrollToEnd();
    }
  }

  /// 结构化复盘消息的前缀，正文里存的是它 + AI 返回的 JSON
  static const String _digestPrefix = 'DIGEST_JSON:';

  /// 手动复盘：不看时间，把现在的错词都过一遍
  Future<void> _manualDigest() async {
    if (_busy || _digestRunning) return;
    final List<String> items = await _collectPending(all: true);
    if (!mounted) return;
    if (items.isEmpty) {
      AppToast.show(context, '还没有记录过错词');
      return;
    }
    await _runDigestTask(
      DigestTask(
        payload: items.map((String e) => '· $e').join('\n'),
        words: <String>[],
        count: items.length,
      ),
    );
  }

  /// 收集错词。all=true 时忽略「上次复盘时间」，把当前所有错词都拿进来。
  Future<List<String>> _collectPending({bool all = false}) async {
    final DatabaseHelper db = DatabaseHelper.instance;
    final int last = all
        ? 0
        : (int.tryParse(await db.getSetting('last_digest_at') ?? '') ?? 0);
    final List<String> out = <String>[];
    final Set<String> seen = <String>{};

    final List<EssayMarkHit> marks = await db.getEssayMarkHits(
      track: TrackStore.current.value,
    );
    for (final EssayMarkHit h in marks) {
      if (h.mark.createdAt <= last) continue;
      final String w = h.mark.word.trim();
      if (w.isEmpty || !seen.add(w.toLowerCase())) continue;
      final String sent = h.mark.sentence.trim();
      out.add(sent.isEmpty ? w : '$w  ——  原句：$sent');
      // 作文标记最多取 10 条，剩下名额留给做题错词
      if (out.length >= 10) break;
    }

    final List<Word> words = await db.getWrongWords(
      track: TrackStore.current.value,
    );
    for (final Word w in words) {
      final int t = w.lastReview?.millisecondsSinceEpoch ?? 0;
      if (last > 0 && t <= last) continue;
      if (!seen.add(w.en.toLowerCase())) continue;
      out.add('${w.en}  ${w.zh}${w.wrong > 0 ? '（错 ${w.wrong} 次）' : ''}');
      if (out.length >= 20) break;
    }
    return out;
  }

  /// 后台跑一次复盘：固定会话、不插用户气泡、只落一条结果
  Future<void> _runDigestTask(DigestTask task) async {
    if (_digestRunning) return;
    setState(() {
      _digestRunning = true;
      _error = null;
    });

    try {
      final DatabaseHelper db = DatabaseHelper.instance;
      final int sid = await db.ensureDigestSession();
      await _refreshSessions();
      if (!mounted) return;
      await _openSession(sid);

      final int recId = await db.addDigestRecord(
        sessionId: sid,
        payload: task.payload,
        itemCount: task.count,
      );

      final AiConfig cfg = await AiService.loadConfig();
      final String raw = await AiService.digestWrongWords(cfg, task.payload);
      final DigestResult? result = DigestResult.tryParse(raw);
      if (result == null) throw Exception('复盘结果解析失败');

      final String content = '$_digestPrefix$raw';
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
        _digestResults[mid] = result;
        for (int i = 0; i < result.items.length; i++) {
          final String k = '$mid-$i';
          _digestKeys[k] = GlobalKey();
          _rail.add(_RailEntry(word: result.items[i].word, keyId: k));
        }
        _digestRunning = false;
      });
      _scrollToEnd();
      await _refreshSessions();
    } catch (e, st) {
      debugPrint('digest failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _digestRunning = false;
        _error = '复盘失败：${_clean(e.toString())}';
      });
      _scrollToEnd();
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  /// 异常 toString 自带 "Exception: " 前缀，显示前去掉
  String _clean(String s) {
    return s.replaceFirst(RegExp(r'^Exception:\s*'), '');
  }

  /// 清空整段对话：界面和数据库一起清
  Future<void> _clear() async {
    final int? sid = _sessionId;
    if (sid != null) {
      await DatabaseHelper.instance.clearChat(sessionId: sid);
    }
    if (!mounted) return;
    setState(() {
      _messages.clear();
      _error = null;
    });
  }

  /// 删掉指定的一句：长按气泡后选「删除」
  Future<void> _deleteOne(ChatMessage m) async {
    final int? id = m.id;
    if (id != null) {
      await DatabaseHelper.instance.deleteChatMessage(id);
    }
    if (!mounted) return;
    setState(() {
      _messages.removeWhere((ChatMessage x) => x.id == m.id);
    });
    AppToast.show(context, '已删除这一句');
  }

  /// 长按一条消息：复制 / 删除
  void _showMessageMenu(ChatMessage m) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.copy_all_outlined),
                title: const Text('复制这句'),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: m.content));
                  Navigator.of(ctx).pop();
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: cs.error),
                title: Text('删除这句', style: TextStyle(color: cs.error)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _deleteOne(m);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    ChatFocus.mode.addListener(_onModeRequest);
    _loadHistory();
  }

  @override
  void dispose() {
    ChatFocus.mode.removeListener(_onModeRequest);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onModeRequest() {
    final int m = ChatFocus.mode.value;
    if (m < 0 || !mounted) return;
    setState(() => _mode = m);
    ChatFocus.mode.value = -1;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        _buildModeBar(),
        Expanded(
          child: IndexedStack(
            index: _mode,
            children: <Widget>[_buildBody(), const DigestView()],
          ),
        ),
        if (_mode == 0) _buildInputBar(),
      ],
    );
  }

  /// 顶部：普通对话 / 错词复盘两个固定入口
  Widget _buildModeBar() {
    final ModulePalette p = ModulePalette.of(context);
    Widget tab(String label, int value) {
      final bool on = _mode == value;
      return GestureDetector(
        onTap: () => setState(() => _mode = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: on ? p.blue.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: on ? FontWeight.w600 : FontWeight.w400,
              color: on ? p.blue : p.muted,
            ),
          ),
        ),
      );
    }

    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: p.canvas,
      child: Row(
        children: <Widget>[
          tab('对话', 0),
          const SizedBox(width: 2),
          tab('错词复盘', 1),
          const Spacer(),
          if (_mode == 0) ...<Widget>[
            FxIconButton(
              icon: Icons.segment,
              fx: TapFx.dots,
              tooltip: '历史对话',
              size: 19,
              color: p.chat,
              onPressed: _openSessions,
            ),
            FxIconButton(
              icon: Icons.add_comment_outlined,
              fx: TapFx.pop,
              tooltip: '新对话',
              size: 19,
              color: p.blue,
              onPressed: _newChat,
            ),
          ],
          if (_mode == 1)
            FxIconButton(
              icon: Icons.history,
              fx: TapFx.flipY,
              tooltip: '复盘记录',
              size: 19,
              color: p.blue,
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (BuildContext _) => const DigestRecordsPage(),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  /// 顶部一条：当前对话名 + 历史 + 新对话
  Widget _buildSessionBar() {
    final ModulePalette p = ModulePalette.of(context);
    return Container(
      height: 42,
      padding: const EdgeInsets.only(left: 6, right: 6),
      color: p.canvas,
      child: Row(
        children: <Widget>[
          FxIconButton(
            icon: Icons.segment,
            fx: TapFx.dots,
            tooltip: '历史对话',
            size: 19,
            color: p.chat,
            onPressed: _openSessions,
          ),
          Expanded(
            child: Text(
              _title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: p.ink),
            ),
          ),
          FxIconButton(
            icon: Icons.add_comment_outlined,
            fx: TapFx.pop,
            tooltip: '新对话',
            size: 19,
            color: p.blue,
            onPressed: _newChat,
          ),
        ],
      ),
    );
  }

  /// 历史会话面板：切换 / 删除
  Future<void> _openSessions() async {
    await _refreshSessions();
    if (!mounted) return;
    final ModulePalette p = ModulePalette.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        maxChildSize: 0.85,
        builder: (BuildContext c, ScrollController sc) => ListView(
          controller: sc,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Row(
                children: <Widget>[
                  Text(
                    '对话记录',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: p.ink,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_sessions.length} 段',
                    style: TextStyle(fontSize: 11, color: p.muted),
                  ),
                ],
              ),
            ),
            if (_sessions.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    '还没有对话',
                    style: TextStyle(fontSize: 13, color: p.muted),
                  ),
                ),
              ),
            ..._sessions.map(
              (ChatSession s) => ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                title: Text(
                  s.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: p.ink,
                    fontWeight: s.id == _sessionId
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
                subtitle: Text(
                  _timeLabel(s.updatedAt),
                  style: TextStyle(fontSize: 11, color: p.muted),
                ),
                trailing: IconButton(
                  tooltip: '删除',
                  icon: Icon(Icons.delete_outline, size: 18, color: p.wrong),
                  onPressed: () => _deleteSession(s, ctx),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _openSession(s.id);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _timeLabel(DateTime t) {
    final DateTime now = DateTime.now();
    final bool sameDay =
        t.year == now.year && t.month == now.month && t.day == now.day;
    final String hm =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return sameDay ? '今天 $hm' : '${t.month} 月 ${t.day} 日';
  }

  Future<void> _deleteSession(ChatSession s, BuildContext sheetCtx) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('删除这段对话？'),
        content: Text('「${s.title}」里的消息会一起删掉。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await DatabaseHelper.instance.deleteChatSession(s.id);
    await _refreshSessions();
    if (!mounted) return;
    if (_sessionId == s.id) {
      if (_sessions.isNotEmpty) {
        await _openSession(_sessions.first.id);
      } else {
        _newChat();
      }
    }
    if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
  }

  Widget _buildBody() {
    final ModulePalette p = ModulePalette.of(context);
    // 历史还没读回来时先转个圈，不然会闪一下空态
    if (_loadingHistory) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_messages.isEmpty && !_digestRunning) {
      if (_isDigest) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.psychology_outlined, size: 34, color: p.muted),
                const SizedBox(height: 12),
                Text(
                  _error ?? '还没有复盘记录\n去错词本点「提交今日错词」',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, height: 1.6, color: p.muted),
                ),
              ],
            ),
          ),
        );
      }
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
        children: <Widget>[
          Icon(
            Icons.forum_outlined,
            size: 28,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 18),
          ..._suggestions
              .take(3)
              .map(
                (String q) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ActionChip(
                      label: Text(
                        q,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onPressed: () => _send(q),
                    ),
                  ),
                ),
              ),
        ],
      );
    }

    if (_isDigest) return _buildDigestList();

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      itemCount: _messages.length + (_busy || _error != null ? 1 : 0),
      itemBuilder: (BuildContext context, int i) {
        if (i >= _messages.length) {
          return _error != null ? _errorBubble() : _typingBubble();
        }
        return _bubble(_messages[i]);
      },
    );
  }

  /// 复盘固定会话：非懒加载，保证每个词的行都在，目录才能精准跳转
  Widget _buildDigestList() {
    return Stack(
      children: <Widget>[
        ListView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(12, 12, 44, 8),
          children: <Widget>[
            for (final ChatMessage m in _messages) _bubble(m),
            if (_digestRunning) _digestLoading(),
            if (_error != null) _errorBubble(),
          ],
        ),
        if (_rail.isNotEmpty)
          Positioned(
            top: 12,
            bottom: 12,
            right: 0,
            width: 32,
            child: _DigestRail(entries: _rail, onTap: _jumpToWord),
          ),
      ],
    );
  }

  void _jumpToWord(_RailEntry e) {
    final BuildContext? ctx = _digestKeys[e.keyId]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        alignment: 0.06,
      );
    }
    AppToast.show(context, e.word);
  }

  Widget _digestLoading() {
    final ModulePalette p = ModulePalette.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.line),
      ),
      child: Row(
        children: <Widget>[
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text('正在整理今天的错词…', style: TextStyle(fontSize: 12.5, color: p.muted)),
        ],
      ),
    );
  }

  /// 顶部一行小字：现在问的是哪门考试（系统提示里也带了，这里是给用户看的）
  Widget _bubble(ChatMessage m) {
    final int? mid = m.id;
    if (_isDigest && mid != null && m.content.startsWith(_digestPrefix)) {
      final DigestResult? r = _digestResults[mid];
      if (r != null) {
        return DigestAnswerCard(
          result: r,
          keyAt: (int i) => _digestKeys['$mid-$i'] ?? GlobalKey(),
        );
      }
    }
    final ModulePalette p = ModulePalette.of(context);
    final bool user = m.isUser;
    final Color userFg = p.brightness == Brightness.light
        ? Colors.white
        : const Color(0xFF06101F);
    final MemoryGraph? graph = m.id == null ? null : _graphs[m.id!];
    final Widget bubble = Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: user
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: <Widget>[
          if (!user)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.auto_awesome, size: 11, color: p.blue),
                  const SizedBox(width: 4),
                  Text(
                    'AI',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 0.4,
                      color: p.blue,
                    ),
                  ),
                ],
              ),
            ),
          GestureDetector(
            // 长按任何一句都能单独处理：复制或删除
            onLongPress: () => _showMessageMenu(m),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 302),
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
              decoration: BoxDecoration(
                color: user ? p.blue : p.surface,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(user ? 16 : 5),
                  topRight: Radius.circular(user ? 5 : 16),
                  bottomLeft: const Radius.circular(16),
                  bottomRight: const Radius.circular(16),
                ),
                border: user ? null : Border.all(color: p.line),
              ),
              child: Text(
                user ? m.content : _plain(m.content),
                style: TextStyle(
                  fontSize: 15,
                  height: user ? 1.5 : 1.65,
                  letterSpacing: 0.15,
                  color: user ? userFg : p.ink,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (graph == null) return bubble;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        bubble,
        MemoryGraphCard(graph: graph),
      ],
    );
  }

  /// 模型有时还是会在正文里加 ** 和反引号，显示前统一抹掉
  String _plain(String s) {
    try {
      String t = s
          .replaceAllMapped(
            RegExp(r'\*\*(.+?)\*\*'),
            (Match m) => m.group(1) ?? '',
          )
          .replaceAllMapped(RegExp(r'`(.+?)`'), (Match m) => m.group(1) ?? '')
          // Dart 不支持 (?m) 这种内联写法，多行模式要用构造参数
          .replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '')
          .replaceAll('**', '')
          .replaceAll('```', '');
      t = t.replaceAll(RegExp(r'\n{3,}'), '\n\n');
      return t.trim();
    } catch (_) {
      return s;
    }
  }

  Widget _typingBubble() {
    final ModulePalette p = ModulePalette.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Text('思考中', style: TextStyle(fontSize: 13, color: p.muted)),
          ],
        ),
      ),
    );
  }

  Widget _errorBubble() {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.error_outline, size: 18, color: cs.onErrorContainer),
              const SizedBox(width: 6),
              Text(
                '没答上来',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: cs.onErrorContainer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(
            _error!,
            style: TextStyle(fontSize: 13, color: cs.onErrorContainer),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              TextButton.icon(
                onPressed: () async {
                  // 把刚才那条提问从界面和数据库里都删掉再重发，
                  // 只删界面的话，库里会留下一条重复提问
                  if (_messages.isEmpty || !_messages.last.isUser) return;
                  final ChatMessage last = _messages.last;
                  setState(() {
                    _messages.removeLast();
                    _error = null;
                  });
                  final int? id = last.id;
                  if (id != null) {
                    await DatabaseHelper.instance.deleteChatMessage(id);
                  }
                  if (!mounted) return;
                  await _send(last.content);
                },
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('重试'),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (BuildContext context) => const SettingsPage(),
                    ),
                  );
                },
                icon: const Icon(Icons.settings_outlined, size: 16),
                label: const Text('去设置'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    final ModulePalette p = ModulePalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
      color: p.canvas,
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            if (_messages.isNotEmpty)
              FxIconButton(
                icon: Icons.delete_sweep_outlined,
                fx: TapFx.shake,
                tooltip: '清空对话',
                color: p.muted,
                onPressed: _busy ? null : _clear,
              ),
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: const InputDecoration(
                  hintText: '问点什么',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _PlaneSendButton(busy: _busy, onPressed: () => _send()),
          ],
        ),
      ),
    );
  }
}

/// 发送键：按一下，纸飞机从圆圈里飞出去再飞回来。
/// 用 sin 做「出去—回来」的往返，比位移到外面再跳回来自然。
class _PlaneSendButton extends StatefulWidget {
  final bool busy;
  final VoidCallback onPressed;

  const _PlaneSendButton({required this.busy, required this.onPressed});

  @override
  State<_PlaneSendButton> createState() => _PlaneSendButtonState();
}

class _PlaneSendButtonState extends State<_PlaneSendButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _tap() {
    if (widget.busy) return;
    _c.forward(from: 0);
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final ModulePalette p = ModulePalette.of(context);
    return SizedBox(
      width: 46,
      height: 46,
      child: Material(
        color: widget.busy ? p.surfaceAlt : p.chat,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _tap,
          child: Center(
            child: widget.busy
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: p.muted,
                    ),
                  )
                : AnimatedBuilder(
                    animation: _c,
                    builder: (BuildContext context, Widget? child) {
                      final double t = _c.value;
                      // 0 → 1 → 0，出去再回来
                      final double wave = math.sin(math.pi * t);
                      return Transform.translate(
                        offset: Offset(18 * wave, -8 * wave),
                        child: Transform.rotate(
                          angle: 0.5 * wave,
                          child: Transform.scale(
                            scale: 1 + 0.15 * wave,
                            child: child,
                          ),
                        ),
                      );
                    },
                    child: Icon(
                      Icons.send,
                      color: ModulePalette.onAccent(p.chat),
                      size: 20,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// 右侧目录的一条：词 + 对应的行 key
class _RailEntry {
  final String word;
  final String keyId;

  const _RailEntry({required this.word, required this.keyId});
}

/// 竖向排列的横线目录：一条线代表一个词，点一下跳到那一行
class _DigestRail extends StatelessWidget {
  final List<_RailEntry> entries;
  final void Function(_RailEntry) onTap;

  const _DigestRail({required this.entries, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final ModulePalette p = ModulePalette.of(context);
    if (entries.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (BuildContext ctx, BoxConstraints c) {
        final int n = entries.length;
        final double usable = c.maxHeight - 12;
        final double step = n <= 1 ? 0 : usable / (n - 1);
        return Stack(
          clipBehavior: Clip.none,
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
