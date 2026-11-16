// 作文精读：每天一篇，读原文、点词看释义、标红想记的词。
//
// 版式照 PDF 来：正文没有卡片、没有边框，就是纸上一段段文字。
// 标红的词自动进错词本，错词本里点一下能回到这篇文章的对应段落。
//
// 这一页是常驻页签（embedded = true），外面已经有 AppBar 和导航条。

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../db/database_helper.dart';
import '../models/essay.dart';
import '../models/word.dart';
import '../services/ai_service.dart';
import '../services/essay_focus.dart';
import '../services/essay_service.dart';
import '../services/essay_store.dart';
import '../services/track_store.dart';
import '../services/tts_service.dart';
import '../theme/module_palette.dart';
import '../widgets/fx.dart';
import '../widgets/app_toast.dart';
import '../widgets/motion_button.dart';

class EssayPage extends StatefulWidget {
  const EssayPage({super.key, this.embedded = false});

  /// true：作为底部页签常驻，不自己套 Scaffold
  final bool embedded;

  @override
  State<EssayPage> createState() => _EssayPageState();
}

class _EssayPageState extends State<EssayPage> {
  final ScrollController _scroll = ScrollController();

  Essay? _essay;
  List<List<EssayToken>> _paras = <List<EssayToken>>[];
  final Map<int, GlobalKey> _paraKeys = <int, GlobalKey>{};

  /// 小写英文 → 本地词条
  Map<String, Word> _dict = <String, Word>{};

  /// AI 补出来的释义
  final Map<String, WordEntry> _aiDict = <String, WordEntry>{};

  /// 点词后 AI 给的详解
  final Map<String, String> _aiNotes = <String, String>{};

  /// 标红的词（小写）。连续标几个就是短语
  final Set<String> _marked = <String>{};

  /// 当前这篇的标记，落库用
  List<EssayMark> _marks = <EssayMark>[];

  /// 逐句译文（生成过就落库，下次直接读）
  List<EssayPair> _pairs = <EssayPair>[];
  bool _translating = false;

  bool _loading = true;
  bool _marking = false;
  bool _filling = false;

  /// 正文下面要不要挂中文。默认挂上，读的时候直接看到意思；
  /// 想只看英文再关掉。
  bool _showZh = true;

  /// 正文字号，设置里可调
  double _fontSize = 17;

  String? _error;
  String? _pendingWord;

  /// 从错词本跳过来时要突出的词
  String? _focusWord;

  String _topic = EssayStore.topics.first.id;

  /// 上一次是怎么生成的：换一篇时沿用同样的方式
  String? _lastPrompt;
  String? _lastWebQuery;

  /// 当前这组生成条件（体裁 / 字数 / 难度 / 内容要求）
  EssayPrefs _prefs = const EssayPrefs(
    topic: 'argument',
    words: 180,
    level: '适中',
    requirement: '',
  );

  @override
  void initState() {
    super.initState();
    EssayFocus.request.addListener(_onFocusRequest);
    EssayStore.fontNotifier.addListener(_onFontSize);
    _load();
  }

  @override
  void dispose() {
    EssayFocus.request.removeListener(_onFocusRequest);
    EssayStore.fontNotifier.removeListener(_onFontSize);
    _scroll.dispose();
    super.dispose();
  }

  /// 设置里拖完字号，这边立刻跟着变（页签是常驻的，不会重建）
  void _onFontSize() {
    final double v = EssayStore.fontNotifier.value;
    if (!mounted || v == _fontSize) return;
    setState(() => _fontSize = v);
  }

  String get _track => TrackStore.current.value;

  // ---------------- 加载 ----------------

