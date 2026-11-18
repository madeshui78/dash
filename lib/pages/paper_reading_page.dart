// 联网搜索：一次检索，两个视角。
//   精读：中文概括 + 结构化精读，读完可「读原文」
//   原文：直接把这篇文章作为作文正文打开
// 页面本身不落地任何文件，PDF 只在后台读取。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/paper.dart';
import '../services/paper_service.dart';
import '../theme/module_palette.dart';
import '../widgets/app_toast.dart';

class PaperSearchPage extends StatefulWidget {
  final String initialQuery;

  const PaperSearchPage({super.key, this.initialQuery = ''});

  @override
  State<PaperSearchPage> createState() => _PaperSearchPageState();
}

class _PaperSearchPageState extends State<PaperSearchPage> {
  final TextEditingController _q = TextEditingController();
  List<PaperMeta> _results = <PaperMeta>[];
  List<String> _zh = <String>[];
  PaperMeta? _paper;
  Map<String, dynamic>? _data;
  bool _busy = false;
  String _stage = '';
  String? _error;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _q.text = widget.initialQuery;
    if (widget.initialQuery.trim().isNotEmpty) {
      Future<void>.microtask(_search);
    }
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final String q = _q.text.trim();
    if (q.isEmpty) {
      AppToast.show(context, '先写一句想找什么');
      return;
    }
    setState(() {
      _busy = true;
      _stage = '正在检索…';
      _error = null;
      _results = <PaperMeta>[];
      _zh = <String>[];
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
      if (list.isNotEmpty) {
        final List<String> zh = await PaperService.summaries(list);
        if (!mounted) return;
        setState(() => _zh = zh);
      }
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
    if (_tab == 1) {
      Navigator.of(context).pop(p);
      return;
    }
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
    if (v is List) return v.map((dynamic e) => e.toString()).toList();
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
      appBar: AppBar(title: const Text('联网搜索')),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: _searchBar(p),
            ),
            const SizedBox(height: 8),
            _tabs(p),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(
                          fontSize: 12,
                          color: p.wrong,
                          height: 1.5,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _busy ? null : _search,
                      child: const Text('重试', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: _busy
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const CircularProgressIndicator(strokeWidth: 2),
                          const SizedBox(height: 10),
                          Text(
                            _stage,
                            style: TextStyle(fontSize: 12, color: p.muted),
                          ),
                        ],
                      ),
                    )
                  : _paper == null
                  ? _listView(p)
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      children: <Widget>[_detail(p)],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabs(ModulePalette p) {
    Widget tab(String label, int v) {
      final bool on = _tab == v;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _tab = v),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              color: on ? p.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              boxShadow: on
                  ? <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 4,
                      ),
                    ]
                  : null,
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                color: on ? p.ink : p.muted,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: p.surfaceAlt,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(children: <Widget>[tab('精读', 0), tab('原文', 1)]),
      ),
    );
  }

  Widget _searchBar(ModulePalette p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('论文/文章，越具体越准', style: TextStyle(fontSize: 11.5, color: p.muted)),
        const SizedBox(height: 6),
        TextField(
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
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
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

  Widget _listView(ModulePalette p) {
    if (_results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            '输入一句需求，点搜索。\n「精读」先看结构和结论，「原文」直接读全文。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, height: 1.7, color: p.muted),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      children: <Widget>[
        Text(
          _tab == 0
              ? '找到 ${_results.length} 篇，点一篇看精读'
              : '找到 ${_results.length} 篇，点一篇读原文',
          style: TextStyle(fontSize: 11.5, color: p.muted),
        ),
        const SizedBox(height: 8),
        for (int i = 0; i < _results.length; i++) _card(p, _results[i], i),
      ],
    );
  }

  Widget _card(ModulePalette p, PaperMeta m, int i) {
    final String zh = i < _zh.length ? _zh[i] : '';
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
            if (zh.isNotEmpty) ...<Widget>[
              Text(
                zh,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.55,
                  color: p.ink.withValues(alpha: 0.85),
                ),
              ),
              const SizedBox(height: 6),
            ] else ...<Widget>[
              Text(
                m.abstract,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, height: 1.5, color: p.muted),
              ),
              const SizedBox(height: 6),
            ],
            Text(
              '${m.authorsLine} · ${m.shortMeta}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, color: p.muted),
            ),
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                Icon(
                  _tab == 0 ? Icons.auto_awesome : Icons.menu_book_outlined,
                  size: 13,
                  color: p.blue,
                ),
                const SizedBox(width: 4),
                Text(
                  _tab == 0 ? '看精读' : '读原文',
                  style: TextStyle(fontSize: 11, color: p.blue),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _detail(ModulePalette p) {
    final PaperMeta m = _paper!;
    final Map<String, dynamic> d = _data!;

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
                    padding: const EdgeInsets.only(top: 6, right: 6),
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
        const SizedBox(height: 6),
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
              onPressed: () => Navigator.of(context).pop(m),
              icon: const Icon(Icons.menu_book_outlined, size: 15),
              label: const Text('读原文'),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          m.title,
          style: TextStyle(
            fontSize: 18,
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
        if (_terms().isNotEmpty) ...<Widget>[
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
          for (final Map<String, String> t in _terms())
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
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pop(m),
            icon: const Icon(Icons.menu_book_outlined, size: 17),
            label: const Text('读原文'),
          ),
        ),
      ],
    );
  }
}
