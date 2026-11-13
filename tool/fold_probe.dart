// 探针：用真实 docx 导出的行数据，验证 foldWordListRows 折叠效果
import 'dart:io';

import 'package:english_agent/services/word_list_fold.dart';

void main(List<String> args) {
  final List<String> lines =
      File('D:/ea-tmp/docx_lines.txt').readAsLinesSync();

  // 还原成"每行一格"的 rows（模拟 docx 解析输出）
  final List<List<String>> rows = lines.map((String l) => <String>[l]).toList();
  print('输入行数: ${rows.length}');

  final List<List<String>> out = foldWordListRows(rows);
  print('折叠后行数: ${out.length}');
  print('--- 前 8 行 ---');
  for (int i = 0; i < out.length && i < 8; i++) {
    print('${i + 1}: ${out[i].join(' | ')}');
  }
  // 抽查几个特定词
  for (final String key in <String>['ache', 'acquaintance', 'accurate']) {
    final List<List<String>> hit =
        out.where((List<String> r) => r[0].toLowerCase() == key).toList();
    print('抽查 $key: ${hit.isEmpty ? "没找到" : hit.first.join(" | ")}');
  }
  // 统计异常行：没有释义的词
  final List<List<String>> noZh =
      out.where((List<String> r) => r[1].trim().isEmpty).toList();
  print('没释义的词: ${noZh.length} 个');
  for (int i = 0; i < noZh.length && i < 6; i++) {
    print('  - ${noZh[i].join(" | ")}');
  }
}