  Future<void> _load({
    bool forceNew = false,
    EssayPrefs? options,
    String? prompt,
    String? webQuery,
  }) async {
    setState(() {
      _loading = true;
      _error = null;
      _focusWord = null;
      if (forceNew) _essay = null;
      if (prompt != null) {
        _lastPrompt = prompt;
        _lastWebQuery = null;
      }
      if (webQuery != null) {
        _lastWebQuery = webQuery;
        _lastPrompt = null;
      }
    });

    try {
      _prefs = await EssayStore.prefs();
      _topic = _prefs.topic;
      _fontSize = await EssayStore.fontSize();
      final Essay essay = webQuery != null
          ? await EssayStore.fromWeb(webQuery)
          : (prompt != null
              ? await EssayStore.fromPrompt(prompt)
              : await EssayStore.todayEssay(
                  forceNew: forceNew,
                  options: options ?? _prefs,
                ));
      _topic = essay.topic;
      await _prepare(essay);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _short(e);
      });
    }
  }

  /// 把文章切成段、分词、查词库、读回标记
  Future<void> _prepare(Essay essay, {int? focusPara}) async {
    final List<List<EssayToken>> paras = _splitParas(essay.text);
    final List<EssayMark> marks =
        await DatabaseHelper.instance.getEssayMarks(essay.id);
    final String? savedZh =
        await DatabaseHelper.instance.getEssayTranslation(essay.id);

    // 本地词库批量查一遍（原词 + 词形还原）
    final List<String> lookups = <String>[];
    for (final List<EssayToken> p in paras) {
      for (final EssayToken t in p) {
        if (t.word != null) lookups.addAll(lemmaCandidates(t.word!));
      }
    }
    final Map<String, Word> found =
        await DatabaseHelper.instance.findByEnBatch(
      track: _track,
      words: lookups,
    );

    final Map<String, Word> dict = <String, Word>{};
    final Set<String> uniq = <String>{};
    for (final List<EssayToken> p in paras) {
      for (final EssayToken t in p) {
        if (t.word == null) continue;
        final String key = t.word!.toLowerCase();
        if (!uniq.add(key)) continue;
        for (final String c in lemmaCandidates(t.word!)) {
          final Word? w = found[c];
          if (w != null) {
            dict[key] = w;
            break;
          }
        }
      }
    }

    final Set<String> marked = <String>{};
    for (final EssayMark m in marks) {
      for (final String w in m.word.split(' ')) {
        if (w.trim().isNotEmpty) marked.add(w.trim().toLowerCase());
      }
    }

    // 先把以前补过的词从库里读出来，打开就能看到释义，不用再等 AI
    final List<String> unknownKeys = uniq
        .where((String k) => !dict.containsKey(k) && !_aiDict.containsKey(k))
        .toList();
    if (unknownKeys.isNotEmpty) {
      final Map<String, String> cached =
          await DatabaseHelper.instance.getGlosses(unknownKeys);
      cached.forEach((String k, String zh) {
        if (zh.isNotEmpty) {
          _aiDict[k] = WordEntry(
            en: k,
            phonetic: '',
            zh: zh,
            example: '',
            root: '',
          );
        }
      });
    }

    if (!mounted) return;
    setState(() {
      _essay = essay;
      _paras = paras;
      _dict = dict;
      _marks = marks;
      _pairs = _parsePairs(savedZh);
      _marked
        ..clear()
        ..addAll(marked);
      _paraKeys
        ..clear()
        ..addEntries(
          List<MapEntry<int, GlobalKey>>.generate(
            paras.length,
            (int i) => MapEntry<int, GlobalKey>(i, GlobalKey()),
          ),
        );
      _loading = false;
      _error = null;
    });

    // 打开后不挡界面，后台把不认识的词补上
    _fillUnknown(paras, dict);

    if (focusPara != null) _scrollToPara(focusPara);
  }

  List<List<EssayToken>> _splitParas(String text) {
    List<String> chunks = text
        .split(RegExp(r'\n\s*\n'))
        .map((String s) => s.trim())
        .where((String s) => s.isNotEmpty)
        .toList();
    // 模型把段落用单换行隔开时，整篇只有一块，再按行切一次
    if (chunks.length == 1 && text.contains('\n')) {
      chunks = text
          .split('\n')
          .map((String s) => s.trim())
          .where((String s) => s.isNotEmpty)
          .toList();
    }
    return chunks.map(tokenizeEssay).toList();
  }

  void _onFocusRequest() {
    final EssayFocusRequest? req = EssayFocus.request.value;
    if (req == null) return;
    _openEssay(req.essayId, word: req.word, para: req.para);
    EssayFocus.clear();
  }

  Future<void> _openEssay(
    String id, {
    String? word,
    int para = 0,
  }) async {
    final Essay? essay = await DatabaseHelper.instance.getEssayById(id);
    if (!mounted) return;
    if (essay == null) {
      // 标记指向的原文已经不在了（早期版本换一篇会删旧文）
      _toast('这篇作文已经不在，标记保留但找不到原文');
      return;
    }
    setState(() {
      _focusWord = word;
      _loading = true;
    });
    await _prepare(essay, focusPara: para);
    if (!mounted || word == null) return;
    // 页签切换有 300ms 动画，等它落位再滚一次，不然算出来的位置是隐藏状态的
    await Future<void>.delayed(const Duration(milliseconds: 380));
    if (mounted) _scrollToPara(para);
  }

  void _scrollToPara(int para) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final BuildContext? ctx = _paraKeys[para]?.currentContext;
      if (ctx == null || !_scroll.hasClients) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
        alignment: 0.15,
      );
    });
  }

  /// 后台补生词释义。只问中文，一批 40 个，两批并发，回来的立刻落库。
  Future<void> _fillUnknown(
    List<List<EssayToken>> paras,
    Map<String, Word> dict,
  ) async {
    final List<String> todo = <String>[];
    final Set<String> seen = <String>{};
    for (final List<EssayToken> p in paras) {
      for (final EssayToken t in p) {
        if (t.word == null) continue;
        final String key = t.word!.toLowerCase();
        if (dict.containsKey(key) || seen.contains(key)) continue;
        // 上一篇已经问过的词直接用现成的，别重复花钱
        if (_aiDict.containsKey(key)) continue;
        seen.add(key);
        todo.add(t.word!);
      }
    }
    if (todo.isEmpty) return;
    if (todo.length > 240) todo.removeRange(240, todo.length);

    setState(() => _filling = true);
    try {
      final AiConfig cfg = await AiService.loadConfig();
      const int size = AiService.glossBatchSize;

      // 每次并发两批，整体大概能快一倍
      for (int i = 0; i < todo.length; i += size * 2) {
        final List<Future<Map<String, String>>> jobs =
            <Future<Map<String, String>>>[];
        for (int j = 0; j < 2; j++) {
          final int start = i + j * size;
          if (start >= todo.length) break;
          final int end =
              start + size > todo.length ? todo.length : start + size;
          jobs.add(AiService.lookupGlosses(cfg, todo.sublist(start, end)));
        }
        final List<Map<String, String>> results =
            await Future.wait(jobs);

        final Map<String, String> merged = <String, String>{};
        for (final Map<String, String> r in results) {
          merged.addAll(r);
          r.forEach((String k, String zh) {
            _aiDict[k] = WordEntry(
              en: k,
              phonetic: '',
              zh: zh,
              example: '',
              root: '',
            );
          });
        }
        await DatabaseHelper.instance.saveGlosses(merged);
        if (!mounted) return;
        setState(() {});
      }
    } catch (_) {
      // 补不上不影响阅读，点词还能单独问
    }
    if (mounted) setState(() => _filling = false);
  }

  // ---------------- 标记 ----------------

  Future<void> _toggleMark(String word) async {
    final String key = word.toLowerCase();
    if (!_marked.add(key)) _marked.remove(key);
    setState(() {});
    await _syncMarks();
  }

  /// 把手上的标记整理成「连续的一串词就是一条」，落库并同步到错词本
  Future<void> _syncMarks() async {
    final Essay? essay = _essay;
    if (essay == null) return;

    final List<EssayMark> next = <EssayMark>[];
    final Set<String> used = <String>{};

    for (int p = 0; p < _paras.length; p++) {
      final List<EssayToken> toks = _paras[p];
      final List<String> words = <String>[];
      int runStart = -1;

      void flush() {
        if (words.isEmpty) return;
        final String phrase = words.join(' ');
        if (used.add(phrase.toLowerCase())) {
          next.add(
            EssayMark(
              essayId: essay.id,
              word: phrase,
              sentence: _sentenceAt(toks, runStart),
              para: p,
              start: runStart,
              createdAt: DateTime.now().millisecondsSinceEpoch,
            ),
          );
        }
        words.clear();
        runStart = -1;
      }

      for (int i = 0; i < toks.length; i++) {
        final EssayToken t = toks[i];
        if (t.word == null) {
          // 句末标点断开短语；逗号不断（look, forward 仍算连着）
          if (t.text.contains('.') ||
              t.text.contains('!') ||
              t.text.contains('?') ||
              t.text.contains(';')) {
            flush();
          }
          continue;
        }
        if (_marked.contains(t.word!.toLowerCase())) {
          if (words.isEmpty) runStart = i;
          words.add(t.word!);
        } else {
          flush();
        }
      }
      flush();
    }

    // 取消掉的词，如果是作文带进错词本的，一起撤掉
    final Set<String> oldWords =
        _marks.map((EssayMark m) => m.word.toLowerCase()).toSet();
    final Set<String> newWords =
        next.map((EssayMark m) => m.word.toLowerCase()).toSet();

    await DatabaseHelper.instance.replaceEssayMarks(essay.id, next);

    if (newWords.isNotEmpty) {
      final List<Word> add = next
          .where((EssayMark m) => !oldWords.contains(m.word.toLowerCase()))
          .map(
            (EssayMark m) => Word(
              id: null,
              en: m.word,
              zh: _zhOf(m.word),
              tag: '作文',
              track: _track,
              wrong: 1,
            ),
          )
          .toList();
      if (add.isNotEmpty) {
        await DatabaseHelper.instance.insertWordsBatch(add);
      }
    }

    for (final String gone in oldWords.difference(newWords)) {
      await DatabaseHelper.instance.deleteEssayWordIfUntouched(
        track: _track,
        en: gone,
      );
    }

    if (mounted) setState(() => _marks = next);
  }

  String _zhOf(String word) {
    final String first = word.split(' ').first.toLowerCase();
    final Word? w = _dict[first];
    if (w != null && w.zh.isNotEmpty) return w.zh;
    return _aiDict[first]?.zh ?? '';
  }

  /// 标记可能是短语（that textbooks），拆开逐个高亮
  bool _isFocusWord(String raw) {
    final String? f = _focusWord;
    if (f == null) return false;
    final String w = raw.toLowerCase();
    for (final String part in f.toLowerCase().split(RegExp(r'\s+'))) {
      if (part.isNotEmpty && part == w) return true;
    }
    return false;
  }

  /// 正文里一个词的中文：本地词库优先，其次 AI 补的
  String _zhFor(String raw) {
    final String key = raw.toLowerCase();
    final Word? w = _dict[key];
    if (w != null && w.zh.isNotEmpty) return w.zh;
    return _aiDict[key]?.zh ?? '';
  }

  /// 某个 token 所在的那一句，存进标记里当语境
  String _sentenceAt(List<EssayToken> toks, int start) {
    int offset = 0;
    for (int i = 0; i < start && i < toks.length; i++) {
      offset += toks[i].text.length;
    }
    final String flat = toks.map((EssayToken t) => t.text).join();
    final List<String> sentences = splitSentences(flat);
    int acc = 0;
    for (final String s in sentences) {
      if (offset <= acc + s.length) return s;
      acc += s.length + 1;
    }
    return sentences.isEmpty ? flat : sentences.last;
  }

  // ---------------- 点词 ----------------

  void _openWord(String raw) {
    final String key = raw.toLowerCase();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext ctx) => _WordSheet(
        raw: raw,
        word: _dict[key],
        ai: _aiDict[key],
        note: _aiNotes[key],
        loading: _pendingWord == key,
        marked: _marked.contains(key),
        onExplain: () async {
          final String note = await _explain(raw);
          if (!mounted) return;
          setState(() => _aiNotes[key] = note);
        },
        onMark: () {
          Navigator.of(ctx).pop();
          _toggleMark(raw);
        },
      ),
    );
  }

  Future<String> _explain(String raw) async {
    setState(() => _pendingWord = raw.toLowerCase());
    String out;
    try {
      final AiConfig cfg = await AiService.loadConfig();
      final String ctx = _sentenceAround(raw);
      out = await AiService.chat(
        cfg,
        <ChatMessage>[
          ChatMessage(
            role: 'user',
            content: '讲一下英文 "$raw"。'
                '${ctx.isEmpty ? '' : '它出现在这句里：$ctx\n'}'
                '按这几块回答：句中的意思、常见释义和词性、词根词缀、两个常用搭配、一个例句。',
          ),
        ],
        systemPrompt: '你是一名英语老师，讲解具体、简短，不写客套话。',
      );
    } catch (e) {
      out = 'AI 没答上来：$e';
    }
    if (mounted) setState(() => _pendingWord = null);
    return out;
  }

  String _sentenceAround(String raw) {
    for (final List<EssayToken> p in _paras) {
      final String flat = p.map((EssayToken t) => t.text).join();
      final int idx = flat.toLowerCase().indexOf(raw.toLowerCase());
      if (idx < 0) continue;
      int start = idx;
      int end = idx + raw.length;
      while (start > 0 && '.\n!?'.contains(flat[start - 1]) == false) {
        start--;
      }
      while (end < flat.length && '.\n!?'.contains(flat[end]) == false) {
        end++;
      }
      return flat.substring(start, end).trim();
    }
    return '';
  }

  // ---------------- 别的动作 ----------------

  /// 换一篇：沿用上一次的生成方式，不会把网摘偷偷换成 AI 作文
  Future<void> _regenerate() async {
    if (_lastWebQuery != null) {
      await _load(forceNew: true, webQuery: _lastWebQuery);
    } else if (_lastPrompt != null) {
      await _load(forceNew: true, prompt: _lastPrompt);
    } else {
      await _load(forceNew: true);
    }
  }

  /// 生成入口：要么一句话描述，要么从网上摘一篇
  Future<void> _openComposeSheet() async {
    final _ComposeRequest? req = await showModalBottomSheet<_ComposeRequest>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext ctx) => _ComposeSheet(
        initialMode: _topic == 'web' ? 1 : 0,
        initialText: _topic == 'web'
            ? (_lastWebQuery ?? '')
            : (_lastPrompt ?? _prefs.requirement),
      ),
    );
    if (req == null || !mounted) return;
    final String text = req.text.trim();
    if (text.isEmpty) {
      _toast(req.mode == 1 ? '先写一句想找什么文章' : '先写一句想要什么作文');
      return;
    }
    if (req.mode == 1) {
      await _load(forceNew: true, webQuery: text);
    } else {
      await _load(forceNew: true, prompt: text);
    }
  }

  /// 自定义：体裁、字数、难度、内容要求
  Future<void> _openCustomSheet() async {
    EssayPrefs draft = _prefs;
    final TextEditingController req =
        TextEditingController(text: draft.requirement);

    final EssayPrefs? result = await showModalBottomSheet<EssayPrefs>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (BuildContext ctx, StateSetter setSheet) {
            Widget chips<T>(List<T> values, T current, String Function(T) label,
                ValueChanged<T> onPick) {
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: values
                    .map(
                      (T v) => ChoiceChip(
                        label: Text(label(v)),
                        selected: v == current,
                        onSelected: (_) => setSheet(() => onPick(v)),
                      ),
                    )
                    .toList(),
              );
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  0,
                  20,
                  20 + MediaQuery.of(ctx).viewInsets.bottom,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Text(
                        '生成条件',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text('体裁', style: TextStyle(fontSize: 12)),
                      const SizedBox(height: 8),
                      chips<EssayTopic>(
                        EssayStore.topics,
                        EssayStore.topics.firstWhere(
                          (EssayTopic t) => t.id == draft.topic,
                          orElse: () => EssayStore.topics.first,
                        ),
                        (EssayTopic t) => t.label,
                        (EssayTopic t) => draft = EssayPrefs(
                          topic: t.id,
                          words: draft.words,
                          level: draft.level,
                          requirement: req.text.trim(),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text('篇幅', style: TextStyle(fontSize: 12)),
                      const SizedBox(height: 8),
                      chips<int>(
                        EssayStore.wordOptions,
                        draft.words,
                        (int n) => '$n 词',
                        (int n) => draft = EssayPrefs(
                          topic: draft.topic,
                          words: n,
                          level: draft.level,
                          requirement: req.text.trim(),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text('难度', style: TextStyle(fontSize: 12)),
                      const SizedBox(height: 8),
                      chips<String>(
                        EssayStore.levels,
                        draft.level,
                        (String s) => s,
                        (String s) => draft = EssayPrefs(
                          topic: draft.topic,
                          words: draft.words,
                          level: s,
                          requirement: req.text.trim(),
                        ),
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: req,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: '内容要求（可空）',
                          hintText: '例如：人工智能对学习的影响，偏议论',
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () {
                            Navigator.of(ctx).pop(
                              EssayPrefs(
                                topic: draft.topic,
                                words: draft.words,
                                level: draft.level,
                                requirement: req.text.trim(),
                              ),
                            );
                          },
                          child: const Text('生成一篇'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (result == null || !mounted) return;
    await EssayStore.savePrefs(result);
    setState(() => _prefs = result);
    await _load(forceNew: true, options: result);
  }

  /// 历史：今天以前的作文都在，点一条就能打开
  Future<void> _openHistory() async {
    final List<Essay> list =
        await DatabaseHelper.instance.getRecentEssays(track: _track, limit: 30);
    if (!mounted) return;
    if (list.isEmpty) {
      _toast('还没有历史作文');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (BuildContext c, ScrollController sc) => ListView(
          controller: sc,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: list
              .map(
                (Essay e) => ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: Text(
                    e.title.isEmpty ? '无标题' : e.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${e.date} · ${EssayStore.labelOf(e.topic)} · ${e.wordCount} 词',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: e.id == _essay?.id
                      ? const Icon(Icons.check, size: 16)
                      : null,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _openEssay(e.id);
                  },
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  /// 有译文就直接打开；没有先生成再打开
  Future<void> _openTranslation() async {
    final Essay? essay = _essay;
    if (essay == null) return;
    if (_pairs.isEmpty) {
      await _generateTranslation(essay);
    }
    if (!mounted || _pairs.isEmpty) return;
    _showTranslationSheet();
  }

  Future<void> _generateTranslation(Essay essay) async {
    setState(() => _translating = true);
    try {
      final AiConfig cfg = await AiService.loadConfig();

      // 按段落切成 2–3 块并发翻译，比整篇一次快一倍左右
      final List<String> paras = essay.text
          .split(RegExp(r'\n\s*\n'))
          .map((String s) => s.trim())
          .where((String s) => s.isNotEmpty)
          .toList();
      final List<String> chunks = <String>[];
      if (paras.length >= 3) {
        final int n = paras.length >= 6 ? 3 : 2;
        final int per = (paras.length / n).ceil();
        for (int i = 0; i < paras.length; i += per) {
          final int end = i + per > paras.length ? paras.length : i + per;
          chunks.add(paras.sublist(i, end).join('\n\n'));
        }
      } else {
        chunks.add(essay.text);
      }

      final List<List<Map<String, String>>> results = await Future.wait(
        chunks.map((String t) => AiService.translateSentences(cfg, t)),
      );

      final List<EssayPair> pairs = <EssayPair>[];
      for (final List<Map<String, String>> part in results) {
        for (final Map<String, String> m in part) {
          pairs.add(EssayPair(en: m['en'] ?? '', zh: m['zh'] ?? ''));
        }
      }
      if (pairs.isEmpty) throw Exception('没解析出译文，换个说法再试');

      await DatabaseHelper.instance.saveEssayTranslation(
        essay.id,
        jsonEncode(
          pairs
              .map((EssayPair p) => <String, String>{'en': p.en, 'zh': p.zh})
              .toList(),
        ),
      );
      if (!mounted) return;
      setState(() => _pairs = pairs);
    } catch (e) {
      if (mounted) _toast('翻译失败：${_short(e)}');
    } finally {
      if (mounted) setState(() => _translating = false);
    }
  }

  List<EssayPair> _parsePairs(String? raw) {
    if (raw == null || raw.trim().isEmpty) return <EssayPair>[];
    String s = raw.trim();
    // 去掉 ```json ... ``` 包裹
    s = s.replaceAll(RegExp(r'^```[a-zA-Z]*'), '').replaceAll('```', '');
    final int start = s.indexOf('[');
    final int end = s.lastIndexOf(']');
    if (start >= 0 && end > start) {
      try {
        final Object? data = jsonDecode(s.substring(start, end + 1));
        if (data is List) {
          final List<EssayPair> out = <EssayPair>[];
          for (final Object? item in data) {
            if (item is Map) {
              final String en = (item['en'] ?? '').toString().trim();
              final String zh = (item['zh'] ?? '').toString().trim();
              if (en.isNotEmpty) out.add(EssayPair(en: en, zh: zh));
            }
          }
          if (out.isNotEmpty) return out;
        }
      } catch (_) {
        // 落到下面的按行切
      }
    }
    // 兜底：英文行 + 紧跟的中文行
    final List<EssayPair> out = <EssayPair>[];
    String pending = '';
    for (final String line in s.split('\n')) {
      final String t = line.trim();
      if (t.isEmpty) continue;
      final bool chinese = RegExp(r'[\u4e00-\u9fa5]').hasMatch(t);
      if (!chinese) {
        if (pending.isNotEmpty) out.add(EssayPair(en: pending, zh: ''));
        pending = t;
      } else if (pending.isNotEmpty) {
        out.add(EssayPair(en: pending, zh: t));
        pending = '';
      }
    }
    if (pending.isNotEmpty) out.add(EssayPair(en: pending, zh: ''));
    return out;
  }

  void _showTranslationSheet() {
    final ModulePalette p = ModulePalette.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.68,
        maxChildSize: 0.92,
        builder: (BuildContext c, ScrollController sc) => ListView.builder(
          controller: sc,
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
          itemCount: _pairs.length + 1,
          itemBuilder: (BuildContext c, int i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: <Widget>[
                    Text(
                      '逐句译文',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: p.ink,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${_pairs.length} 句',
                      style: TextStyle(fontSize: 11, color: p.muted),
                    ),
                  ],
                ),
              );
            }
            final EssayPair pair = _pairs[i - 1];
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: SelectableText(
                          pair.en,
                          style: TextStyle(
                            fontSize: 14.5,
                            height: 1.5,
                            color: p.ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      FxIconButton(
                        icon: Icons.volume_up_outlined,
                        fx: TapFx.wave,
                        size: 17,
                        color: p.blue,
                        onPressed: () => TtsService.speak(pair.en),
                      ),
                    ],
                  ),
                  if (pair.zh.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 4),
                    SelectableText(
                      pair.zh,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: p.muted,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// 手动导入一篇自己的：txt / md / pdf
  Future<void> _import() async {
    final PlatformFile? picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: <String>['txt', 'md', 'pdf'],
      dialogTitle: '选择文件',
    );
    if (picked == null) return;
    final String? path = picked.path;
    if (path == null) {
      _toast('读不到文件路径');
      return;
    }

    String text;
    try {
      final Uint8List bytes = await File(path).readAsBytes();
      if (path.toLowerCase().endsWith('.pdf')) {
        final PdfDocument doc = PdfDocument(inputBytes: bytes);
        try {
          final PdfTextExtractor ex = PdfTextExtractor(doc);
          final StringBuffer sb = StringBuffer();
          for (int i = 0; i < doc.pages.count; i++) {
            sb.writeln(ex.extractText(startPageIndex: i, endPageIndex: i));
          }
          text = sb.toString();
        } finally {
          doc.dispose();
        }
      } else {
        text = utf8.decode(bytes, allowMalformed: true);
      }
    } catch (e) {
      _toast('文件读不出来：$e');
      return;
    }

    if (text.trim().isEmpty) {
      _toast('没抽到文字（扫描版 PDF 不行）');
      return;
    }

    final Essay essay = Essay(
      id: newUuid(),
      date: EssayStore.today(),
      topic: 'custom',
      title: picked.name.replaceAll(RegExp(r'\.(txt|md|pdf)$'), ''),
      text: text.trim(),
      track: _track,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await DatabaseHelper.instance.saveEssay(essay);
    if (!mounted) return;
    setState(() => _loading = true);
    await _prepare(essay);
  }

  void _toast(String msg) {
    if (!mounted) return;
    AppToast.show(context, msg);
  }

  String _short(Object e) {
    return e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
  }

  // ---------------- 界面 ----------------

  @override
  Widget build(BuildContext context) {
    final ModulePalette p = ModulePalette.of(context);

    final Widget body = SafeArea(
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null
              ? _errorView(p)
              : Column(
                  children: <Widget>[
                    Expanded(child: _article(p)),
                    _translationBar(p),
                  ],
                )),
    );

    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('作文')),
      body: body,
    );
  }

  /// 底部固定的一条：生成 / 查看逐句译文
  Widget _translationBar(ModulePalette p) {
    final bool has = _pairs.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: p.canvas,
        border: Border(top: BorderSide(color: p.line)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 44,
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _translating ? null : _openTranslation,
            icon: _translating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.translate, size: 18, color: p.blue),
            label: Text(
              _translating
                  ? '生成译文…'
                  : (has ? '查看逐句译文 · ${_pairs.length} 句' : '生成逐句译文'),
              style: TextStyle(fontSize: 13, color: p.ink),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: p.line),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorView(ModulePalette p) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
      children: <Widget>[
        Icon(Icons.cloud_off_outlined, size: 34, color: p.muted),
        const SizedBox(height: 14),
        Text(
          _error!,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, height: 1.5, color: p.muted),
        ),
        const SizedBox(height: 20),
        FilledButton(onPressed: () => _load(), child: const Text('重试')),
      ],
    );
  }

  Widget _article(ModulePalette p) {
    final Essay essay = _essay!;
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(22, 6, 22, 32),
      children: <Widget>[
        _toolbar(p),
        if (_focusWord != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
              decoration: BoxDecoration(
                color: p.wrong.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: <Widget>[
                  Icon(Icons.bookmark, size: 15, color: p.wrong),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '已标出：$_focusWord',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: p.wrong),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _focusWord = null),
                    child: const Text('知道了', style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 20),
        if (essay.title.trim().isNotEmpty) ...<Widget>[
          Text(
            essay.title,
            style: TextStyle(
              fontSize: 21,
              height: 1.35,
              fontWeight: FontWeight.w600,
              color: p.ink,
            ),
          ),
          const SizedBox(height: 6),
        ],
        Text(
          '${EssayStore.labelOf(essay.topic)} · ${essay.wordCount} 词'
          '${_marks.isEmpty ? '' : ' · 标记 ${_marks.length}'}',
          style: TextStyle(fontSize: 11, color: p.muted),
        ),
        const SizedBox(height: 20),
        for (int para = 0; para < _paras.length; para++)
          Padding(
            key: _paraKeys[para],
            padding: const EdgeInsets.only(bottom: 20),
            child: Wrap(
              spacing: _showZh ? 5 : 4,
              runSpacing: _showZh ? 9 : 2,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: <Widget>[
                for (final EssayToken t in _paras[para])
                  if (t.isWord)
                    _WordText(
                      display: t.text,
                      zh: _zhFor(t.word!),
                      showGloss: _showZh,
                      size: _fontSize,
                      marked: _marked.contains(t.word!.toLowerCase()),
                      focused: _isFocusWord(t.word!),
                      unknown: _zhFor(t.word!).isEmpty,
                      onTap: _marking
                          ? () => _toggleMark(t.word!)
                          : () => _openWord(t.word!),
                    )
                  else if (t.text.trim().isNotEmpty)
                    Text(
                      t.text.trim(),
                      style: TextStyle(
                        fontSize: _fontSize,
                        height: _showZh ? 1.3 : 1.62,
                        color: p.ink,
                      ),
                    ),
              ],
            ),
          ),
        if (_filling)
          Row(
            children: <Widget>[
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Text(
                '补释义',
                style: TextStyle(fontSize: 11, color: p.muted),
              ),
            ],
          ),
        const SizedBox(height: 22),
        Align(
          alignment: Alignment.centerLeft,
          child: MotionButton(
            label: '换一篇',
            icon: Icons.autorenew,
            kind: MotionKind.spin,
            filled: false,
            onPressed: _regenerate,
          ),
        ),
      ],
    );
  }

  Widget _toolbar(ModulePalette p) {
    return Row(
      children: <Widget>[
        // 一个入口：一句话描述，或从网上摘一篇
        InkWell(
          onTap: _openComposeSheet,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.auto_awesome, size: 16, color: p.essay),
                const SizedBox(width: 6),
                Text(
                  _topic == 'web'
                      ? '网上摘录'
                      : (_topic == 'custom'
                          ? 'AI 生成'
                          : '${EssayStore.labelOf(_topic)} · 目标 ${_prefs.words} 词'),
                  style: TextStyle(fontSize: 12, color: p.essay),
                ),
                Icon(Icons.expand_more, size: 15, color: p.essay),
              ],
            ),
          ),
        ),
        const Spacer(),
        FxIconButton(
          icon: Icons.history,
          fx: TapFx.flipY,
          tooltip: '历史',
          size: 20,
          color: p.blue,
          onPressed: _openHistory,
        ),
        FxIconButton(
          icon: Icons.edit_outlined,
          fx: TapFx.tilt,
          tooltip: _marking ? '退出标记' : '标记',
          size: 20,
          color: _marking ? p.wrong : p.wrong.withValues(alpha: 0.55),
          onPressed: () => setState(() => _marking = !_marking),
        ),
        FxIconButton(
          icon: Icons.subtitles_outlined,
          fx: TapFx.pulse,
          tooltip: '释义',
          size: 20,
          color: _showZh ? p.green : p.green.withValues(alpha: 0.60),
          onPressed: () => setState(() => _showZh = !_showZh),
        ),
        PopupMenuButton<String>(
          icon: Icon(Icons.more_horiz, size: 20, color: p.muted),
          onSelected: (String v) {
            if (v == 'import') _import();
            if (v == 'speak') TtsService.speak(_essay?.text ?? '');
          },
          itemBuilder: (BuildContext ctx) => const <PopupMenuEntry<String>>[
            PopupMenuItem<String>(value: 'speak', child: Text('朗读全文')),
            PopupMenuItem<String>(value: 'import', child: Text('导入文件')),
          ],
        ),
      ],
    );
  }
}

/// 正文里的一个词：没有框，只有字色变化。
/// 标红 = 已标记；蓝色 = 词库里有；黑色带虚线 = 不认识。
class _WordText extends StatelessWidget {
  /// 显示用：带上紧跟的标点（word,）
  final String display;
  final String zh;
  final bool showGloss;
  final double size;
  final bool marked;
  final bool focused;
  final bool unknown;
  final VoidCallback onTap;

  const _WordText({
    required this.display,
    required this.zh,
    required this.showGloss,
    required this.size,
    required this.marked,
    required this.focused,
    required this.unknown,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ModulePalette p = ModulePalette.of(context);
    final Color color = marked ? p.wrong : p.ink;

    final TextStyle wordStyle = TextStyle(
      fontSize: size,
      height: showGloss ? 1.2 : 1.55,
      color: color,
      fontWeight: marked || focused ? FontWeight.w600 : FontWeight.w400,
      decoration: unknown && !marked && showGloss
          ? TextDecoration.underline
          : null,
      decorationStyle: TextDecorationStyle.dotted,
      decorationColor: p.line,
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        decoration: focused
            ? BoxDecoration(
                color: p.amber.withValues(alpha: 0.30),
                borderRadius: BorderRadius.circular(4),
                border: Border(
                  bottom: BorderSide(color: p.wrong, width: 2),
                ),
              )
            : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(display, style: wordStyle),
            if (showGloss)
              SizedBox(
                height: size * 0.62,
                child: zh.isEmpty
                    ? null
                    : Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          zh,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: size * 0.52,
                            height: 1.0,
                            color: marked ? p.wrong : p.muted,
                          ),
                        ),
                      ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 点词弹出的详情
class _WordSheet extends StatelessWidget {
  final String raw;
  final Word? word;
  final WordEntry? ai;
  final String? note;
  final bool loading;
  final bool marked;
  final Future<void> Function() onExplain;
  final VoidCallback onMark;

  const _WordSheet({
    required this.raw,
    required this.word,
    this.ai,
    required this.note,
    required this.loading,
    required this.marked,
    required this.onExplain,
    required this.onMark,
  });

  @override
  Widget build(BuildContext context) {
    final ModulePalette p = ModulePalette.of(context);
    String? pick(String? a, String? b) {
      if (a != null && a.isNotEmpty) return a;
      if (b != null && b.isNotEmpty) return b;
      return null;
    }

    final String? phonetic = pick(word?.phonetic, ai?.phonetic);
    final String zh = pick(word?.zh, ai?.zh) ?? '';
    final String? example = pick(word?.example, ai?.example);
    final String? root = pick(ai?.root, null);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    raw,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                IconButton.outlined(
                  onPressed: () => TtsService.speak(raw),
                  icon: const Icon(Icons.volume_up_outlined, size: 20),
                ),
              ],
            ),
            if (phonetic != null) ...<Widget>[
              const SizedBox(height: 2),
              Text(phonetic, style: TextStyle(fontSize: 15, color: p.essay)),
            ],
            const SizedBox(height: 8),
            Text(
              zh.isEmpty ? '还没查到释义' : zh,
              style: TextStyle(
                fontSize: 17,
                color: zh.isEmpty ? p.muted : p.ink,
              ),
            ),
            if (example != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                example,
                style: TextStyle(fontSize: 14, color: p.muted),
              ),
            ],
            if (root != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(root, style: const TextStyle(fontSize: 13)),
            ],
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.icon(
                    onPressed: loading ? null : onExplain,
                    icon: loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome, size: 18),
                    label: Text(note == null ? 'AI 讲讲' : '再问一次'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: onMark,
                  icon: Icon(
                    marked ? Icons.check : Icons.edit_outlined,
                    size: 18,
                    color: marked ? p.wrong : null,
                  ),
                  label: Text(marked ? '取消标记' : '标记'),
                ),
              ],
            ),
            if (note != null) ...<Widget>[
              const SizedBox(height: 14),
              const Divider(),
              const SizedBox(height: 8),
              SelectableText(note!, style: const TextStyle(fontSize: 14)),
            ],
          ],
        ),
      ),
    );
  }
}

