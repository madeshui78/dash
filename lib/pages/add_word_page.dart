// 添加单词页：表单校验 + 写入数据库

import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/word.dart';
import '../services/ai_service.dart';
import '../services/track_store.dart';
import 'import_page.dart';

class AddWordPage extends StatefulWidget {
  /// 导入完成后自增，让单词页刷新
  final ValueNotifier<int>? refreshTick;

  const AddWordPage({super.key, this.refreshTick});

  @override
  State<AddWordPage> createState() => _AddWordPageState();
}

class _AddWordPageState extends State<AddWordPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _en = TextEditingController();
  final TextEditingController _zh = TextEditingController();
  final TextEditingController _phonetic = TextEditingController();
  final TextEditingController _example = TextEditingController();
  final TextEditingController _source = TextEditingController();
  final TextEditingController _tag = TextEditingController();

  bool _saving = false;

  /// 正在等 AI 返回音标/释义/例句
  bool _aiLoading = false;

  @override
  void dispose() {
    _en.dispose();
    _zh.dispose();
    _phonetic.dispose();
    _example.dispose();
    _source.dispose();
    _tag.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    // 校验不通过就别往下走
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    // 防重合：先看这个词在四条赛道里的落点
    //   1) 当前赛道已有 → 直接拦下，不重复录
    //   2) 别的赛道已有 → 弹确认，避免四条赛道内容互相串味
    final String enKey = _en.text.trim().toLowerCase();
    final List<Word> all = await DatabaseHelper.instance.getAllWords();
    final List<String> hitHere = <String>[];
    final List<String> hitOther = <String>[];
    for (final Word w in all) {
      if (w.en.trim().toLowerCase() != enKey) continue;
      if (w.track == TrackStore.current.value) {
        hitHere.add(w.track);
      } else {
        hitOther.add(w.track);
      }
    }

    if (!mounted) return;
    if (hitHere.isNotEmpty) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '「${_en.text.trim()}」已经在「${TrackStore.labelOf(
              TrackStore.current.value,
            )}」里了，不用重复添加',
          ),
        ),
      );
      return;
    }

    if (hitOther.isNotEmpty) {
      final String others = hitOther
          .map((String t) => '「${TrackStore.labelOf(t)}」')
          .join('、');
      final bool goOn = await showDialog<bool>(
            context: context,
            builder: (BuildContext ctx) => AlertDialog(
              title: const Text('这个词已在其他考试里'),
              content: Text(
                '「${_en.text.trim()}」已存在于 $others。\n\n'
                '仍要加入「${TrackStore.labelOf(TrackStore.current.value)}」吗？'
                '加入后两边各自独立复习，互不影响。',
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('仍然添加'),
                ),
              ],
            ),
          ) ??
          false;
      if (!goOn) {
        if (mounted) setState(() => _saving = false);
        return;
      }
    }

    final Word word = Word(
      en: _en.text.trim(),
      zh: _zh.text.trim(),
      phonetic: _nullIfEmpty(_phonetic.text),
      example: _nullIfEmpty(_example.text),
      source: _nullIfEmpty(_source.text),
      tag: _nullIfEmpty(_tag.text),
      // 录进当前选中的考试赛道，不会串到别的考试里去
      track: TrackStore.current.value,
    );
    try {
      await DatabaseHelper.instance.insertWord(word);
      if (!mounted) return;

      // 清空正文，保留来源和课次 —— 连着录同一个单元的单词时省事
      _en.clear();
      _zh.clear();
      _phonetic.clear();
      _example.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已保存 ${word.en}')),
      );
      // 收起键盘，光标回到英文输入框
      FocusScope.of(context).unfocus();
      // 立刻通知单词页重新拉数据（并自动把新词补进今天这批）
      widget.refreshTick?.value++;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 顶部提示条：显示单词会被录进哪个考试赛道。
  /// 用 ValueListenableBuilder 监听赛道变化，切赛道时这行字会自己更新。
  Widget _trackBanner() {
    return ValueListenableBuilder<String>(
      valueListenable: TrackStore.current,
      builder: (BuildContext context, String track, Widget? _) {
        final ColorScheme cs = Theme.of(context).colorScheme;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.school_outlined,
                  size: 18, color: cs.onPrimaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '正在录入「${TrackStore.labelOf(track)}」，与其他考试互不影响',
                  style: TextStyle(fontSize: 13, color: cs.onPrimaryContainer),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String? _nullIfEmpty(String s) {
    final String t = s.trim();
    return t.isEmpty ? null : t;
  }

  /// AI 补全：把英文框里的词发给 Ollama，让 AI 生成音标/释义/例句填进表单。
  /// 地址和模型名来自设置页；没设置过就用默认值。
  Future<void> _aiFill() async {
    final String word = _en.text.trim();
    if (word.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('先输入英文单词，再点 AI 补全')),
      );
      return;
    }

    setState(() => _aiLoading = true);
    try {
      // 用哪个后端（本地 / 云端）由设置页决定，这里不用关心
      final AiConfig cfg = await AiService.loadConfig();
      final Map<String, String> entry = await AiService.lookupWord(cfg, word);

      if (!mounted) return;
      setState(() {
        if (entry['phonetic']!.isNotEmpty) _phonetic.text = entry['phonetic']!;
        if (entry['zh']!.isNotEmpty) _zh.text = entry['zh']!;
        if (entry['example']!.isNotEmpty) _example.text = entry['example']!;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已填充「$word」，请核对后保存')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('AI 补全失败：$e'),
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) setState(() => _aiLoading = false);
    }
  }

  String? _required(String? v, String field) {
    if (v == null || v.trim().isEmpty) return '$field不能为空';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // 点空白处收起键盘
      onTap: () => FocusScope.of(context).unfocus(),
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            // 明确提示「现在录进哪个考试」，避免录错赛道
            _trackBanner(),
            const SizedBox(height: 10),
            // 一个个录太慢，单词表直接导入
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<Object?>(
                    builder: (BuildContext context) =>
                        ImportPage(refreshTick: widget.refreshTick),
                  ),
                );
              },
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('批量导入单词表（Word / Excel）'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _en,
              decoration: InputDecoration(
                labelText: '英文 *',
                hintText: 'apple',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.abc),
                // AI 补全入口：输完单词点一下小星星，自动填音标/释义/例句
                suffixIcon: IconButton(
                  tooltip: 'AI 补全：音标 / 释义 / 例句',
                  icon: _aiLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome),
                  onPressed: _aiLoading ? null : _aiFill,
                ),
              ),
              textInputAction: TextInputAction.next,
              validator: (String? v) => _required(v, '英文'),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _zh,
              decoration: const InputDecoration(
                labelText: '中文 *',
                hintText: '苹果',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.translate),
              ),
              textInputAction: TextInputAction.next,
              validator: (String? v) => _required(v, '中文'),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _phonetic,
              decoration: const InputDecoration(
                labelText: '音标',
                hintText: '/ˈæpl/',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.record_voice_over_outlined),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _example,
              decoration: const InputDecoration(
                labelText: '例句',
                hintText: 'I eat an apple every day.',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.notes),
                alignLabelWithHint: true,
              ),
              maxLines: 3,
              textInputAction: TextInputAction.newline,
            ),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextFormField(
                    controller: _tag,
                    decoration: const InputDecoration(
                      labelText: '课次',
                      hintText: 'Lesson 1',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _source,
                    decoration: const InputDecoration(
                      labelText: '来源',
                      hintText: '课本 / 阅读',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Text('保存到生词本', style: TextStyle(fontSize: 16)),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
