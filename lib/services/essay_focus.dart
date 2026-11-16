// 页面之间传「跳到哪篇作文的哪个位置」。
//
// 错词本点一条标记 → 这里放一个请求 → 主壳切到作文页 →
// 作文页读到请求后加载那篇、滚到那一段。

import 'package:flutter/foundation.dart';

class EssayFocusRequest {
  final String essayId;

  /// 要突出显示的词/短语
  final String word;

  /// 第几段
  final int para;

  /// 从批注本跳过来时，顺手把这个词也标红
  final bool markOnOpen;

  const EssayFocusRequest({
    required this.essayId,
    required this.word,
    required this.para,
    this.markOnOpen = false,
  });
}

class EssayFocus {
  EssayFocus._();

  static final ValueNotifier<EssayFocusRequest?> request =
      ValueNotifier<EssayFocusRequest?>(null);

  /// 从别的页面点「去原文」时，让主壳切到作文页签
  static final ValueNotifier<bool> switchToEssay = ValueNotifier<bool>(false);

  static void go(EssayFocusRequest r) {
    request.value = r;
  }

  static void clear() {
    request.value = null;
  }
}
