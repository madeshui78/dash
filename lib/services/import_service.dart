// 批量导入的解析层：把 Word / Excel / CSV / 纯文本 / PDF 里的单词表读成二维行。
// 只负责"读成一个表格"，认哪一列是英文、哪一列是中文交给页面（或交给 AI 判断）。
//
// 支持的格式：
//   .xlsx —— 本质是 zip + xml，自己解（省掉一个重依赖）
//   .docx —— 同上，读段落文字和表格
//   .csv / .txt —— 按行按分隔符切
//   .pdf  —— 文字型 PDF 提取文本（扫描件不行，见 _parsePdf 里的提示）

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:xml/xml.dart';

// 单列单词表折叠逻辑在 word_list_fold.dart（纯 Dart，可被探针直接测试）
export 'word_list_fold.dart' show foldWordListRows;

class ImportService {
  ImportService._();

  /// 入口：按扩展名分派解析。返回二维行（每行是一串单元格文本）。
  /// 解析不了的文件会抛异常，页面负责提示。
  static List<List<String>> parse(String fileName, Uint8List bytes) {
    final String name = fileName.toLowerCase();
    if (name.endsWith('.xlsx')) return _parseXlsx(bytes);
    if (name.endsWith('.docx')) return _parseDocx(bytes);
    if (name.endsWith('.csv') || name.endsWith('.txt')) {
      return _parseDelimited(bytes);
    }
    if (name.endsWith('.pdf')) return _parsePdf(bytes);
    throw Exception(
      '暂不支持这个格式：$fileName\n'
      '可以存成 .pdf（文字型）、.xlsx（Excel）、.docx（Word）、.csv 或 .txt 再来',
    );
  }

  // ---------------- xlsx ----------------

  static List<List<String>> _parseXlsx(Uint8List bytes) {
    final Archive archive = ZipDecoder().decodeBytes(bytes);

    // 共享字符串：单元格里存的只是下标
    final List<String> shared = <String>[];
    final ArchiveFile? ss = _find(archive, 'xl/sharedStrings.xml');
    if (ss != null) {
      final XmlDocument doc = XmlDocument.parse(utf8.decode(ss.content));
      for (final XmlElement si in doc.findAllElements('si')) {
        shared.add(
          si.findAllElements('t').map((XmlElement t) => t.innerText).join(),
        );
      }
    }

    // 取第一张工作表
    final ArchiveFile? sheet =
        _find(archive, 'xl/worksheets/sheet1.xml') ?? _firstSheet(archive);
    if (sheet == null) throw Exception('这个 Excel 里没找到工作表');

    final XmlDocument doc = XmlDocument.parse(utf8.decode(sheet.content));
    final List<List<String>> rows = <List<String>>[];

    for (final XmlElement row in doc.findAllElements('row')) {
      final List<String> cells = <String>[];
      for (final XmlElement c in row.findElements('c')) {
        // r="C5" 里的字母决定这是第几列，中间的空格子要补空串，否则列会错位
        final String? ref = c.getAttribute('r');
        final int col = ref == null ? cells.length : _colFromRef(ref);
        while (cells.length < col) {
          cells.add('');
        }
        cells.add(_cellValue(c, shared));
      }
      if (cells.any((String s) => s.trim().isNotEmpty)) rows.add(cells);
    }
    return rows;
  }

  /// 单元格取值：t="s" 是共享字符串下标，t="inlineStr" 是内联文本，其余是数字
  static String _cellValue(XmlElement c, List<String> shared) {
    final String? t = c.getAttribute('t');
    final String? v = c.getElement('v')?.innerText;
    if (t == 's' && v != null) {
      final int? i = int.tryParse(v.trim());
      if (i != null && i >= 0 && i < shared.length) return shared[i];
      return '';
    }
    if (t == 'inlineStr') {
      return c.findAllElements('t').map((XmlElement e) => e.innerText).join();
    }
    return (v ?? '').trim();
  }

  /// "C5" → 2（第 0 列是 A）
  static int _colFromRef(String ref) {
    int col = 0;
    for (final int code in ref.codeUnits) {
      if (code >= 65 && code <= 90) {
        col = col * 26 + (code - 64);
      } else {
        break; // 遇到数字（行号）就停
      }
    }
    return col - 1;
  }

