// 批量导入页：选一个 PDF / Word / Excel / CSV / 文本 → 预览 → 指定哪列是什么
// （也可以让 AI 自己判断）→ 可选让 AI 批量补全音标释义例句 → 一键导入。
// 导入的词进当前选中的考试赛道，跟手动添加的一样参与抽词和复习。

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/word.dart';
import '../services/ai_service.dart';
import '../widgets/app_toast.dart';
import '../services/import_service.dart';
import '../services/track_store.dart';
import '../services/word_enrich_service.dart';

class ImportPage extends StatefulWidget {
  /// 导入成功后自增，让单词页重新拉数据
  final ValueNotifier<int>? refreshTick;

  const ImportPage({super.key, this.refreshTick});

  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  /// 后台 isolate 入口：解析文件 + 折叠单列单词表
  static List<List<String>> _parseAndFold(List<Object> args) {
    return foldWordListRows(
      ImportService.parse(args[0] as String, args[1] as Uint8List),
    );
  }

  String? _fileName;
  List<List<String>>? _rows;

  /// 列下标，-1 表示"这一列不要"
  int _enCol = 0;
  int _zhCol = 1;
  int _phCol = -1;
  int _exCol = -1;

  bool _hasHeader = true;
  bool _importing = false;

  /// AI 列识别：选完文件自动跑一次，判不出来就保持默认值，不算失败
  bool _guessing = false;

  /// AI 批量补全的状态
  bool _enriching = false;
  bool _enrichCancel = false;
  int _enrichDone = 0;
  int _enrichTotal = 0;
  Map<String, WordEntry> _entries = <String, WordEntry>{};
  List<String> _enrichMissing = <String>[];
  String? _enrichError;

  /// 导入到哪条赛道，默认当前选中的，可以在这里当场改
  late String _target;

  @override
  void initState() {
    super.initState();
    // 必须在这里先赋值：空界面那句「导入到「XX」」在选文件之前就要读它，
    // late 字段没初始化会直接抛 LateInitializationError（release 下表现就是黑屏）
    _target = TrackStore.current.value;
  }

  /// 最多用到第几列
  int get _colCount {
    if (_rows == null) return 0;
    int max = 0;
    for (final List<String> r in _rows!) {
      if (r.length > max) max = r.length;
    }
    return max;
  }

  Future<void> _pickFile() async {
    final PlatformFile? picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: <String>['pdf', 'xlsx', 'docx', 'csv', 'txt'],
      dialogTitle: '选择单词表文件',
    );
    if (picked == null) return;

    final String? path = picked.path;
    if (path == null) {
      if (!mounted) return;
      _showError('拿不到文件路径，换个文件管理器试试');
      return;
    }
    final Uint8List data = await File(path).readAsBytes();

