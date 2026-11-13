// 隐私政策同意状态：存在 settings 表里，不额外引入依赖。
// 国内应用商店都会检测「收集个人信息前是否弹窗征得同意」，没有这一步基本都会被驳回。

import '../db/database_helper.dart';

class ConsentStore {
  ConsentStore._();

  static const String _key = 'privacy_accepted';

  /// 政策版本号：隐私政策内容改动时加一，老用户会重新看到确认页
  static const String policyVersion = '1';

  static Future<bool> isAccepted() async {
    final String? v = await DatabaseHelper.instance.getSetting(_key);
    return v == policyVersion;
  }

  static Future<void> accept() async {
    await DatabaseHelper.instance.setSetting(_key, policyVersion);
  }
}
