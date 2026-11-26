// 全局统一的页面过渡。
//
// 安卓上 MaterialPageRoute 默认是"整页从底部推上来"，而底部导航切页是横向的——
// 两套动作混在一起，来回切会觉得很割裂。这里统一成同一手感的短过渡：
// 淡入 + 极轻微上浮 + 缩放，看着像在同一个层级里移动。
//
// 主页切 tab、抽屉里开页面、单词页进作文/复习，全走这一条，
// 不然同一款 App 里会有好几种"开门方式"。

import 'package:flutter/material.dart';

class SmoothRoute<T> extends PageRouteBuilder<T> {
  final Widget page;

  SmoothRoute({required this.page})
    : super(
        transitionDuration: const Duration(milliseconds: 280),
        reverseTransitionDuration: const Duration(milliseconds: 230),
        pageBuilder: (_, _, _) => page,
        transitionsBuilder:
            (
              BuildContext context,
              Animation<double> animation,
              Animation<double> secondaryAnimation,
              Widget child,
            ) {
              final CurvedAnimation curve = CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              );
              return FadeTransition(
                opacity: curve,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.035),
                    end: Offset.zero,
                  ).animate(curve),
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.985, end: 1.0).animate(curve),
                    child: child,
                  ),
                ),
              );
            },
      );
}
