// AI 查词：参考必应词典的卡片结构，内容全部由 AI 生成。
// 不抓网页、不存数据，查完即走。

import 'package:flutter/material.dart';

import '../services/ai_service.dart';
import '../services/error_text.dart';
import '../services/tts_service.dart';
import '../theme/module_palette.dart';
import '../theme/ui.dart';
import '../widgets/app_toast.dart';

class WordExplainPage extends StatefulWidget {
  final String initialQuery;

  const WordExplainPage({super.key, this.initialQuery = ''});

  @override
  State<WordExplainPage> createState() => _WordExplainPageState();
}

class _WordExplainPageState extends State<WordExplainPage> {
  final TextEditingController _q = TextEditingController();
  Map<String, dynamic>? _data;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _q.text = widget.initialQuery;
    if (widget.initialQuery.trim().isNotEmpty) {
      Future<void>.microtask(_lookup);
    }
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    final String q = _q.text.trim();
    if (q.isEmpty) {
      AppToast.show(context, '先输入一个词或短语');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _data = null;
    });
    try {
      final AiConfig cfg = await AiService.loadConfig();
      final Map<String, dynamic> data = await AiService.explainWord(cfg, q);
      if (!mounted) return;
      setState(() {
        _data = data;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = friendlyError(e);
      });
    }
  }

  List<Map<String, dynamic>> _senses() {
    final dynamic v = _data?['senses'];
    if (v is! List) return <Map<String, dynamic>>[];
    return v.whereType<Map>().map((Map e) {
      return <String, dynamic>{
        'pos': (e['pos'] ?? '').toString(),
        'zh': (e['zh'] ?? '').toString(),
        'en': (e['en'] ?? '').toString(),
        'example': (e['example'] ?? '').toString(),
        'example_zh': (e['example_zh'] ?? '').toString(),
      };
    }).toList();
  }

  List<String> _strings(String key) {
    final dynamic v = _data?[key];
    if (v is! List) return <String>[];
    return v
        .map((dynamic e) => e.toString())
        .where((String s) => s.isNotEmpty)
        .toList();
  }

  List<Map<String, String>> _pairs(String key) {
    final dynamic v = _data?[key];
    if (v is! List) return <Map<String, String>>[];
    return v.whereType<Map>().map((Map e) {
      return <String, String>{
        'en': (e['en'] ?? '').toString(),
        'zh': (e['zh'] ?? '').toString(),
      };
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final ModulePalette p = ModulePalette.of(context);
    return Scaffold(
      backgroundColor: p.canvas,
      appBar: AppBar(title: const Text('AI 查词')),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _q,
                      autofocus: widget.initialQuery.trim().isEmpty,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _lookup(),
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: '单词、短语或一句话',
                        hintStyle: TextStyle(fontSize: 13, color: p.muted),
                        filled: true,
                        fillColor: p.surface,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 11,
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
                    height: UiSize.button,
                    child: FilledButton(
                      onPressed: _busy ? null : _lookup,
                      style: FilledButton.styleFrom(
                        backgroundColor: p.blue,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('查'),
                    ),
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
                            '正在讲解…',
                            style: TextStyle(fontSize: 12, color: p.muted),
                          ),
                        ],
                      ),
                    )
                  : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          '查询失败：$_error',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: p.wrong),
                        ),
                      ),
                    )
                  : _data == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          '输入一个词或短语。\n释义、例句、搭配都由 AI 生成。',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.7,
                            color: p.muted,
                          ),
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                      children: <Widget>[_result(p)],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _result(ModulePalette p) {
    final Map<String, dynamic> d = _data!;
    final String word = (d['word'] ?? _q.text).toString();
    final String phonetic = (d['phonetic'] ?? '').toString();
    final String note = (d['note'] ?? '').toString();
    final List<Map<String, dynamic>> senses = _senses();
    final List<String> forms = _strings('forms');
    final List<String> collocations = _strings('collocations');
    final List<Map<String, String>> synonyms = _pairs('synonyms');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: Text(
                word,
                style: TextStyle(
                  fontSize: 28,
                  height: 1.15,
                  fontWeight: FontWeight.w600,
                  color: p.ink,
                ),
              ),
            ),
            IconButton.outlined(
              onPressed: () => TtsService.speak(word),
              icon: const Icon(Icons.volume_up_outlined, size: 20),
            ),
          ],
        ),
        if (phonetic.isNotEmpty) ...<Widget>[
          const SizedBox(height: 2),
          Text(phonetic, style: TextStyle(fontSize: 14, color: p.blue)),
        ],
        const SizedBox(height: 4),
        Text('AI 生成 · 仅供参考', style: TextStyle(fontSize: 10.5, color: p.muted)),
        const SizedBox(height: 12),
        Divider(height: 1, color: p.line),
        if (senses.isEmpty) ...[
          const SizedBox(height: 16),
          Text(
            note.isEmpty ? '没有拿到释义，换个词再试。' : note,
            style: TextStyle(fontSize: 13.5, height: 1.7, color: p.ink),
          ),
        ],
        for (int i = 0; i < senses.length; i++) _sense(p, senses[i], i),
        if (forms.isNotEmpty) ..._chipSection(p, '词形变化', forms, p.green),
        if (synonyms.isNotEmpty) ..._pairSection(p, '近义词', synonyms, p.violet),
        if (collocations.isNotEmpty)
          ..._plainSection(p, '常用搭配', collocations, p.orange),
        if (note.isNotEmpty && senses.isNotEmpty) ...<Widget>[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: p.amber.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(Icons.lightbulb_outline, size: 16, color: p.amber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    note,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.65,
                      color: p.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _sense(ModulePalette p, Map<String, dynamic> s, int i) {
    final String pos = s['pos'] as String? ?? '';
    final String zh = s['zh'] as String? ?? '';
    final String en = s['en'] as String? ?? '';
    final String example = s['example'] as String? ?? '';
    final String exZh = s['example_zh'] as String? ?? '';

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 28,
            child: Text(
              '${i + 1}.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: p.muted,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (pos.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    margin: const EdgeInsets.only(bottom: 6),
                    decoration: BoxDecoration(
                      color: p.blue.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      pos,
                      style: TextStyle(fontSize: 10.5, color: p.blue),
                    ),
                  ),
                Text(
                  zh,
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                    color: p.ink,
                  ),
                ),
                if (en.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(
                    en,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.55,
                      color: p.muted,
                    ),
                  ),
                ],
                if (example.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    decoration: BoxDecoration(
                      color: p.surfaceAlt,
                      borderRadius: BorderRadius.circular(8),
                      border: Border(
                        left: BorderSide(color: p.blue, width: 2.5),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          example,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.55,
                            fontStyle: FontStyle.italic,
                            color: p.ink,
                          ),
                        ),
                        if (exZh.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 3),
                          Text(
                            exZh,
                            style: TextStyle(
                              fontSize: 11.5,
                              height: 1.5,
                              color: p.muted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _chipSection(
    ModulePalette p,
    String title,
    List<String> items,
    Color color,
  ) {
    return <Widget>[
      const SizedBox(height: 22),
      Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: p.muted,
        ),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: <Widget>[
          for (final String s in items)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: p.line),
              ),
              child: Text(s, style: TextStyle(fontSize: 12, color: color)),
            ),
        ],
      ),
    ];
  }

  List<Widget> _pairSection(
    ModulePalette p,
    String title,
    List<Map<String, String>> items,
    Color color,
  ) {
    return <Widget>[
      const SizedBox(height: 22),
      Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: p.muted,
        ),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: <Widget>[
          for (final Map<String, String> m in items)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: p.line),
              ),
              child: Text.rich(
                TextSpan(
                  children: <TextSpan>[
                    TextSpan(
                      text: m['en'] ?? '',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                    if ((m['zh'] ?? '').isNotEmpty)
                      TextSpan(
                        text: '  ${m['zh']}',
                        style: TextStyle(fontSize: 11, color: p.muted),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ];
  }

  List<Widget> _plainSection(
    ModulePalette p,
    String title,
    List<String> items,
    Color color,
  ) {
    return <Widget>[
      const SizedBox(height: 22),
      Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: p.muted,
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
                padding: const EdgeInsets.only(top: 7, right: 7),
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  s,
                  style: TextStyle(fontSize: 12.5, height: 1.6, color: p.ink),
                ),
              ),
            ],
          ),
        ),
    ];
  }
}
