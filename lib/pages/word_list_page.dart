// 单词页：字典式浏览 + 每日抽词入口。
//
// 顶部两组控件：
//   1. 搜索框          —— 英文和中文释义都能搜
//   2. 字母索引        —— a → ap → app 逐级下钻，像查字典
// 列表里最上面是「今日抽词」卡片，点进去走四步学习流程。
// 每个词条默认只占一行（英文 + 中文），点一下展开看音标 / 例句 / 操作。
// 列表本身按字母升序排（忽略大小写）。

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/word.dart';
import '../services/study_settings.dart';
import '../services/track_store.dart';
import '../services/tts_service.dart';
import '../theme/module_palette.dart';
import '../widgets/app_toast.dart';
import '../widgets/empty_view.dart';
import '../widgets/home_cards.dart';
import '../widgets/smooth_route.dart';
import '../widgets/word_detail_sheet.dart';
import '../pages/review_page.dart';
import 'import_page.dart';
import 'loop_session_page.dart';
import 'quick_quiz_page.dart';
import 'study_session_page.dart';
import 'word_explain_page.dart';

class WordListPage extends StatefulWidget {
  /// 切 Tab / 换赛道 / 导入完成时自增，页面重新拉数据
  final ValueNotifier<int>? refreshTick;

  const WordListPage({super.key, this.refreshTick});

  @override
  State<WordListPage> createState() => _WordListPageState();
}

class _WordListPageState extends State<WordListPage> {
  final TextEditingController _search = TextEditingController();

  String _keyword = '';
  String _prefix = ''; // 字典下钻：'a' / 'ap' / 'app'

  late Future<_ViewData> _future;

  /// 多选模式：批量改归属时用
  bool _selectMode = false;
  final Set<int> _selected = <int>{};

  /// 整本词表收不收起：true = 展开那一长列
  bool _listOpen = false;
  late String _moveTarget;

  /// 记录「上次自动抽词时，这条赛道还有多少没抽过的词」。
  /// 词量一变（手动加了词、导入了一批）就再自动抽一次，把新词带进来；
  /// 词量不变则不再抽，避免刷一次页面就重复抽一批。
  final Map<String, int> _autoDrawnAt = <String, int>{};

  /// 设置里的默认学习流程：steps = 四步卡片，loop = 连续小循环
  bool _loop = false;

  @override
  void initState() {
    super.initState();
    // 目标赛道不能等于当前赛道：下拉里没这一项，选中值不在列表里会出问题
    _moveTarget = TrackStore.tracks
        .firstWhere(
          (Track t) => t.id != TrackStore.current.value,
          orElse: () => TrackStore.tracks.first,
        )
        .id;
    _future = _load();
    _loadFlow();
    widget.refreshTick?.addListener(_onTick);
  }

  void _onTick() {
    _loadFlow();
    _reload();
  }

  Future<void> _loadFlow() async {
    final bool v = await StudySettings.isLoop();
    if (!mounted) return;
    setState(() => _loop = v);
  }

  @override
  void dispose() {
    widget.refreshTick?.removeListener(_onTick);
    _search.dispose();
    super.dispose();
  }

