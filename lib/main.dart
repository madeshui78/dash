// 入口 + 四页签（作文 / 单词 / 错词本 / 问答）+ 侧边抽屉。
//
// 打开先到打卡日历，打完卡才进主界面——这是每天的起点。

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pages/add_word_page.dart';
import 'pages/chat_page.dart';
import 'pages/consent_gate.dart';
import 'pages/checkin_page.dart';
import 'pages/checkin_records_page.dart';
import 'pages/essay_notes_page.dart';
import 'pages/essay_page.dart';
import 'pages/import_page.dart';
import 'pages/key_gate.dart';
import 'pages/review_page.dart';
import 'pages/sections_page.dart';
import 'pages/settings_page.dart';
import 'pages/stats_page.dart';
import 'pages/word_list_page.dart';
import 'pages/wrong_word_page.dart';
import 'services/chat_focus.dart';
import 'services/essay_focus.dart';
import 'services/starter_words.dart';
import 'services/theme_store.dart';
import 'services/track_store.dart';
import 'theme/app_theme.dart';
import 'theme/module_palette.dart';
import 'widgets/export_sheet.dart';
import 'widgets/fx.dart';
import 'widgets/smooth_route.dart';

void main() async {
  // runApp 之前有异步初始化（读上次选的考试赛道、外观），必须先绑 Flutter 引擎
  WidgetsFlutterBinding.ensureInitialized();

  // 页面里抛异常时，release 包默认只给一块黑屏，啥也看不出来。
  // 这里换成能看见的错误页，出问题截图就能定位。
  ErrorWidget.builder = (FlutterErrorDetails details) =>
      _ErrorScreen(details: details);
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    FlutterError.reportError(
      FlutterErrorDetails(exception: error, stack: stack),
    );
    return true;
  };

  await TrackStore.load();
  await ThemeStore.load();
  // 第一次装：先给四级灌 500 个起步词，打开就有东西可背
  await StarterWords.ensureLoaded();

  runApp(const EnglishApp());
}

/// 出错时显示的页面：把异常和堆栈直接摆出来，方便截图排查
class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen({required this.details});

  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) {
    return Material(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('页面出错了'),
          backgroundColor: Colors.red.shade700,
          foregroundColor: Colors.white,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SelectableText(
            '${details.exception}\n\n${details.stack}',
            style: const TextStyle(fontSize: 12, height: 1.4),
          ),
        ),
      ),
    );
  }
}

