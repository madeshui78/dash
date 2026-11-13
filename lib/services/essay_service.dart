// 作文逐词翻译的分词和词形还原。
// 纯 Dart，不依赖 Flutter，方便单独拿真实文本试。

/// 一个切出来的片段：要么是英文单词，要么是标点/空白/其它。
class EssayToken {
  /// 原文，原样保留
  final String text;

  /// 是英文单词时才非 null，已去掉前后标点，小写前的原样
  final String? word;

  const EssayToken(this.text, {this.word});

  bool get isWord => word != null;
}

/// 把整篇英文切成 token 序列。
///
/// 单词内部允许出现撇号和连字符（don't、well-known），
/// 这样查词的时候能拿到完整的 don't，而不是 don 和 t。
List<EssayToken> tokenizeEssay(String text) {
  final List<EssayToken> out = <EssayToken>[];
  final RegExp wordRe = RegExp(r"[A-Za-z]+(?:['’\-][A-Za-z]+)*");
  int last = 0;
  for (final RegExpMatch m in wordRe.allMatches(text)) {
    if (m.start > last) {
      out.add(EssayToken(text.substring(last, m.start)));
    }
    out.add(EssayToken(m.group(0)!, word: m.group(0)!));
    last = m.end;
  }
  if (last < text.length) {
    out.add(EssayToken(text.substring(last)));
  }

  // 把紧跟在单词后面的标点并进这个单词的显示文本。
  // 不并的话，逗号句号会变成 Wrap 里独立的一项，
  // 被底部对齐推到下一行，版面上就是一堆孤零零的标点。
  final List<EssayToken> merged = <EssayToken>[];
  for (int i = 0; i < out.length; i++) {
    final EssayToken t = out[i];
    if (!t.isWord) {
      merged.add(t);
      continue;
    }
    String display = t.word!;
    int j = i + 1;
    while (j < out.length &&
        !out[j].isWord &&
        out[j].text.trim().isNotEmpty) {
      display += out[j].text.trim();
      j++;
    }
    merged.add(EssayToken(display, word: t.word));
    i = j - 1;
  }
  return merged;
}

/// 常见不规则变化，还原表查不到时兜底。
/// 只收作文里真会碰到的那些，不求全。
const Map<String, String> _irregular = <String, String>{
  'am': 'be', 'is': 'be', 'are': 'be', 'was': 'be', 'were': 'be',
  'been': 'be', 'being': 'be',
  'has': 'have', 'had': 'have', 'having': 'have',
  'does': 'do', 'did': 'do', 'done': 'do', 'doing': 'do',
  'went': 'go', 'gone': 'go', 'going': 'go', 'goes': 'go',
  'got': 'get', 'gotten': 'get', 'getting': 'get',
  'made': 'make', 'making': 'make',
  'said': 'say', 'says': 'say', 'saying': 'say',
  'saw': 'see', 'seen': 'see', 'seeing': 'see',
  'took': 'take', 'taken': 'take', 'taking': 'take',
  'came': 'come', 'coming': 'come',
  'thought': 'think', 'thinking': 'think',
  'found': 'find', 'finding': 'find',
  'gave': 'give', 'given': 'give', 'giving': 'give',
  'kept': 'keep', 'keeping': 'keep',
  'knew': 'know', 'known': 'know', 'knowing': 'know',
  'wrote': 'write', 'written': 'write', 'writing': 'write',
  'children': 'child', 'people': 'person', 'men': 'man', 'women': 'woman',
  'feet': 'foot', 'teeth': 'tooth', 'mice': 'mouse',
  'better': 'good', 'best': 'good', 'worse': 'bad', 'worst': 'bad',
  'more': 'much', 'most': 'much',

  // 缩写：作文里到处都是，还原不对就等于查不到
  "don't": 'do', "doesn't": 'do', "didn't": 'do',
  "isn't": 'be', "aren't": 'be', "wasn't": 'be', "weren't": 'be',
  "can't": 'can', "couldn't": 'could',
  "won't": 'will', "wouldn't": 'will',
  "shouldn't": 'should', "haven't": 'have', "hasn't": 'have',
  "hadn't": 'have', "i'm": 'be', "you're": 'be', "it's": 'be',
  "that's": 'be', "there's": 'be',
};

