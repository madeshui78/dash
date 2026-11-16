// 错词复盘视图：嵌在「问答」页里的固定窗口，不是独立路由。
// 上面是复盘卡片 + 右侧词目录，下面保留输入框，随时可以追问。

import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/chat_session.dart';
import '../models/digest_result.dart';
import '../models/word.dart';
import '../services/ai_service.dart';
import '../services/digest_queue.dart';
import '../services/track_store.dart';
import '../services/tts_service.dart';
import '../theme/module_palette.dart';
import '../widgets/app_toast.dart';
import '../widgets/digest_answer_card.dart';

class DigestView extends StatefulWidget {
  const DigestView({super.key});

  @override
  State<DigestView> createState() => _DigestViewState();
}

class _DigestViewState extends State<DigestView> {
  static const String _prefix = 'DIGEST_JSON:';

  bool _loading = true;
  bool _running = false;
  bool _qaBusy = false;
  bool _panelOpen = false;
  int? _sid;
  String? _error;

  final List<ChatMessage> _messages = <ChatMessage>[];
  final Map<int, DigestResult> _results = <int, DigestResult>{};
  final Map<String, GlobalKey> _keys = <String, GlobalKey>{};
  final List<_Rail> _rail = <_Rail>[];
  final ScrollController _scroll = ScrollController();

  /// 右侧悬浮追问窗：只存在内存里，不写进复盘记录
  final List<ChatMessage> _qa = <ChatMessage>[];
  final TextEditingController _qaInput = TextEditingController();
  final ScrollController _qaScroll = ScrollController();
  final GlobalKey _listKey = GlobalKey();
  int _active = 0;
  int _lastSync = 0;

  /// 当前追问挂在哪条复盘结果下
  int? _qaMessageId;

  /// 用户正看着哪个词（从词详情进来时设置）
  String? _qaFocus;

  @override
  void initState() {
    super.initState();
    DigestQueue.task.addListener(_onTask);
    _boot();
  }

