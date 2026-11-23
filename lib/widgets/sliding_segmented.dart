// 分段控件：选中态是一块独立的底板，切换时平滑滑到目标位置。
//
// 只适用于「同一行、等宽、2-4 个选项」的场景。
// 选项多到换行、或宽度差异很大时不要用，色块会跳得很难看。

import 'package:flutter/material.dart';

import '../theme/module_palette.dart';

class SlidingSegmented extends StatelessWidget {
  final int index;
  final List<Widget> children;
  final ValueChanged<int> onChanged;
  final double height;
  final double padding;
  final double radius;

  const SlidingSegmented({
    super.key,
    required this.index,
    required this.children,
    required this.onChanged,
    this.height = 38,
    this.padding = 3,
    this.radius = 10,
  });

  @override
  Widget build(BuildContext context) {
    final ModulePalette p = ModulePalette.of(context);
    final int count = children.length;
    if (count == 0) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final double segW = (c.maxWidth - padding * 2) / count;
        return Container(
          height: height,
          padding: EdgeInsets.all(padding),
          decoration: BoxDecoration(
            color: p.surfaceAlt,
            borderRadius: BorderRadius.circular(radius + padding),
          ),
          child: Stack(
            children: <Widget>[
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                left: segW * index,
                top: 0,
                width: segW,
                height: height - padding * 2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: p.surface,
                    borderRadius: BorderRadius.circular(radius),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.07),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: <Widget>[
                  for (int i = 0; i < count; i++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onChanged(i),
                        child: SizedBox(
                          height: height - padding * 2,
                          child: Center(child: children[i]),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
