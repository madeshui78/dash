// 打卡记录：一个月历 + 最近打卡，不再只弹一句 toast。

import 'package:flutter/material.dart';

import '../services/checkin_store.dart';
import '../theme/module_palette.dart';

class CheckinRecordsPage extends StatefulWidget {
  const CheckinRecordsPage({super.key});

  @override
  State<CheckinRecordsPage> createState() => _CheckinRecordsPageState();
}

class _CheckinRecordsPageState extends State<CheckinRecordsPage> {
  bool _loading = true;
  Set<String> _days = <String>{};
  Set<int> _monthDays = <int>{};
  int _streak = 0;

  static const List<String> _week = <String>['一', '二', '三', '四', '五', '六', '日'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final Set<String> days = await CheckInStore.all();
    final Set<int> md = await CheckInStore.monthDays(DateTime.now());
    final int streak = await CheckInStore.streak();
    if (!mounted) return;
    setState(() {
      _days = days;
      _monthDays = md;
      _streak = streak;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ModulePalette p = ModulePalette.of(context);
    final DateTime now = DateTime.now();

    return Scaffold(
      backgroundColor: p.canvas,
      appBar: AppBar(title: const Text('打卡记录')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: <Widget>[
                _summary(p),
                const SizedBox(height: 14),
                _calendar(p, now),
                const SizedBox(height: 18),
                Text(
                  '最近打卡',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: p.muted,
                  ),
                ),
                const SizedBox(height: 8),
                if (_days.isEmpty)
                  Text(
                    '还没有打卡记录，回到首页点一下按钮开始。',
                    style: TextStyle(fontSize: 13, color: p.muted),
                  )
                else
                  ..._recent(p),
              ],
            ),
    );
  }

  Widget _summary(ModulePalette p) {
    Widget cell(String value, String label) {
      return Expanded(
        child: Column(
          children: <Widget>[
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: p.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 11, color: p.muted)),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.line),
      ),
      child: Row(
        children: <Widget>[
          cell('$_streak', '连续天数'),
          Container(width: 1, height: 30, color: p.line),
          cell('${_monthDays.length}', '本月打卡'),
          Container(width: 1, height: 30, color: p.line),
          cell('${_days.length}', '累计天数'),
        ],
      ),
    );
  }

  Widget _calendar(ModulePalette p, DateTime now) {
    final int daysInMonth = DateUtils.getDaysInMonth(now.year, now.month);
    final DateTime first = DateTime(now.year, now.month, 1);
    final int leading = first.weekday - 1; // 周一开头
    final int cells = leading + daysInMonth;
    final int rows = (cells / 7).ceil();

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.line),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                '${now.year} 年 ${now.month} 月',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: p.ink,
                ),
              ),
              const Spacer(),
              Text(
                '本月 ${_monthDays.length} 天',
                style: TextStyle(fontSize: 11, color: p.muted),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              for (final String w in _week)
                Expanded(
                  child: Center(
                    child: Text(
                      w,
                      style: TextStyle(fontSize: 10.5, color: p.muted),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (int r = 0; r < rows; r++)
            Row(
              children: <Widget>[
                for (int c = 0; c < 7; c++)
                  Expanded(
                    child: _dayCell(p, r * 7 + c - leading + 1, daysInMonth),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _dayCell(ModulePalette p, int day, int daysInMonth) {
    if (day < 1 || day > daysInMonth) {
      return const SizedBox(height: 38);
    }
    final DateTime now = DateTime.now();
    final bool on = _monthDays.contains(day);
    final bool today = day == now.day;

    return SizedBox(
      height: 38,
      child: Center(
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? p.wrong.withValues(alpha: 0.12) : Colors.transparent,
            shape: BoxShape.circle,
            border: today && !on
                ? Border.all(color: p.line)
                : (today ? Border.all(color: p.wrong, width: 1.2) : null),
          ),
          child: Text(
            '$day',
            style: TextStyle(
              fontSize: 12,
              fontWeight: on ? FontWeight.w600 : FontWeight.w400,
              color: on ? p.wrong : (today ? p.ink : p.muted),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _recent(ModulePalette p) {
    final List<String> sorted = _days.toList()..sort((String a, String b) => b.compareTo(a));
    final List<String> recent = sorted.take(14).toList();

    return <Widget>[
      Container(
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: p.line),
        ),
        child: Column(
          children: <Widget>[
            for (int i = 0; i < recent.length; i++) ...<Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.check_circle, size: 16, color: p.green),
                    const SizedBox(width: 10),
                    Text(
                      recent[i],
                      style: TextStyle(fontSize: 13, color: p.ink),
                    ),
                    const Spacer(),
                    Text(
                      _weekLabel(recent[i]),
                      style: TextStyle(fontSize: 11, color: p.muted),
                    ),
                  ],
                ),
              ),
              if (i != recent.length - 1)
                Divider(height: 1, indent: 40, color: p.line),
            ],
          ],
        ),
      ),
    ];
  }

  String _weekLabel(String day) {
    final DateTime? d = DateTime.tryParse(day);
    if (d == null) return '';
    const List<String> names = <String>['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return names[d.weekday - 1];
  }
}
