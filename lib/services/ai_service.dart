// AI 服务：统一封装 DeepSeek 调用。
// 查词、补全、长难句分析、多轮问答都从这里走。
// 页面上只跟 AiService 打交道。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../db/database_helper.dart';

/// AI 批量补全出来的一条词典条目。
/// 字段为空表示 AI 没给出来，调用方自己决定要不要重试。
class WordEntry {
  final String en;
  final String phonetic;
  final String zh;
  final String example;
  final String root;

  const WordEntry({
    required this.en,
    required this.phonetic,
    required this.zh,
    required this.example,
    required this.root,
  });

  bool get isEmpty =>
      phonetic.isEmpty && zh.isEmpty && example.isEmpty && root.isEmpty;
}

/// AI 看完样本行后给出的列判断
class ColumnGuess {
  /// 英文单词在第几列（0 开始）
  final int enColumn;

  /// 中文释义在第几列，没有就是 null
  final int? zhColumn;

  /// 第一行是不是表头
  final bool hasHeader;

  const ColumnGuess({
    required this.enColumn,
    this.zhColumn,
    this.hasHeader = false,
  });
}

/// 一次调用所需的全部配置，从设置里读出来
class AiConfig {
  final String deepseekKey;
  final String deepseekModel;

  const AiConfig({
    required this.deepseekKey,
    required this.deepseekModel,
  });

  /// 当前在用的模型名，界面上显示用
  String get modelName => deepseekModel;
}
/// 对话里的一条消息。role 只有 'user' / 'assistant' 两种。
/// id 和 createdAt 是落库之后才有的（存在 chat_messages 表里，杀掉 App 也在）。
class ChatMessage {
  final int? id;
  final String role;
  final String content;
  final DateTime? createdAt;

  const ChatMessage({
    this.id,
    required this.role,
    required this.content,
    this.createdAt,
  });

  bool get isUser => role == 'user';

