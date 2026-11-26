// 轻提示：替代 SnackBar。
//
// 为什么要自己写：SnackBar 只能向下滑走，停留 4 秒，还是黑底。
// 这里改成 1.8 秒自动消失，向左一划就走，颜色跟应用一致。

import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/module_palette.dart';

class AppToast {
  AppToast._();

  static OverlayEntry? _entry;

  static void show(
    BuildContext context,
    String message, {
    Duration duration = const Duration(milliseconds: 1800),
  }) {
    dismiss();
    final OverlayState overlay = Overlay.of(context, rootOverlay: true);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (BuildContext ctx) => _ToastHost(
        message: message,
        duration: duration,
        onDone: () {
          if (_entry == entry) _entry = null;
          if (entry.mounted) entry.remove();
        },
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }

  static void dismiss() {
    _entry?.remove();
    _entry = null;
  }
}

class _ToastHost extends StatefulWidget {
  final String message;
  final Duration duration;
  final VoidCallback onDone;

  const _ToastHost({
    required this.message,
    required this.duration,
    required this.onDone,
  });

  @override
  State<_ToastHost> createState() => _ToastHostState();
}

class _ToastHostState extends State<_ToastHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );
  Timer? _timer;
  double _dx = 0;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _c.forward();
    _timer = Timer(widget.duration, _close);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    _timer?.cancel();
    await _c.reverse();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final ModulePalette p = ModulePalette.of(context);
    final double bottom = 92 + MediaQuery.paddingOf(context).bottom;

    return Positioned(
      left: 24,
      right: 24,
      bottom: bottom,
      child: GestureDetector(
        onHorizontalDragUpdate: (DragUpdateDetails d) {
          if (d.delta.dx < 0) setState(() => _dx += d.delta.dx);
        },
        onHorizontalDragEnd: (DragEndDetails d) {
          // 向左划超过 48 就关掉
          if (_dx < -48 ||
              d.primaryVelocity != null && d.primaryVelocity! < -250) {
            _close();
          } else {
            setState(() => _dx = 0);
          }
        },
        child: AnimatedSlide(
          offset: Offset(_dx / 240, 0),
          duration: const Duration(milliseconds: 120),
          child: FadeTransition(
            opacity: _c,
            child: Material(
              color: p.brightness == Brightness.dark
                  ? p.surfaceAlt
                  : const Color(0xFF1F2430),
              borderRadius: BorderRadius.circular(14),
              elevation: 6,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                child: Text(
                  widget.message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