class EnglishApp extends StatelessWidget {
  const EnglishApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 抽屉里改外观时，这里跟着重建整个 App
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeStore.mode,
      builder: (BuildContext context, ThemeMode mode, Widget? _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'dash',
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: mode,
          home: const ConsentGate(child: KeyGate(child: _EntryPoint())),
        );
      },
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// 默认落在作文页：打完卡就该看到今天那篇。
  int _index = 0;

  String _track = TrackStore.current.value;

  final ValueNotifier<int> _refreshTick = ValueNotifier<int>(0);

  late final List<Widget> _pages;

  static const List<String> _titles = <String>['作文', '单词本', '错词本', '问答'];

  @override
  void initState() {
    super.initState();
    _pages = <Widget>[
      const EssayPage(embedded: true),
      WordListPage(refreshTick: _refreshTick),
      WrongWordPage(
        refreshTick: _refreshTick,
        onOpenEssay: () => setState(() => _index = 0),
      ),
      const ChatPage(),
    ];
    ChatFocus.mode.addListener(_onModeRequest);
    EssayFocus.switchToEssay.addListener(_onEssayTab);
  }

  void _onEssayTab() {
    if (!EssayFocus.switchToEssay.value) return;
    EssayFocus.switchToEssay.value = false;
    setState(() => _index = 0);
  }

  void _onModeRequest() {
    if (ChatFocus.mode.value < 0) return;
    setState(() => _index = 3);
  }

  @override
  void dispose() {
    ChatFocus.mode.removeListener(_onModeRequest);
    EssayFocus.switchToEssay.removeListener(_onEssayTab);
    _refreshTick.dispose();
    super.dispose();
  }

  Future<void> _switchTrack(String id) async {
    await TrackStore.setCurrent(id);
    if (!mounted) return;
    setState(() => _track = id);
    _refreshTick.value++;
  }

  void _onTap(int i) {
    setState(() => _index = i);
    if (i == 1 || i == 2) _refreshTick.value++;
  }

  Future<void> _openPage(Widget page, String title) async {
    await Navigator.of(context).push<Object?>(
      SmoothRoute<Object?>(
        page: _StandalonePage(title: title, child: page),
      ),
    );
    _refreshTick.value++;
  }

  Future<void> _push(Widget page) async {
    await Navigator.of(context).push<Object?>(SmoothRoute<Object?>(page: page));
    _refreshTick.value++;
  }

  @override
  Widget build(BuildContext context) {
    final ModulePalette p = ModulePalette.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: p.brightness == Brightness.light
            ? Brightness.dark
            : Brightness.light,
        systemNavigationBarColor: p.canvas,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: p.brightness == Brightness.light
            ? Brightness.dark
            : Brightness.light,
        // 关掉系统给手势条加的对比蒙层，底部不会再出现一条半透明黑边
        systemNavigationBarContrastEnforced: false,
      ),
      child: Scaffold(
        appBar: AppBar(
          leading: Builder(
            builder: (BuildContext ctx) => FxIconButton(
              icon: Icons.menu_rounded,
              fx: TapFx.slideRight,
              tooltip: '菜单',
              size: 22,
              onPressed: () => Scaffold.of(ctx).openDrawer(),
            ),
          ),
          title: Text(_titles[_index]),
          actions: <Widget>[
            if (_index == 1)
              FxIconButton(
                icon: Icons.refresh,
                fx: TapFx.spin,
                tooltip: '刷新',
                onPressed: () => _refreshTick.value++,
              ),
          ],
        ),
        drawer: _AppDrawer(
          track: _track,
          refreshTick: _refreshTick,
          onSwitchTrack: _switchTrack,
          onOpenPage: _openPage,
          onPush: _push,
        ),
        body: _AnimatedBody(index: _index, pages: _pages),
        bottomNavigationBar: _ArcNavBar(index: _index, onTap: _onTap),
        backgroundColor: p.canvas,
      ),
    );
  }
}

/// 切页动效：带方向的位移 + 缩放 + 淡入。
class _AnimatedBody extends StatefulWidget {
  final int index;
  final List<Widget> pages;

  const _AnimatedBody({required this.index, required this.pages});

  @override
  State<_AnimatedBody> createState() => _AnimatedBodyState();
}

class _AnimatedBodyState extends State<_AnimatedBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    value: 1,
  );
  bool _forward = true;

  @override
  void didUpdateWidget(covariant _AnimatedBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      _forward = widget.index >= oldWidget.index;
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 注意：不要给动画容器加 ValueKey(index)。
    // 加了会导致每次切页重建整棵 IndexedStack，页面状态（聊天记录、草稿）全丢。
    return AnimatedBuilder(
      animation: _c,
      builder: (BuildContext context, Widget? child) {
        final double t = Curves.easeOutCubic.transform(_c.value);
        return Transform.translate(
          offset: Offset((_forward ? 1 : -1) * 26 * (1 - t), 0),
          child: Transform.scale(
            scale: 0.965 + 0.035 * t,
            child: Opacity(opacity: 0.35 + 0.65 * t, child: child),
          ),
        );
      },
      child: IndexedStack(index: widget.index, children: widget.pages),
    );
  }
}

