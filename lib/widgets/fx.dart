// 点击动效库：每个按钮给一种，不重样。
//
// 做法统一：按下时跑一次 420ms 动画，跑完回到原样。
// 不做一直循环的装饰动画——那会让人分心，也费电。
//
// 分配（见各页）：
//   侧边栏   三横线 → 依次错开滑一下
//   刷新     → 整圈
//   返回     → 向左滑出
//   月份箭头 → 左/右滑
//   朗读     → 声波式双脉冲
//   标记     → 笔尖倾斜
//   释义     → 上下轻点
//   译文     → Y 轴翻面
//   更多     → 三个点依次跳
//   导出     → 向上抬起
//   删除/清空 → 左右抖动
//   关闭     → 交叉旋转
//   设置     → 齿轮转
//   展开     → 弹一下

import 'dart:math' as math;

import 'package:flutter/material.dart';

enum TapFx {
  spin,
  flipY,
  pulse,
  shake,
  slideLeft,
  slideRight,
  pop,
  tilt,
  wave,
  dots,
  sweep,
  gear,
  lift,
  close,
}

/// 按时间 t（0~1）给图标套一层变换
Widget applyFx(TapFx fx, double t, Widget child) {
  final double w = math.sin(math.pi * t);
  switch (fx) {
    case TapFx.spin:
      return Transform.rotate(angle: 2 * math.pi * t, child: child);
    case TapFx.flipY:
      return Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0014)
          ..rotateY(math.pi * t),
        child: child,
      );
    case TapFx.pulse:
      return Transform.scale(scale: 1 + 0.42 * w, child: child);
    case TapFx.shake:
      return Transform.translate(
        offset: Offset(4.5 * math.sin(6 * math.pi * t) * (1 - t * 0.6), 0),
        child: child,
      );
    case TapFx.slideLeft:
      return Transform.translate(offset: Offset(-8 * w, 0), child: child);
    case TapFx.slideRight:
      return Transform.translate(offset: Offset(8 * w, 0), child: child);
    case TapFx.pop:
      return Transform.scale(scale: 1 + 0.28 * w, child: child);
    case TapFx.tilt:
      return Transform.rotate(angle: -0.38 * w, child: child);
    case TapFx.wave:
      // 两下脉冲，像声波
      return Transform.scale(scale: 1 + 0.3 * math.sin(2 * math.pi * t).abs(), child: child);
    case TapFx.dots:
      return Transform.translate(
        offset: Offset(0, -5 * math.sin(2 * math.pi * t).abs()),
        child: child,
      );
    case TapFx.sweep:
      return Transform.translate(
        offset: Offset(5 * w, 0),
        child: Transform.rotate(angle: 0.5 * w, child: child),
      );
    case TapFx.gear:
      return Transform.rotate(angle: 1.6 * math.pi * t, child: child);
    case TapFx.lift:
      return Transform.translate(
        offset: Offset(0, -6 * w),
        child: Transform.scale(scale: 1 + 0.08 * w, child: child),
      );
    case TapFx.close:
      return Transform.rotate(
        angle: math.pi * 0.5 * t,
        child: Transform.scale(scale: 1 + 0.18 * w, child: child),
      );
  }
}

/// 带点击动效的图标按钮。样式尽量贴主题，不额外加装饰。
class FxIconButton extends StatefulWidget {
  final IconData icon;
  final TapFx fx;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final Color? color;
  final bool compact;

  const FxIconButton({
    super.key,
    required this.icon,
    required this.fx,
    required this.onPressed,
    this.tooltip,
    this.size = 22,
    this.color,
    this.compact = true,
  });

  @override
  State<FxIconButton> createState() => _FxIconButtonState();
}

class _FxIconButtonState extends State<FxIconButton>
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
      // 动画跑完回到 0：flipY / gear 这类终点不是原位的效果
      // 如果不复位，图标会一直歪着或镜像着。
      if (mounted) _c.value = 0;
    });
    widget.onPressed?.call();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: widget.tooltip,
      visualDensity: widget.compact ? VisualDensity.compact : null,
      onPressed: widget.onPressed == null ? null : _tap,
      icon: AnimatedBuilder(
        animation: _c,
        builder: (BuildContext context, Widget? child) =>
            applyFx(widget.fx, _c.value, child!),
        child: Icon(
          widget.icon,
          size: widget.size,
          color: widget.color ?? Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 给任意可点区域套一个动效：子控件自己不动，整块跟着变换。
class FxTap extends StatefulWidget {
  final Widget child;
  final TapFx fx;
  final VoidCallback? onTap;
  final BorderRadius? radius;

  const FxTap({
    super.key,
    required this.child,
    required this.fx,
    this.onTap,
    this.radius,
  });

  @override
  State<FxTap> createState() => _FxTapState();
}

class _FxTapState extends State<FxTap> with SingleTickerProviderStateMixin {
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
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: widget.onTap == null ? null : _tap,
      borderRadius: widget.radius ?? BorderRadius.circular(12),
      child: AnimatedBuilder(
        animation: _c,
        builder: (BuildContext context, Widget? child) =>
            applyFx(widget.fx, _c.value, child!),
        child: widget.child,
      ),
    );
  }
}
