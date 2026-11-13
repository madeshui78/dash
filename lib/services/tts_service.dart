// 发音服务：用手机自带的 TTS 引擎读英文单词。
// 不联网、不花钱，缺点是各家手机装的引擎音质不一样（vivo / 小米 / 华为各自一套）。
//
// 为什么必须有：你背单词最大的问题是"音形没绑定"——看着字母抄，耳朵和嘴都没参与。
// 每次出现一个词就自动读一遍，逼着耳朵跟着走。

import 'package:flutter_tts/flutter_tts.dart';

import 'study_settings.dart';

class TtsService {
  TtsService._();

  static final FlutterTts _tts = FlutterTts();
  static bool _inited = false;

  /// 当前生效的语速。改设置会调 applyRate 立刻生效，不用重启。
  static double rate = StudySettings.defaultRate;

  /// 总开关：设置里可以关掉（有人觉得自动念烦）
  static bool enabled = true;

  static Future<void> init() async {
    if (_inited) return;
    try {
      rate = await StudySettings.speechRate();
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(rate);
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);
      _inited = true;
    } catch (_) {
      // 手机上没装 TTS 引擎，读不出来也不该让 App 崩
      _inited = false;
    }
  }

  /// 设置页拖完滑块调一次，下次朗读就用新语速
  static Future<void> applyRate(double r) async {
    rate = r;
    await StudySettings.setSpeechRate(r);
    try {
      await _tts.setSpeechRate(r);
      await _tts.stop();
    } catch (_) {
      // 引擎还没起来，等 init 时会读设置里的值
    }
  }

  /// 读一句英文
  static Future<void> speak(String text) async {
    if (!enabled) return;
    final String t = text.trim();
    if (t.isEmpty) return;
    await init();
    await _tts.stop();
    await _tts.setLanguage('en-US');
    await _tts.speak(t);
  }

  /// 读中文（例句的中文释义、提示语）
  static Future<void> speakZh(String text) async {
    if (!enabled) return;
    final String t = text.trim();
    if (t.isEmpty) return;
    await init();
    await _tts.stop();
    await _tts.setLanguage('zh-CN');
    await _tts.speak(t);
  }

  static Future<void> stop() async {
    await _tts.stop();
  }
}