/// 底部导航：浮着的圆角条，每个页签有自己的功能色和点击动效。
class _ArcNavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;

  const _ArcNavBar({required this.index, required this.onTap});

  static const double _radius = 24;

  static const List<IconData> _icons = <IconData>[
    Icons.article_outlined,
    Icons.book_outlined,
    Icons.error_outline,
    Icons.chat_bubble_outline,
  ];

  static const List<IconData> _iconsOn = <IconData>[
    Icons.article,
    Icons.book,
    Icons.error,
    Icons.chat_bubble,
  ];

  static const List<String> _labels = <String>['作文', '单词', '错词本', '问答'];

  static const List<TapFx> _fx = <TapFx>[
    TapFx.lift,
    TapFx.pop,
    TapFx.shake,
    TapFx.dots,
  ];

  @override
  Widget build(BuildContext context) {
    final ModulePalette p = ModulePalette.of(context);
    final double bottomInset = MediaQuery.paddingOf(context).bottom;
    return Container(
      color: p.canvas,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
        child: Material(
          color: p.surface,
          borderRadius: BorderRadius.circular(_radius),
          clipBehavior: Clip.antiAlias,
          elevation: 2,
          shadowColor: p.ink.withValues(alpha: 0.12),
          child: SizedBox(
            height: 62,
            child: Row(
              children: List<Widget>.generate(4, (int i) {
                final bool on = i == index;
                return Expanded(
                  child: _NavItem(
                    icon: on ? _iconsOn[i] : _icons[i],
                    label: _labels[i],
                    color: p.tab(i),
                    selected: on,
                    fx: _fx[i],
                    onTap: () => onTap(i),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool selected;
  final TapFx fx;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.selected,
    required this.fx,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ModulePalette p = ModulePalette.of(context);
    return FxTap(
      fx: fx,
      onTap: onTap,
      radius: BorderRadius.circular(18),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
            decoration: BoxDecoration(
              color: selected
                  ? color.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 21, color: selected ? color : p.muted),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? color : p.muted,
            ),
          ),
        ],
      ),
    );
  }
}

/// 给抽屉里打开的页面套个 AppBar
class _StandalonePage extends StatelessWidget {
  const _StandalonePage({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: child,
    );
  }
}

/// 侧边抽屉：按用途分成四块，不再是一条长列表。
class _AppDrawer extends StatelessWidget {
  const _AppDrawer({
    required this.track,
    required this.refreshTick,
    required this.onSwitchTrack,
    required this.onOpenPage,
    required this.onPush,
  });

  final String track;
  final ValueNotifier<int> refreshTick;
  final Future<void> Function(String) onSwitchTrack;
  final Future<void> Function(Widget, String) onOpenPage;
  final Future<void> Function(Widget) onPush;

  @override
  Widget build(BuildContext context) {
    final ModulePalette p = ModulePalette.of(context);

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
          children: <Widget>[
            // 头部不再是黑色大块：只留名字和当前赛道
            Text(
              'dash',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: p.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              TrackStore.labelOf(track),
              style: TextStyle(fontSize: 12, color: p.muted),
            ),
            const SizedBox(height: 22),

            _Section(
              title: '学习',
              children: <Widget>[
                _DrawerRow(
                  icon: Icons.add_circle_outline,
                  label: '添加单词',
                  color: p.green,
                  fx: TapFx.pop,
                  divider: true,
                  onTap: () {
                    Navigator.of(context).pop();
                    onOpenPage(AddWordPage(refreshTick: refreshTick), '添加单词');
                  },
                ),
                _DrawerRow(
                  icon: Icons.bar_chart_outlined,
                  label: '统计',
                  color: p.violet,
                  fx: TapFx.lift,
                  divider: true,
                  onTap: () {
                    Navigator.of(context).pop();
                    onOpenPage(StatsPage(refreshTick: refreshTick), '统计');
                  },
                ),
                _DrawerRow(
                  icon: Icons.psychology_outlined,
                  label: '错词复盘',
                  color: p.blue,
                  fx: TapFx.pulse,
                  onTap: () {
                    Navigator.of(context).pop();
                    ChatFocus.openDigest();
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),

            _Section(
              title: '内容与数据',
              children: <Widget>[
                _DrawerRow(
                  icon: Icons.sticky_note_2_outlined,
                  label: '批注本',
                  color: p.amber,
                  fx: TapFx.pop,
                  divider: true,
                  onTap: () {
                    Navigator.of(context).pop();
                    onPush(const EssayNotesPage());
                  },
                ),
                _DrawerRow(
                  icon: Icons.ios_share_outlined,
                  label: '导出词表',
                  color: p.amber,
                  fx: TapFx.lift,
                  divider: true,
                  onTap: () {
                    Navigator.of(context).pop();
                    showExportSheet(context);
                  },
                ),
                _DrawerRow(
                  icon: Icons.file_open_outlined,
                  label: '批量导入',
                  color: p.orange,
                  fx: TapFx.slideRight,
                  divider: true,
                  onTap: () {
                    Navigator.of(context).pop();
                    onPush(ImportPage(refreshTick: refreshTick));
                  },
                ),
                _DrawerRow(
                  icon: Icons.local_fire_department_outlined,
                  label: '打卡记录',
                  color: p.wrong,
                  fx: TapFx.wave,
                  onTap: () async {
                    Navigator.of(context).pop();
                    onPush(const CheckinRecordsPage());
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),

            _Section(
              title: '偏好',
              children: <Widget>[
                _FieldBlock(
                  label: '分区',
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: TrackStore.tracks
                        .map(
                          (Track t) => _Pill(
                            label: t.label,
                            selected: t.id == track,
                            color: p.blue,
                            onTap: () => onSwitchTrack(t.id),
                          ),
                        )
                        .toList(),
                  ),
                ),
                const Divider(indent: 16, endIndent: 16),
                _DrawerRow(
                  icon: Icons.folder_outlined,
                  label: '管理分区',
                  color: p.blue,
                  fx: TapFx.lift,
                  divider: true,
                  onTap: () {
                    Navigator.of(context).pop();
                    onPush(const SectionsPage());
                  },
                ),
                _DrawerRow(
                  icon: Icons.settings_outlined,
                  label: '设置',
                  color: p.muted,
                  fx: TapFx.gear,
                  onTap: () {
                    Navigator.of(context).pop();
                    onPush(const SettingsPage());
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 抽屉里的一块：小标题 + 一张圆角面板
class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final ModulePalette p = ModulePalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.6,
              color: p.muted,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ],
    );
  }
}

/// 一行入口：彩色图标 + 文字 + 箭头，行高 52。
/// 图标直接用彩色线条，不加底色块——微信就是这么做的，
/// 一屏幕十来个色块反而比十来个彩色图标更吵。
class _DrawerRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final TapFx fx;
  final VoidCallback onTap;
  final bool divider;

  const _DrawerRow({
    required this.icon,
    required this.label,
    required this.color,
    required this.fx,
    required this.onTap,
    this.divider = false,
  });

  @override
  Widget build(BuildContext context) {
    final ModulePalette p = ModulePalette.of(context);
    return Column(
      children: <Widget>[
        FxTap(
          fx: fx,
          onTap: onTap,
          radius: BorderRadius.zero,
          child: SizedBox(
            height: 52,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: <Widget>[
                  Icon(icon, size: 21, color: color),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(fontSize: 15, color: p.ink),
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 17, color: p.line),
                ],
              ),
            ),
          ),
        ),
        if (divider) Divider(indent: 51, endIndent: 16, color: p.line),
      ],
    );
  }
}

/// 卡片里的一段：小标签 + 内容（胶囊组）
class _FieldBlock extends StatelessWidget {
  final String label;
  final Widget child;

  const _FieldBlock({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    final ModulePalette p = ModulePalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: TextStyle(fontSize: 11, color: p.muted)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

/// 抽屉里的选择胶囊
class _Pill extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _Pill({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ModulePalette p = ModulePalette.of(context);
    return FxTap(
      fx: TapFx.pop,
      onTap: onTap,
      radius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color.withValues(alpha: 0.55) : p.line,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? color : p.muted,
            fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

/// 首启入口：先打卡，打完卡进主界面
class _EntryPoint extends StatelessWidget {
  const _EntryPoint();

  @override
  Widget build(BuildContext context) {
    return CheckInPage(
      onEnter: () {
        Navigator.of(context)
            .pushReplacement(SmoothRoute<Object?>(page: const HomePage()));
      },
    );
  }
}
