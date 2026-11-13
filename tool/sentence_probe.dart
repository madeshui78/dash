// 纯 Dart 探针：验证作文按句切分。跑法：
//   dart run tool/sentence_probe.dart
//
// 断句错了「逐句对照」就是错位的，所以在进 App 之前先在这里看一眼。

import '../lib/services/essay_service.dart';

void main() {
  const String text = '''
Dear Tom,
I am writing to tell you about my plan for the summer vacation. It is going to be
a busy one, isn't it? I have decided to take a part-time job at a bookstore!

"Books are expensive," my mother said. I want to buy some with my own money.
''';

  final List<String> out = splitSentences(text);
  for (int i = 0; i < out.length; i++) {
    print('${i + 1}. ${out[i]}');
  }
  print('--- ${out.length} 句');

  // 中文混在里头不该被吃掉，空行也不该产出空句
  final List<String> mixed = splitSentences('第一段中文。Hello there!   \n\n');
  print('mixed=${mixed.length} -> $mixed');
}
