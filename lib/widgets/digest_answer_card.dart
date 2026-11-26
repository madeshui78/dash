// 复盘结果的卡片：分组概览 + 逐词纠错 + 三步路线。
// 每个词占一行，行上挂了 GlobalKey，右侧目录点击时可以 ensureVisible。

import 'package:flutter/material.dart';

import '../models/digest_result.dart';
import '../theme/module_palette.dart';

class DigestAnswerCard extends StatelessWidget {
  final DigestResult result;

  /// 第 index 个词对应行的 key
  final GlobalKey Function(int index) keyAt;

  /// 点某一行（看详情 / 发音）
  final void Function(DigestItem item)? onItemTap;

  const DigestAnswerCard({
    super.key,
    required this.result,
    required this.keyAt,
    this.onItemTap,
  });

  @override
  Widget build(BuildContext context) {
    final ModulePalette p = ModulePalette.of(context);
    final Map<String, Color> groupColors = <String, Color>{};
    final List<Color> palette = <Color>[
      p.blue,
      p.violet,
      p.green,
      p.orange,
      p.amber,
    ];
    for (int i = 0; i < result.groups.length; i++) {
      groupColors[result.groups[i].title] = palette[i % palette.length];
    }

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
              Icon(Icons.psychology_outlined, size: 18, color: p.blue),
              const SizedBox(width: 6),
              Text(
                '错词复盘',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: p.ink,
                ),
              ),
              const Spacer(),
              Text(
                '${result.items.length} 个词',
                style: TextStyle(fontSize: 11, color: p.muted),
              ),
            ],
          ),
          if (result.groups.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: result.groups
                  .map(
                    (DigestGroup g) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: (groupColors[g.title] ?? p.blue).withValues(
                          alpha: 0.10,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${g.title} ${g.words.length}',
                        style: TextStyle(
                          fontSize: 11,
                          color: groupColors[g.title] ?? p.blue,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 10),
          Divider(color: p.line, height: 1),
          for (int i = 0; i < result.items.length; i++)
            InkWell(
              key: keyAt(i),
              borderRadius: BorderRadius.circular(8),
              onTap: onItemTap == null
                  ? null
                  : () => onItemTap!(result.items[i]),
              child: Container(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Container(
                          width: 3,
                          height: 16,
                          margin: const EdgeInsets.only(top: 2, right: 8),
                          decoration: BoxDecoration(
                            color: groupColors[result.items[i].group] ?? p.blue,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Text(
                                    result.items[i].word,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: p.ink,
                                    ),
                                  ),
                                  if (result
                                      .items[i]
                                      .group
                                      .isNotEmpty) ...<Widget>[
                                    const SizedBox(width: 6),
                                    Text(
                                      result.items[i].group,
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        color: p.muted,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              if (result.items[i].meaning.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    result.items[i].meaning,
                                    style: TextStyle(
                                      fontSize: 13,
                                      height: 1.45,
                                      color: p.ink,
                                    ),
                                  ),
                                ),
                              if (result.items[i].memory.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    result.items[i].memory,
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.45,
                                      color: p.muted,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (result.path.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
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
                  const SizedBox(height: 6),
                  for (int i = 0; i < result.path.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '${i + 1}. ',
                            style: TextStyle(
                              fontSize: 12,
                              color: p.blue,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              result.path[i],
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
}
