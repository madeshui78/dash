// 一次性验证脚本：拿 tool/testdata 下的样例文件跑一遍 ImportService，
// 确认 xlsx / docx / csv 都能读成表格。跑法：dart run tool/check_import.dart

import 'dart:io';

import 'package:english_agent/services/import_service.dart';

void main() {
  const List<String> files = <String>[
    'test.xlsx',
    'test.docx',
    'test.csv',
  ];
  for (final String name in files) {
    final File f = File('tool/testdata/$name');
    if (!f.existsSync()) {
      stdout.writeln('$name —— 文件不存在，跳过');
      continue;
    }
    try {
      final List<List<String>> rows =
          ImportService.parse(name, f.readAsBytesSync());
      stdout.writeln('=== $name 共 ${rows.length} 行 ===');
      for (final List<String> r in rows) {
        stdout.writeln(r.map((String s) => '[$s]').join(' '));
      }
    } catch (e) {
      stdout.writeln('=== $name 解析失败：$e');
    }
  }
}
