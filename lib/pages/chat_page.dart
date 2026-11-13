// AI 问答页：跟 AI 直接聊英语——问单词、问语法、改句子、练作文。
// 整段对话都存在数据库的 chat_messages 表里，杀掉 App 再打开还在；
// 长按任意一句可以单独复制或删除。

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../db/database_helper.dart';
import '../models/chat_session.dart';
import '../services/ai_service.dart';
import '../services/track_store.dart';
import '../theme/module_palette.dart';
import '../widgets/fx.dart';
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
    final List<ChatSession> list =
        await DatabaseHelper.instance.getChatSessions();
    if (!mounted) return;
    setState(() => _sessions = list);
    if (list.isEmpty) {
      setState(() => _loadingHistory = false);
      return;
    }
    await _openSession(list.first.id);
  }

  Future<void> _refreshSessions() async {
    final List<ChatSession> list =
        await DatabaseHelper.instance.getChatSessions();
    if (!mounted) return;
    setState(() => _sessions = list);
  }

  Future<void> _openSession(int id) async {
    final List<ChatMessage> history =
        await DatabaseHelper.instance.getChatMessages(sessionId: id);
    if (!mounted) return;
    String title = '对话';
    for (final ChatSession s in _sessions) {
      if (s.id == id) title = s.title;
    }
    setState(() {
      _sessionId = id;
      _title = title;
      _messages
        ..clear()
        ..addAll(history);
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
      final String title = text.length > 18 ? '${text.substring(0, 18)}…' : text;
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
      final String reply =
          await AiService.chat(cfg, _messages, systemPrompt: _systemPrompt);
      if (!mounted) return;
      final int replyId = await DatabaseHelper.instance.addChatMessage(
        ChatMessage(role: 'assistant', content: reply),
        sessionId: sid,
      );
      if (!mounted) return;
      setState(() {
        _messages.add(
          ChatMessage(
            id: replyId,
            role: 'assistant',
            content: reply,
            createdAt: DateTime.now(),
          ),
        );
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
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已删除这一句')));
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
    _loadHistory();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        _buildSessionBar(),
        Expanded(child: _buildBody()),
        _buildInputBar(),
      ],
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
                    fontWeight:
                        s.id == _sessionId ? FontWeight.w600 : FontWeight.w400,
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
    // 历史还没读回来时先转个圈，不然会闪一下空态
    if (_loadingHistory) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_messages.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
        children: <Widget>[
          Icon(
            Icons.forum_outlined,
            size: 28,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 18),
          ..._suggestions.take(3).map(
                (String q) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ActionChip(
                      label: Text(q, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onPressed: () => _send(q),
                    ),
                  ),
                ),
              ),
        ],
      );
    }

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

  /// 顶部一行小字：现在问的是哪门考试（系统提示里也带了，这里是给用户看的）
  Widget _bubble(ChatMessage m) {
    final ModulePalette p = ModulePalette.of(context);
    final bool user = m.isUser;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        // 长按任何一句都能单独处理：复制或删除
        onLongPress: () => _showMessageMenu(m),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 300),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: user ? p.surfaceAlt : p.surface,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(user ? 14 : 4),
              bottomRight: Radius.circular(user ? 4 : 14),
            ),
          ),
          child: SelectableText(
            m.content,
            style: TextStyle(
              fontSize: 15,
              height: 1.45,
              color: p.ink,
            ),
          ),
        ),
      ),
    );
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
            Text(
              '思考中',
              style: TextStyle(fontSize: 13, color: p.muted),
            ),
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
            _PlaneSendButton(
              busy: _busy,
              onPressed: () => _send(),
            ),
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
