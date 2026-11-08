import '../../models/vocab.dart';
import '../vocab_confusables.dart';
import 'word.dart';

/// 合并层：把例句 / 词组 / 语法标记 / 分析结果并进词库。
///
/// 全部是「库进 → 库出」的纯函数，找不到目标词条时原样返回；
/// 合并键统一走 lemma（`vocab/word.dart`），不允许各函数自己再拼一套。
/// 与 Web 版 `src/core/vocab/merge.ts` 一一对应。

/// 来源句是否「有用」（有原句，或有句子 id）。
bool _sourceHasText(VocabSource? s) =>
    s != null && (s.sentenceText.trim().isNotEmpty || (s.sentenceId ?? '').isNotEmpty);

/// 有原句的来源优先；都没有就用新的（保证来源不空）。
VocabSource betterSource(VocabSource? a, VocabSource b) => _sourceHasText(a) ? a! : b;

String _contextKey(VocabContext c) =>
    '${c.fileName ?? c.articleId}|${c.sentenceId ?? c.sentenceText}';

/// 记一条「出现语境」：同篇同句只留一条；同篇新句追加（保留最近 20 条）。
List<VocabContext> upsertContext(List<VocabContext>? list, VocabContext ctx, {int cap = 20}) {
  final cur = list ?? const <VocabContext>[];
  if ((ctx.fileName ?? '').isEmpty && ctx.sentenceText.isEmpty) return cur;
  final k = _contextKey(ctx);
  final i = cur.indexWhere((c) => _contextKey(c) == k);
  if (i >= 0) {
    final prev = cur[i];
    final next = VocabContext(
      articleId: ctx.articleId,
      fileName: ctx.fileName ?? prev.fileName,
      sentenceId: ctx.sentenceId ?? prev.sentenceId,
      sentenceText: ctx.sentenceText,
      meaning: ctx.meaning ?? prev.meaning,
      at: prev.at.isNotEmpty ? prev.at : ctx.at,
    );
    if (next.meaning == prev.meaning && next.sentenceText == prev.sentenceText) return cur;
    return [
      for (var j = 0; j < cur.length; j++) j == i ? next : cur[j],
    ];
  }
  final out = [...cur, ctx];
  return out.length > cap ? out.sublist(out.length - cap) : out;
}

/// 由「来源」造一条语境。
VocabContext contextFromSource(VocabSource source, String at, {String? meaning}) => VocabContext(
      articleId: source.articleId,
      fileName: source.fileName,
      sentenceId: source.sentenceId,
      sentenceText: source.sentenceText,
      meaning: meaning,
      at: at,
    );

String _exampleKey(VocabExample x) => x.sentenceId ?? x.text;

List<VocabExample> mergeExamples(List<VocabExample> a, List<VocabExample> b) {
  final out = [...a];
  for (final e in b) {
    final key = _exampleKey(e);
    if (!out.any((x) => _exampleKey(x) == key)) out.add(e);
  }
  return out;
}

List<String> mergeUnique(List<String> a, List<String> b) {
  final out = [...a];
  for (final x in b) {
    if (!out.contains(x)) out.add(x);
  }
  return out;
}

/// 合并两个「可选列表」：两边都缺 → 保持缺失（null）；否则合并去重。
List<String>? _mergeOptionalList(List<String>? a, List<String>? b) {
  if (a == null && b == null) return null;
  return mergeUnique(a ?? const [], b ?? const []);
}

/// 一个词最多保留几条例句（避免反复查词越堆越多）。
const int maxExamples = 6;

