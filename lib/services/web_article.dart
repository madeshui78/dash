// 从公开网页摘一篇英文文章，作为作文精读的正文。
//
// 两条路：
//   1. 学术类（含「论文 / paper / 研究」）先查 arXiv，优先取 HTML 全文，退而取摘要
//   2. 其余走 Bing 搜索，取前几个结果里英文正文最长的一篇
// 都用最朴素的正则抽 <p>，不引额外解析库；抽不出英文就换下一个来源。

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import 'ai_service.dart';

class WebArticle {
  final String title;
  final String text;
  final String source;

  const WebArticle({
    required this.title,
    required this.text,
    required this.source,
  });
}

class WebArticleService {
  static const String _ua =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36';

  static Future<WebArticle> fetch(
    String query, {
    Set<String> avoidTitles = const <String>{},
  }) async {
    final String q = query.trim();
    if (q.isEmpty) throw Exception('先写一句想要什么文章');

    if (q.startsWith('http://') || q.startsWith('https://')) {
      final WebArticle? a = await _fromUrl(q);
      if (a != null) return a;
      throw Exception('这个链接里没抽到英文正文');
    }

    final String en = await _englishQuery(q);
    final bool academic =
        RegExp(r'论文|paper|研究|arxiv|study|research', caseSensitive: false)
            .hasMatch(q);

    if (academic) {
      final WebArticle? a =
          await _fromArxiv(en, avoidTitles: avoidTitles);
      if (a != null) return a;
    }

    final WebArticle? b =
        await _fromBing(en, avoidTitles: avoidTitles);
    if (b != null) return b;

    // 学术没抓到、搜索也没抓到，再给 arXiv 一次机会
    if (!academic) {
      final WebArticle? a =
          await _fromArxiv(en, avoidTitles: avoidTitles);
      if (a != null) return a;
    }
    throw Exception('没找到合适的英文文章，换个更具体的说法试试');
  }

  /// 让 AI 把中文需求压成几个英文检索词
  static Future<String> _englishQuery(String q) async {
    try {
      final AiConfig cfg = await AiService.loadConfig();
      final String out = await AiService.chat(
        cfg,
        <ChatMessage>[
          ChatMessage(
            role: 'user',
            content: '把下面的需求转成 2-5 个英文检索词，只输出检索词，'
                '不要引号、不要解释：$q',
          ),
        ],
        systemPrompt: '你负责把中文的阅读需求转成精准的英文搜索关键词。',
      );
      final String s = out.replaceAll(RegExp(r'[\n"]'), ' ').trim();
      return s.isEmpty ? q : s;
    } catch (_) {
      return q;
    }
  }

