// 论文精读：OpenAlex 检索 -> 选一篇 -> 抓全文 -> AI 结构化精读。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/paper.dart';
import '../services/paper_service.dart';
import '../theme/module_palette.dart';
import '../widgets/app_toast.dart';

class PaperReadingPage extends StatefulWidget {
  const PaperReadingPage({super.key});

  @override
  State<PaperReadingPage> createState() => _PaperReadingPageState();
}

class _PaperReadingPageState extends State<PaperReadingPage> {
  final TextEditingController _q = TextEditingController();
  List<PaperMeta> _results = <PaperMeta>[];
  PaperMeta? _paper;
  Map<String, dynamic>? _data;
  bool _busy = false;
  String _stage = '';
  String? _error;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final String q = _q.text.trim();
    if (q.isEmpty) {
      AppToast.show(context, '先写一句想找什么论文');
      return;
    }
    setState(() {
      _busy = true;
      _stage = '正在检索…';
      _error = null;
      _results = <PaperMeta>[];
      _paper = null;
      _data = null;
    });
    try {
      final List<PaperMeta> list = await PaperService.search(q);
      if (!mounted) return;
      setState(() {
        _results = list;
        _busy = false;
        _stage = '';
        if (list.isEmpty) _error = '没有找到开放获取的论文，换个说法试试';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _stage = '';
        _error = '$e';
      });
    }
  }

  Future<void> _open(PaperMeta p) async {
    setState(() {
      _paper = p;
      _busy = true;
      _stage = '正在下载全文…';
      _error = null;
      _data = null;
    });
    try {
      final String text = await PaperService.fetchText(p);
      if (!mounted) return;
      setState(() => _stage = '正在精读…');
      final Map<String, dynamic> data = await PaperService.analyze(p, text);
      if (!mounted) return;
      setState(() {
        _data = data;
        _busy = false;
        _stage = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _stage = '';
        _error = '精读失败：$e';
      });
    }
  }

  List<String> _list(String key) {
    final dynamic v = _data?[key];
    if (v is List) {
      return v.map((dynamic e) => e.toString()).toList();
    }
    return <String>[];
  }

  List<Map<String, String>> _terms() {
    final dynamic v = _data?['terms'];
    if (v is! List) return <Map<String, String>>[];
    return v.whereType<Map>().map((Map m) {
      return <String, String>{
        'en': (m['en'] ?? '').toString(),
        'zh': (m['zh'] ?? '').toString(),
      };
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final ModulePalette p = ModulePalette.of(context);
    return Scaffold(
      backgroundColor: p.canvas,
      appBar: AppBar(title: const Text('论文精读')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: <Widget>[
          _searchBar(p),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: TextStyle(fontSize: 12, color: p.wrong, height: 1.5),
            ),
          ],
          if (_busy) ...<Widget>[
            const SizedBox(height: 28),
            Center(
              child: Column(
                children: <Widget>[
                  const CircularProgressIndicator(strokeWidth: 2),
                  const SizedBox(height: 10),
                  Text(_stage, style: TextStyle(fontSize: 12, color: p.muted)),
                ],
              ),
            ),
          ],
          if (!_busy && _paper == null && _results.isNotEmpty) ...<Widget>[
            const SizedBox(height: 14),
            Text(
              '找到 ${_results.length} 篇，选一篇看精读',
              style: TextStyle(fontSize: 11.5, color: p.muted),
            ),
            const SizedBox(height: 8),
            for (final PaperMeta m in _results) _resultCard(p, m),
          ],
          if (!_busy && _data != null && _paper != null) _detail(p),
        ],
      ),
    );
  }

  Widget _searchBar(ModulePalette p) {
    return Row(
      children: <Widget>[
        Expanded(
          child: TextField(
            controller: _q,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            style: const TextStyle(fontSize: 13.5),
            decoration: InputDecoration(
              hintText: '例如：英语学习投入 的实证研究',
              hintStyle: TextStyle(fontSize: 12.5, color: p.muted),
              filled: true,
              fillColor: p.surface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: p.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: p.line),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 44,
          child: FilledButton(
            onPressed: _busy ? null : _search,
            style: FilledButton.styleFrom(
              backgroundColor: p.blue,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('搜索'),
          ),
        ),
      ],
    );
  }

  Widget _resultCard(ModulePalette p, PaperMeta m) {
    return GestureDetector(
      onTap: _busy ? null : () => _open(m),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: p.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              m.title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: p.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              m.authorsLine,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: p.muted),
            ),
            const SizedBox(height: 4),
            Text(m.shortMeta, style: TextStyle(fontSize: 11, color: p.muted)),
            if (m.abstract.isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                m.abstract,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, height: 1.5, color: p.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detail(ModulePalette p) {
    final PaperMeta m = _paper!;
    final Map<String, dynamic> d = _data!;
    final List<Map<String, String>> terms = _terms();

    Widget section(String title, List<String> items) {
      if (items.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: 18),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: p.ink,
            ),
          ),
          const SizedBox(height: 6),
          for (final String s in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(top: 5, right: 6),
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: p.blue,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      s,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.6,
                        color: p.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            TextButton.icon(
              onPressed: () => setState(() {
                _paper = null;
                _data = null;
              }),
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('返回候选'),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _markdown(m, d)));
                AppToast.show(context, 'Markdown 已复制');
              },
              icon: const Icon(Icons.copy, size: 15),
              label: const Text('复制全文'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          m.title,
          style: TextStyle(
            fontSize: 19,
            height: 1.35,
            fontWeight: FontWeight.w600,
            color: p.ink,
          ),
        ),
        const SizedBox(height: 8),
        Text(m.authorsLine, style: TextStyle(fontSize: 12, color: p.muted)),
        const SizedBox(height: 4),
        Text(m.shortMeta, style: TextStyle(fontSize: 11.5, color: p.muted)),
        if (m.doi.isNotEmpty) ...<Widget>[
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: m.doi));
              AppToast.show(context, 'DOI 已复制');
            },
            child: Text(
              'DOI: ${m.doi}',
              style: TextStyle(fontSize: 11.5, color: p.blue),
            ),
          ),
        ],
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: p.blue.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            (d['summary'] ?? '').toString(),
            style: TextStyle(fontSize: 12.5, height: 1.65, color: p.ink),
          ),
        ),
        if ((d['abstract_zh'] ?? '').toString().isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          Text(
            '摘要译文',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: p.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            d['abstract_zh'].toString(),
            style: TextStyle(fontSize: 12.5, height: 1.65, color: p.ink),
          ),
        ],
        section('研究问题', _list('questions')),
        section('方法', _list('methods')),
        section('主要结果', _list('findings')),
        if (terms.isNotEmpty) ...<Widget>[
          const SizedBox(height: 18),
          Text(
            '核心术语',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: p.ink,
            ),
          ),
          const SizedBox(height: 6),
          for (final Map<String, String> t in terms)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: RichText(
                text: TextSpan(
                  style: TextStyle(fontSize: 12.5, height: 1.55, color: p.ink),
                  children: <TextSpan>[
                    TextSpan(
                      text: '${t['en']}  ',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: p.blue,
                      ),
                    ),
                    TextSpan(text: t['zh']),
                  ],
                ),
              ),
            ),
        ],
        section('可抄句型', _list('sentences')),
        section('对我的启示', _list('takeaways')),
      ],
    );
  }

  String _markdown(PaperMeta m, Map<String, dynamic> d) {
    final StringBuffer b = StringBuffer()
      ..writeln('# ${m.title}')
      ..writeln()
      ..writeln('- 作者：${m.authorsLine}')
      ..writeln('- 期刊：${m.journal}')
      ..writeln('- 日期：${m.date}')
      ..writeln('- DOI：${m.doi}')
      ..writeln('- 链接：${m.url}')
      ..writeln()
      ..writeln('## 概括')
      ..writeln(d['summary'] ?? '')
      ..writeln()
      ..writeln('## 摘要译文')
      ..writeln(d['abstract_zh'] ?? '');

    void sec(String title, List<String> items) {
      if (items.isEmpty) return;
      b
        ..writeln()
        ..writeln('## $title');
      for (final String s in items) {
        b.writeln('- $s');
      }
    }

    sec('研究问题', _list('questions'));
    sec('方法', _list('methods'));
    sec('主要结果', _list('findings'));
    final List<Map<String, String>> terms = _terms();
    if (terms.isNotEmpty) {
      b
        ..writeln()
        ..writeln('## 核心术语');
      for (final Map<String, String> t in terms) {
        b.writeln('- **${t['en']}**：${t['zh']}');
      }
    }
    sec('可抄句型', _list('sentences'));
    sec('对我的启示', _list('takeaways'));
    b
      ..writeln('---')
      ..writeln('由 dash 论文精读生成');
    return b.toString();
  }
}