/// 查词典用的候选原形，按"最可能"排：原词 → 不规则表 → 规则还原。
///
/// 例：studies → [studies, study]；running → [running, run]；
///     went → [went, go]。本地词库查不到原词时按这个顺序往下试。
List<String> lemmaCandidates(String raw) {
  final String w = raw.trim().toLowerCase().replaceAll('’', "'");
  if (w.isEmpty) return const <String>[];

  final List<String> out = <String>[w];
  void add(String? s) {
    if (s == null || s.isEmpty || out.contains(s)) return;
    // 太短的还原结果基本都是截坏的（never → nev），宁可不猜
    if (s.length < 3 && !_irregular.containsKey(w)) return;
    out.add(s);
  }

  add(_irregular[w]);

  // 撇号形式：don't → do；children's → children
  final int apos = w.indexOf("'");
  if (apos > 0) {
    final String head = w.substring(0, apos);
    add(_irregular[head] ?? head);
  }

  if (w.length > 3) {
    // studies / cities → study / city
    if (w.endsWith('ies')) add('${w.substring(0, w.length - 3)}y');
    // boxes / goes → box / go
    if (w.endsWith('es') &&
        (w.endsWith('ses') || w.endsWith('xes') ||
            w.endsWith('zes') || w.endsWith('ches') ||
            w.endsWith('shes'))) {
      add(w.substring(0, w.length - 2));
    }
    // books → book
    if (w.endsWith('s') && !w.endsWith('ss')) {
      add(w.substring(0, w.length - 1));
    }
    // studied → study；carried → carry
    if (w.endsWith('ied')) add('${w.substring(0, w.length - 3)}y');
    // studied → study（上面那个），worked → work
    if (w.endsWith('ed')) {
      add(w.substring(0, w.length - 2));
      if (w.length > 4 && w[w.length - 3] == w[w.length - 4]) {
        // stopped → stop（双写辅音）
        add(w.substring(0, w.length - 3));
      }
      if (w.endsWith('ied')) add('${w.substring(0, w.length - 3)}y');
    }
    // running → run；making → make
    if (w.endsWith('ing')) {
      final String stem = w.substring(0, w.length - 3);
      // 双写辅音的（running）先剥一个，再加 e 意义不大
      final bool doubled = stem.length >= 2 &&
          stem[stem.length - 1] == stem[stem.length - 2];
      if (doubled) add(stem.substring(0, stem.length - 1));
      add(stem);
      // make → making，反过来要补 e；但 go → going 不该补成 goe
      if (!doubled && !_isVowel(stem[stem.length - 1])) add('${stem}e');
    }
    // bigger → big（双写辅音 + er）；teacher 这种以 er 结尾的名词
    // 会被误当比较级，靠「剩下至少 4 个字母」这条挡掉 nev / bet 之类
    if (w.endsWith('er') || w.endsWith('est')) {
      final int cut = w.endsWith('est') ? 3 : 2;
      final String stem = w.substring(0, w.length - cut);
      if (stem.length >= 4) {
        final bool doubled = stem.length >= 2 &&
            stem[stem.length - 1] == stem[stem.length - 2];
        if (doubled) add(stem.substring(0, stem.length - 1));
        add(stem);
        if (!doubled && !_isVowel(stem[stem.length - 1])) add('${stem}e');
        if (w.endsWith('ier')) add('${stem}y');
      }
    }
    // happily → happy
    if (w.endsWith('ily')) add('${w.substring(0, w.length - 3)}y');
    if (w.endsWith('ly')) add(w.substring(0, w.length - 2));
  }
  return out;
}

bool _isVowel(String c) =>
    c == 'a' || c == 'e' || c == 'i' || c == 'o' || c == 'u';

/// 把整篇文章按句切开，句末标点跟着前一句走。
///
/// 换行先压成空格：PDF 和粘贴的文本经常在句中硬换行，
/// 不压掉会把一句话拆成两句。
///
/// 缩写（Mr. / e.g. / U.S.）会被误切，这是按标点切句的通病；
/// 作文里出现得少，不做专门处理，免得把规则搞得又长又难查。
List<String> splitSentences(String text) {
  final String flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (flat.isEmpty) return <String>[];

  final List<String> out = <String>[];
  final StringBuffer buf = StringBuffer();

  for (int i = 0; i < flat.length; i++) {
    final String ch = flat[i];
    buf.write(ch);
    final bool end = ch == '.' || ch == '!' || ch == '?';
    if (!end) continue;

    // 把紧跟着的引号/括号也归到这句
    while (i + 1 < flat.length && '"\')]”’'.contains(flat[i + 1])) {
      i++;
      buf.write(flat[i]);
    }
    final String s = buf.toString().trim();
    if (s.isNotEmpty) out.add(s);
    buf.clear();
  }

  final String rest = buf.toString().trim();
  if (rest.isNotEmpty) out.add(rest);
  return out;
}
