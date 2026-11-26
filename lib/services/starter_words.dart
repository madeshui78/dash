// 新用户第一次打开时，往四级赛道灌一份 500 词的起步词表。
//
// 为什么要内置：应用本身不带词库，装完打开单词本是空的，
// 新用户不知道下一步该干嘛。先给一批能直接背的词，闭环才转得起来。
//
// 只灌一次，而且只在这个赛道一个字都没有的时候灌——
// 老用户升级上来不会被塞 500 个词。

import 'package:flutter/services.dart' show rootBundle;

import '../db/database_helper.dart';
import '../models/word.dart';

class StarterWords {
  StarterWords._();

  static const String asset = 'assets/starter_cet4.txt';
  static const String key = 'starter_cet4_loaded';
  static const String track = 'CET4';

  static Future<void> ensureLoaded() async {
    final DatabaseHelper db = DatabaseHelper.instance;
    final String? done = await db.getSetting(key);
    if (done == '1') return;

    // 已经有词了就不动，避免覆盖/灌重
    final int existing = await db.countWords(track: track);
    if (existing > 0) {
      await db.setSetting(key, '1');
      return;
    }

    try {
      final String raw = await rootBundle.loadString(asset);
      final List<Word> words = <Word>[];
      for (final String line in raw.split('\n')) {
        final String t = line.trim();
        if (t.isEmpty) continue;
        final int bar = t.indexOf('|');
        if (bar <= 0) continue;
        final String en = t.substring(0, bar).trim();
        final String zh = t.substring(bar + 1).trim();
        if (en.isEmpty || zh.isEmpty) continue;
        words.add(Word(id: null, en: en, zh: zh, tag: '四级', track: track));
      }
      if (words.isNotEmpty) {
        await db.insertWordsBatch(words);
      }
      await db.setSetting(key, '1');
    } catch (_) {
      // 资源读不到也不能把启动卡住，下次打开还会再试
    }
  }
}