  ChatMessage copyWith({
    int? id,
    String? role,
    String? content,
    DateTime? createdAt,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class AiService {
  AiService._(); // 纯静态工具类，禁止实例化

  // 默认值：设置页从没保存过时使用
  static const String defaultDeepseekModel = 'deepseek-chat';

  /// DeepSeek 的接口地址（兼容 OpenAI 格式）
  static const String deepseekEndpoint =
      'https://api.deepseek.com/chat/completions';

  /// 词典角色设定：让模型老老实实只输出 JSON。
  /// 注意：DeepSeek 开了 response_format=json_object 时，提示词里必须出现
  /// **小写** json 字样，否则直接返回 400——大写 JSON 不算，踩过这个坑。
  static const String _systemPrompt = '你是一部英汉词典。无论用户说什么，'
      '都只输出一个 json 对象（小写的 json），不要输出任何解释性文字或多余内容。';

  static const Duration _timeout = Duration(seconds: 60);

  /// 对话比查词慢，给足时间
  static const Duration _chatTimeout = Duration(seconds: 120);

  // ---------------- 配置读写 ----------------

  /// 从本地设置里读出完整配置
  static Future<AiConfig> loadConfig() async {
    final DatabaseHelper db = DatabaseHelper.instance;
    return AiConfig(
      deepseekKey: await db.getSetting('deepseek_key') ?? '',
      deepseekModel:
          await db.getSetting('deepseek_model') ?? defaultDeepseekModel,
    );
  }

  /// 保存配置（设置页调用）
  static Future<void> saveConfig({
    required String deepseekKey,
    required String deepseekModel,
  }) async {
    final DatabaseHelper db = DatabaseHelper.instance;
    await db.setSetting('deepseek_key', deepseekKey);
    await db.setSetting('deepseek_model', deepseekModel);
  }

  /// 统一出口：所有 AI 请求都从 DeepSeek 走。
  /// 之前这里还有一层「本地 / 云端」的路由，本地那套已经整块删掉了，
  /// 保留这个方法只是让调用处不用跟着改。
  static Future<T> run<T>(
    AiConfig cfg,
    Future<T> Function(AiConfig) body,
  ) async {
    return body(cfg);
  }

  // ---------------- 连通性测试 ----------------

  /// 把超时、断网、证书这类错误翻成人话。
  static Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on TimeoutException {
      throw Exception('请求超时。检查手机能不能上外网。');
    } on SocketException catch (e) {
      throw Exception('网络连不上（${e.message}）。检查手机网络');
    } on HandshakeException {
      throw Exception(
        'HTTPS 握手失败：当前网络可能拦截了 api.deepseek.com，换个网络（关掉代理/VPN）再试',
      );
    } on http.ClientException catch (e) {
      throw Exception('网络请求失败：${e.message}');
    } on FormatException {
      throw Exception('服务器返回的内容不是合法 JSON，检查接口地址填对没有');
    }
  }

  /// 测试当前配置能不能用。成功返回一句人话描述，失败抛异常。
  static Future<String> testConnection(AiConfig cfg) async {
    return _guard(() async {
      if (cfg.deepseekKey.trim().isEmpty) {
        throw Exception('还没有填 DeepSeek 的 API Key');
      }
      // 测试连接不带 json 输出模式，把环境因素降到最少
      await _callDeepSeek(cfg, '回复 ok 两个字', maxTokens: 8, jsonMode: false);
      return 'DeepSeek 连接成功（模型 ${cfg.deepseekModel}）';
    });
  }

  // ---------------- 查词 ----------------

  /// 让 AI 生成一个单词的词典条目，
  /// 返回 {"phonetic": "音标", "zh": "中文释义", "example": "英文例句"}
  static Future<Map<String, String>> lookupWord(
    AiConfig cfg,
    String word,
  ) async {
    final String prompt = '为英文单词 "$word" 生成词典条目，严格按此 json 格式输出：'
        '{"phonetic":"音标，形如 /xx/","zh":"简短中文释义",'
        '"example":"一个简单常用的英文例句"}';

    final String raw = await _guard<String>(() {
      return _callDeepSeek(cfg, prompt);
    });

    return _parseEntry(raw);
  }

  /// 调用 DeepSeek 的 /chat/completions（OpenAI 兼容格式）
  static Future<String> _callDeepSeek(
    AiConfig cfg,
    String prompt, {
    int maxTokens = 300,
    bool jsonMode = true,
  }) async {
    final String key = cfg.deepseekKey.trim();
    if (key.isEmpty) {
      throw Exception('还没填 DeepSeek 的 API Key，去设置页填一下');
    }
    if (!key.startsWith('sk-')) {
      throw Exception(
          'Key 格式不对：DeepSeek 的 Key 以 sk- 开头，检查一下是不是复制少了');
    }

    final http.Response response = await http
        .post(
          Uri.parse(deepseekEndpoint),
          headers: <String, String>{
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $key',
          },
          body: jsonEncode(<String, dynamic>{
            'model': cfg.deepseekModel,
            'messages': <Map<String, String>>[
              <String, String>{'role': 'system', 'content': _systemPrompt},
              <String, String>{'role': 'user', 'content': prompt},
            ],
            // 让云端只返回 json。DeepSeek 的规矩：开这个参数，
            // 提示词里就必须有小写 json 字样，否则 400。
            if (jsonMode)
              'response_format': <String, String>{'type': 'json_object'},
            'temperature': 0.3,
            'max_tokens': maxTokens,
            'stream': false,
          }),
        )
        .timeout(_timeout);

    if (response.statusCode != 200) {
      throw Exception(_httpError(response.statusCode, response.body));
    }
    final Map<String, dynamic> data =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final List<dynamic> choices = data['choices'] as List<dynamic>? ?? [];
    if (choices.isEmpty) throw Exception('云端返回内容为空');
    final Map<String, dynamic> message =
        choices.first['message'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final String text = (message['content'] as String? ?? '').trim();
    if (text.isEmpty) throw Exception('云端返回了空内容');
    return text;
  }

  // ---------------- 通用补全（带自定义 system 提示） ----------------

  /// 一次自由对话式补全，system / 最大 token 都由调用方给。
  /// 批量补全、列识别、长难句这些都走它。
  static Future<String> _complete(
    AiConfig cfg,
    String systemPrompt,
    String userPrompt, {
    int maxTokens = 3000,
    bool jsonMode = true,
  }) async {
    return _completeDeepSeek(
        cfg, systemPrompt, userPrompt, maxTokens, jsonMode);
  }

  static Future<String> _completeDeepSeek(
    AiConfig cfg,
    String systemPrompt,
    String userPrompt,
    int maxTokens,
    bool jsonMode,
  ) async {
    final String key = cfg.deepseekKey.trim();
    if (key.isEmpty) {
      throw Exception('还没填 DeepSeek 的 API Key，去设置页填一下');
    }
    if (!key.startsWith('sk-')) {
      throw Exception(
          'Key 格式不对：DeepSeek 的 Key 以 sk- 开头，检查一下是不是复制少了');
    }

    final http.Response response = await http
        .post(
          Uri.parse(deepseekEndpoint),
          headers: <String, String>{
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $key',
          },
          body: jsonEncode(<String, dynamic>{
            'model': cfg.deepseekModel,
            'messages': <Map<String, String>>[
              <String, String>{'role': 'system', 'content': systemPrompt},
              <String, String>{'role': 'user', 'content': userPrompt},
            ],
            // DeepSeek 的规矩：开 json_object 时提示词里必须有小写 json 字样
            if (jsonMode)
              'response_format': <String, String>{'type': 'json_object'},
            'temperature': 0.3,
            'max_tokens': maxTokens,
            'stream': false,
          }),
        )
        .timeout(_chatTimeout);

    if (response.statusCode != 200) {
      throw Exception(_httpError(response.statusCode, response.body));
    }
    final Map<String, dynamic> data =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final List<dynamic> choices = data['choices'] as List<dynamic>? ?? [];
    if (choices.isEmpty) throw Exception('云端返回内容为空');
    final Map<String, dynamic> message =
        choices.first['message'] as Map<String, dynamic>? ?? <String, dynamic>{};
    return (message['content'] as String? ?? '').trim();
  }

  // ---------------- 批量补全 / 列识别 / 长难句 ----------------

  /// 一次请求补全多少个词。25 是实测比较稳的量：再多容易超 token 或被截断。
  static const int batchSize = 25;

  /// 批量补全：一次请求给一批词补齐音标、释义、例句、词根。
  /// 逐个词调用要几百次请求，根本不现实，所以按批走。
  /// 返回的条数与入参一一对应，AI 漏掉的词会是空内容（调用方决定是否重试）。
  static Future<List<WordEntry>> lookupWords(
    AiConfig cfg,
    List<String> words,
  ) async {
    if (words.isEmpty) return const <WordEntry>[];

    final String context = await loadUserContext();
    final String prompt = '为下面这批英文单词各生成一条词典条目。\n'
        '严格按 json 数组输出，每个元素形如：'
        '{"en":"单词原文","phonetic":"/音标/","zh":"简短中文释义",'
        '"example":"一个简单常用的英文例句",'
        '"root":"词根词缀拆解，用一句话中文说明"}\n'
        '例句要贴合这个人的背景：$context\n'
        '只输出 json，不要任何解释文字。单词列表：\n'
        '${words.join('\n')}';

    final String raw = await _guard<String>(() {
      return run(
        cfg,
        (AiConfig c) => _complete(
          c,
          '你是一部英汉词典，擅长词根词缀拆解，能结合学习者背景造例句。',
          prompt,
          maxTokens: 4000,
        ),
      );
    });

    return _parseEntryList(raw, words);
  }

  /// 作文补词专用：只要一个短释义。
  /// 比 lookupWords 少要音标/例句/词根，输出小很多，一批能塞 40 个。
  static const int glossBatchSize = 40;

  static Future<Map<String, String>> lookupGlosses(
    AiConfig cfg,
    List<String> words,
  ) async {
    if (words.isEmpty) return <String, String>{};
    final String prompt = '给下面每个英文单词一条简短中文释义。\n'
        '严格输出 JSON 数组，每个元素形如：{"en":"单词原文","zh":"中文，12 字以内"}\n'
        '不要音标、不要例句、不要词根、不要解释。单词列表：\n'
        '${words.join('\n')}';

    final String raw = await _guard<String>(() {
      return run(
        cfg,
        (AiConfig c) => _complete(
          c,
          '你是一部紧凑的英汉词典，只给最短的中文释义。',
          prompt,
          maxTokens: 1600,
        ),
      );
    });

    String text = raw.trim();
    if (text.startsWith('```')) {
      text = text.replaceAll('```json', '').replaceAll('```', '').trim();
    }
    final int start = text.indexOf('[');
    final int end = text.lastIndexOf(']');
    if (start >= 0 && end > start) text = text.substring(start, end + 1);

    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      return <String, String>{};
    }
    if (decoded is! List) return <String, String>{};

    final Map<String, String> out = <String, String>{};
    for (final Object? item in decoded) {
      if (item is! Map) continue;
      final String en = (item['en'] ?? '').toString().trim().toLowerCase();
      final String zh = (item['zh'] ?? '').toString().trim();
      if (en.isNotEmpty && zh.isNotEmpty) out[en] = zh;
    }
    return out;
  }

  /// 错词复盘：输入已经拼好的错词清单，返回结构化 JSON 文本
  static Future<String> digestWrongWords(
    AiConfig cfg,
    String payload,
  ) async {
    final String prompt = '下面是一批需要复盘的英语错词和短语，'
        '有的来自作文标记（带原句），有的来自做题（带错题次数）。\n'
        '请整理成学习复盘，严格输出 JSON，不要 markdown，不要解释：\n'
        '{"groups":[{"title":"组名","words":["词1"],"tip":"一句话"}],'
        '"items":[{"word":"词或短语","meaning":"正确意思","memory":"一句记忆方法",'
        '"group":"所属组名"}],'
        '"path":["第一步","第二步","第三步"]}\n'
        '要求：items 覆盖每一个词，memory 控制在 30 字内；'
        '分组不超过 4 组；path 三步。\n\n$payload';

    return _guard<String>(() {
      return run(
        cfg,
        (AiConfig c) => _complete(
          c,
          '你是一名英语错词教练，擅长归类、纠错和记忆法，严格输出 JSON。',
          prompt,
          maxTokens: 3000,
        ),
      );
    });
  }

  /// 逐句翻译一段。返回 [{en, zh}]，解析失败返回空列表。
  static Future<List<Map<String, String>>> translateSentences(
    AiConfig cfg,
    String text,
  ) async {
    final String prompt = '把下面这段英语逐句翻译成中文。\n'
        '严格输出 JSON 数组，不要 markdown，不要解释：\n'
        '[{"en":"原句","zh":"中文译文"}]\n'
        '一句一条，按原文顺序，不要合并句子。\n\n$text';

    final String raw = await _guard<String>(() {
      return run(
        cfg,
        (AiConfig c) => _complete(
          c,
          '你是一名英语翻译，译文自然准确，严格输出 JSON。',
          prompt,
          maxTokens: 2400,
        ),
      );
    });

    String s = raw.trim();
    s = s.replaceAll(RegExp(r'^```[a-zA-Z]*'), '').replaceAll('```', '');
    final int start = s.indexOf('[');
    final int end = s.lastIndexOf(']');
    if (start < 0 || end <= start) return <Map<String, String>>[];
    try {
      final Object? data = jsonDecode(s.substring(start, end + 1));
      if (data is! List) return <Map<String, String>>[];
      final List<Map<String, String>> out = <Map<String, String>>[];
      for (final Object? item in data) {
        if (item is! Map) continue;
        final String en = (item['en'] ?? '').toString().trim();
        final String zh = (item['zh'] ?? '').toString().trim();
        if (en.isNotEmpty) out.add(<String, String>{'en': en, 'zh': zh});
      }
      return out;
    } catch (_) {
      return <Map<String, String>>[];
    }
  }

  static List<WordEntry> _parseEntryList(String raw, List<String> words) {
    String text = raw.trim();
    if (text.startsWith('```')) {
      text = text.replaceAll('```json', '').replaceAll('```', '').trim();
    }
    // 有的模型前后爱加两句废话，只取方括号包住的那段
    final int start = text.indexOf('[');
    final int end = text.lastIndexOf(']');
    if (start >= 0 && end > start) text = text.substring(start, end + 1);

    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      throw Exception('AI 返回的内容不是合法 JSON，换个小一点的批次再试');
    }

    final List<dynamic> list = decoded is List
        ? decoded
        : (decoded is Map && decoded['words'] is List
            ? decoded['words'] as List<dynamic>
            : <dynamic>[]);

    final Map<String, WordEntry> byEn = <String, WordEntry>{};
    for (final Object? item in list) {
      if (item is! Map) continue;
      final String en = (item['en'] as String? ?? '').trim();
      if (en.isEmpty) continue;
      byEn[en.toLowerCase()] = WordEntry(
        en: en,
        phonetic: (item['phonetic'] as String? ?? '').trim(),
        zh: (item['zh'] as String? ?? '').trim(),
        example: (item['example'] as String? ?? '').trim(),
        root: (item['root'] as String? ?? '').trim(),
      );
    }

    return words
        .map(
          (String w) => byEn[w.toLowerCase()] ??
              WordEntry(
                en: w,
                phonetic: '',
                zh: '',
                example: '',
                root: '',
              ),
        )
        .toList();
  }

  /// 让 AI 看几行样本，判断哪一列是英文、哪一列是中文、首行是不是表头。
  /// 返回 null 表示它觉得这根本不是单词表（比如是一整篇文章）。
  static Future<ColumnGuess?> guessColumns(
    AiConfig cfg,
    List<List<String>> sample,
  ) async {
    if (sample.isEmpty) return null;

    final String dump = jsonEncode(
      sample.take(12).map((List<String> r) => r).toList(),
    );
    final String prompt = '下面是一个文件的前几行，每行是一个数组（数组的第 0 项'
        '是这一行的第 1 列，以此类推）。\n'
        '判断它是不是一张单词表，如果是，指出：\n'
        'is_word_list：是否单词表（布尔）\n'
        'en_column：英文单词在第几列（从 0 开始数）\n'
        'zh_column：中文释义在第几列；没有就填 null\n'
        'has_header：第一行是不是表头（布尔）\n'
        '严格按 json 输出这四个字段，不要解释。数据：\n$dump';

    final String raw = await _guard<String>(() {
      return run(
        cfg,
        (AiConfig c) => _complete(
          c,
          '你负责判断表格结构，只输出 json。',
          prompt,
          maxTokens: 200,
        ),
      );
    });

    try {
      String text = raw.trim();
      if (text.startsWith('```')) {
        text = text.replaceAll('```json', '').replaceAll('```', '').trim();
      }
      final int s = text.indexOf('{');
      final int e = text.lastIndexOf('}');
      if (s >= 0 && e > s) text = text.substring(s, e + 1);
      final Map<String, dynamic> m = jsonDecode(text) as Map<String, dynamic>;

      if (m['is_word_list'] == false) return null;
      final int? en = m['en_column'] as int?;
      if (en == null) return null;
      return ColumnGuess(
        enColumn: en,
        zhColumn: m['zh_column'] as int?,
        hasHeader: m['has_header'] == true,
      );
    } catch (_) {
      // 判断不出来就让页面回到手动选列，不算失败
      return null;
    }
  }

  /// 长难句分析：拆主谓宾、点出从句和生词，回一段中文讲解。
  static Future<String> analyzeSentence(AiConfig cfg, String sentence) async {
    final String prompt = '用中文拆解这个英文句子：$sentence\n'
        '按这四块讲，别写客套话：\n'
        '1. 句子主干（主谓宾）\n'
        '2. 从句 / 修饰成分分别修饰什么\n'
        '3. 里面的生词或短语，给中文意思\n'
        '4. 整句的中文翻译';

    final String text = await _guard<String>(() {
      return run(
        cfg,
        (AiConfig c) => _complete(
          c,
          '你是英语语法老师，讲解简洁、直击要点。',
          prompt,
          maxTokens: 1200,
          jsonMode: false,
        ),
      );
    });
    return text.isEmpty ? '（这次没分析出来，换个句子试试）' : text;
  }

  /// 给一个单词造贴合用户背景的例句，返回若干条
  static Future<List<String>> makeExamples(
    AiConfig cfg,
    String word,
  ) async {
    final String context = await loadUserContext();
    final String prompt = '为英文单词 "$word" 造 3 个英文例句。\n'
        '要求：句子简短好懂（不超过 15 个词），场景贴合这个人的背景：$context。\n'
        '严格按 json 数组输出，形如 ["句子1","句子2","句子3"]，不要解释。';

    final String raw = await _guard<String>(() {
      return run(
        cfg,
        (AiConfig c) => _complete(
          c,
          '你负责造贴合学习者背景的英文例句，只输出 json。',
          prompt,
          maxTokens: 600,
        ),
      );
    });

    try {
      String text = raw.trim();
      if (text.startsWith('```')) {
        text = text.replaceAll('```json', '').replaceAll('```', '').trim();
      }
      final int s = text.indexOf('[');
      final int e = text.lastIndexOf(']');
      if (s >= 0 && e > s) text = text.substring(s, e + 1);
      final List<dynamic> list = jsonDecode(text) as List<dynamic>;
      return list
          .map((Object? o) => (o as String?)?.trim() ?? '')
          .where((String s) => s.isNotEmpty)
          .toList();
    } catch (_) {
      return const <String>[];
    }
  }

  /// 学习者的背景设定，喂给 AI 让它造的例句更贴身。
  /// 存在 settings 里，设置页可改。
  static const String defaultUserContext = '不尽长江滚滚来';

  static Future<String> loadUserContext() async {
    final String? v =
        await DatabaseHelper.instance.getSetting('user_context');
    final String s = (v ?? '').trim();
    return s.isEmpty ? defaultUserContext : s;
  }

  static Future<void> saveUserContext(String value) async {
    await DatabaseHelper.instance.setSetting('user_context', value.trim());
  }

  // ---------------- 对话（AI 问答页） ----------------

  /// 多轮对话：把历史消息一起发给模型，返回它这次的回复。
  /// history 里最后一条应该是用户刚说的话。
  /// systemPrompt 由调用方拼（里面带上当前在准备哪门考试）。
  static Future<String> chat(
    AiConfig cfg,
    List<ChatMessage> history, {
    String systemPrompt = '',
  }) async {
    // 只带最近 20 条：长对话也要留够上下文，但别把整段历史都塞进去
    final List<ChatMessage> recent = history.length > 20
        ? history.sublist(history.length - 20)
        : history;

    final String text = await _guard<String>(() {
      return _chatDeepSeek(cfg, systemPrompt, recent);
    });

    final String reply = text.trim();
    return reply.isEmpty ? '（AI 这次没有返回内容，换个问法试试）' : reply;
  }

  /// DeepSeek 多轮对话
  static Future<String> _chatDeepSeek(
    AiConfig cfg,
    String systemPrompt,
    List<ChatMessage> history,
  ) async {
    final String key = cfg.deepseekKey.trim();
    if (key.isEmpty) {
      throw Exception('还没填 DeepSeek 的 API Key，去设置页填一下');
    }
    if (!key.startsWith('sk-')) {
      throw Exception(
          'Key 格式不对：DeepSeek 的 Key 以 sk- 开头，检查一下是不是复制少了');
    }

    final http.Response response = await http
        .post(
          Uri.parse(deepseekEndpoint),
          headers: <String, String>{
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $key',
          },
          body: jsonEncode(<String, dynamic>{
            'model': cfg.deepseekModel,
            'messages': <Map<String, String>>[
              if (systemPrompt.isNotEmpty)
                <String, String>{'role': 'system', 'content': systemPrompt},
              ...history.map(
                (ChatMessage m) => <String, String>{
                  'role': m.isUser ? 'user' : 'assistant',
                  'content': m.content,
                },
              ),
            ],
            'temperature': 0.7,
            'max_tokens': 1200,
            'stream': false,
          }),
        )
        .timeout(_chatTimeout);

    if (response.statusCode != 200) {
      throw Exception(_httpError(response.statusCode, response.body));
    }
    final Map<String, dynamic> data =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final List<dynamic> choices = data['choices'] as List<dynamic>? ?? [];
    if (choices.isEmpty) throw Exception('云端返回内容为空');
    final Map<String, dynamic> message =
        choices.first['message'] as Map<String, dynamic>? ?? <String, dynamic>{};
    return (message['content'] as String? ?? '').trim();
  }

  // ---------------- 工具 ----------------

  /// 把 DeepSeek 的 HTTP 错误翻成人话。
  /// 之前只报「HTTP 401」，看不出到底哪错了，现在按状态码给具体原因。
  static String _httpError(int code, String body) {
    String detail = '';
    try {
      final Map<String, dynamic> m = jsonDecode(body) as Map<String, dynamic>;
      final Object? err = m['error'];
      if (err is Map) {
        detail = (err['message'] as String? ?? '').trim();
      } else if (err is String) {
        detail = err;
      }
    } catch (_) {
      // 返回的不是 JSON（比如网关的 HTML 报错页），就用原文的前 120 字
      detail = body.trim();
      if (detail.length > 120) detail = '${detail.substring(0, 120)}…';
    }

    switch (code) {
      case 401:
        return 'DeepSeek 拒绝了请求（401）：Key 无效或已失效。'
            '${detail.isEmpty ? '' : ' 服务端说：$detail'}';
      case 402:
        return 'DeepSeek 账户余额不足（402），去平台充值后再试。';
      case 404:
        return '接口或模型名不存在（404）。模型名请填 deepseek-chat。';
      case 400:
        return '请求被拒（400）：${detail.isEmpty ? '参数有误' : detail}'
            '。最常见原因是模型名称填错了——DeepSeek 只有'
            ' deepseek-chat 和 deepseek-reasoner 两个，改过来再测';
      case 422:
        return '请求参数被拒（422）：${detail.isEmpty ? '用中文再问一次试试' : detail}';
      case 429:
        return '请求太频繁或超出并发限制（429），等一会儿再试。';
      case 500:
      case 502:
      case 503:
        return 'DeepSeek 服务端暂时故障（$code），稍后重试。';
      default:
        return 'DeepSeek 返回 HTTP $code：${detail.isEmpty ? body : detail}';
    }
  }

  /// 把 AI 返回的文本解析成词典条目
  static Map<String, String> _parseEntry(String raw) {
    // 容错：有的模型会给 JSON 套一层 ```json ``` 代码围栏，先剥掉
    String text = raw.trim();
    if (text.startsWith('```')) {
      text = text.replaceAll('```json', '').replaceAll('```', '').trim();
    }

    final Map<String, dynamic> entry;
    try {
      entry = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('AI 返回的内容不是合法 JSON：$text');
    }

    return <String, String>{
      'phonetic': (entry['phonetic'] as String? ?? '').trim(),
      'zh': (entry['zh'] as String? ?? '').trim(),
      'example': (entry['example'] as String? ?? '').trim(),
    };
  }

  /// 单词学习卡：词根词缀、词组搭配、例句。返回解析后的 Map，失败返回 null。
  static Future<Map<String, dynamic>?> wordCard(
    AiConfig cfg,
    String word,
  ) async {
    final String raw = await chat(
      cfg,
      <ChatMessage>[
        ChatMessage(
          role: 'user',
          content: '给英语单词 "$word" 做一张学习卡片。\n'
              '只输出 JSON，不要 markdown 代码块，不要解释：\n'
              '{"root":"词根词缀拆解，中文，80 字以内；没有明显词根就说由什么构成",'
              '"pos":"词性，如 conj. / v. / n.",'
              '"collocations":["常见搭配（中文）","...","..."],'
              '"examples":[{"en":"例句","zh":"译文"},{"en":"例句","zh":"译文"}]}\n'
              '搭配 3 条，例句 2 条，贴近考试场景。',
        ),
      ],
      systemPrompt: '你是英语词汇老师，输出严格合法的 JSON。',
    );
    String s = raw.trim();
    s = s.replaceAll(RegExp(r'^```[a-zA-Z]*'), '').replaceAll('```', '');
    final int a = s.indexOf('{');
    final int b = s.lastIndexOf('}');
    if (a < 0 || b <= a) return null;
    try {
      final Object? data = jsonDecode(s.substring(a, b + 1));
      if (data is Map<String, dynamic>) return data;
    } catch (_) {}
    return null;
  }
}
