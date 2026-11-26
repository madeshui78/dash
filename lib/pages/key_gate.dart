// 首次启动的 Key 门禁：没有 DeepSeek Key 就不让进。
//
// Key 只存在本机 settings 表里，不上传。这里不做网络校验——
// 网络校验会把「暂时没网」也拦在门外，体验更差；真正调用失败时页面会提示。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../db/database_helper.dart';
import '../theme/module_palette.dart';
import '../widgets/app_toast.dart';

class KeyGate extends StatefulWidget {
  final Widget child;

  const KeyGate({super.key, required this.child});

  @override
  State<KeyGate> createState() => _KeyGateState();
}

class _KeyGateState extends State<KeyGate> {
  static const String _url = 'https://platform.deepseek.com/api_keys';

  bool? _hasKey;
  bool _obscure = true;
  String? _error;
  final TextEditingController _key = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final String? saved = await DatabaseHelper.instance.getSetting(
      'deepseek_key',
    );
    if (!mounted) return;
    setState(() => _hasKey = (saved ?? '').trim().length >= 20);
  }

  Future<void> _save() async {
    final String k = _key.text.trim();
    if (k.length < 20 || !k.startsWith('sk-')) {
      setState(() => _error = 'Key 格式不对：DeepSeek 的 Key 以 sk- 开头，长度 20 以上');
      return;
    }
    await DatabaseHelper.instance.setSetting('deepseek_key', k);
    if (!mounted) return;
    setState(() {
      _error = null;
      _hasKey = true;
    });
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(const ClipboardData(text: _url));
    if (!mounted) return;
    AppToast.show(context, '链接已复制，去浏览器打开');
  }

  @override
  Widget build(BuildContext context) {
    if (_hasKey == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_hasKey == true) return widget.child;

    final ModulePalette p = ModulePalette.of(context);
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.asset(
                    'assets/icon.png',
                    width: 76,
                    height: 76,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Center(
                child: Text(
                  'dash',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: p.ink,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  '每天一小段，把英语跑成习惯',
                  style: TextStyle(fontSize: 12, color: p.muted),
                ),
              ),
              const SizedBox(height: 34),
              Text(
                '先填一个 DeepSeek Key',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: p.ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '作文生成、查词释义、错词复盘都靠它。没有 Key，应用没法正常使用。'
                'Key 只保存在这台手机上，不会上传到别处。',
                style: TextStyle(fontSize: 13, height: 1.65, color: p.muted),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                decoration: BoxDecoration(
                  color: p.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: p.line),
                ),
                child: TextField(
                  controller: _key,
                  obscureText: _obscure,
                  autofocus: false,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'DeepSeek API Key',
                    hintText: 'sk-...',
                    errorText: _error,
                    border: InputBorder.none,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 18,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  onSubmitted: (_) => _save(),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: p.blue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('保存并开始'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: OutlinedButton.icon(
                  onPressed: _copyLink,
                  icon: const Icon(Icons.open_in_new, size: 17),
                  label: const Text('去获取 Key'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: p.ink,
                    side: BorderSide(color: p.line),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: TextButton(
                  onPressed: () => SystemNavigator.pop(),
                  child: Text(
                    '没有 Key，先退出应用',
                    style: TextStyle(fontSize: 12, color: p.muted),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: SelectableText(
                  _url,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: p.muted),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '进入后也可以在「设置 → DeepSeek」里随时更换 Key。',
                style: TextStyle(fontSize: 12, height: 1.6, color: p.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
