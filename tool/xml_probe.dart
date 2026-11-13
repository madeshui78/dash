// 临时探针：验证 docx 解析的命名空间兼容查找逻辑
// ignore_for_file: avoid_print
import 'package:xml/xml.dart';

/// 按局部名收集所有后代元素（不挑前缀）
Iterable<XmlElement> allByLocal(XmlNode scope, String local) =>
    scope.descendantElements.where((XmlElement e) => e.name.local == local);

void main() {
  const String docXml = '''
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p><w:r><w:t>apple</w:t></w:r></w:p>
    <w:tbl><w:tr><w:tc><w:t>like</w:t></w:tc><w:tc><w:t>喜欢</w:t></w:tc></w:tr></w:tbl>
  </w:body>
</w:document>''';

  final XmlDocument doc = XmlDocument.parse(docXml);
  final Iterable<XmlElement> bodies = allByLocal(doc, 'body');
  print('body 匹配数: ${bodies.length}');
  if (bodies.isEmpty) {
    print('FAIL');
    return;
  }
  final XmlElement body = bodies.first;
  final String p =
      allByLocal(body, 't').map((t) => t.innerText).join('|');
  print('段落文本: $p');
  final XmlElement tbl = allByLocal(body, 'tbl').first;
  final String cells = allByLocal(tbl, 'tc')
      .map((tc) => allByLocal(tc, 't').map((t) => t.innerText).join())
      .join(' / ');
  print('表格单元格: $cells');
  print(p == 'apple' && cells == 'like / 喜欢' ? 'PASS' : 'FAIL');
}
