// 首启隐私政策拦截：未同意前不进入主界面。
// 拒绝时按工信部要求提供「不使用并退出」出口。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/consent_store.dart';
import 'privacy_page.dart';

class ConsentGate extends StatefulWidget {
  const ConsentGate({super.key, required this.child});

  final Widget child;

  @override
  State<ConsentGate> createState() => _ConsentGateState();
}

class _ConsentGateState extends State<ConsentGate> {
  /// null = 还在读本地记录
  bool? _accepted;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    bool ok = false;
    try {
      ok = await ConsentStore.isAccepted();
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    setState(() => _accepted = ok);
  }

  Future<void> _agree() async {
    try {
      await ConsentStore.accept();
    } catch (_) {
      // 写本地失败也不该把用户卡死在政策页上
    }
    if (!mounted) return;
    setState(() => _accepted = true);
  }

  Future<void> _reject() async {
    final bool? quit = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('需要同意隐私政策'),
        content: const Text('本应用会在你的手机本地保存学习记录。不同意隐私政策将无法使用本应用，确定要退出吗？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('再看看'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (quit == true) {
      await SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_accepted == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_accepted == true) {
      return widget.child;
    }
    return PrivacyPage(
      requireConsent: true,
      onAgree: _agree,
      onReject: _reject,
    );
  }
}