    try {
      // 解析 + 单列折叠放后台 isolate：大文件（几 MB 的 XML）在主 isolate
      // 上跑会把界面卡住几秒
      final List<List<String>> rows = await compute(_parseAndFold, <Object>[
        picked.name,
        data,
      ]);
      if (!mounted) return;
      if (rows.isEmpty) {
        _showError('这个文件里没读到任何内容');
        return;
      }
      setState(() {
        _fileName = picked.name;
        _rows = rows;
        _target = TrackStore.current.value;
        // 猜一下列：默认第 1 列英文、第 2 列中文、第 3 列音标（如果折叠出来了）
        _enCol = 0;
        _zhCol = _colCount > 1 ? 1 : -1;
        _phCol = _colCount > 2 ? 2 : -1;
        _exCol = -1;
        _hasHeader = _looksLikeHeader(rows.first);
        // 换文件就把上一次的补全结果丢掉
        _entries = <String, WordEntry>{};
        _enrichMissing = <String>[];
        _enrichError = null;
        _enrichDone = 0;
        _enrichTotal = 0;
      });
      _guessColumnsWithAi();
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  /// 第一行看着像标题（不含英文单词，或者写着"单词/英文/word"这类）就当它是表头
  bool _looksLikeHeader(List<String> row) {
    final String joined = row.join(' ').toLowerCase();
    const List<String> hints = <String>[
      '单词',
      '英文',
      '词汇',
      '中文',
      '释义',
      '音标',
      '例句',
      'word',
      'english',
      'meaning',
      ' phonetic',
      'example',
    ];
    for (final String h in hints) {
      if (joined.contains(h)) return true;
    }
    return false;
  }

  /// 让 AI 看前几行判断哪一列是英文、哪一列是中文。
  /// 判不出来就静默保持原样——它只是省一步手动点选，不是必经环节。
  Future<void> _guessColumnsWithAi() async {
    if (_rows == null || _rows!.isEmpty) return;
    setState(() => _guessing = true);
    try {
      final AiConfig cfg = await AiService.loadConfig();
      final ColumnGuess? g = await AiService.guessColumns(cfg, _rows!);
      if (!mounted || g == null) return;
      // 只认下标在范围内的判断，AI 数错列也不能把界面搞坏
      if (g.enColumn >= 0 && g.enColumn < _colCount) {
        setState(() {
          _enCol = g.enColumn;
          _zhCol =
              (g.zhColumn != null &&
                  g.zhColumn! >= 0 &&
                  g.zhColumn! < _colCount)
              ? g.zhColumn!
              : -1;
          _hasHeader = g.hasHeader;
        });
      }
    } catch (_) {
      // AI 不可用（没填 Key、Ollama 没开）就当没这回事
    } finally {
      if (mounted) setState(() => _guessing = false);
    }
  }

  /// 待导入的英文词列表（按当前列设置和表头开关算出来）
  List<String> get _pendingWords {
    if (_rows == null || _enCol < 0) return const <String>[];
    final int start = _hasHeader ? 1 : 0;
    final List<String> out = <String>[];
    final Set<String> seen = <String>{};
    for (int i = start; i < _rows!.length; i++) {
      final String en = _cell(_rows![i], _enCol).trim();
      if (en.isEmpty) continue;
      // 同一个词只补一次
      if (seen.add(en.toLowerCase())) out.add(en);
    }
    return out;
  }

  /// AI 批量补全音标 / 释义 / 例句 / 词根
  Future<void> _runEnrich() async {
    final List<String> words = _pendingWords;
    if (words.isEmpty) {
      _showError('先选好哪一列是英文，才能补全');
      return;
    }

    setState(() {
      _enriching = true;
      _enrichCancel = false;
      _enrichDone = 0;
      _enrichTotal = words.length;
      _enrichError = null;
    });

    try {
      final AiConfig cfg = await AiService.loadConfig();
      final EnrichOutcome r = await WordEnrichService.enrich(
        words: words,
        cfg: cfg,
        isCancelled: () => _enrichCancel,
        onProgress: (int done, int total) {
          if (!mounted) return;
          setState(() {
            _enrichDone = done;
            _enrichTotal = total;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _entries = r.entries;
        _enrichMissing = r.missing;
        _enrichError = r.error;
        _enriching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enriching = false;
        _enrichError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _doImport() async {
    if (_rows == null) return;
    if (_enCol < 0) {
      _showError('至少得指定哪一列是英文');
      return;
    }

    setState(() => _importing = true);
    try {
      final int start = _hasHeader ? 1 : 0;
      final String track = _target;
      final List<Word> words = <Word>[];

      for (int i = start; i < _rows!.length; i++) {
        final List<String> row = _rows![i];
        final String en = _cell(row, _enCol);
        if (en.isEmpty) continue;

        // 文件里自带的优先，缺的才用 AI 补的
        String zh = _cell(row, _zhCol);
        String ph = _cell(row, _phCol);
        String ex = _cell(row, _exCol);

        final WordEntry? ai = _entries[en.toLowerCase()];
        if (ai != null) {
          if (zh.isEmpty && ai.zh.isNotEmpty) zh = ai.zh;
          if (ph.isEmpty && ai.phonetic.isNotEmpty) ph = ai.phonetic;
          if (ex.isEmpty && ai.example.isNotEmpty) ex = ai.example;
        }

        words.add(
          Word(
            en: en,
            zh: zh.isEmpty ? '（待补充）' : zh,
            phonetic: ph.isEmpty ? null : ph,
            example: ex.isEmpty ? null : ex,
            source: _fileName,
            track: track,
          ),
        );
      }

      if (words.isEmpty) {
        setState(() => _importing = false);
        _showError('没读到能导入的单词，检查一下列选对没有');
        return;
      }

      final ImportResult r = await DatabaseHelper.instance.insertWordsBatch(
        words,
      );
      if (!mounted) return;
      setState(() => _importing = false);

      widget.refreshTick?.value++;
      final String aiNote = _entries.isEmpty
          ? ''
          : '（其中 ${_entries.length} 个由 AI 补全了音标和释义）';
      AppToast.show(
        context,
        '导入完成：新增 ${r.added} 个，跳过 ${r.skipped} 个$aiNote',
        duration: const Duration(seconds: 3),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _importing = false);
      _showError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  String _cell(List<String> row, int col) {
    if (col < 0 || col >= row.length) return '';
    return row[col].trim();
  }

  void _showError(String msg) {
    AppToast.show(context, msg, duration: const Duration(seconds: 3));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('批量导入'),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: _rows == null ? _buildEmpty() : _buildPreview(),
    );
  }

  Widget _buildEmpty() {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _trackHint(cs),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _pickFile,
          icon: const Icon(Icons.file_open_outlined),
          label: const Text('选择文件', style: TextStyle(fontSize: 16)),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
        const SizedBox(height: 20),
        Text(
          '支持的格式',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: cs.primary,
          ),
        ),
        const SizedBox(height: 8),
        _hint(cs, '.pdf  文字型 PDF（扫描件不行，得先转成文字版）'),
        _hint(cs, '.xlsx  Excel 表格（.xls 老格式请另存为 .xlsx）'),
        _hint(cs, '.docx  Word 文档，段落和表格都能读'),
        _hint(cs, '.csv / .txt  每行一个词，用逗号或制表符分隔'),
        const SizedBox(height: 20),
        Text(
          'AI 能帮你干什么',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: cs.primary,
          ),
        ),
        const SizedBox(height: 8),
        _hint(
          cs,
          '选完文件，AI 会先看一眼判断哪一列是英文、哪一列是中文，'
          '你再确认一下就行。',
        ),
        _hint(
          cs,
          '只要一列英文也能导入：音标、中文释义、例句、词根拆解'
          '都可以让 AI 批量补齐。',
        ),
        const SizedBox(height: 20),
        Text(
          '怎么排都行',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: cs.primary,
          ),
        ),
        const SizedBox(height: 8),
        _hint(
          cs,
          '两列（英文|中文）、多列（英文|音标|中文|例句）都可以，'
          '选完文件后你自己点一下哪一列是什么。',
        ),
        _hint(cs, '重复的词会自动跳过，不会覆盖你已经学过的进度。'),
        _hint(
          cs,
          '导入的词进「${TrackStore.labelOf(TrackStore.current.value)}」，'
          '跟别的考试互不影响。',
        ),
      ],
    );
  }

  Widget _buildPreview() {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final int start = _hasHeader ? 1 : 0;
    final int previewEnd = _rows!.length > (start + 8)
        ? start + 8
        : _rows!.length;

    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.description_outlined, size: 18, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _fileName!,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _pickFile,
                    icon: const Icon(Icons.swap_horiz, size: 16),
                    label: const Text('换一个'),
                  ),
                ],
              ),
              Row(
                children: <Widget>[
                  const Text('导入到', style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _target,
                      isExpanded: true,
                      isDense: true,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                      ),
                      items: TrackStore.tracks
                          .map(
                            (Track t) => DropdownMenuItem<String>(
                              value: t.id,
                              child: Text(t.label),
                            ),
                          )
                          .toList(),
                      onChanged: (String? v) {
                        if (v != null) setState(() => _target = v);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '共 ${_rows!.length} 行，别的考试看不到这批词',
                style: TextStyle(fontSize: 12, color: cs.outline),
              ),
              const SizedBox(height: 14),

              // 表头开关
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('第一行是表标题', style: TextStyle(fontSize: 14)),
                subtitle: Text(
                  _hasHeader ? '导入时跳过第一行' : '第一行也算单词',
                  style: TextStyle(fontSize: 12, color: cs.outline),
                ),
                value: _hasHeader,
                onChanged: (bool v) => setState(() => _hasHeader = v),
              ),
              const Divider(),

              // 列映射
              Text(
                '哪一列是什么',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: cs.primary,
                ),
              ),
              const SizedBox(height: 10),
              _colPicker('英文 *', _enCol, (int v) => setState(() => _enCol = v)),
              const SizedBox(height: 8),
              _colPicker('中文释义', _zhCol, (int v) => setState(() => _zhCol = v)),
              const SizedBox(height: 8),
              _colPicker(
                '音标（可不选）',
                _phCol,
                (int v) => setState(() => _phCol = v),
              ),
              const SizedBox(height: 8),
              _colPicker(
                '例句（可不选）',
                _exCol,
                (int v) => setState(() => _exCol = v),
              ),
              if (_guessing)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: <Widget>[
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: cs.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'AI 正在看这份文件，判断哪一列是什么…',
                        style: TextStyle(fontSize: 12, color: cs.outline),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 18),
              _buildEnrichCard(cs),

              const SizedBox(height: 18),
              Text(
                '预览（前 ${previewEnd - start} 行）',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: cs.primary,
                ),
              ),
              const SizedBox(height: 8),
              _buildTable(start, previewEnd),
            ],
          ),
        ),
        _buildBottomBar(),
      ],
    );
  }

  /// AI 批量补全卡片：没跑过给按钮，跑着给进度，跑完给结果预览
  Widget _buildEnrichCard(ColorScheme cs) {
    if (_enriching) {
      final double v = _enrichTotal == 0 ? 0 : _enrichDone / _enrichTotal;
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.auto_awesome,
                  size: 18,
                  color: cs.onPrimaryContainer,
                ),
                const SizedBox(width: 8),
                Text(
                  'AI 正在补全…',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: cs.onPrimaryContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(value: v),
            const SizedBox(height: 8),
            Text(
              '$_enrichDone / $_enrichTotal 个词',
              style: TextStyle(fontSize: 12, color: cs.onPrimaryContainer),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => setState(() => _enrichCancel = true),
                child: Text(
                  '停止',
                  style: TextStyle(color: cs.onPrimaryContainer),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final List<Widget> children = <Widget>[
      Row(
        children: <Widget>[
          Icon(Icons.auto_awesome_outlined, size: 18, color: cs.primary),
          const SizedBox(width: 8),
          Text(
            '让 AI 补全音标和释义',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: cs.primary,
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
    ];

    if (_entries.isEmpty) {
      children.add(
        Text(
          '你的表里只有英文也没关系——点一下，音标、中文释义、例句、词根拆解'
          '都由 AI 补齐。文件里已有的内容不会被覆盖。',
          style: TextStyle(fontSize: 12, height: 1.5, color: cs.outline),
        ),
      );
    } else {
      children.add(
        Text(
          '已补全 ${_entries.length} 个词'
          '${_enrichMissing.isEmpty ? '' : '，${_enrichMissing.length} 个没补出来'}'
          '${_enrichError == null ? '' : '（最后一次报错：$_enrichError）'}',
          style: TextStyle(fontSize: 12, height: 1.5, color: cs.outline),
        ),
      );
      final List<WordEntry> sample = _entries.values.take(3).toList();
      for (final WordEntry e in sample) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${e.en}  ${e.phonetic}  ${e.zh}',
              style: TextStyle(fontSize: 12, color: cs.onSurface),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      }
    }

    children.add(const SizedBox(height: 10));
    children.add(
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: _runEnrich,
          icon: const Icon(Icons.auto_awesome, size: 16),
          label: Text(_entries.isEmpty ? '开始补全' : '再补一次'),
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildTable(int start, int end) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final List<TableRow> body = <TableRow>[];
    for (int i = start; i < end; i++) {
      final List<String> row = _rows![i];
      body.add(
        TableRow(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
              child: Text(
                '${i + 1}',
                style: TextStyle(fontSize: 11, color: cs.outline),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
              child: Text(
                _cell(row, _enCol),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: _enCol >= 0 ? cs.onSurface : cs.outline,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
              child: Text(
                _cell(row, _zhCol),
                style: TextStyle(
                  fontSize: 13,
                  color: _zhCol >= 0 ? cs.onSurface : cs.outline,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Table(
        columnWidths: const <int, TableColumnWidth>{
          0: IntrinsicColumnWidth(),
          1: FlexColumnWidth(2),
          2: FlexColumnWidth(3),
        },
        children: <TableRow>[
          TableRow(
            decoration: BoxDecoration(color: cs.surfaceContainerHighest),
            children: <Widget>[
              _th('#', cs),
              _th(_enCol >= 0 ? '英文' : '英文（未选）', cs),
              _th(_zhCol >= 0 ? '中文' : '中文（未选）', cs),
            ],
          ),
          ...body,
        ],
      ),
    );
  }

  Widget _th(String text, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _colPicker(String label, int value, ValueChanged<int> onChanged) {
    final List<DropdownMenuItem<int>> items = <DropdownMenuItem<int>>[
      const DropdownMenuItem<int>(value: -1, child: Text('不导入')),
    ];
    for (int i = 0; i < _colCount; i++) {
      final String sample = _rows!.isEmpty
          ? ''
          : _cell(_rows![_hasHeader ? 1 : 0], i);
      items.add(
        DropdownMenuItem<int>(
          value: i,
          child: Text(
            sample.isEmpty ? '第 ${i + 1} 列' : '第 ${i + 1} 列：$sample',
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }
    return Row(
      children: <Widget>[
        SizedBox(
          width: 110,
          child: Text(label, style: const TextStyle(fontSize: 13)),
        ),
        Expanded(
          child: DropdownButtonFormField<int>(
            initialValue: value,
            isExpanded: true,
            items: items,
            onChanged: (int? v) => onChanged(v ?? -1),
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomBar() {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: FilledButton.icon(
          onPressed: _importing ? null : _doImport,
          icon: _importing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download_done_outlined),
          label: const Text('导入到生词本', style: TextStyle(fontSize: 16)),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
      ),
    );
  }

  Widget _trackHint(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.school_outlined, size: 18, color: cs.onPrimaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '导入到「${TrackStore.labelOf(_target)}」',
              style: TextStyle(fontSize: 13, color: cs.onPrimaryContainer),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hint(ColorScheme cs, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        '· $text',
        style: TextStyle(
          fontSize: 12,
          height: 1.5,
          color: cs.onSurface.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}
