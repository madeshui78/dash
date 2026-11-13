// 统计页：总量、已掌握、待复习、今日复习情况

import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../services/track_store.dart';

class StatsPage extends StatefulWidget {
  final ValueNotifier<int>? refreshTick;

  const StatsPage({super.key, this.refreshTick});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  late Future<Map<String, int>> _future;

  @override
  void initState() {
    super.initState();
    _future = DatabaseHelper.instance.getStats(track: TrackStore.current.value);
    widget.refreshTick?.addListener(_reload);
  }

  void _reload() {
    setState(() {
      _future =
          DatabaseHelper.instance.getStats(track: TrackStore.current.value);
    });
  }

  @override
  void dispose() {
    widget.refreshTick?.removeListener(_reload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, int>>(
      future: _future,
      builder: (BuildContext context, AsyncSnapshot<Map<String, int>> snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('出错了：${snap.error}'));
        }

        final Map<String, int> s = snap.data!;
        final int total = s['total'] ?? 0;
        final int mastered = s['mastered'] ?? 0;
        final int due = s['due'] ?? 0;
        final int todayReviews = s['todayReviews'] ?? 0;
        final int todayCorrect = s['todayCorrect'] ?? 0;
        final double rate = todayReviews == 0 ? 0 : todayCorrect / todayReviews;

        return RefreshIndicator(
          onRefresh: () async {
            setState(() {
              _future = DatabaseHelper.instance
                  .getStats(track: TrackStore.current.value);
            });
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(child: _statCard('总单词', '$total', Icons.book_outlined, Colors.teal)),
                  const SizedBox(width: 12),
                  Expanded(child: _statCard('已掌握', '$mastered', Icons.check_circle_outline, Colors.green)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(child: _statCard('待复习', '$due', Icons.schedule_outlined, Colors.orange)),
                  const SizedBox(width: 12),
                  Expanded(child: _statCard('今日复习', '$todayReviews', Icons.today_outlined, Colors.blue)),
                ],
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text('今日正确率',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: rate,
                        minHeight: 10,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$todayCorrect / $todayReviews  '
                        '(${(rate * 100).round()}%)',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (total > 0) ...<Widget>[
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text('掌握进度',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 12),
                        LinearProgressIndicator(
                          value: mastered / total,
                          minHeight: 10,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$mastered / $total',
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 10),
            Text(value,
                style: TextStyle(
                    fontSize: 26, fontWeight: FontWeight.w500, color: cs.onSurface)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 12, color: cs.outline)),
          ],
        ),
      ),
    );
  }
}
