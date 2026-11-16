// 设置页：DeepSeek 配置 + 学习偏好 + 数据备份。
// 所有配置都存在本地 settings 表里，改完点保存即可，不用改代码重新编译。

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../db/database_helper.dart';
import '../models/word.dart';
import '../services/ai_service.dart';
import '../services/essay_store.dart';
import '../services/backup_service.dart';
import '../services/study_settings.dart';
import '../services/track_store.dart';
import '../services/tts_service.dart';
import '../widgets/app_toast.dart';
import 'privacy_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // ---------- AI ----------
  final TextEditingController _deepseekKey = TextEditingController();
  final TextEditingController _deepseekModel = TextEditingController();

  bool _loading = true; // 还在读已保存的配置
  bool _testing = false; // 正在测试连接
  bool _saving = false; // 正在保存

  // ---------- 备份 ----------
  bool _busyBackup = false;

  // ---------- 学习 ----------
  int _dailyCount = StudySettings.defaultCount;
  String _dictationMode = 'list';
  String _studyFlow = 'steps';
  final TextEditingController _countInput = TextEditingController();

  // ---------- 发音 / 背景 ----------
  bool _ttsOn = true;
  double _speechRate = StudySettings.defaultRate;

  /// 作文字号
  double _essayFontSize = 17;
  final TextEditingController _context = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final AiConfig cfg = await AiService.loadConfig();
    final int count = await StudySettings.dailyCount();
    final String mode = await StudySettings.dictationMode();
    final String flow = await StudySettings.studyFlow();
    final String context = await AiService.loadUserContext();
    final bool tts = await DatabaseHelper.instance.getSetting('tts_enabled') != '0';
    final double rate = await StudySettings.speechRate();
    final double essaySize = await EssayStore.fontSize();
    if (!mounted) return;
    setState(() {
      _deepseekKey.text = cfg.deepseekKey;
      _deepseekModel.text = cfg.deepseekModel;
      _dailyCount = count;
      _dictationMode = mode;
      _studyFlow = flow;
      _countInput.text = '$count';
      _context.text = context;
      _ttsOn = tts;
      _speechRate = rate;
      _essayFontSize = essaySize;
      TtsService.enabled = tts; // 进设置就把开关同步过去，不用等保存
      _loading = false;
    });
  }

  /// 学习设置改完立刻存，不用点保存
  Future<void> _saveStudy() async {
    final int? n = int.tryParse(_countInput.text.trim());
    if (n == null || n < 1) {
      AppToast.show(context, '每天抽几个要填 1 以上的整数');
      return;
    }
    await StudySettings.setDailyCount(n);
    await StudySettings.setDictationMode(_dictationMode);
    await StudySettings.setStudyFlow(_studyFlow);
    if (!mounted) return;
    setState(() => _dailyCount = n);
    AppToast.show(context, '学习设置已保存');
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await AiService.saveConfig(
        deepseekKey: _deepseekKey.text.trim(),
        deepseekModel: _deepseekModel.text.trim(),
      );
      await AiService.saveUserContext(_context.text);
      // 发音开关改完立刻生效，不用等下次进设置
      TtsService.enabled = _ttsOn;
      await DatabaseHelper.instance
          .setSetting('tts_enabled', _ttsOn ? '1' : '0');
      if (!mounted) return;
      AppToast.show(context, '已保存');
    } catch (e) {
      if (!mounted) return;
      _showError('保存失败', e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 测试当前填的 Key 能不能连通
  Future<void> _test() async {
    setState(() => _testing = true);
    try {
      // 用界面上正在填的值测，不用非得先保存
      final AiConfig cfg = AiConfig(
        deepseekKey: _deepseekKey.text.trim(),
        deepseekModel: _deepseekModel.text.trim().isEmpty
            ? AiService.defaultDeepseekModel
            : _deepseekModel.text.trim(),
      );
      final String message = await AiService.testConnection(cfg);
      if (!mounted) return;
      _showResult('连接成功', message);
    } catch (e) {
      if (!mounted) return;
      _showError('连接失败', e);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  // ---------------- 备份 ----------------

  /// 导出：生成 JSON 文件后调系统分享面板，可以存网盘、发微信、存到本地都行
  Future<void> _export() async {
    setState(() => _busyBackup = true);
    try {
      final String json = await BackupService.exportJson();
      final Directory dir = await getTemporaryDirectory();
      final String stamp = _timestamp();
      final File file = File('${dir.path}${Platform.pathSeparator}'
          'english_backup_$stamp.json');
      await file.writeAsString(json);

      if (!mounted) return;
      // 调系统分享面板，用户可以选择存网盘、发微信、存到手机等任意去处
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile(file.path)],
          subject: '英语单词备份 $stamp',
          text: '英语单词本备份文件，可保存到网盘或发给自己',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showError('导出失败', e);
    } finally {
      if (mounted) setState(() => _busyBackup = false);
    }
  }

  /// 导入：选一个之前导出的 .json 文件，把单词合并回本地库
  Future<void> _import() async {
    setState(() => _busyBackup = true);
    try {
      // 打开系统文件选择器，只让选 .json
      final PlatformFile? picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: <String>['json'],
        dialogTitle: '选择备份文件',
      );
      if (picked == null) {
        // 用户取消了选择
        if (mounted) setState(() => _busyBackup = false);
        return;
      }

      final String? path = picked.path;
      if (path == null) {
        throw Exception('拿不到文件路径，换个文件管理器试试');
      }
      final String content = await File(path).readAsString();

      final int count = await BackupService.importJson(content);
      if (!mounted) return;
      AppToast.show(context, '已导入 $count 个单词');
    } catch (e) {
      if (!mounted) return;
      _showError('导入失败', e);
    } finally {
      if (mounted) setState(() => _busyBackup = false);
    }
  }

  /// 异常默认带 "Exception: " 前缀，显示前去掉
  String _msg(Object e) {
    return e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
  }

  /// 结果提示：短提示走 SnackBar，完整内容点「详情」弹窗看（能选中复制）
  void _showResult(String title, String msg) {
    final String head = title.isEmpty ? '' : '$title：';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$head$msg',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: '详情',
          onPressed: () {
            showDialog<void>(
              context: context,
              builder: (BuildContext ctx) => AlertDialog(
                title: Text(title.isEmpty ? '结果' : title),
                content: SelectableText(msg),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('关闭'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _showError(String title, Object e) => _showResult(title, _msg(e));

  /// 生成形如 20261008_1047 的时间戳，用作文件名

  String _timestamp() {
    final DateTime now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}';
  }

  @override
  void dispose() {
    _deepseekKey.dispose();
    _deepseekModel.dispose();
    _countInput.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        centerTitle: true,
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        surfaceTintColor: cs.surfaceTint,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                _sectionTitle(cs, 'AI'),
                TextFormField(
                  controller: _deepseekKey,
                  obscureText: true, // Key 是敏感信息，输入时打码
                  decoration: const InputDecoration(
                    labelText: 'DeepSeek API Key',
                    hintText: 'sk-xxxxxxxx',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.key_outlined),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _deepseekModel,
                  decoration: const InputDecoration(
                    labelText: '模型',
                    hintText: 'deepseek-chat',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.psychology_outlined),
                  ),
                ),
                const SizedBox(height: 8),
                _hint(cs, 'Key 在 platform.deepseek.com 申请。按量计费。'),

                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _testing ? null : _test,
                  icon: _testing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering_outlined),
                  label: const Text('测试连接'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('保存设置'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),

                const SizedBox(height: 28),
                const Divider(),
                const SizedBox(height: 12),

                _sectionTitle(cs, '发音与背景'),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('背单词时自动发音', style: TextStyle(fontSize: 14)),
                  subtitle: Text(
                    '每个词自动读一遍',
                    style: TextStyle(fontSize: 12, color: cs.outline),
                  ),
                  value: _ttsOn,
                  onChanged: (bool v) => setState(() => _ttsOn = v),
                ),
                const SizedBox(height: 6),
                _speechRateRow(cs),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _context,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: '我的背景（AI 据此造例句）',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 6),
                _hint(cs, 'AI 造例句时会参考。'),

                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('保存上面这些设置'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),

                const SizedBox(height: 28),
                const Divider(),
                const SizedBox(height: 12),

                _sectionTitle(cs, '学习设置'),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text('每天自动抽几个新词',
                          style: TextStyle(fontSize: 13, color: cs.onSurface)),
                    ),
                    SizedBox(
                      width: 90,
                      child: TextFormField(
                        controller: _countInput,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(),
                          suffixText: '个',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: <Widget>[
                    Text('作文字号',
                        style: TextStyle(fontSize: 13, color: cs.onSurface)),
                    const Spacer(),
                    Text(
                      '${_essayFontSize.round()}',
                      style: TextStyle(fontSize: 12, color: cs.outline),
                    ),
                  ],
                ),
                Slider(
                  value: _essayFontSize,
                  min: 14,
                  max: 24,
                  divisions: 10,
                  label: '${_essayFontSize.round()}',
                  onChanged: (double v) =>
                      setState(() => _essayFontSize = v),
                  onChangeEnd: (double v) => EssayStore.setFontSize(v),
                ),
                const SizedBox(height: 6),
                Text('默写用什么形式',
                    style: TextStyle(fontSize: 13, color: cs.onSurface)),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const <ButtonSegment<String>>[
                    ButtonSegment<String>(
                      value: 'list',
                      icon: Icon(Icons.list_alt),
                      label: Text('一屏列完'),
                    ),
                    ButtonSegment<String>(
                      value: 'card',
                      icon: Icon(Icons.style_outlined),
                      label: Text('逐个来'),
                    ),
                  ],
                  selected: <String>{_dictationMode},
                  onSelectionChanged: (Set<String> next) {
                    setState(() => _dictationMode = next.first);
                  },
                ),
                const SizedBox(height: 22),
                Text('学习走哪套流程',
                    style: TextStyle(fontSize: 13, color: cs.onSurface)),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const <ButtonSegment<String>>[
                    ButtonSegment<String>(
                      value: 'steps',
                      icon: Icon(Icons.format_list_numbered),
                      label: Text('四步流程'),
                    ),
                    ButtonSegment<String>(
                      value: 'loop',
                      icon: Icon(Icons.loop_outlined),
                      label: Text('连续小循环'),
                    ),
                  ],
                  selected: <String>{_studyFlow},
                  onSelectionChanged: (Set<String> next) {
                    setState(() => _studyFlow = next.first);
                  },
                ),
                const SizedBox(height: 8),
                _hint(
                  cs,
                  _studyFlow == 'loop'
                      ? '拼第 1 个 → 闪中文并朗读 → 拼第 2 个 → 回头考第 1 个，'
                          '依次往后。每一步都能听发音，耳朵必须参与。'
                      : '一批词过四遍：看英想中 → 看中想英 → 写中文 → 写英文。'
                          '适合一次性啃完一批。',
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: _saveStudy,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('保存学习设置'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                  ),
                ),
                const SizedBox(height: 8),
                _hint(
                  cs,
                  '现在每天抽 $_dailyCount 个。抽词只从「没掌握、也没抽过」的词里'
                      '随机取，跨天不会重复；词抽完了会提示你再导入一批。',
                ),

                const SizedBox(height: 28),
                const Divider(),
                const SizedBox(height: 12),

                _sectionTitle(cs, '数据备份'),
                const SizedBox(height: 12),
                _hint(
                  cs,
                  '卸载 App 会丢数据。导出后把文件存到网盘或发给自己，换手机/误删时导回来就行。',
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busyBackup ? null : _export,
                        icon: const Icon(Icons.upload_file_outlined),
                        label: const Text('导出备份'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: _busyBackup ? null : _import,
                        icon: const Icon(Icons.download_outlined),
                        label: const Text('导入备份'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                _sectionTitle(cs, '隐私'),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('隐私政策'),
                  subtitle: const Text('不注册账号，学习数据只存在你的手机里'),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (BuildContext _) => const PrivacyPage(),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _sectionTitle(ColorScheme cs, String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: cs.primary,
      ),
    );
  }

  /// 语速滑块。1.0 是正常说话，背单词一般要慢一点才听得清每个音节。
  Widget _speechRateRow(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Text('朗读语速', style: TextStyle(fontSize: 14)),
            const Spacer(),
            Text(
              '${_speechRate.toStringAsFixed(2)}×',
              style: TextStyle(fontSize: 13, color: cs.primary),
            ),
          ],
        ),
        Slider(
          value: _speechRate,
          min: StudySettings.minRate,
          max: StudySettings.maxRate,
          divisions: 17,
          label: _speechRate.toStringAsFixed(2),
          onChanged: (double v) {
            setState(() => _speechRate = v);
            TtsService.applyRate(v);
            TtsService.speak('pronunciation');
          },
        ),
        _hint(
          cs,
          '往左更慢（听得清每个音节），往右更快（接近正常说话）。'
              '拖动时会念一个词给你试听。',
        ),
      ],
    );
  }

  Widget _hint(ColorScheme cs, String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        height: 1.5,
        color: cs.onSurface.withValues(alpha: 0.5),
      ),
    );
  }
}
