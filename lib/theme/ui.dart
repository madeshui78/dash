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