/// 把一批例句并入词条（按 lemma / 词形匹配）。
///
/// - [origin]：这批例句的来源（AI 生成 / 离线例句库）。
/// - 同一正文的已有例句**不重复加**，但 AI 例句会把它的来源「认领」成 ai
///   （这样「还缺 AI 例句」的判据不会因为离线例句先到而永远为真 → 防死循环），并顺手补上缺的翻译。
VocabLibrary applyExamples(
  VocabLibrary library,
  List<({String word, List<({String text, String? translation})> examples})> rows, [
  DateTime? now,
  VocabExampleOrigin origin = VocabExampleOrigin.ai,
]) {
  final iso = (now ?? DateTime.now()).toIso8601String();
  var changed = false;
  final items = library.items.map((it) {
    final row = rows.where((r) => lemmaOf(r.word) == it.lemma || normalizeWord(r.word) == normalizeWord(it.word));
    if (row.isEmpty) return it;
    final next = [...it.examples];
    var touched = false;
    for (final inc in row.first.examples) {
      final text = inc.text.trim();
      if (text.isEmpty) continue;
      final i = next.indexWhere((x) => x.text.trim() == text);
      if (i >= 0) {
        final cur = next[i];
        final claim = origin == VocabExampleOrigin.ai && cur.origin != VocabExampleOrigin.ai;
        final fillTr = (cur.translation ?? '').isEmpty && (inc.translation ?? '').isNotEmpty;
        if (claim || fillTr) {
          next[i] = VocabExample(
            text: cur.text,
            translation: fillTr ? inc.translation : cur.translation,
            articleId: cur.articleId,
            fileName: cur.fileName,
            sentenceId: cur.sentenceId,
            origin: claim ? VocabExampleOrigin.ai : cur.origin,
          );
          touched = true;
        }
      } else {
        next.add(VocabExample(text: text, translation: inc.translation, origin: origin));
        touched = true;
      }
    }
    if (!touched) return it;
    final capped = next.length > maxExamples ? next.sublist(0, maxExamples) : next;
    // 裁剪后内容没变（例如已经满了）→ 不算改动，避免反复写库
    final same = capped.length == it.examples.length &&
        List.generate(capped.length, (i) {
          final x = capped[i];
          final y = it.examples[i];
          return x.text == y.text && x.origin == y.origin && x.translation == y.translation;
        }).every((ok) => ok);
    if (same) return it;
    changed = true;
    return it.copyWith(examples: capped, updatedAt: iso);
  }).toList();
  return changed ? library.copyWith(items: items) : library;
}

/// 把 AI 生成的「词组 / 习语」并入词条（按 lemma / 词形匹配）。
/// 词组去重，并滤掉已经在「用法」里的，避免卡片上「用法」和「词组」两块重复。
///
/// 被 AI 列出的词 = 已标注过：哪怕词组为空（如 mrs），也写空数组，避免永远重复待办。
VocabLibrary applyPhrases(
  VocabLibrary library,
  List<({String word, List<String> phrases, List<String> idioms})> rows, [
  DateTime? now,
]) {
  if (rows.isEmpty) return library;
  final iso = (now ?? DateTime.now()).toIso8601String();
  var changed = false;
  final items = library.items.map((it) {
    final row = rows.where((r) => lemmaOf(r.word) == it.lemma || normalizeWord(r.word) == normalizeWord(it.word));
    if (row.isEmpty) return it;
    final r = row.first;
    final usedKeys = it.usage.map(normalizeWord).toSet();
    final phrases = mergeUnique(
      it.phrases ?? const [],
      r.phrases.where((p) => p.trim().isNotEmpty && !usedKeys.contains(normalizeWord(p))).toList(),
    );
    final idioms = mergeUnique(it.idioms ?? const [], r.idioms.where((s) => s.trim().isNotEmpty).toList());
    final curPhrases = it.phrases;
    final curIdioms = it.idioms;
    if (curPhrases != null &&
        curIdioms != null &&
        phrases.length == curPhrases.length &&
        idioms.length == curIdioms.length) {
      return it;
    }
    changed = true;
    return it.copyWith(phrases: () => phrases, idioms: () => idioms, updatedAt: iso);
  }).toList();
  return changed ? library.copyWith(items: items) : library;
}

/// 语法标记归属的类别：可数性只对名词、及物性只对动词、可分级只对形容词。
const Map<String, String> _markGroup = {
  '可数': 'noun',
  '不可数': 'noun',
  '及物': 'verb',
  '不及物': 'verb',
  '可分级': 'adj',
  '不可分级': 'adj',
};

List<String> _posTokens(String? pos) => normalizePos(pos)
    .split(RegExp(r'[/,，;；\s]+'))
    .map((s) => s.replaceFirst(RegExp(r'\.+$'), '').trim().toLowerCase())
    .toList();

/// 词性是否含某一类（n./v./adj）。
bool _posHas(String? pos, String kind) {
  final tokens = _posTokens(pos);
  final words = kind == 'noun'
      ? const ['n', 'noun']
      : kind == 'verb'
          ? const ['v', 'verb']
          : const ['adj', 'adjective'];
  return tokens.any(words.contains);
}

