// 冒烟测试：覆盖「数据模型」和「通用组件」两层。
//
// 为什么不直接测试整页 UI：
//   WordListPage / ReviewPage 等页面在 initState 里就会访问 SQLite，
//   而 `flutter test` 的运行环境没有数据库插件，会抛 MissingPluginException。
//   所以这里挑没有副作用的部分来测，保证测试稳定、可长期跑。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:english_agent/models/word.dart';
import 'package:english_agent/pages/import_page.dart';
import 'package:english_agent/widgets/empty_view.dart';

void main() {
  test('Word.fromMap 能正确解析各字段', () {
    final Map<String, dynamic> row = <String, dynamic>{
      'id': 1,
      'en': 'apple',
      'zh': '苹果',
      'phonetic': '/ˈæpl/',
      'correct': 2,
      'wrong': 1,
      'interval': 3,
      'ease': 2.6,
      'next_review': '2026-10-01T00:00:00.000',
    };

    final Word w = Word.fromMap(row);

    expect(w.en, 'apple');
    expect(w.zh, '苹果');
    expect(w.correct, 2);
    expect(w.wrong, 1);
    expect(w.interval, 3);
    expect(w.ease, 2.6);
    expect(w.nextReview, isNotNull);
    // mastered 是落库的标记，这一行没有标记 → 未掌握
    expect(w.mastered, isFalse);
  });

  test('mastered 列写入 1 才算已掌握', () {
    final Word w = Word.fromMap(<String, dynamic>{
      'en': 'x',
      'zh': 'y',
      'mastered': 1,
    });
    expect(w.mastered, isTrue);
    // 写回数据库时转成 1 / 0
    expect(w.toMap()['mastered'], 1);
  });

  test('toMap 会带上 id，copyWith 保留未修改的字段', () {
    const Word w = Word(id: 7, en: 'book', zh: '书');
    expect(w.toMap()['id'], 7);

    final Word cleared = w.copyWith(wrong: 0);
    expect(cleared.wrong, 0);
    expect(cleared.en, 'book');
    expect(cleared.id, 7);
  });

  testWidgets('EmptyView 渲染标题与副标题', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EmptyView(
            icon: Icons.book_outlined,
            title: '还没有单词',
            subtitle: '去「添加」页录入第一个单词',
          ),
        ),
      ),
    );

    expect(find.text('还没有单词'), findsOneWidget);
    expect(find.text('去「添加」页录入第一个单词'), findsOneWidget);
  });

  // 这个页面出过事：late 字段没初始化，release 装到手机上点开就是黑屏。
  // 这里在选文件之前就渲染一次，确保空界面本身不会抛异常。
  testWidgets('ImportPage 选文件前能正常渲染', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ImportPage()),
    );

    expect(find.text('批量导入'), findsOneWidget);
    expect(find.text('选择文件'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
