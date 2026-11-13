// 打开 App 的第一屏：日历 + 打卡。
//
// 整页只有三样东西：连续天数、这个月的打卡记录、一个按钮。

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/checkin_store.dart';
import '../theme/module_palette.dart';
import '../widgets/fx.dart';

class CheckInPage extends StatefulWidget {
  /// 打完卡进入主界面。由 main 传进来，避免这里反向 import 主壳。
  final VoidCallback onEnter;

  const CheckInPage({super.key, required this.onEnter});

  @override
  State<CheckInPage> createState() => _CheckInPageState();
}

class _CheckInPageState extends State<CheckInPage> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  bool _loading = true;
  bool _doneToday = false;
  int _streak = 0;
  Set<int> _checkedDays = <int>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bool done = await CheckInStore.doneToday();
    final int streak = await CheckInStore.streak();
    final Set<int> days = await CheckInStore.monthDays(_month);
    if (!mounted) return;
    setState(() {
      _doneToday = done;
      _streak = streak;
      _checkedDays = days;
      _loading = false;
    });
  }

  Future<void> _shiftMonth(int delta) async {
    final DateTime next = DateTime(_month.year, _month.month + delta);
    final Set<int> days = await CheckInStore.monthDays(next);
    if (!mounted) return;
    setState(() {
      _month = next;
      _checkedDays = days;
    });
  }

  Future<void> _checkIn() async {
    await CheckInStore.checkIn();
    if (!mounted) return;
    setState(() => _doneToday = true);
    widget.onEnter();
  }

  @override
  Widget build(BuildContext context) {
    final ModulePalette p = ModulePalette.of(context);
    final DateTime now = DateTime.now();
    final bool thisMonth =
        _month.year == now.year && _month.month == now.month;

    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
                children: <Widget>[
                  Text(
                    '$_streak',
                    style: TextStyle(
                      fontSize: 68,
                      height: 1.0,
                      fontWeight: FontWeight.w300,
                      color: p.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '天连续打卡',
                    style: TextStyle(fontSize: 12, color: p.muted),
                  ),
                  const SizedBox(height: 32),

                  Row(
                    children: <Widget>[
                      Text(
                        '${_month.year} 年 ${_month.month} 月',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: p.ink,
                        ),
                      ),
                      const Spacer(),
                      FxIconButton(
                        icon: Icons.chevron_left,
                        fx: TapFx.slideLeft,
                        size: 20,
                        color: p.muted,
                        onPressed: () => _shiftMonth(-1),
                      ),
                      FxIconButton(
                        icon: Icons.chevron_right,
                        fx: TapFx.slideRight,
                        size: 20,
                        color: p.muted,
                        onPressed: () => _shiftMonth(1),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _Calendar(
                    month: _month,
                    checked: _checkedDays,
                    today: thisMonth ? now.day : -1,
                  ),

                  const SizedBox(height: 36),
                  _CheckInButton(
                    label: _doneToday ? '进入学习' : '打卡',
                    color: p.essay,
                    onTap: _checkIn,
                  ),
                ],
              ),
      ),
    );
  }
}

/// 打卡按钮：按下去时对勾「盖」上来，同时整块轻压一下。
class _CheckInButton extends StatefulWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _CheckInButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  State<_CheckInButton> createState() => _CheckInButtonState();
}

class _CheckInButtonState extends State<_CheckInButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (BuildContext context, Widget? child) {
        final double press = math.sin(math.pi * _c.value);
        return Transform.scale(scale: 1 - 0.02 * press, child: child);
      },
      child: SizedBox(
        height: 50,
        child: Material(
          color: widget.color,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              _c.forward(from: 0);
              widget.onTap();
            },
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  AnimatedBuilder(
                    animation: _c,
                    builder: (BuildContext context, Widget? child) {
                      final double t = Curves.easeOutBack.transform(_c.value);
                      return Transform.rotate(
                        angle: (1 - t) * -0.8,
                        child: Transform.scale(
                          scale: t.clamp(0.0, 1.2),
                          child: child,
                        ),
                      );
                    },
                    child: Icon(
                      Icons.check,
                      size: 18,
                      color: ModulePalette.onAccent(widget.color)
                          .withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: ModulePalette.onAccent(widget.color),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 一个月的日期格
class _Calendar extends StatelessWidget {
  final DateTime month;
  final Set<int> checked;
  final int today;

  const _Calendar({
    required this.month,
    required this.checked,
    required this.today,
  });

  @override
  Widget build(BuildContext context) {
    final ModulePalette p = ModulePalette.of(context);
    final int daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final int firstWeekday = DateTime(month.year, month.month, 1).weekday;
    final int lead = firstWeekday - 1;

    return Column(
      children: <Widget>[
        Row(
          children: <String>['一', '二', '三', '四', '五', '六', '日']
              .map(
                (String d) => Expanded(
                  child: Center(
                    child: Text(
                      d,
                      style: TextStyle(fontSize: 11, color: p.muted),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1,
          children: <Widget>[
            for (int i = 0; i < lead; i++) const SizedBox.shrink(),
            for (int d = 1; d <= daysInMonth; d++)
              _DayCell(
                day: d,
                checked: checked.contains(d),
                isToday: d == today,
              ),
          ],
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  final int day;
  final bool checked;
  final bool isToday;

  const _DayCell({
    required this.day,
    required this.checked,
    required this.isToday,
  });

  @override
  Widget build(BuildContext context) {
    final ModulePalette p = ModulePalette.of(context);
    return Center(
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: checked ? p.essay : Colors.transparent,
          border: isToday && !checked
              ? Border.all(color: p.essay, width: 1.2)
              : null,
        ),
        child: Text(
          '$day',
          style: TextStyle(
            fontSize: 13,
            color: checked ? Colors.white : (isToday ? p.essay : p.ink),
            fontWeight: checked || isToday ? FontWeight.w500 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