/// 一句原文 + 一句译文
class EssayPair {
  final String en;
  final String zh;

  const EssayPair({required this.en, required this.zh});
}

/// 生成作文的两种方式
class _ComposeRequest {
  final int mode; // 0 描述生成，1 网上摘录
  final String text;

  const _ComposeRequest(this.mode, this.text);
}

class _ComposeSheet extends StatefulWidget {
  final int initialMode;
  final String initialText;

  const _ComposeSheet({
    required this.initialMode,
    required this.initialText,
  });

  @override
  State<_ComposeSheet> createState() => _ComposeSheetState();
}

class _ComposeSheetState extends State<_ComposeSheet> {
  late int _mode;
  late final TextEditingController _text;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _text = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ModulePalette p = ModulePalette.of(context);
    final bool web = _mode == 1;

    Widget tab(String label, int v) {
      final bool on = _mode == v;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _mode = v),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: on ? p.essay.withValues(alpha: 0.12) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: on ? p.essay.withValues(alpha: 0.35) : p.line,
              ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                color: on ? p.essay : p.muted,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(
        left: 18,
        right: 18,
        top: 4,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 18,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '生成一篇',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: p.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '说人话就行，不用挑选项。',
            style: TextStyle(fontSize: 12, color: p.muted),
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              tab('描述生成', 0),
              const SizedBox(width: 8),
              tab('网上找一篇', 1),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _text,
            minLines: 3,
            maxLines: 6,
            autofocus: false,
            style: const TextStyle(fontSize: 14, height: 1.5),
            decoration: InputDecoration(
              hintText: web
                  ? '例如：给我一篇关于人工智能的最新论文\n或者贴一个文章链接'
                  : '例如：给我一篇关于人与自然的议论文，\n难度大概相当于高一水平',
              hintStyle: TextStyle(fontSize: 13, height: 1.6, color: p.muted),
              filled: true,
              fillColor: p.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: p.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: p.line),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            web
                ? '会从公开网页抓一篇英文正文，可能需要 10–20 秒；抓不到会换一个来源。'
                : '体裁、篇幅、难度都可以写在一句话里，没写就按高中/CET4、400 词左右处理。',
            style: TextStyle(fontSize: 11, height: 1.6, color: p.muted),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(_ComposeRequest(_mode, _text.text)),
              style: FilledButton.styleFrom(
                backgroundColor: p.essay,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(web ? '去网上找' : '生成'),
            ),
          ),
        ],
      ),
    );
  }
}
