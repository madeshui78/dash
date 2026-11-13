// 全局配色：一套中性底色 + 四个功能色。
//
// 规则只有三条：
//   1. 所有页面的底色是同一个 canvas，不再一会儿纯白一会儿纯黑；
//   2. 四个模块各有一个固定的功能色，只出现在本模块的图标和主按钮上；
//   3. 红色只表示「错 / 标记」，不拿来装饰。
//
// 之前主色是纯黑（ink），所有 FilledButton 都是黑块，
// 配上白底就是一块黑一块白——这就是"配色乱"的来源。现在主色换成墨绿，
// 黑色只留给正文。

import 'package:flutter/material.dart';

class ModulePalette {
  final Brightness brightness;

  /// 页面底色（所有页统一）
  final Color canvas;

  /// 卡片 / 浮层
  final Color surface;

  /// 次级底（分组、输入框内衬）
  final Color surfaceAlt;

  final Color ink;
  final Color muted;
  final Color line;

  /// 作文：墨绿
  final Color essay;

  /// 单词：靛蓝
  final Color word;

  /// 错词本：砖红
  final Color wrong;

  /// 问答：中性灰蓝
  final Color chat;

  /// 图标用的辅助色。只上在图标上，不做大面积底色。
  final Color green;
  final Color blue;
  final Color orange;
  final Color violet;
  final Color amber;

  const ModulePalette({
    required this.brightness,
    required this.canvas,
    required this.surface,
    required this.surfaceAlt,
    required this.ink,
    required this.muted,
    required this.line,
    required this.essay,
    required this.word,
    required this.wrong,
    required this.chat,
    required this.green,
    required this.blue,
    required this.orange,
    required this.violet,
    required this.amber,
  });

  static const ModulePalette light = ModulePalette(
    brightness: Brightness.light,
    canvas: Color(0xFFF5F7FB),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFEDF0F6),
    ink: Color(0xFF101828),
    muted: Color(0xFF667085),
    line: Color(0xFFD8DEE9),
    essay: Color(0xFF2E76F2),
    word: Color(0xFF5B2FF5),
    wrong: Color(0xFFD14B3D),
    chat: Color(0xFF475467),
    green: Color(0xFF2FA36B),
    blue: Color(0xFF2E76F2),
    orange: Color(0xFFF07A2B),
    violet: Color(0xFF7A4BE0),
    amber: Color(0xFFD99A16),
  );

  static const ModulePalette dark = ModulePalette(
    brightness: Brightness.dark,
    canvas: Color(0xFF0B1020),
    surface: Color(0xFF141A2A),
    surfaceAlt: Color(0xFF1D2436),
    ink: Color(0xFFECEEF5),
    muted: Color(0xFF98A2B3),
    line: Color(0xFF2A3247),
    essay: Color(0xFF7FA8FF),
    word: Color(0xFFA98CFF),
    wrong: Color(0xFFFF9B8F),
    chat: Color(0xFFB3BCCB),
    green: Color(0xFF6FD3A3),
    blue: Color(0xFF7FA8FF),
    orange: Color(0xFFFFA366),
    violet: Color(0xFFC0A6FF),
    amber: Color(0xFFFFC94D),
  );

  static ModulePalette of(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? dark : light;
  }

  /// 功能色上的文字色：深底用白、浅底用墨。
  /// 深色模式下功能色是浅的，再用白字就看不清了。
  static Color onAccent(Color c) {
    return ThemeData.estimateBrightnessForColor(c) == Brightness.dark
        ? Colors.white
        : const Color(0xFF161616);
  }

  /// 底部四个页签对应的功能色
  Color tab(int index) {
    switch (index) {
      case 0:
        return essay;
      case 1:
        return word;
      case 2:
        return wrong;
      default:
        return chat;
    }
  }
}
