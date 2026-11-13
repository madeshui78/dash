# dash

一款极简的英语学习 App：每天打卡、读一篇作文精读、点词存进错词本、碎片时间快刷自测。

用 Flutter 写的 Android 应用，数据全部存在手机本地，不需要注册账号。

## 功能

- **每日打卡** — 一屏三样：连续天数、本月记录、一个按钮
- **作文精读** — 每天一篇，纸面排版无卡片；点词看释义，标红的词自动进错词本
- **快刷自测** — 一题一词，点完立刻对错并给释义，随时能停
- **单词本 / 错词本** — 标红与答错的词自动归集，可回到原文那一段；支持导入 PDF / Excel 单词表
- **AI 问答** — 问单词、问语法、改句子、练作文；对话存在本地
- **备份导出** — 一个文件拷到新手机即可迁移

## 下载

APK 见 [Releases](../../releases)。官网：[madeshui.com/dash.html](https://madeshui.com/dash.html)

- arm64 版：绝大多数 2018 年后的安卓手机
- 通用版：装不上或闪退时使用

## 构建

```bash
flutter pub get
flutter build apk --release             # 通用包
flutter build apk --release --split-per-abi   # 按架构拆分
```

签名配置放在 `android/key.properties` 与 `android/keystore/`，**这两个不进仓库**（见 `.gitignore`）。没有它们也能构建 debug 包，只是不能发版。

## 运行环境

- Android 7.0（API 24）及以上
- 被选中的 AI 功能需要自行配置：本地 Ollama 地址，或自己的 DeepSeek API Key。不配置不影响其他功能。

## 隐私

不注册、不上传学习数据，全部信息存于手机本地。完整说明见
[madeshui.com/dash-privacy.html](https://madeshui.com/dash-privacy.html)。

## 状态

个人项目，持续在改。1.0.2 是可分发版本。