  static ArchiveFile? _firstSheet(Archive archive) {
    for (final ArchiveFile f in archive.files) {
      if (f.name.startsWith('xl/worksheets/') && f.name.endsWith('.xml')) {
        return f;
      }
    }
    return null;
  }

  // ---------------- docx ----------------

  static List<List<String>> _parseDocx(Uint8List bytes) {
    // docx 本质是 zip。很多"Word 文件"其实是老格式/网页版伪装的，
    // 先看文件头，别让用户对着一句看不懂的 zip 报错猜原因。
    if (bytes.length >= 8 &&
        bytes[0] == 0xD0 &&
        bytes[1] == 0xCF &&
        bytes[2] == 0x11 &&
        bytes[3] == 0xE0) {
      throw Exception(
        '这是老版的 .doc 格式（或改了扩展名的 .doc），不是真正的 .docx。\n'
        '用 WPS / Word 打开后「另存为 .docx」，再回来导入。',
      );
    }
    final String head = bytes.length >= 8
        ? String.fromCharCodes(bytes.sublist(0, 8))
        : '';
    if (head.startsWith('{\\rtf')) {
      throw Exception(
        '这是 RTF 格式（或改了扩展名的 RTF），不是真正的 .docx。\n'
        '用 WPS / Word 打开后另存为 .docx，再回来导入。',
      );
    }
    if (head.trimLeft().startsWith('<')) {
      throw Exception(
        '这是一个网页 / HTML 文件（扩展名被改成了 .docx），不是真正的 Word 文档。\n'
        '用浏览器打开确认内容后，把单词表存成 .csv 或 .txt 再来。',
      );
    }

    final Archive archive = ZipDecoder().decodeBytes(bytes);
    // 有的工具打包时会把条目名写成别的形式（大小写、带 ./ 前缀），
    // 精确匹配找不到就放宽成「名字以 document.xml 结尾」。
    ArchiveFile? f = _find(archive, 'word/document.xml');
    f ??= _findBySuffix(archive, 'document.xml');
    if (f == null) {
      throw Exception(
        '这个 Word 文件里没找到正文（压缩包里没有 word/document.xml）。\n'
        '文件可能在传输中被损坏了，重新另存一份 .docx 再试。',
      );
    }

    final XmlDocument doc = XmlDocument.parse(utf8.decode(f.content));
    // 正文节点必须按「局部名」找：findAllElements('body') 只匹配限定名，
    // 匹配不到带 w: 前缀的节点（实测），所以这里自己按 local 过滤。
    final List<XmlElement> bodies = doc.descendantElements
        .where((XmlElement e) => e.name.local == 'body')
        .toList();
    if (bodies.isEmpty) {
      throw Exception('这个 Word 文件里没有正文内容，检查一下文档是不是空的。');
    }
    final XmlElement body = bodies.first;
    final List<List<String>> rows = <List<String>>[];

    // 按正文顺序走：段落 = 一行一列；表格 = 一行一个格子
    for (final XmlNode node in body.children) {
      if (node is! XmlElement) continue;
      final String tag = node.name.local;

      if (tag == 'p') {
        final String text = node.descendantElements
            .where((XmlElement e) => e.name.local == 't')
            .map((XmlElement t) => t.innerText)
            .join()
            .trim();
        if (text.isNotEmpty) rows.add(<String>[text]);
      } else if (tag == 'tbl') {
        for (final XmlElement tr in node.descendantElements.where(
          (XmlElement e) => e.name.local == 'tr',
        )) {
          final List<String> cells = tr.descendantElements
              .where((XmlElement e) => e.name.local == 'tc')
              .map(
                (XmlElement tc) => tc.descendantElements
                    .where((XmlElement e) => e.name.local == 't')
                    .map((XmlElement t) => t.innerText)
                    .join()
                    .trim(),
              )
              .toList();
          if (cells.any((String s) => s.isNotEmpty)) rows.add(cells);
        }
      }
    }
    return rows;
  }

  // ---------------- csv / txt ----------------

