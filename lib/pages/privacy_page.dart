// 隐私政策页。上架必填项：商店后台要填「隐私政策链接」，App 内也要能随时打开。
// 首启时 requireConsent = true，用户不点「同意」就进不了主界面（工信部检测的硬性要求）。

import 'package:flutter/material.dart';

/// 上架前必须改成真实信息：商店审核会核对这里的开发者主体和联系邮箱，
/// 与你在商店后台填写的是否一致。
const String kAppName = 'dash';
const String kDeveloper = '高岩峰';
const String kContactEmail = 'gaoyanfeng_7@163.com';
const String kPolicyDate = '2026 年 11 月 12 日';

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({
    super.key,
    this.requireConsent = false,
    this.onAgree,
    this.onReject,
  });

  /// true 时显示底部「同意/不同意」按钮，用于首启拦截
  final bool requireConsent;
  final VoidCallback? onAgree;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('隐私政策'),
        automaticallyImplyLeading: !requireConsent,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: <Widget>[
            Text(
              '$kAppName 隐私政策',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              '更新日期：$kPolicyDate',
              style: TextStyle(fontSize: 12, color: cs.outline),
            ),
            const SizedBox(height: 4),
            Text(
              '开发者：$kDeveloper',
              style: TextStyle(fontSize: 12, color: cs.outline),
            ),
            const SizedBox(height: 14),
            _p('本应用是一款背单词与句式训练工具。我们非常重视你的个人信息保护，本政策说明本应用如何处理你的信息。请你在使用前仔细阅读。'),

            _h('一、我们收集哪些信息'),
            _p('本应用不需要注册账号，不收集你的手机号、通讯录、位置、设备识别码或任何可识别你身份的信息。'),
            _p('1. 你主动录入的单词、例句、笔记，以及导入的单词表内容：仅保存在你的手机本地数据库。'),
            _p('2. 你主动选择导入的文件（Excel / CSV / PDF）：仅在手机本地解析，不会上传到我们的服务器。'),
            _p('3. 学习记录（背诵次数、正确率、复习计划）：仅保存在本地数据库。'),

            _h('二、这些信息用来做什么'),
            _p('只用于在你手机上展示单词本、安排复习计划、生成学习统计。我们不会把这些内容用于广告、用户画像或任何其他用途。'),

            _h('三、信息存在哪里、保存多久'),
            _p('全部信息存储在手机本地的 SQLite 数据库中。卸载应用即全部删除。我们没有服务器保存你的学习数据。'),

            _h('四、AI 功能说明（重要）'),
            _p('AI 问答、AI 造句、词根词缀拆解、例句补全属于可选功能，有两种工作方式，由你在「设置 - AI 模型」中自行选择：'),
            _p('1. 本地 Ollama：请求只发送到你指定的局域网地址（例如 http://192.168.1.2:11434），由你自己的电脑处理，不经过任何第三方服务器。'),
            _p('2. DeepSeek 云端：只有你自行填写自己的 DeepSeek API Key 后才会启用。启用后你输入的提问内容会通过 HTTPS 发送至 api.deepseek.com 用于生成结果。该服务由杭州深度求索人工智能基础技术研究有限公司提供，其数据处理规则适用其公开的隐私政策。'),
            _p('不启用任何 AI 功能，不影响背单词、复习、导入等核心功能。'),

            _h('五、我们申请了哪些系统权限'),
            _p('1. 网络访问（INTERNET）：仅用于上述第四条的 AI 请求。关闭 AI 功能时，应用不会发起任何网络请求。'),
            _p('2. 读取文件：仅在你主动点击「导入单词表」时打开系统文件选择器，由你选择具体文件，应用无权访问其他文件。'),
            _p('3. 语音朗读：调用手机系统自带的文字转语音引擎在本机发音，不录音，不上传麦克风内容。'),
            _p('本应用未申请相机、麦克风、通讯录、短信、位置、电话状态等权限。'),

            _h('六、第三方组件'),
            _p('本应用基于 Flutter 跨平台框架开发，使用了 sqflite（本地数据库）、path_provider（本地路径）、flutter_tts（系统语音合成）、file_picker（文件选择）、share_plus（分享导出）、archive 与 xml（压缩包与表格解析）、syncfusion_flutter_pdf（PDF 本地解析）、http（网络请求）等开源组件。'),
            _p('这些组件均在你的手机本地运行。本应用不包含广告 SDK 或用户行为统计 SDK，我们不会向任何第三方出售或共享你的个人信息。'),

            _h('七、你的权利'),
            _p('你可以随时在应用内查看、修改、删除单词与学习记录，可导出备份文件自行保存，卸载应用即可删除全部本地数据。'),
            _p('如需行使查阅、更正、删除个人信息等权利，可通过下方邮箱联系我们，我们会在 15 个工作日内答复。'),

            _h('八、未成年人保护'),
            _p('本应用是学习工具，不设社交与付费功能。若你是未满 14 周岁的未成年人，请在监护人陪同下阅读本政策并使用本应用。'),

            _h('九、政策更新'),
            _p('本政策内容变更时，我们会在应用启动时重新展示本页，请你重新确认。若你不同意变更后的内容，可停止使用并卸载应用。'),

            _h('十、联系我们'),
            _p('开发者：$kDeveloper'),
            _p('联系邮箱：$kContactEmail'),
            _p('我们会在收到请求后 15 个工作日内回复。'),

            if (requireConsent) ...<Widget>[
              const SizedBox(height: 8),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                '点击「同意并继续」即表示你已阅读并同意本隐私政策的全部内容。',
                style: TextStyle(fontSize: 13, color: cs.outline),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onReject,
                      child: const Text('不同意'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: onAgree,
                      child: const Text('同意并继续'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _h(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 6),
      child: Text(
        text,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _p(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: const TextStyle(fontSize: 14, height: 1.6)),
    );
  }
}
