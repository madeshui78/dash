// 按钮点下去的那一下动画。
//
// 四个页签各用不同的动作：
//   作文 —— 换一篇：整圈翻转（像翻页）
//   单词 —— 开始学习：书页对折（Y 轴翻）
//   错词本 —— 复测：脉冲放大（强调）
//   问答 —— 发送：纸飞机飞出去再飞回来（单独实现，见 chat_page）
//
// 都只跑一次，跑完回到静止状态，不搞一直转的装饰动画。

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/module_palette.dart';

enum MotionKind {
  /// 整圈翻转，用于刷新/换一篇
  spin,

  /// Y 轴对折，像翻书
  flip,

  /// 放大回弹
  pulse,
}

class MotionButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final MotionKind kind;
  final VoidCallback? onPressed;

  /// true = 实心按钮，false = 描边按钮
  final bool filled;

  /// 主按钮的功能色，不传就用主题主色
  final Color? color;

  const MotionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.kind,
    required this.onPressed,
    this.filled = true,
    this.color,
  });

  @override
  State<MotionButton> createState() => _MotionButtonState();
}

class _MotionButtonState extends State<MotionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _tap() {
    _c.forward(from: 0).whenComplete(() {
      if (mounted) _c.value = 0;
    });
    widget.onPressed?.call();
  }

  @override
  Widget build(BuildContext context) {
    final Widget icon = AnimatedBuilder(
      animation: _c,
      builder: (BuildContext context, Widget? child) {
        final double t = Curves.easeInOutCubic.transform(_c.value);
        switch (widget.kind) {
          case MotionKind.spin:
            return Transform.rotate(angle: 2 * math.pi * t, child: child);
          case MotionKind.flip:
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0015)
                ..rotateY(math.pi * t),
              child: child,
            );
          case MotionKind.pulse:
            final double s = 1 + 0.45 * math.sin(math.pi * t);
            return Transform.scale(scale: s, child: child);
        }
      },
      child: Icon(widget.icon),
    );

    if (widget.filled) {
      return FilledButton.icon(
        onPressed: widget.onPressed == null ? null : _tap,
        icon: icon,
        label: Text(widget.label),
        style: widget.color == null
            ? null
            : FilledButton.styleFrom(
                backgroundColor: widget.color,
                foregroundColor: ModulePalette.onAccent(widget.color!),
              ),
      );
    }
    return OutlinedButton.icon(
      onPressed: widget.onPressed == null ? null : _tap,
      icon: icon,
      label: Text(widget.label),
      style: widget.color == null
          ? null
          : OutlinedButton.styleFrom(
              foregroundColor: widget.color,
              side: BorderSide(color: widget.color!.withValues(alpha: 0.45)),
            ),
    );
  }
}
