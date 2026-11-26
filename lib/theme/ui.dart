// 全局视觉尺度。目的只有一个：同一类东西在各页面长得一样。
//
// 三档圆角：
//   卡片 / 弹层 14
//   输入框 / 按钮 12
//   标签 / 小色块 8
//
// 一种主按钮高度：46
// 字号：11 说明、12.5 次要、14 正文、17 小标题、20 标题、28 展示

import 'package:flutter/material.dart';

class UiRadius {
  UiRadius._();

  static const double card = 14;
  static const double control = 12;
  static const double chip = 8;

  static BorderRadius cardAll = BorderRadius.circular(card);
  static BorderRadius controlAll = BorderRadius.circular(control);
  static BorderRadius chipAll = BorderRadius.circular(chip);
}

class UiSize {
  UiSize._();

  static const double button = 46;
  static const double field = 46;
}

class UiGap {
  UiGap._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 14;
  static const double lg = 20;
}

/// 字号只有这几档，新代码不要再写 12.5 / 13.5 这种中间值
class UiText {
  UiText._();

  /// 说明、脚注、标签
  static const double caption = 11;

  /// 次要信息：作者、日期、提示
  static const double secondary = 12;

  /// 正文偏小：列表标题、词条
  static const double bodySmall = 13;

  /// 正文
  static const double body = 14;

  /// 小节标题
  static const double section = 16;

  /// 页面标题
  static const double title = 18;
}