/// 按词性过滤语法标记：**可数/不可数只对名词、及物/不及物只对动词、可分级只对形容词**。
/// 治的是 AI 给形容词（sprawling）也标「不可数」这种张冠李戴。
/// 不在受控词表里的标记（未来的扩展）一律保留。
List<String> marksForPos(List<String> marks, String? pos) {
  final known = normalizePos(pos).trim().isNotEmpty;
  final out = <String>[];
  for (final raw in marks) {
    final m = raw.trim();
    if (m.isEmpty) continue;
    final g = _markGroup[m];
    if (g == null) {
      out.add(m); // 不在受控词表里的扩展标记：保留
      continue;
    }
    if (!known) {
      out.add(m); // 词性还没标注：没法判断，先保留
      continue;
    }
    if (_posHas(pos, g)) out.add(m);
  }
  return out;
}

/// 整库修一遍语法标记（清掉与词性不匹配的）；加载时跑一次即可，幂等。
VocabLibrary normalizeGrammarMarks(VocabLibrary library) {
  var changed = false;
  final items = library.items.map((it) {
    final marks = it.grammarMarks;
    if (marks == null || marks.isEmpty) return it;
    final fixed = marksForPos(marks, it.partOfSpeech);
    if (fixed.length == marks.length) return it;
    changed = true;
    return it.copyWith(grammarMarks: () => fixed);
  }).toList();
  return changed ? library.copyWith(items: items) : library;
}

/// 把 AI 标注的「语法标记」（可数/不可数、及物/不及物…）并入词条。
/// 按 lemma / 词形匹配，去重合并，并**按词性过滤**（不匹配的丢掉）。
///
/// 关键：**被 AI 列出的词 = 已标注过**。哪怕该词没有可标项（marks 为空，如 mrs），
/// 也要把 `grammarMarks` 写成空数组，表示「查过、无可标」，否则会永远重复待办。
VocabLibrary applyGrammarMarks(
  VocabLibrary library,
  List<({String word, List<String> marks})> rows, [
  DateTime? now,
]) {
  if (rows.isEmpty) return library;
  final iso = (now ?? DateTime.now()).toIso8601String();
  var changed = false;
  final items = library.items.map((it) {
    final row = rows.where((r) => lemmaOf(r.word) == it.lemma || normalizeWord(r.word) == normalizeWord(it.word));
    if (row.isEmpty) return it;
    final marks = mergeUnique(it.grammarMarks ?? const [], marksForPos(row.first.marks, it.partOfSpeech));
    final cur = it.grammarMarks;
    // 已标注过且没有新增 → 不动（避免无意义地刷新 updatedAt）
    if (cur != null && marks.length == cur.length) return it;
    changed = true;
    return it.copyWith(grammarMarks: () => marks, updatedAt: iso);
  }).toList();
  return changed ? library.copyWith(items: items) : library;
}

/// 词性是否含名词 / 动词 / 形容词（只有这几类才需要标语法标记）。
bool isMarkablePos(String? pos) {
  final p = normalizePos(pos);
  if (p.isEmpty) return false;
  final tokens = _posTokens(p);
  return tokens.any((t) => const ['n', 'noun', 'v', 'verb', 'adj', 'adjective'].contains(t));
}

/// 本词自己的例句（排除「就是来源句」的那条）。
List<VocabExample> ownExamples(VocabItem item) {
  final src = (item.source?.sentenceText ?? '').trim();
  return item.examples.where((e) {
    final text = e.text.trim();
    return text.isNotEmpty && text != src;
  }).toList();
}

/// 是否有「自己的例句」（只有来源句等于没有）。
bool hasOwnExamples(VocabItem item) => ownExamples(item).isNotEmpty;

/// 每个词目标补几条离线例句（离线、免费，和 AI 例句并存）。
const int targetOfflineExamples = 3;

/// 从候选里挑出「该补的离线例句」：
///   - 目标：每词 [target] 条离线例句（按 `origin == tatoeba` 计）——所以是幂等的；
///   - 不超卡片上限 [maxExamples]，也不重复已有的句子。
List<({String text, String? translation})> pickOfflineExamples(
  VocabItem item,
  List<({String text, String? translation})> candidates, {
  int target = targetOfflineExamples,
}) {
  final have = item.examples.map((e) => e.text.trim()).toSet();
  final offline = item.examples.where((e) => e.origin == VocabExampleOrigin.tatoeba).length;
  final room = maxExamples - item.examples.length;
  final want = [target - offline, room].reduce((a, b) => a < b ? a : b);
  if (want <= 0) return const [];
  final out = <({String text, String? translation})>[];
  for (final c in candidates) {
    final text = c.text.trim();
    if (text.isEmpty || have.contains(text)) continue;
    out.add(c);
    if (out.length >= want) break;
  }
  return out;
}

