// 记忆图谱卡片：挂在错词复盘那条 AI 回复下面。
// 结构很简单——中心是这次复盘，往下分几组词，最后是三步学习路线。
// 不用图表库，纯布局 + 连接线，小屏也读得清。

import 'package:flutter/material.dart';

import '../models/memory_graph.dart';
import '../theme/module_palette.dart';

class MemoryGraphCard extends StatelessWidget {
  final MemoryGraph graph;

  const MemoryGraphCard({super.key, required this.graph});

  @override
  Widget build(BuildContext context) {
    final ModulePalette p = ModulePalette.of(context);
    if (graph.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.blue.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.hub_outlined, size: 15, color: p.blue),
              ),
              const SizedBox(width: 8),
              Text(
                '记忆图谱',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: p.ink,
                ),
              ),
              const Spacer(),
              Text(
                '${graph.wordCount} 个词',
                style: TextStyle(fontSize: 11, color: p.muted),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (int i = 0; i < graph.groups.length; i++)
            _GroupRow(
              group: graph.groups[i],
              color: _colors(p)[i % _colors(p).length],
              last: i == graph.groups.length - 1,
            ),
          if (graph.path.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: p.blue.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '学习路线',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: p.blue,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (int i = 0; i < graph.path.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Container(
                            width: 16,
                            height: 16,
                            margin: const EdgeInsets.only(top: 1, right: 8),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: p.blue,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '${i + 1}',
                              style: const TextStyle(
                                fontSize: 9,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              graph.path[i],
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.45,
                                color: p.ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Color> _colors(ModulePalette p) => <Color>[
    p.blue,
    p.violet,
    p.green,
    p.orange,
    p.amber,
  ];
}

class _GroupRow extends StatelessWidget {
  final MemoryGroup group;
  final Color color;
  final bool last;

  const _GroupRow({
    required this.group,
    required this.color,
    required this.last,
  });

  @override
  Widget build(BuildContext context) {
    final ModulePalette p = ModulePalette.of(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            width: 18,
            child: Column(
              children: <Widget>[
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 12),
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!last)
                  Expanded(child: Container(width: 1.5, color: p.line)),
              ],
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              decoration: BoxDecoration(
                color: p.surfaceAlt,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    group.title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  if (group.words.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: group.words
                          .map(
                            (String w) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: p.surface,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                w,
                                style: TextStyle(fontSize: 12, color: p.ink),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                  if (group.tip.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 6),
                    Text(
                      group.tip,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.45,
                        color: p.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