  static List<List<String>> _parseDelimited(Uint8List bytes) {
    // 可能有 BOM，先去掉
    String text = utf8.decode(bytes, allowMalformed: true);
    if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) {
      text = text.substring(1);
    }

    final List<List<String>> rows = <List<String>>[];
    for (final String rawLine in const LineSplitter().convert(text)) {
      final String line = rawLine.trim();
      if (line.isEmpty) continue;
      rows.add(_splitLine(line));
    }
    return rows;
  }

  /// 分隔符猜一个：谁切出来的列最多就用谁
  static List<String> _splitLine(String line) {
    const List<String> seps = <String>[',', '\t', ';', '，', '|', '  '];
    List<String> best = <String>[line];
    for (final String sep in seps) {
      final List<String> parts = line
          .split(sep)
          .map((String s) => s.trim())
          .where((String s) => s.isNotEmpty)
          .toList();
      if (parts.length > best.length) best = parts;
    }
    return best;
  }

  // ---------------- pdf ----------------

  /// 文字型 PDF：按页提取文本，再按行切成二维行。
  /// 扫描件（本质是图片）提取出来是空的，会给出明确提示让用户先转文本。
  static List<List<String>> _parsePdf(Uint8List bytes) {
    final PdfDocument doc = PdfDocument(inputBytes: bytes);
    try {
      final PdfTextExtractor extractor = PdfTextExtractor(doc);
      final List<List<String>> rows = <List<String>>[];
      int chars = 0;

      for (int i = 0; i < doc.pages.count; i++) {
        final String pageText = extractor.extractText(
          startPageIndex: i,
          endPageIndex: i,
        );
        chars += pageText.trim().length;
        for (final String rawLine in const LineSplitter().convert(pageText)) {
          final String line = rawLine.trim();
          if (line.isEmpty) continue;
          rows.add(_splitPdfLine(line));
        }
      }

      // 整份文件几乎没提取出字 —— 基本可以断定是扫描件
      if (rows.isEmpty || chars < doc.pages.count * 10) {
        throw const _ScanOnlyPdfException();
      }
      return rows;
    } finally {
      doc.dispose();
    }
  }

  /// PDF 里表格的列通常靠多个空格对齐，优先按「两个及以上空格」切；
  /// 切不动再退回单空格 / 制表符。
  static List<String> _splitPdfLine(String line) {
    final RegExp wide = RegExp(r'\s{2,}');
    List<String> parts = line
        .split(wide)
        .map((String s) => s.trim())
        .where((String s) => s.isNotEmpty)
        .toList();
    if (parts.length > 1) return parts;

    if (line.contains('\t')) {
      parts = line
          .split('\t')
          .map((String s) => s.trim())
          .where((String s) => s.isNotEmpty)
          .toList();
      if (parts.length > 1) return parts;
    }

    // 单空格切：只认「一个英文词 + 后面一串中文/解释」这种最常见的排版
    final List<String> bySpace = line
        .split(' ')
        .map((String s) => s.trim())
        .toList();
    return bySpace.isEmpty ? <String>[line] : bySpace;
  }

  static ArchiveFile? _find(Archive archive, String path) {
    for (final ArchiveFile f in archive.files) {
      if (f.name == path) return f;
    }
    return null;
  }

  /// 放宽匹配：忽略大小写和路径前缀，只要条目名以 suffix 结尾就算
  static ArchiveFile? _findBySuffix(Archive archive, String suffix) {
    for (final ArchiveFile f in archive.files) {
      if (f.name.toLowerCase().endsWith('/${suffix.toLowerCase()}') ||
          f.name.toLowerCase() == suffix.toLowerCase()) {
        return f;
      }
    }
    return null;
  }
}

/// PDF 里一张字的文本都没有（扫描件 / 拍照件），单独用一个类型好让页面给专属提示
class _ScanOnlyPdfException implements Exception {
  const _ScanOnlyPdfException();

  @override
  String toString() =>
      '这个 PDF 里没有可复制的文字，应该是扫描件或拍照件。\n'
      '先用 WPS 或在线工具把它转成文字版（.txt / .xlsx / .docx），再来导入。';
}
