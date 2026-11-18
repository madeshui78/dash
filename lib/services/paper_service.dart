// 论文检索（OpenAlex）+ 全文抽取 + 结构化精读。
//
// OpenAlex 免 key，返回标题/作者/期刊/DOI/开放获取 PDF/摘要，
// 比直接搜网页靠谱；摘要用倒排索引存，需要自己拼回正常语序。

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../models/paper.dart';
import 'ai_service.dart';

class PaperService {
  PaperService._();

  static const String _ua = 'dash/1.0 (https://github.com/madeshui78/dash)';

  /// 第一次请求常常因为网络还没热起来失败，重试一次再报错
  static Future<http.Response> _getWithRetry(
    Uri uri, {
    Duration timeout = const Duration(seconds: 25),
  }) async {
    Object? last;
    for (int i = 0; i < 2; i++) {
      try {
        final http.Response r = await http
            .get(uri, headers: <String, String>{'User-Agent': _ua})
            .timeout(timeout);
        if (r.statusCode == 200) return r;
        last = Exception('HTTP ${r.statusCode}');
      } catch (e) {
        last = e;
      }
      if (i == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 900));
      }
    }
    throw last ?? Exception('网络请求失败');
  }

  static Future<List<PaperMeta>> search(String query) async {
    final String q = query.trim();
    if (q.isEmpty) throw Exception('先写一句想要什么论文');
    final String en = await _englishQuery(q);

    final Uri uri = Uri.parse(
      'https://api.openalex.org/works'
      '?search=${Uri.encodeQueryComponent(en)}'
      '&filter=is_oa:true,language:en'
      '&sort=relevance_score:desc'
      '&per-page=8'
      '&mailto=dash@example.com',
    );

    final http.Response r = await _getWithRetry(
      uri,
      timeout: const Duration(seconds: 20),
    );

    final Map<String, dynamic> data =
        jsonDecode(r.body) as Map<String, dynamic>;
    final List<dynamic> items = (data['results'] as List<dynamic>?) ?? [];
    return items
        .map((dynamic e) => _toMeta(e as Map<String, dynamic>))
        .where((PaperMeta p) => p.title.isNotEmpty)
        .toList();
  }

  static PaperMeta _toMeta(Map<String, dynamic> m) {
    final String id = (m['id'] as String?) ?? '';
    final String title = ((m['title'] as String?) ?? '').trim();
    final String date = (m['publication_date'] as String?) ?? '';
    final String doi = ((m['doi'] as String?) ?? '').replaceFirst(
      'https://doi.org/',
      '',
    );

    final List<String> authors = <String>[];
    final List<dynamic> auths = (m['authorships'] as List<dynamic>?) ?? [];
    for (final dynamic a in auths) {
      final Map<String, dynamic>? author =
          (a as Map<String, dynamic>)['author'] as Map<String, dynamic>?;
      final String name = (author?['display_name'] as String?) ?? '';
      if (name.isNotEmpty) authors.add(name);
    }

    String journal = '';
    final Map<String, dynamic>? loc =
        m['primary_location'] as Map<String, dynamic>?;
    final Map<String, dynamic>? src = loc?['source'] as Map<String, dynamic>?;
    journal = (src?['display_name'] as String?) ?? '';

    String landing = (loc?['landing_page_url'] as String?) ?? '';
    final Map<String, dynamic>? best =
        m['best_oa_location'] as Map<String, dynamic>?;
    final String pdf = (best?['pdf_url'] as String?) ?? '';
    final String oa =
        ((m['open_access'] as Map<String, dynamic>?)?['oa_url'] as String?) ??
        '';
    if (landing.isEmpty) landing = oa;
    if (landing.isEmpty) landing = id;

    return PaperMeta(
      id: id,
      title: title,
      authors: authors,
      journal: journal,
      date: date,
      doi: doi,
      url: landing,
      pdfUrl: pdf.isNotEmpty ? pdf : (oa.endsWith('.pdf') ? oa : ''),
      abstract: _abstract(m['abstract_inverted_index']),
      citedBy: (m['cited_by_count'] as int?) ?? 0,
    );
  }

  /// 倒排索引 {词: [位置...]} 还原成段落
  static String _abstract(dynamic raw) {
    if (raw is! Map) return '';
    final Map<int, String> words = <int, String>{};
    raw.forEach((dynamic k, dynamic v) {
      if (v is! List) return;
      for (final dynamic pos in v) {
        if (pos is int) words[pos] = k.toString();
      }
    });
    if (words.isEmpty) return '';
    final List<int> keys = words.keys.toList()..sort();
    return keys.map((int k) => words[k]!).join(' ');
  }

  /// 优先下 PDF 抽全文；失败则抓落地页正文；再不行用摘要
  static Future<String> fetchText(
    PaperMeta p, {
    bool preferHtml = false,
  }) async {
    // 读原文时优先网页：PDF 抽出来的分栏常常是碎的
    if (preferHtml && p.url.isNotEmpty) {
      try {
        final http.Response r = await http
            .get(Uri.parse(p.url), headers: <String, String>{'User-Agent': _ua})
            .timeout(const Duration(seconds: 25));
        if (r.statusCode == 200) {
          final String text = _htmlText(r.body);
          if (text.length > 800) return text;
        }
      } catch (_) {}
    }

    if (p.pdfUrl.isNotEmpty) {
      try {
        final http.Response r = await http
            .get(
              Uri.parse(p.pdfUrl),
              headers: <String, String>{'User-Agent': _ua},
            )
            .timeout(const Duration(seconds: 40));
        if (r.statusCode == 200 && r.bodyBytes.length > 5000) {
          final String text = _pdfText(r.bodyBytes);
          if (text.length > 800) return text;
        }
      } catch (_) {}
    }

    if (p.url.isNotEmpty) {
      try {
        final http.Response r = await http
            .get(Uri.parse(p.url), headers: <String, String>{'User-Agent': _ua})
            .timeout(const Duration(seconds: 25));
        if (r.statusCode == 200) {
          final String text = _htmlText(r.body);
          if (text.length > 800) return text;
        }
      } catch (_) {}
    }

    return p.abstract;
  }

  /// 把 8 篇候选压成一句中文概括，一次调用搞定
  static Future<List<String>> summaries(List<PaperMeta> list) async {
    if (list.isEmpty) return <String>[];
    final StringBuffer b = StringBuffer();
    for (int i = 0; i < list.length; i++) {
      final PaperMeta p = list[i];
      final String abs = p.abstract.length > 260
          ? '${p.abstract.substring(0, 260)}…'
          : p.abstract;
      b.writeln('${i + 1}. ${p.title}\n$abs\n');
    }

    try {
      final AiConfig cfg = await AiService.loadConfig();
      final String out = await AiService.chat(cfg, <ChatMessage>[
        ChatMessage(
          role: 'user',
          content:
              '下面是 ${list.length} 篇论文的标题和摘要。'
              '给每篇写一句中文概括，20-35 字，说清研究对象和主要发现，'
              '不要评价。按顺序输出 JSON 字符串数组，例如 ["...","..."]，'
              '不要代码块、不要序号。\n\n$b',
        ),
      ], systemPrompt: '你负责把英文学术摘要压成一句话中文概括。');
      String s = out.trim().replaceAll(RegExp(r'^```[a-zA-Z]*'), '');
      s = s.replaceAll('```', '').trim();
      final int start = s.indexOf('[');
      final int end = s.lastIndexOf(']');
      if (start >= 0 && end > start) s = s.substring(start, end + 1);
      final dynamic data = jsonDecode(s);
      if (data is List) {
        return data.map((dynamic e) => e.toString()).toList();
      }
    } catch (_) {}
    return List<String>.filled(list.length, '');
  }

  static String _pdfText(List<int> bytes) {
    PdfDocument? doc;
    try {
      doc = PdfDocument(inputBytes: bytes);
      final PdfTextExtractor extractor = PdfTextExtractor(doc);
      final String text = extractor.extractText();
      return _cleanPdf(text);
    } catch (_) {
      return '';
    } finally {
      doc?.dispose();
    }
  }

  /// PDF 分栏会把一行拆成很多短行，丢掉这些碎片，只留成句的段落
  static String _cleanPdf(String raw) {
    final List<String> kept = <String>[];
    for (final String line in raw.split('\n')) {
      final String t = line.trim();
      if (t.isEmpty) continue;
      final int words = RegExp(r"[A-Za-z]+(?:['’\-][A-Za-z]+)*")
          .allMatches(t)
          .length;
      if (words < 4) continue;
      kept.add(t);
    }
    return _clean(kept.join(' '));
  }

  static String _htmlText(String html) {
    String s = html
        .replaceAll(
          RegExp(r'<script[\s\S]*?</script>', caseSensitive: false),
          ' ',
        )
        .replaceAll(
          RegExp(r'<style[\s\S]*?</style>', caseSensitive: false),
          ' ',
        );
    final List<String> paras = <String>[];
    for (final RegExpMatch m in RegExp(
      r'<p[^>]*>([\s\S]*?)</p>',
      caseSensitive: false,
    ).allMatches(s)) {
      final String t = m
          .group(1)!
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .replaceAll('&amp;', '&')
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&nbsp;', ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (t.length >= 60) paras.add(t);
    }
    return _clean(paras.join('\n\n'));
  }

  static String _clean(String s) {
    return s
        .replaceAll(RegExp(r'\[[0-9,\-\s]+\]'), ' ') // 参考文献角标
        .replaceAll(RegExp(r'-\s*\n'), '') // 断词连字符
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  static Future<Map<String, dynamic>> analyze(
    PaperMeta p,
    String fullText,
  ) async {
    final AiConfig cfg = await AiService.loadConfig();
    final String text = fullText.length > 12000
        ? '${fullText.substring(0, 12000)}\n\n[后文省略]'
        : fullText;

    final String out = await AiService.chat(cfg, <ChatMessage>[
      ChatMessage(
        role: 'user',
        content:
            '下面是一篇真实论文的元数据和正文。请做一份中文精读，'
            '所有内容必须来自原文，不要编造数字或结论。\n\n'
            '标题：${p.title}\n'
            '作者：${p.authorsLine}\n'
            '期刊：${p.journal}\n'
            '日期：${p.date}\n'
            'DOI：${p.doi}\n\n'
            '原文：\n$text\n\n'
            '只输出 JSON，不要 Markdown 代码块，结构如下：\n'
            '{"summary":"4-6 句中文概括",'
            '"abstract_zh":"摘要的中文翻译",'
            '"questions":["研究问题/假设，1-4 条"],'
            '"methods":["数据、样本、方法，2-5 条"],'
            '"findings":["主要结果，带原文里的关键数字，2-6 条"],'
            '"terms":[{"en":"核心术语","zh":"中文解释"}],'
            '"sentences":["值得抄走的英文学术句型，2-5 条"],'
            '"takeaways":["对英语学习者/写作者的启示，2-4 条"]}',
      ),
    ], systemPrompt: '你是学术论文精读助手，只依据给定原文作答，不补充原文没有的信息。');

    String s = out.trim();
    s = s.replaceAll(RegExp(r'^```[a-zA-Z]*'), '').replaceAll('```', '').trim();
    final int start = s.indexOf('{');
    final int end = s.lastIndexOf('}');
    if (start >= 0 && end > start) s = s.substring(start, end + 1);
    try {
      return jsonDecode(s) as Map<String, dynamic>;
    } catch (_) {
      return <String, dynamic>{'summary': out};
    }
  }

  static Future<String> _englishQuery(String q) async {
    try {
      final AiConfig cfg = await AiService.loadConfig();
      final String out = await AiService.chat(cfg, <ChatMessage>[
        ChatMessage(
          role: 'user',
          content:
              '把下面的论文需求转成一组英文学术检索词，'
              '保留主题、对象、方法等关键限定，只输出检索词：$q',
        ),
      ], systemPrompt: '你负责把中文论文需求转成精准的英文学术检索词。');
      final String s = out.replaceAll(RegExp(r'[\n"]'), ' ').trim();
      return s.isEmpty ? q : s;
    } catch (_) {
      return q;
    }
  }
}
