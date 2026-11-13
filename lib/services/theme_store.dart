// 外观设置：跟随系统 / 浅色 / 深色，存在 settings 表里，抽屉里改，改完立刻生效。

import 'package:flutter/material.dart';

import '../db/database_helper.dart';

class ThemeStore {
  ThemeStore._();

  /// 当前模式，UI 监听它重建 MaterialApp
  static final ValueNotifier<ThemeMode> mode =
      ValueNotifier<ThemeMode>(ThemeMode.system);

  static const String _key = 'theme_mode';

  static Future<void> load() async {
    final String? v = await DatabaseHelper.instance.getSetting(_key);
    mode.value = _parse(v);
  }

  static Future<void> set(ThemeMode m) async {
    mode.value = m;
    await DatabaseHelper.instance.setSetting(_key, m.name);
  }

  static ThemeMode _parse(String? v) {
    switch (v) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }
}