/// 「还需要 AI 例句吗」：自己的例句里还没有 AI 生成的（离线例句不算数）。
/// 离线例句先补上时，AI 仍会给一份带中文的；AI 回来后就不再排（防死循环）。
bool needsAiExamples(VocabItem item) {
  final src = (item.source?.sentenceText ?? '').trim();
  return item.examples.every(
    (e) => e.origin == VocabExampleOrigin.tatoeba || e.text.trim() == src,
  );
}

/// 卡片上带小标题的一段内容（规范化「语境 / 用法 / 词组 / 习语 / 例句 / 来源 / 易混」）。
class VocabCardBlock {
  const VocabCardBlock({required this.key, required this.label, required this.lines});

  /// `context` / `usage` / `phrases` / `idioms` / `examples` / `source` / `confusables`。
  final String key;

  /// 小标题，如「例句」。
  final String label;
  final List<String> lines;
}

/// 把词条整理成卡片上按固定顺序排列、带小标题的内容块。
/// 只返回有内容的块；例句只取「自己的例句」（跳过与来源句相同的那条）。
List<VocabCardBlock> vocabCardBlocks(VocabItem item, {int? maxExamples}) {
  final blocks = <VocabCardBlock>[];
  void push(String key, String label, List<String> lines) {
    if (lines.isNotEmpty) blocks.add(VocabCardBlock(key: key, label: label, lines: lines));
  }

  push('usage', '用法', item.usage.map((s) => s.trim()).where((s) => s.isNotEmpty).toList());

  // 语境：在哪些句子里出现过（最近 2 条）；有「此处含义」就带上
  final ctxs = (item.contexts ?? const <VocabContext>[]).reversed.take(2).toList();
  push(
    'context',
    '语境',
    ctxs
        .where((c) => c.sentenceText.trim().isNotEmpty)
        .map((c) {
          final text = c.sentenceText.trim();
          final meaning = c.meaning;
          return (meaning ?? '').isNotEmpty ? '$text — 此处：$meaning' : text;
        })
        .toList(),
  );

  push('phrases', '词组', (item.phrases ?? const []).map((s) => s.trim()).where((s) => s.isNotEmpty).toList());
  push('idioms', '习语', (item.idioms ?? const []).map((s) => s.trim()).where((s) => s.isNotEmpty).toList());

  final examples = ownExamples(item).map((e) {
    final tag = e.origin == VocabExampleOrigin.tatoeba
        ? '[离线] '
        : e.origin == VocabExampleOrigin.ai
            ? '[AI] '
            : '';
    final tr = e.translation;
    return (tr ?? '').isNotEmpty ? '$tag${e.text} — $tr' : '$tag${e.text}';
  }).toList();
  push('examples', '例句', maxExamples != null ? examples.take(maxExamples).toList() : examples);

  final sentence = (item.source?.sentenceText ?? '').trim();
  push('source', '来源', sentence.isNotEmpty ? [sentence] : const []);

  final confusableTag = confusableSourceLabel(item.confusablesSource);
  final confusablePrefix = confusableTag.isNotEmpty ? '[$confusableTag] ' : '';
  push(
    'confusables',
    '易混',
    (item.confusables ?? const [])
        .where((c) => c.word.trim().isNotEmpty)
        .map((c) {
          final m = c.meaning;
          return (m ?? '').isNotEmpty ? '$confusablePrefix${c.word}（$m）' : '$confusablePrefix${c.word}';
        })
        .toList(),
  );

  return blocks;
}

List<VocabConfusable>? _mergeConfusables(
  List<VocabConfusable>? a,
  List<VocabConfusable>? b,
) {
  final out = [...(a ?? const <VocabConfusable>[])];
  for (final c in b ?? const <VocabConfusable>[]) {
    if (!out.any((x) => x.word.toLowerCase() == c.word.toLowerCase())) out.add(c);
  }
  return out.isEmpty ? null : out;
}

