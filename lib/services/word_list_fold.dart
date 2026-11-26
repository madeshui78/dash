// 单列单词表折叠：把「一行一个词 + 下面几行释义」的排版合并成多列。
// 纯 Dart，无 Flutter 依赖——这样 dart CLI 探针也能直接跑它做回归测试。

/// 把 Word 里常见的「词 [音标] 一行、释义一到两行、空行分隔」的单列单词表
/// 折叠成 [英文, 中文, 音标?] 三列。不满足结构时原样返回。
///
/// 例：
///   accurate ['?kjurit]      →  accurate | a.准确的,精确的 | ['?kjurit]
///   a.准确的,精确的
/// 音标单独拆一列，否则默写判分时它会跟着英文一起被比较。
List<List<String>> foldWordListRows(List<List<String>> rows) {
  if (rows.isEmpty || rows.any((List<String> r) => r.length != 1)) {
    return rows;
  }
  final List<String> lines = rows
      .map((List<String> r) => r[0].trim())
      .where((String l) => l.isNotEmpty)
      .toList();
  if (lines.length < 2) return rows;

  bool hasCjk(String s) => s.runes.any((int c) => c >= 0x4E00 && c <= 0x9FFF);
  // 英文行：不含中文、以字母开头（词，后面可带 [音标]）
  bool isEnLine(String s) => !hasCjk(s) && RegExp(r'^[A-Za-z]').hasMatch(s);
  final int zhCount = lines.where(hasCjk).length;
  // 全英文 / 全中文都不是这种结构
  if (zhCount == 0 || zhCount == lines.length) return rows;

  final List<List<String>> out = <List<String>>[];
  String? en;
  String? phonetic;
  final List<String> zhBuf = <String>[];

  void flush() {
    if (en != null) {
      out.add(<String>[en, zhBuf.join('；'), if (phonetic != null) phonetic]);
    }
    zhBuf.clear();
  }

  for (final String line in lines) {
    if (isEnLine(line)) {
      flush();
      // 词行末尾的 [音标] / 【音标】拆出去，别混进英文单词里
      final Match? m = RegExp(r'^(.*?)\s*[\[【](.+?)[\]】]\s*$').firstMatch(line);
      if (m != null && m.group(1)!.trim().isNotEmpty) {
        en = m.group(1)!.trim().replaceAll(RegExp(r'\s+'), ' ');
        phonetic = '[${m.group(2)}]';
      } else {
        en = line.replaceAll(RegExp(r'\s+'), ' ');
        phonetic = null;
      }
    } else if (en != null && hasCjk(line)) {
      // 释义可能占一到两行，都归到当前这个词
      zhBuf.add(line);
    }
    // 其余行（开头的中文标题、无中文的杂行）丢弃
  }
  flush();
  return out;
}
