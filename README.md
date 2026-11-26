# dash

一款极简的英语学习 App：每天打卡、读一篇作文精读、点词存进错词本、碎片时间快刷自测，
再把错词交给 AI 做一次结构化复盘。

用 Flutter 写的 Android 应用，学习数据全部存在手机本地，不需要注册账号。

详细用法见 [使用指南](docs/使用指南.md)。

## 功能

- **每日打卡** — 一屏三样：连续天数、本月记录、一个按钮
- **作文精读** — 每天一篇，纸面排版无卡片；点词看释义，标红的词自动进错词本
- **快刷自测** — 一题一词，点完立刻对错并给释义，随时能停
- **单词本 / 错词本** — 标红与答错的词自动归集，可回到原文那一段并高亮；支持导入 PDF / Excel 单词表
- **AI 问答** — 问单词、问语法、改句子、练作文；对话存在本地
- **错词复盘** — 在错词本点「提交今日错词」，AI 把词分类、逐条纠错、给记忆法和学习路线；
  复盘是问答页里的固定窗口，右侧有词目录可精准跳转，右下角悬浮窗可以继续追问
- **备份导出** — 一个文件拷到新手机即可迁移

## 首次使用

第一次打开需要填一个 DeepSeek API Key，作文生成、查词释义、错词复盘都依赖它，
没有 Key 无法进入应用。

- 获取地址：<https://platform.deepseek.com/api_keys>
- Key 只保存在本机数据库里，不会上传到任何服务器
- 进入后可在「设置 → DeepSeek」里更换

## 下载

APK 见 [Releases](../../releases)。

- arm64 版：绝大多数 2018 年后的安卓手机
- 通用版：装不上或闪退时使用

## 构建

```bash
flutter pub get
flutter build apk --release                    # 通用包
flutter build apk --release --split-per-abi    # 按架构拆分
```

签名配置放在 `android/key.properties` 与 `android/keystore/`，**这两个不进仓库**（见 `.gitignore`）。
没有它们也能构建 debug 包，只是不能发版。

## 技术栈

- Flutter / Dart，Android 单平台
- `sqflite` 本地数据库（作文、单词、错词、对话、复盘记录）
- DeepSeek Chat Completions API（作文生成、释义、复盘、问答）
- `flutter_tts` 朗读，`pdf` / `excel` 解析导入单词表

## 项目结构

```
lib/
  db/          数据库与迁移
  models/      数据模型（作文、单词、对话、复盘结果）
  pages/       页面（打卡、作文、单词、错词本、问答、设置、Key 门禁）
  services/    AI、TTS、赛道、导入导出、复盘队列
  widgets/     通用组件（复盘卡片、悬浮窗、目录、动效）
android/       Android 工程与签名配置（签名文件不入库）
```

## 运行环境

- Android 7.0（API 24）及以上
- 需要可用的 DeepSeek API Key

## 隐私

不注册、不上传学习数据，作文、单词、对话、复盘记录全部存在手机本地；
API Key 同样只存本机，仅用于直连 DeepSeek 接口。

## 状态

个人项目，持续在改。当前版本 1.10.0。

## 协议

[MIT](LICENSE) © 2026 madeshui
