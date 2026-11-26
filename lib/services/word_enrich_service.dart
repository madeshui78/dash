// AI 批量补全过程：把一批单词分批喂给 AI，补齐音标 / 释义 / 例句 / 词根。
// 单个词调用要几百次请求，不现实；这里按批走，带进度、重试和中断。

import '../services/ai_service.dart';

class EnrichOutcome {
  /// 补出来的条目，key 是单词小写
  final Map<String, WordEntry> entries;

  /// AI 没给出来的词（漏返回或返回空）
  final List<String> missing;

  /// 是不是被用户中途停掉了
  final bool cancelled;

  /// 最后一次的错误；全部成功就是 null
  final String? error;

  const EnrichOutcome({
    required this.entries,
    required this.missing,
    required this.cancelled,
    this.error,
  });

  int get count => entries.length;
}

class WordEnrichService {
  WordEnrichService._();

  /// 分批补全。
  /// [onProgress] 每批完成后回调（已完成数, 总数）。
  /// [isCancelled] 返回 true 就立刻停，已经补完的批次照常返回，不白跑。
  static Future<EnrichOutcome> enrich({
    required List<String> words,
    required AiConfig cfg,
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final Map<String, WordEntry> out = <String, WordEntry>{};
    final List<String> missing = <String>[];
    final int total = words.length;
    int done = 0;
    String? lastError;

    final List<String> queue = words
        .map((String w) => w.trim())
        .where((String w) => w.isNotEmpty)
        .toList();

    for (int i = 0; i < queue.length; i += AiService.batchSize) {
      if (isCancelled?.call() ?? false) {
        return EnrichOutcome(
          entries: out,
          missing: missing,
          cancelled: true,
          error: lastError,
        );
      }

      final List<String> batch = queue
          .skip(i)
          .take(AiService.batchSize)
          .toList();

      List<WordEntry>? got;
      for (int attempt = 0; attempt < 3 && got == null; attempt++) {
        try {
          got = await AiService.lookupWords(cfg, batch);
        } catch (e) {
          lastError = e.toString().replaceFirst('Exception: ', '');
          // 失败退一退再试，连续冲击只会连续失败
          if (attempt < 2) {
            await Future<void>.delayed(Duration(seconds: 2 * (attempt + 1)));
          }
        }
      }

      if (got == null) {
        lastError ??= 'AI 没返回结果';
        missing.addAll(batch);
      } else {
        for (final WordEntry e in got) {
          if (e.isEmpty) {
            missing.add(e.en);
          } else {
            out[e.en.toLowerCase()] = e;
          }
        }
      }

      done += batch.length;
      onProgress?.call(done > total ? total : done, total);
    }

    return EnrichOutcome(
      entries: out,
      missing: missing,
      cancelled: false,
      error: lastError,
    );
  }
}
