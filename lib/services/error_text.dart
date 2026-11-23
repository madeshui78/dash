// 把技术异常翻成人话。界面上不再直接出现 SocketException / HTTP 502。

import 'dart:async';
import 'dart:io';

String friendlyError(Object e) {
  final String s = e.toString().toLowerCase();

  if (e is TimeoutException || s.contains('timeout')) {
    return '网络有点慢，超时了，再试一次';
  }
  if (e is SocketException ||
      s.contains('socketexception') ||
      s.contains('connection refused') ||
      s.contains('connection closed') ||
      s.contains('network is unreachable')) {
    return '连不上网络，检查一下网络再试';
  }
  if (s.contains('401') || s.contains('invalid api key')) {
    return 'API Key 不对或已过期，去设置里检查一下';
  }
  if (s.contains('402') || s.contains('insufficient')) {
    return '账户额度不够了，充值后再试';
  }
  if (s.contains('403')) {
    return '接口拒绝了这次请求，可能触发了限制';
  }
  if (s.contains('429')) {
    return '请求太频繁，等几秒再试';
  }
  if (s.contains('500') ||
      s.contains('502') ||
      s.contains('503') ||
      s.contains('504')) {
    return '服务端暂时不可用，稍后再试';
  }

  final String raw = e
      .toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst('FormatException: ', '')
      .trim();
  if (raw.isEmpty) return '出了点问题，再试一次';
  return raw.length > 60 ? '${raw.substring(0, 60)}…' : raw;
}