  @override
  void dispose() {
    DigestQueue.task.removeListener(_onTask);
    _qaInput.dispose();
    _qaScroll.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onTask() {
    final DigestTask? t = DigestQueue.task.value;
    if (t == null || _running) return;
    DigestQueue.take();
    _run(t);
  }

  Future<void> _boot() async {
    await _load();
    final DigestTask? t = DigestQueue.take();
    if (t != null) await _run(t);
  }

  Future<void> _load() async {
    final ChatSession? s = await DatabaseHelper.instance.getDigestSession();
    if (!mounted) return;
    if (s == null) {
      setState(() => _loading = false);
      return;
    }
    final List<ChatMessage> msgs =
        await DatabaseHelper.instance.getChatMessages(sessionId: s.id);
    int? lastDigest;
    for (final ChatMessage m in msgs) {
      if (m.content.startsWith(_prefix)) lastDigest = m.id;
    }
    final List<ChatMessage> qa = lastDigest == null
        ? <ChatMessage>[]
        : await DatabaseHelper.instance.getDigestQa(lastDigest);
    if (!mounted) return;
    setState(() {
      _sid = s.id;
      _qaMessageId = lastDigest;
      _qa
        ..clear()
        ..addAll(qa);
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
      _loading = true;
      _error = null;
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
        _qaMessageId = mid;
        _qa.clear();
        _active = 0;
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

  Future<void> _ask() async {
    final String text = _qaInput.text.trim();
    if (text.isEmpty || _qaBusy) return;

    setState(() {
      _qa.add(ChatMessage(role: 'user', content: text));
      _qaBusy = true;
    });
    _qaInput.clear();
    _scrollQa();
    if (_qaMessageId != null) {
      await DatabaseHelper.instance
          .addDigestQa(_qaMessageId!, 'user', text);
    }

    try {
      final AiConfig cfg = await AiService.loadConfig();
      final String reply = await AiService.chat(
        cfg,
        _qa,
        systemPrompt: _qaPrompt(),
      );
      if (!mounted) return;
      if (_qaMessageId != null) {
        await DatabaseHelper.instance
            .addDigestQa(_qaMessageId!, 'assistant', reply);
      }
      if (!mounted) return;
      setState(() {
        _qa.add(ChatMessage(role: 'assistant', content: reply));
        _qaBusy = false;
      });
      _scrollQa();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _qaBusy = false;
        _qa.add(
          ChatMessage(
            role: 'assistant',
            content: '回答失败：${e.toString().replaceFirst('Exception: ', '')}',
          ),
        );
      });
      _scrollQa();
    }
  }

  String _qaPrompt() {
    final List<DigestItem> items = <DigestItem>[];
    for (final DigestResult r in _results.values) {
      items.addAll(r.items);
    }
    final String ctx = items
        .take(24)
        .map((DigestItem e) => '${e.word}：${e.meaning}')
        .join('；');
    return '你正在「错词复盘」里回答追问。本次复盘涉及的词：$ctx。\n'
        '${_qaFocus == null ? '' : '用户正在看「$_qaFocus」，回答要围绕它，别跑题。\n'}'
        '回答用中文、简洁，必要时给一句例句，不要重复整篇复盘。';
  }

  void _scrollQa() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_qaScroll.hasClients) return;
      _qaScroll.animateTo(
        _qaScroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    });
  }

  /// 列表滑动时，把目录的高亮同步到滚动进度上
  void _syncActive() {
    if (_rail.isEmpty || !_scroll.hasClients) return;
    final int now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastSync < 60) return;
    _lastSync = now;

    final double max = _scroll.position.maxScrollExtent;
    final int idx = max <= 0
        ? 0
        : ((_scroll.offset / max).clamp(0.0, 1.0) * (_rail.length - 1))
            .round();
    if (idx != _active) setState(() => _active = idx);
  }

  void _jumpTo(int i, {bool fast = false}) {
    if (i < 0 || i >= _rail.length) return;
    setState(() => _active = i);
    final BuildContext? ctx = _keys[_rail[i].keyId]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: fast ? Duration.zero : const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: 0.06,
      );
    }
    if (!fast) AppToast.dismiss();
  }

  Future<void> _openWord(DigestItem item) async {
    TtsService.speak(item.word);
    final Word? local = await DatabaseHelper.instance.findByEn(
      track: TrackStore.current.value,
      en: item.word,
    );
    if (!mounted) return;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (BuildContext ctx) {
        final ModulePalette p = ModulePalette.of(context);
        return SizedBox(
          width: double.infinity,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        item.word,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          color: p.ink,
                        ),
                      ),
                    ),
                    IconButton.filledTonal(
                      onPressed: () => TtsService.speak(item.word),
                      icon: const Icon(Icons.volume_up_outlined, size: 20),
                      tooltip: '读一遍',
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    if (local?.phonetic != null &&
                        local!.phonetic!.isNotEmpty)
                      _chip(p, local.phonetic!, p.blue),
                    if (item.group.isNotEmpty)
                      _chip(p, item.group, p.violet),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  item.meaning,
                  style: TextStyle(fontSize: 16, height: 1.5, color: p.ink),
                ),
                if (item.memory.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    '记忆法',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: p.muted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.memory,
                    style: TextStyle(fontSize: 13, height: 1.55, color: p.muted),
                  ),
                ],
                if (local?.example != null &&
                    local!.example!.trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    '例句',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: p.muted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    local.example!,
                    style: TextStyle(fontSize: 13, height: 1.55, color: p.ink),
                  ),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      setState(() {
                        _panelOpen = true;
                        _qaFocus = item.word;
                        _qaInput.text = '${item.word} 怎么记？';
                        _qaInput.selection = TextSelection.collapsed(
                          offset: _qaInput.text.length,
                        );
                      });
                    },
                    icon: const Icon(Icons.chat_bubble_outline, size: 16),
                    label: const Text('在复盘里继续问'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      side: BorderSide(color: p.line),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _chip(ModulePalette p, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: TextStyle(fontSize: 11.5, color: color)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ModulePalette p = ModulePalette.of(context);
    if (_loading) return const Center(child: CircularProgressIndicator());

    return Stack(
      children: <Widget>[
        Column(
          children: <Widget>[
            Expanded(
          child: _messages.isEmpty
              ? _empty(p)
              : Stack(
                  children: <Widget>[
                    NotificationListener<ScrollNotification>(
                      onNotification: (ScrollNotification n) {
                        _syncActive();
                        return false;
                      },
                      child: ListView(
                        key: _listKey,
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                        children: <Widget>[
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                _error!,
                                style: TextStyle(fontSize: 12, color: p.wrong),
                              ),
                            ),
                          for (final ChatMessage m in _messages) _item(m),
                        ],
                      ),
                    ),
                    if (_rail.isNotEmpty)
                      Positioned(
                        top: 10,
                        bottom: 10,
                        // 离右边缘留 12px：太贴边会被系统返回手势吃掉
                        right: 12,
                        width: 30,
                        child: _RailBar(
                          entries: _rail,
                          active: _active,
                          onJump: _jumpTo,
                        ),
                      ),
                  ],
                ),
        ),
      ],
    ),
        Positioned(
          right: 40,
          bottom: 18,
          child: _askFab(p),
        ),
        if (_panelOpen)
          Positioned(
            right: 10,
            bottom: 76,
            child: _qaPanel(p),
          ),
      ],
    );
  }

  Widget _empty(ModulePalette p) {
    if (_running) {
      return Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text(
              '正在整理错词…',
              style: TextStyle(fontSize: 13, color: p.muted),
            ),
          ],
        ),
      );
    }
    return Center(
      child: Text(
        '还没有复盘记录\n去错词本点「提交今日错词」',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, height: 1.6, color: p.muted),
      ),
    );
  }

  Widget _askFab(ModulePalette p) {
    return FloatingActionButton.small(
      heroTag: 'digest_qa',
      backgroundColor: p.blue,
      foregroundColor: Colors.white,
      onPressed: () => setState(() {
        _panelOpen = !_panelOpen;
        if (_panelOpen) _qaFocus = null;
      }),
      child: Icon(_panelOpen ? Icons.close : Icons.forum_outlined, size: 20),
    );
  }

  Widget _item(ChatMessage m) {
    final int? mid = m.id;
    final DigestResult? r = mid == null ? null : _results[mid];
    if (r != null) {
      return DigestAnswerCard(
        result: r,
        keyAt: (int i) => _keys['$mid-$i'] ?? GlobalKey(),
        onItemTap: _openWord,
      );
    }
    return _bubble(m);
  }

  Widget _bubble(ChatMessage m) {
    final ModulePalette p = ModulePalette.of(context);
    final bool user = m.isUser;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(13, 10, 13, 11),
        decoration: BoxDecoration(
          color: user ? p.blue : p.surface,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(user ? 14 : 4),
            topRight: Radius.circular(user ? 4 : 14),
            bottomLeft: const Radius.circular(14),
            bottomRight: const Radius.circular(14),
          ),
          border: user ? null : Border.all(color: p.line),
        ),
        child: Text(
          m.content,
          style: TextStyle(
            fontSize: 14.5,
            height: 1.6,
            color: user
                ? (p.brightness == Brightness.light
                    ? Colors.white
                    : const Color(0xFF06101F))
                : p.ink,
          ),
        ),
      ),
    );
  }

  /// 右侧悬浮追问窗：不占用复盘列表，关掉就消失
  Widget _qaPanel(ModulePalette p) {
    final Size screen = MediaQuery.sizeOf(context);
    final double w = screen.width > 356 ? 316 : screen.width - 28;
    final double h = (screen.height * 0.5).clamp(300.0, 430.0);

    return Material(
      color: p.surface,
      elevation: 10,
      shadowColor: p.ink.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: w,
        height: h,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 6),
              child: Row(
                children: <Widget>[
                  Icon(Icons.forum_outlined, size: 16, color: p.blue),
                  const SizedBox(width: 6),
                  Text(
                    '问 AI',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: p.ink,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close, size: 18, color: p.muted),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _panelOpen = false),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: p.line),
            Expanded(
              child: _qa.isEmpty
                  ? Center(
                      child: Text(
                        '就这次复盘继续问\n比如「accept 和 receive 的区别」',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.6,
                          color: p.muted,
                        ),
                      ),
                    )
                  : ListView(
                      controller: _qaScroll,
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                      children: <Widget>[
                        for (final ChatMessage m in _qa) _qaBubble(m),
                        if (_qaBusy)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: <Widget>[
                                const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '回答中',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: p.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: p.line)),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _qaInput,
                      minLines: 1,
                      maxLines: 3,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _ask(),
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: '继续问…',
                        hintStyle: TextStyle(fontSize: 12, color: p.muted),
                        filled: true,
                        fillColor: p.surfaceAlt,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: FilledButton(
                      onPressed: _qaBusy ? null : _ask,
                      style: FilledButton.styleFrom(
                        padding: EdgeInsets.zero,
                        shape: const CircleBorder(),
                        backgroundColor: p.blue,
                      ),
                      child: _qaBusy
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.arrow_upward, size: 15),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _qaBubble(ChatMessage m) {
    final ModulePalette p = ModulePalette.of(context);
    final bool user = m.isUser;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width - 80),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
        decoration: BoxDecoration(
          color: user ? p.blue : p.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          m.content,
          style: TextStyle(
            fontSize: 12.5,
            height: 1.55,
            color: user
                ? (p.brightness == Brightness.light
                    ? Colors.white
                    : const Color(0xFF06101F))
                : p.ink,
          ),
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

/// 右侧词目录：只有横线，没有竖线；按住上下拖可以连续切换
class _RailBar extends StatefulWidget {
  final List<_Rail> entries;
  final int active;
  final void Function(int index, {bool fast}) onJump;
  const _RailBar({
    required this.entries,
    required this.active,
    required this.onJump,
  });

  @override
  State<_RailBar> createState() => _RailBarState();
}

class _RailBarState extends State<_RailBar> {
  double _height = 0;

  int _indexAt(double dy) {
    final int n = widget.entries.length;
    if (n <= 1 || _height <= 0) return 0;
    final int i = (dy / _height * n).floor();
    return i.clamp(0, n - 1);
  }

  @override
  Widget build(BuildContext context) {
    final ModulePalette p = ModulePalette.of(context);
    return LayoutBuilder(
      builder: (BuildContext ctx, BoxConstraints c) {
        _height = c.maxHeight;
        final int n = widget.entries.length;
        final double slot = n == 0 ? c.maxHeight : c.maxHeight / n;

        int indexAt(double dy) {
          if (n <= 1 || slot <= 0) return 0;
          return (dy / slot).floor().clamp(0, n - 1);
        }

        // 用原始指针事件，不走 GestureDetector：按下就定位，拖动连续跟随，
        // 不会再出现「拖了半天没反应」。
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (PointerDownEvent e) =>
              widget.onJump(indexAt(e.localPosition.dy)),
          onPointerMove: (PointerMoveEvent e) {
            final int i = indexAt(e.localPosition.dy);
            if (i != widget.active) widget.onJump(i, fast: true);
          },
          child: SizedBox(
            width: 28,
            child: Column(
              children: <Widget>[
                for (int i = 0; i < n; i++)
                  Expanded(
                    child: Center(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        curve: Curves.easeOut,
                        width: i == widget.active ? 24 : 12,
                        height: i == widget.active ? 4 : 2,
                        decoration: BoxDecoration(
                          color: i == widget.active
                              ? p.blue
                              : p.blue.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