/// 合并后的易混项来源：
///   - 只有一边有易混项 → 用那边的来源；
///   - 两边都有且来源相同 → 保留；
///   - 两边来源不同 / 有一边没记录 → null（不拿一边的来源代表混合内容）。
VocabConfusableSource? _mergeConfusableSource(
  VocabItem a,
  VocabItem b,
  List<VocabConfusable>? merged,
) {
  if (merged == null || merged.isEmpty) return null;
  final aHas = (a.confusables ?? const []).isNotEmpty;
  final bHas = (b.confusables ?? const []).isNotEmpty;
  if (aHas && !bHas) return a.confusablesSource;
  if (bHas && !aHas) return b.confusablesSource;
  final sa = a.confusablesSource;
  return sa != null && sa == b.confusablesSource ? sa : null;
}

int _statusRank(VocabStatus s) => switch (s) {
      VocabStatus.unqueried => 0,
      VocabStatus.queried => 1,
      VocabStatus.edited => 2,
      VocabStatus.mastered => 3,
    };

/// 合并两个同 lemma 的词条（信息互补；不丢字段）。
VocabItem _mergeItem(VocabItem a, VocabItem b) {
  final stronger = _statusRank(a.status) >= _statusRank(b.status) ? a : b;
  final confusables = _mergeConfusables(a.confusables, b.confusables);
  final fieldSources = <VocabField, VocabFieldSource>{};

  String? pick(VocabField key, String? av, String? bv) {
    final aHas = (av ?? '').trim().isNotEmpty;
    final bHas = (bv ?? '').trim().isNotEmpty;
    if (aHas) {
      final src = a.fieldSources?[key];
      if (src != null) fieldSources[key] = src;
      return av;
    }
    if (bHas) {
      final src = b.fieldSources?[key];
      if (src != null) fieldSources[key] = src;
      return bv;
    }
    return av ?? bv;
  }

  final contexts = (a.contexts ?? const <VocabContext>[])
      .followedBy(b.contexts ?? const <VocabContext>[])
      .fold<List<VocabContext>>([], (acc, c) => upsertContext(acc, c));

  final priorities = [a.priorityUntil, b.priorityUntil].whereType<String>().toList()..sort();

  return VocabItem(
    id: a.id,
    word: a.word,
    lemma: a.lemma,
    kind: a.kind ?? b.kind,
    langPointId: a.langPointId ?? b.langPointId,
    phonetic: pick(VocabField.phonetic, a.phonetic, b.phonetic),
    partOfSpeech: pick(VocabField.partOfSpeech, a.partOfSpeech, b.partOfSpeech),
    meaning: pick(VocabField.meaning, a.meaning, b.meaning),
    grammarMarks: _mergeOptionalList(a.grammarMarks, b.grammarMarks),
    definition: pick(VocabField.definition, a.definition, b.definition),
    fieldSources: fieldSources.isEmpty ? null : fieldSources,
    usage: mergeUnique(a.usage, b.usage),
    phrases: _mergeOptionalList(a.phrases, b.phrases),
    idioms: _mergeOptionalList(a.idioms, b.idioms),
    examples: mergeExamples(a.examples, b.examples),
    source: a.source ?? b.source,
    contexts: contexts,
    status: stronger.status,
    note: a.note.isNotEmpty ? a.note : b.note,
    tags: {...a.tags, ...b.tags}.toList(),
    lastPrintedAt: a.lastPrintedAt ?? b.lastPrintedAt,
    confusables: confusables,
    confusablesSource: _mergeConfusableSource(a, b, confusables),
    priorityUntil: priorities.isEmpty ? null : priorities.last,
    reviewState: stronger.reviewState,
    createdAt: a.createdAt.compareTo(b.createdAt) < 0 ? a.createdAt : b.createdAt,
    updatedAt: a.updatedAt.compareTo(b.updatedAt) > 0 ? a.updatedAt : b.updatedAt,
  );
}

/// 整库按 lemma 去重（合并）。加载/导入后跑一道，
/// 保证即使旧数据或词形还原边角也不会出现两个同根词。
VocabLibrary dedupeLibrary(VocabLibrary library) {
  final byLemma = <String, VocabItem>{};
  for (final it in library.items) {
    final prev = byLemma[it.lemma];
    byLemma[it.lemma] = prev != null ? _mergeItem(prev, it) : it;
  }
  return library.copyWith(items: byLemma.values.toList());
}
