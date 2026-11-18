// 论文检索与精读用的数据模型。

class PaperMeta {
  final String id;
  final String title;
  final List<String> authors;
  final String journal;
  final String date;
  final String doi;
  final String url;
  final String pdfUrl;
  final String abstract;
  final int citedBy;

  const PaperMeta({
    required this.id,
    required this.title,
    required this.authors,
    required this.journal,
    required this.date,
    required this.doi,
    required this.url,
    required this.pdfUrl,
    required this.abstract,
    required this.citedBy,
  });

  String get authorsLine =>
      authors.isEmpty ? '未知作者' : authors.take(6).join(', ');

  String get shortMeta {
    final List<String> bits = <String>[
      if (journal.isNotEmpty) journal,
      if (date.isNotEmpty) date,
      if (citedBy > 0) '被引 $citedBy',
    ];
    return bits.join(' · ');
  }
}

/// 用户选中「读原文」后带回作文页的数据
class PaperPick {
  final PaperMeta meta;
  final String text;

  const PaperPick({required this.meta, required this.text});
}