  /// 一次拉数据的完整流程。
  /// 平台上偶发过「一次查询的响应丢了、Future 永远不回来」的情况
  /// （表现为单词页永远空白、加载圈都没有）。这里包一层超时：
  /// 卡住就换一次新的查询重试，本地 SQLite 正常都是几十毫秒的事。
  Future<_ViewData> _load() async {
    try {
      return await _loadInner().timeout(const Duration(seconds: 12));
    } on TimeoutException {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[wordlist] 查询超时了，重试一次');
      }
      return _loadInner().timeout(const Duration(seconds: 12));
    }
  }

  Future<_ViewData> _loadInner() async {
    final String track = TrackStore.current.value;
    void log(String msg) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[wordlist] $msg');
      }
    }

    log('load start, track=$track');

    // 今天这批还是空的、词库里又有没抽过的词，就自动抽一批。
    // 加完新词回到这里时「可抽数量」变了，会再抽一次，新词直接就能练，
    // 不用先手动点「抽 N 个」。
    final int drawableNow = await DatabaseHelper.instance.countDrawable(
      track: track,
    );
    log('countDrawable=$drawableNow');
    List<Word> todayNow = await DatabaseHelper.instance.getTodayDraw(
      track: track,
    );
    log('todayDraw=${todayNow.length}');
    if (todayNow.isEmpty &&
        drawableNow > 0 &&
        _autoDrawnAt[track] != drawableNow &&
        !(await StudySettings.clearedToday())) {
      _autoDrawnAt[track] = drawableNow;
      final int n = await StudySettings.dailyCount();
      await DatabaseHelper.instance.drawDaily(track: track, count: n);
      todayNow = await DatabaseHelper.instance.getTodayDraw(track: track);
    }

    final List<Word> words = await DatabaseHelper.instance.queryWords(
      track: track,
      prefix: _prefix,
      search: _keyword,
    );
    log('queryWords=${words.length}');

    // 字母索引：只在没搜索、且还没下钻到 3 个字母时显示下一级
    List<String> letters = <String>[];
    if (_keyword.isEmpty && _prefix.length < 3) {
      letters = await DatabaseHelper.instance.getLetterGroups(
        track: track,
        depth: _prefix.length + 1,
        prefix: _prefix,
      );
    }
    log('letters=${letters.length}');

    final List<Word> today = todayNow;
    final int drawable = await DatabaseHelper.instance.countDrawable(
      track: track,
    );
    final int dailyCount = await StudySettings.dailyCount();

    // 到期的旧词数。以前这个数只在复习页和统计页里出现，首页从来不告诉你
    // 今天有多少词该复习——于是你只看见"今天抽的新词"，手一滑就抽多了。
    final List<Word> due = await DatabaseHelper.instance.getDueWords(
      track: track,
      limit: 500,
    );

    // 抽过但没学完的（可能是前天抽的）。这批词以前系统里没人认：
    // 抽词池只按 draw_date 认今天，"能不能再抽"又是 NOT IN (整张抽词池)，
    // 于是它们既不在今天这批、也永远抽不到。这里单独捞出来给个入口。
    // 今天这批不算——它已经在今日卡片里了，别重复显示。
    final Set<int> todayIds = todayNow.map((Word w) => w.id!).toSet();
    final List<Word> unfinished =
        (await DatabaseHelper.instance.getUnfinishedWords(track: track))
            .where((Word w) => !todayIds.contains(w.id))
            .toList();
    log(
      'load done: words=${words.length} today=${today.length} '
      'drawable=$drawable due=${due.length} unfinished=${unfinished.length}',
    );

    return _ViewData(
      words: words,
      letters: letters,
      today: today,
      drawable: drawable,
      dailyCount: dailyCount,
      dueWords: due,
      unfinished: unfinished,
    );
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  void _setPrefix(String p) {
    setState(() => _prefix = p);
    _reload();
  }

  /// 加抽：让用户自己定这一批加几个，默认是每日数量
  Future<void> _drawMore(int n) async {
    final TextEditingController input = TextEditingController(text: '$n');
    final int? count = await showDialog<int>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('加抽几个？'),
        content: TextField(
          controller: input,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: '输入数量', suffixText: '个'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final int? v = int.tryParse(input.text.trim());
              Navigator.of(ctx).pop(v);
            },
            child: const Text('抽'),
          ),
        ],
      ),
    );
    if (count == null || count < 1) return;

    await StudySettings.clearClearedMark();
    await DatabaseHelper.instance.drawMore(
      track: TrackStore.current.value,
      count: count,
    );
    _reload();
  }

  /// 学习流程：四步 ↔ 小循环。只改设置，不直接开课。
  Future<void> _toggleFlow() async {
    final String next = _loop ? 'steps' : 'loop';
    await StudySettings.setStudyFlow(next);
    if (!mounted) return;
    setState(() => _loop = next == 'loop');
  }

  /// 清空今天这批抽词（手滑多抽、今天背不完时用）。
  /// 清空后当天不再自动重抽——要不要再抽、抽几个，交给用户自己点。
  Future<void> _clearToday() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('清空今天这批？'),
        content: const Text('只是把今天抽出来的词退回去，词库不受影响，随时能再抽。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final String track = TrackStore.current.value;
    await DatabaseHelper.instance.clearTodayDraw(track: track);
    await StudySettings.markClearedToday();
    final int drawableNow = await DatabaseHelper.instance.countDrawable(
      track: track,
    );
    _autoDrawnAt[track] = drawableNow;
    if (!mounted) return;
    _reload();
    AppToast.show(context, '已清空今天这批');
  }

  /// 今日队列：补学 → 新词 → 到期，按 id 去重
  List<Word> _todayQueue(_ViewData d) {
    final Set<int> seen = <int>{};
    final List<Word> out = <Word>[];
    for (final Word w in <Word>[...d.unfinished, ...d.today, ...d.dueWords]) {
      final int? id = w.id;
      if (id == null || !seen.add(id)) continue;
      out.add(w);
    }
    return out;
  }

  /// 不常用、或带破坏性的动作收到这里
  void _openMore(_ViewData data) {
    final ModulePalette p = ModulePalette.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: Icon(Icons.add_circle_outline, color: p.word),
              title: const Text('多抽几个词'),
              subtitle: Text(
                '按每日数量再加一批，现在是 ${data.dailyCount} 个',
                style: TextStyle(fontSize: 12, color: p.muted),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                _drawMore(data.dailyCount);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_sweep_outlined, color: p.wrong),
              title: Text('清空今天这批', style: TextStyle(color: p.wrong)),
              subtitle: Text(
                '词库不受影响，随时能再抽',
                style: TextStyle(fontSize: 12, color: p.muted),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                _clearToday();
              },
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  /// 补学只是今日任务的一部分，这里只留一句说明，不再重复开一张卡
  Widget _catchUpHint(_ViewData data) {
    final ModulePalette p = ModulePalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 6),
      child: Row(
        children: <Widget>[
          Icon(Icons.history_toggle_off, size: 13, color: p.muted),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              '其中 ${data.unfinished.length} 个是之前抽到没学完的，已排在最前面',
              style: TextStyle(fontSize: 11, color: p.muted),
            ),
          ),
          TextButton(
            onPressed: () => _giveUpUnfinished(data),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 6),
            ),
            child: Text('放弃这些', style: TextStyle(fontSize: 11, color: p.muted)),
          ),
        ],
      ),
    );
  }

  /// 开快刷自测：一题一词、立刻判对错、随时能停
  Future<void> _openQuiz(List<Word> pool, String title) async {
    if (pool.isEmpty) {
      AppToast.show(context, '这批里没有能出题的词');
      return;
    }
    final Object? changed = await Navigator.of(context).push<Object?>(
      SmoothRoute<Object?>(
        page: QuickQuizPage(
          pool: pool,
          title: title,
          count: pool.length > 20 ? 20 : pool.length,
        ),
      ),
    );
    if (changed == true && mounted) _reload();
  }

  /// 放弃这批没学完的：确认之后从抽词池里摘掉，
  /// 词本身还在词库里，以后还能再抽到。
  Future<void> _giveUpUnfinished(_ViewData data) async {
    final int n = data.unfinished.length;
    final bool go =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            title: const Text('放弃这批？'),
            content: Text('这 $n 个词会退回词库。'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('再想想'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('放弃'),
              ),
            ],
          ),
        ) ??
        false;
    if (!go) return;
    await DatabaseHelper.instance.clearUnfinished(
      track: TrackStore.current.value,
    );
    if (mounted) _reload();
  }

  /// 开一批词的学习页。
  /// loop 传 null 时按设置里的默认流程走；传了就以传入值为准 ——
  /// 卡片上两个按钮各走一种，切了「小循环」也能照样进四步卡片练习。
  Future<void> _openSession(
    List<Word> words, {
    bool daily = true,
    bool? loop,
  }) async {
    final bool useLoop = loop ?? _loop;
    if (!mounted) return;
    final Object? changed = await Navigator.of(context).push<Object?>(
      SmoothRoute<Object?>(
        page: useLoop
            ? LoopSessionPage(words: words, isDaily: daily)
            : StudySessionPage(words: words, isDaily: daily),
      ),
    );
    if (changed == true && mounted) _reload();
  }

  /// 整批改归属：把选中的词挪到目标赛道
  Future<void> _moveBatch() async {
    if (_selected.isEmpty) return;
    final int n = _selected.length;
    final String target = _moveTarget;
    final bool go =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            title: const Text('确认移动'),
            content: Text('把选中的 $n 个词移到「${TrackStore.labelOf(target)}」？'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('移动'),
              ),
            ],
          ),
        ) ??
        false;
    if (!go) return;

    final int moved = await DatabaseHelper.instance.moveWordsTo(
      ids: _selected.toList(),
      track: target,
    );
    if (!mounted) return;
    setState(() {
      _selectMode = false;
      _selected.clear();
    });
    _reload();
    AppToast.show(context, '已移动 $moved 个词到「${TrackStore.labelOf(target)}」');
  }

  Future<void> _delete(Word word) async {
    await DatabaseHelper.instance.deleteWord(word.id!);
    if (!mounted) return;
    _reload();
    AppToast.show(context, '已删除 ${word.en}');
  }

  Future<void> _move(Word word, String track) async {
    await DatabaseHelper.instance.updateWord(word.copyWith(track: track));
    if (!mounted) return;
    _reload();
    AppToast.show(context, '「${word.en}」已移到「${TrackStore.labelOf(track)}」');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        _buildSearchBar(),
        if (_selectMode) _buildSelectBar(),
        Expanded(
          child: FutureBuilder<_ViewData>(
            future: _future,
            builder: (BuildContext context, AsyncSnapshot<_ViewData> snap) {
              if (kDebugMode) {
                // ignore: avoid_print
                print(
                  '[wordlist] builder: state=${snap.connectionState} '
                  'hasData=${snap.hasData} hasError=${snap.hasError}',
                );
              }
              if (snap.connectionState == ConnectionState.waiting &&
                  !snap.hasData) {
                // 光一个转圈看不出是在加载还是页面坏了——
                // 你看到的就是"一片空白"。带上文字，顺便给个重试出口。
                final ColorScheme cs0 = Theme.of(context).colorScheme;
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      Text(
                        '正在加载单词本…',
                        style: TextStyle(fontSize: 13, color: cs0.outline),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _reload,
                        icon: const Icon(Icons.refresh),
                        label: const Text('重试'),
                      ),
                    ],
                  ),
                );
              }
              if (snap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text('出错了：${snap.error}'),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _reload,
                          icon: const Icon(Icons.refresh),
                          label: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              // waiting / 超时后还没数据：给一个看得见的加载态。
              // 绝不能返回空白——之前查询偶尔卡死时，这里就是用户看到的白屏。
              if (!snap.hasData) {
                final ColorScheme cs = Theme.of(context).colorScheme;
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      Text(
                        '正在加载单词本…',
                        style: TextStyle(fontSize: 13, color: cs.outline),
                      ),
                    ],
                  ),
                );
              }
              final _ViewData data = snap.data!;
              // 整本词表默认收起，只留一个按键——进来先看见今天要背的，
              // 不会被 3000 个词糊一脸。点按键才展开下面那一长列。
              final bool listOpen =
                  _listOpen ||
                  _selectMode ||
                  _keyword.isNotEmpty ||
                  _prefix.isNotEmpty;
              // 收起时 3000 个词条一个都不建，展开后交给 builder 按需建，
              // 屏幕外的一律不构造——不然一进页面就卡一下。
              final int headCount = listOpen ? 3 : 2;
              final bool showEmpty = listOpen && data.words.isEmpty;
              final int itemCount =
                  headCount +
                  (showEmpty ? 1 : (listOpen ? data.words.length : 0));

              return RefreshIndicator(
                onRefresh: () async => _reload(),
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                  itemCount: itemCount,
                  itemBuilder: (BuildContext context, int i) {
                    final ModulePalette p = ModulePalette.of(context);
                    if (i == 0) {
                      // 四张卡都搬到 widgets/home_cards.dart 去了，
                      // 这里只负责把数据和动作递过去
                      return Column(
                        children: <Widget>[
                          TodayTaskCard(
                            newCount: data.today.length,
                            dueCount: data.dueWords.length,
                            catchUpCount: data.unfinished.length,
                            onStart: () {
                              final List<Word> q = _todayQueue(data);
                              if (q.isEmpty) {
                                _drawMore(data.dailyCount);
                              } else {
                                _openSession(q);
                              }
                            },
                            onQuiz: () {
                              final List<Word> q = _todayQueue(data);
                              if (q.isEmpty) return;
                              _openQuiz(q, '今日任务');
                            },
                          ),
                          const SizedBox(height: 10),
                          if (data.today.isNotEmpty ||
                              data.dueWords.isNotEmpty ||
                              data.unfinished.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Row(
                                children: <Widget>[
                                  TextButton.icon(
                                    onPressed: _toggleFlow,
                                    icon: Icon(
                                      _loop ? Icons.call_split : Icons.repeat,
                                      size: 15,
                                    ),
                                    label: Text(
                                      _loop ? '换成四步' : '换成小循环',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    style: TextButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ),
                                  const Spacer(),
                                  IconButton(
                                    tooltip: '更多',
                                    onPressed: () => _openMore(data),
                                    icon: Icon(
                                      Icons.more_horiz,
                                      size: 20,
                                      color: p.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (data.unfinished.isNotEmpty) _catchUpHint(data),
                        ],
                      );
                    }
                    if (i == 1) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: _buildListToggle(data, listOpen),
                      );
                    }
                    if (i == 2) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: _buildLetterBar(data.letters),
                      );
                    }
                    if (showEmpty) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 40),
                        child: EmptyView(
                          icon: Icons.search_off,
                          title: _emptyTitle(),
                          subtitle: _emptySubtitle(data),
                        ),
                      );
                    }
                    final Word w = data.words[i - headCount];
                    return _WordTile(
                      word: w,
                      onDelete: _delete,
                      onMove: _move,
                      selecting: _selectMode,
                      selected: _selected.contains(w.id),
                      onToggle: () {
                        setState(() {
                          if (_selected.contains(w.id)) {
                            _selected.remove(w.id);
                          } else {
                            _selected.add(w.id!);
                          }
                        });
                      },
                      onOpen: () => showWordDetail(context, w),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _emptyTitle() {
    if (_keyword.isNotEmpty) return '没搜到「$_keyword」';
    if (_prefix.isNotEmpty) return '「$_prefix」下没有词';
    return '还没有单词';
  }

  String _emptySubtitle(_ViewData data) {
    if (data.words.isEmpty && data.drawable == 0) {
      return '去「添加」页批量导入一个单词表最快';
    }
    return '换个字母或者换个关键词，也可以去导入更多词';
  }

  // ---------------- 控件 ----------------

  Widget _buildSearchBar() {
    final ModulePalette p = ModulePalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: _search,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: '搜单词或释义',
                hintStyle: TextStyle(fontSize: 13, color: p.muted),
                prefixIcon: Icon(Icons.search, size: 20, color: p.muted),
                prefixIconConstraints: const BoxConstraints(minWidth: 42),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    IconButton(
                      tooltip: 'AI 查词',
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (BuildContext _) =>
                                WordExplainPage(initialQuery: _keyword.trim()),
                          ),
                        );
                      },
                      icon: Icon(Icons.auto_awesome, size: 18, color: p.blue),
                    ),
                    if (_keyword.isNotEmpty)
                      IconButton(
                        tooltip: '清空搜索',
                        icon: Icon(Icons.close, size: 18, color: p.muted),
                        onPressed: () {
                          _search.clear();
                          setState(() => _keyword = '');
                          _reload();
                        },
                      ),
                  ],
                ),
                suffixIconConstraints: const BoxConstraints(minWidth: 40),
                filled: true,
                fillColor: p.surface,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 13,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: p.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: p.line),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: p.word, width: 1.3),
                ),
              ),
              textInputAction: TextInputAction.search,
              onChanged: (String v) {
                // 输入即搜，不做防抖——本地 SQLite 几十毫秒就出来了
                setState(() => _keyword = v.trim());
                _reload();
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 46,
            child: OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _selectMode = !_selectMode;
                  _selected.clear();
                });
              },
              icon: Icon(_selectMode ? Icons.close : Icons.checklist, size: 18),
              label: Text(
                _selectMode ? '取消' : '多选',
                style: const TextStyle(fontSize: 12),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 46),
                side: BorderSide(color: p.line),
                foregroundColor: _selectMode ? p.word : p.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 多选模式的操作条：全选 + 选目标赛道 + 移动
  Widget _buildSelectBar() {
    final ModulePalette p = ModulePalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: p.surfaceAlt,
      child: Wrap(
        spacing: 10,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          Text(
            '已选 ${_selected.length} 个',
            style: TextStyle(fontSize: 13, color: p.ink),
          ),
          TextButton.icon(
            onPressed: _toggleSelectAll,
            icon: const Icon(Icons.select_all, size: 18),
            label: const Text('全选 / 全不选'),
          ),
          SizedBox(
            width: 150,
            child: DropdownButtonFormField<String>(
              initialValue: _moveTarget,
              isDense: true,
              isExpanded: true,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
              items: TrackStore.tracks
                  .where((Track t) => t.id != TrackStore.current.value)
                  .map(
                    (Track t) => DropdownMenuItem<String>(
                      value: t.id,
                      child: Text(
                        '移到「${t.label}」',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (String? v) {
                if (v != null) setState(() => _moveTarget = v);
              },
            ),
          ),
          FilledButton.icon(
            onPressed: _selected.isEmpty ? null : _moveBatch,
            icon: const Icon(Icons.move_down, size: 18),
            label: const Text('移动'),
          ),
        ],
      ),
    );
  }

  /// 全选当前筛选出来的词；已经全选了就清空
  Future<void> _toggleSelectAll() async {
    final List<Word> words = await DatabaseHelper.instance.queryWords(
      track: TrackStore.current.value,
      prefix: _prefix,
      search: _keyword,
    );
    if (!mounted) return;
    final bool allIn = words.every((Word w) => _selected.contains(w.id));
    setState(() {
      if (allIn) {
        for (final Word w in words) {
          _selected.remove(w.id);
        }
      } else {
        for (final Word w in words) {
          _selected.add(w.id!);
        }
      }
    });
  }

  /// 整个词表的收起 / 展开按键。
  /// 搜了东西、按字母钻了、或者进了多选模式，就自动展开，不用再点一下。
  Widget _buildListToggle(_ViewData data, bool open) {
    final ModulePalette p = ModulePalette.of(context);
    return Material(
      color: p.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => setState(() => _listOpen = !_listOpen),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Row(
            children: <Widget>[
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.word.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.menu_book_outlined, size: 19, color: p.word),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '单词本',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: p.ink,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${data.words.length} 个词',
                      style: TextStyle(fontSize: 11, color: p.muted),
                    ),
                  ],
                ),
              ),
              AnimatedRotation(
                turns: open ? 0.5 : 0,
                duration: const Duration(milliseconds: 220),
                child: Icon(
                  Icons.keyboard_arrow_down,
                  size: 20,
                  color: p.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 字母索引：点一个字母就钻进去，上面留面包屑可以退回
  Widget _buildLetterBar(List<String> letters) {
    if (letters.isEmpty) return const SizedBox.shrink();
    final ColorScheme cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (_prefix.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Row(
              children: <Widget>[
                ..._breadcrumbs(cs),
                const Spacer(),
                TextButton(
                  onPressed: () => _setPrefix(''),
                  child: const Text('全部'),
                ),
              ],
            ),
          ),
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: letters
                .map(
                  (String g) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text(g),
                      selected: g == _prefix,
                      onSelected: (_) => _setPrefix(g == _prefix ? '' : g),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }

  List<Widget> _breadcrumbs(ColorScheme cs) {
    final List<Widget> out = <Widget>[];
    for (int i = 0; i < _prefix.length; i++) {
      final String part = _prefix.substring(0, i + 1);
      out.add(
        GestureDetector(
          onTap: () => _setPrefix(part),
          child: Text(
            i == 0 ? part : ' · $part',
            style: TextStyle(fontSize: 13, color: cs.primary),
          ),
        ),
      );
    }
    return out;
  }
}

/// 一屏要用的数据，一次查齐
class _ViewData {
  final List<Word> words;
  final List<String> letters;
  final List<Word> today;
  final int drawable;
  final int dailyCount;

  /// 今天到期该复习的旧词（next_review <= 现在）
  final List<Word> dueWords;

  /// 抽过但没学完的词（含前几天留下的），今天这批不算
  final List<Word> unfinished;

  const _ViewData({
    required this.words,
    required this.letters,
    required this.today,
    required this.drawable,
    required this.dailyCount,
    this.dueWords = const <Word>[],
    this.unfinished = const <Word>[],
  });
}

/// 单个词条：默认收起（一行 英文 + 中文），点一下展开看音标 / 例句 / 操作。
/// 收起状态是为了让 3000 词的列表能一屏塞下更多、扫得更快。
class _WordTile extends StatefulWidget {
  final Word word;
  final Future<void> Function(Word) onDelete;
  final Future<void> Function(Word, String) onMove;
  final bool selecting;
  final bool selected;
  final VoidCallback? onToggle;
  final VoidCallback? onOpen;

  const _WordTile({
    required this.word,
    required this.onDelete,
    required this.onMove,
    this.selecting = false,
    this.selected = false,
    this.onToggle,
    this.onOpen,
  });

  @override
  State<_WordTile> createState() => _WordTileState();
}

class _WordTileState extends State<_WordTile> {
  bool _open = false;

  Word get word => widget.word;

  /// 删之前问一句——侧滑和展开里的删除按钮都走这里
  Future<bool> _askDelete() async {
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('删除这个单词？'),
          content: Text('「${word.en}」会从词库里去掉，删了就找不回来了。'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('再想想'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('删掉'),
            ),
          ],
        );
      },
    );
    return go ?? false;
  }

  Future<void> _doDelete() async {
    final bool go = await _askDelete();
    if (!go) return;
    await widget.onDelete(word);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool hasExtra =
        (word.phonetic != null && word.phonetic!.isNotEmpty) ||
        (word.example != null && word.example!.isNotEmpty) ||
        (word.tag != null && word.tag!.isNotEmpty);

    return Dismissible(
      key: ValueKey<int>(word.id!),
      // 多选模式下关掉侧滑，免得手滑删掉
      direction: widget.selecting
          ? DismissDirection.none
          : DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: cs.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.delete_outline, color: cs.onErrorContainer),
      ),
      confirmDismiss: (DismissDirection dir) async {
        await _doDelete();
        return false;
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Card(
          color: widget.selected
              ? ModulePalette.of(context).word.withValues(alpha: 0.08)
              : null,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.selecting
                ? widget.onToggle
                : () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      if (widget.selecting)
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: Checkbox(
                            value: widget.selected,
                            onChanged: (_) => widget.onToggle?.call(),
                          ),
                        ),
                      if (widget.selecting) const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          word.en,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (word.mastered)
                        Icon(
                          Icons.check_circle,
                          size: 15,
                          color: Colors.green.shade600,
                        )
                      else if (word.wrong > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '错',
                            style: TextStyle(fontSize: 11, color: Colors.red),
                          ),
                        ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          word.zh,
                          style: TextStyle(
                            fontSize: 14,
                            color: cs.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // 收起时右边就是个箭头；没有任何附加信息干脆不显示，
                      // 省得点了没反应
                      if (!widget.selecting && hasExtra)
                        Icon(
                          _open
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          size: 20,
                          color: cs.outline,
                        ),
                    ],
                  ),
                  if (_open && !widget.selecting) ...<Widget>[
                    const Divider(height: 16),
                    _buildBody(cs),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (word.phonetic != null && word.phonetic!.isNotEmpty)
          Text(
            word.phonetic!,
            style: TextStyle(fontSize: 14, color: cs.primary),
          ),
        const SizedBox(height: 4),
        Text(word.zh, style: const TextStyle(fontSize: 15)),
        if (word.example != null && word.example!.isNotEmpty) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            word.example!,
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
        ],
        if (word.tag != null && word.tag!.isNotEmpty) ...<Widget>[
          const SizedBox(height: 6),
          Text(word.tag!, style: TextStyle(fontSize: 11, color: cs.outline)),
        ],
        const SizedBox(height: 6),
        Row(
          children: <Widget>[
            Icon(Icons.check, size: 13, color: Colors.green.shade600),
            Text(
              ' ${word.correct}',
              style: TextStyle(fontSize: 11, color: cs.outline),
            ),
            const SizedBox(width: 10),
            Icon(Icons.close, size: 13, color: Colors.red.shade600),
            Text(
              ' ${word.wrong}',
              style: TextStyle(fontSize: 11, color: cs.outline),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            OutlinedButton.icon(
              onPressed: () => TtsService.speak(word.en),
              icon: const Icon(Icons.volume_up, size: 16),
              label: const Text('发音'),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
            if (widget.onOpen != null)
              OutlinedButton.icon(
                onPressed: widget.onOpen,
                icon: const Icon(Icons.auto_awesome, size: 16),
                label: const Text('详情 / AI'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            OutlinedButton.icon(
              onPressed: _pickTrack,
              icon: const Icon(Icons.move_down, size: 16),
              label: const Text('移动'),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
            OutlinedButton.icon(
              onPressed: _doDelete,
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('删除'),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: cs.error,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _pickTrack() async {
    final String? target = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '移到哪个分区',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              ...TrackStore.tracks
                  .where((Track t) => t.id != word.track)
                  .map(
                    (Track t) => ListTile(
                      leading: const Icon(Icons.drive_file_move_outline),
                      title: Text(t.label),
                      onTap: () => Navigator.of(ctx).pop(t.id),
                    ),
                  ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (target == null) return;
    await widget.onMove(word, target);
  }
}