  static Future<WebArticle?> _fromArxiv(
    String query, {
    Set<String> avoidTitles = const <String>{},
  }) async {
    try {
      final Uri uri = Uri.parse(
        'https://export.arxiv.org/api/query?search_query='
        '${Uri.encodeQueryComponent('all:$query')}'
        '&start=0&max_results=8&sortBy=submittedDate&sortOrder=descending',
      );
      final http.Response r =
          await http.get(uri, headers: <String, String>{'User-Agent': _ua})
              .timeout(const Duration(seconds: 18));
      if (r.statusCode != 200) return null;

      final XmlDocument doc = XmlDocument.parse(r.body);
      for (final XmlElement e in doc.findAllElements('entry')) {
        final String title = e.getElement('title')?.innerText.trim() ?? '';
        final String id = e.getElement('id')?.innerText.trim() ?? '';
        final String summary =
            e.getElement('summary')?.innerText.trim() ?? '';
        if (title.isEmpty || id.isEmpty) continue;
        if (avoidTitles.any(
          (String t) => t.toLowerCase() == title.toLowerCase(),
        )) {
          continue;
        }

        // 有 HTML 全文就用全文，否则退回摘要
        final String htmlUrl = id
            .replaceFirst('http://arxiv.org/abs/', 'https://arxiv.org/html/')
            .replaceFirst('https://arxiv.org/abs/', 'https://arxiv.org/html/');
        final WebArticle? full = await _fromUrl(htmlUrl, title: title);
        if (full != null && _words(full.text) >= 220) return full;

        if (_words(summary) >= 60) {
          return WebArticle(
            title: title,
            text: _wrap(summary),
            source: id,
          );
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<WebArticle?> _fromBing(
    String query, {
    Set<String> avoidTitles = const <String>{},
  }) async {
    final List<String> links = <String>[];
    try {
      final Uri uri = Uri.parse(
        'https://www.bing.com/search?q=${Uri.encodeQueryComponent(query)}'
        '&setlang=en&cc=us',
      );
      final http.Response r =
          await http.get(uri, headers: <String, String>{'User-Agent': _ua})
              .timeout(const Duration(seconds: 15));
      if (r.statusCode == 200) {
        final RegExp re = RegExp(
          r'<h2[^>]*>\s*<a[^>]+href="(https?://[^"]+)"',
          caseSensitive: false,
        );
        for (final RegExpMatch m in re.allMatches(r.body)) {
          final String u = m.group(1) ?? '';
          if (u.contains('bing.com') || u.contains('microsoft.com')) continue;
          if (!links.contains(u)) links.add(u);
          if (links.length >= 8) break;
        }
      }
    } catch (_) {}

    for (final String link in links) {
      final WebArticle? a = await _fromUrl(link);
      if (a == null || _words(a.text) < 220) continue;
      if (avoidTitles.any(
        (String t) => t.toLowerCase() == a.title.toLowerCase(),
      )) {
        continue;
      }
      return a;
    }
    return null;
  }

  static Future<WebArticle?> _fromUrl(String url, {String? title}) async {
    try {
      final http.Response r =
          await http.get(Uri.parse(url), headers: <String, String>{
        'User-Agent': _ua,
        'Accept-Language': 'en-US,en;q=0.9',
      }).timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return null;
      final String html = r.body;
      final String text = _extract(html);
      if (text.isEmpty) return null;
      return WebArticle(
        title: (title == null || title.isEmpty) ? _pageTitle(html) : title,
        text: _wrap(_limit(text, 4000)),
        source: url,
      );
    } catch (_) {
      return null;
    }
  }

  static String _extract(String html) {
    String s = html
        .replaceAll(
            RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), ' ')
        .replaceAll(
            RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), ' ')
        .replaceAll(
            RegExp(r'<nav[\s\S]*?</nav>', caseSensitive: false), ' ')
        .replaceAll(
            RegExp(r'<footer[\s\S]*?</footer>', caseSensitive: false), ' ')
        .replaceAll(
            RegExp(r'<header[\s\S]*?</header>', caseSensitive: false), ' ');

    final List<String> paras = <String>[];
    for (final RegExpMatch m in RegExp(
      r'<p[^>]*>([\s\S]*?)</p>',
      caseSensitive: false,
    ).allMatches(s)) {
      final String t = _plain(m.group(1) ?? '');
      if (t.length < 70) continue;
      if (_englishRatio(t) < 0.55) continue;
      if (RegExp(r'cookie|subscribe|sign up|privacy policy',
              caseSensitive: false)
          .hasMatch(t)) {
        continue;
      }
      if (!paras.contains(t)) paras.add(t);
    }
    return paras.join('\n\n');
  }

  static String _plain(String html) {
    String s = html
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&#x27;', "'")
        .replaceAll('&mdash;', '—')
        .replaceAll('&ndash;', '–')
        .replaceAll(RegExp(r'&#\d+;'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return s;
  }

  static String _pageTitle(String html) {
    final RegExpMatch? m = RegExp(
      r'<title[^>]*>([\s\S]*?)</title>',
      caseSensitive: false,
    ).firstMatch(html);
    return m == null ? '' : _plain(m.group(1) ?? '');
  }

  static double _englishRatio(String s) {
    int letters = 0;
    int other = 0;
    for (final int c in s.codeUnits) {
      if ((c >= 65 && c <= 90) || (c >= 97 && c <= 122)) {
        letters++;
      } else if (c > 127) {
        other++;
      }
    }
    final int total = letters + other;
    return total == 0 ? 0 : letters / total;
  }

  static int _words(String s) =>
      RegExp(r"[A-Za-z]+(?:['’\-][A-Za-z]+)*").allMatches(s).length;

  static String _limit(String text, int maxWords) {
    if (_words(text) <= maxWords) return text;
    final List<String> sentences = text
        .split(RegExp(r'(?<=[.!?])\s+'))
        .map((String s) => s.trim())
        .where((String s) => s.isNotEmpty)
        .toList();
    final List<String> out = <String>[];
    int count = 0;
    for (final String s in sentences) {
      final int n = _words(s);
      if (count + n > maxWords) break;
      out.add(s);
      count += n;
    }
    return out.isEmpty ? text : out.join(' ');
  }

  /// 每 2–3 句分一段，读起来不压抑
  static String _wrap(String text) {
    final List<String> sentences = text
        .split(RegExp(r'(?<=[.!?])\s+'))
        .map((String s) => s.trim())
        .where((String s) => s.isNotEmpty)
        .toList();
    final List<String> paras = <String>[];
    for (int i = 0; i < sentences.length; i += 3) {
      final int end =
          i + 3 > sentences.length ? sentences.length : i + 3;
      paras.add(sentences.sublist(i, end).join(' '));
    }
    return paras.join('\n\n');
  }
}
