// 打开「问答」页时的信号。
// 错词复盘要等用户真正切到这一页才触发，不能应用一启动就发请求。

import 'package:flutter/foundation.dart';

class ChatFocus {
  ChatFocus._();

  static final ValueNotifier<int> tick = ValueNotifier<int>(0);

  /// 0 = 普通对话，1 = 错词复盘；-1 表示没有请求
  static final ValueNotifier<int> mode = ValueNotifier<int>(-1);

  static void open() => tick.value++;

  static void openDigest() => mode.value = 1;
}
