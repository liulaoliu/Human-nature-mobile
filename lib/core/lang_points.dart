import '../models/document.dart';
import '../models/vocab.dart';
import 'article_vocab.dart';
import 'entry_kind.dart';
import 'language.dart';
import 'text_norm.dart';
import 'vocab/merge.dart';
import 'vocab/word.dart';

/// 「任意文本」的去重键：保留中文（中文用法笔记用得上），统一大小写、撇号与空白。
///
/// 英文单词请用 `lemmaOf`。
///
/// 对应 Web 版 `src/core/langPoints.ts` 的 `textKey`。注意 Dart 没有内置 NFKC，
/// 这里用 [nfkc]（只处理全角与连字，够用）。
String textKey(String raw) {
  final out = StringBuffer();
  for (final ch in nfkc(raw).split('')) {
    switch (ch) {
      case '\u2018':
      case '\u2019':
      case '\u02bc':
      case '\u2032':
        out.write("'");
      default:
        out.write(ch);
    }
  }
  return out
      .toString()
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .toLowerCase();
}

final RegExp _cjk = RegExp(r'[\u3400-\u9fff\u3040-\u30ff\uac00-\ud7af]');

/// 一次性修正（加载时跑，幂等）：早期版本把「用法笔记」的键取成了笔记里那个英文单词，
/// 于是把**真正的单词词条**误标成了「用法」（不进背单词/考试），也可能把单词标成「词组」。
///
/// 判据分两种：
///   - 词形本身就是单个英文单词 → 一定是单词（连旧的 `langPointId` 一起清掉，
///     否则下次收语言点又会把它改回 usage）；
///   - 有 `kind` 却没有 `langPointId` → 旧数据；含中文的旧笔记改用整条文本做键。
///
/// 对应 Web 版 `repairLanguageKinds`。
VocabLibrary repairLanguageKinds(VocabLibrary library) {
  var changed = false;

  /// 旧用法笔记的坏键（`mantra`）→ 修好的整条笔记键；按篇条目也要跟着改名。
  final renames = <String, List<({String key, String? sentenceId})>>{};

  final items = library.items.map((it) {
    final rawKind = it.kind ?? VocabItemKind.word;
    if (rawKind == VocabItemKind.word) return it;
    final english = normalizeWord(it.word);

    // 单词形态 → 不管有没有 langPointId，都改回普通单词。
    // 历史数据里「单词被标成 usage 且带着旧标记」正是 Profits overboard 里
    // conglomerate / reckon / scrap 永远加不进本篇的原因。
    if (isSingleEnglishWord(it.word)) {
      changed = true;
      final next = it.copyWith(kind: () => null, langPointId: () => null);
      final key = lemmaOf(it.word).isNotEmpty ? lemmaOf(it.word) : textKey(it.word);
      if (key.isNotEmpty && it.lemma != key) {
        final list = renames.putIfAbsent(it.lemma, () => []);
        list.add((key: key, sentenceId: it.source?.sentenceId));
        return next.copyWith(id: 'vocab:$key', lemma: key);
      }
      return next;
    }

    // 新代码收进来的真笔记 / 词组一定带标记，别把它们改成单词。
    if (it.langPointId != null) return it;

    if (rawKind == VocabItemKind.usage) {
      // 旧版把「用法笔记」的键取成笔记里的英文单词（如 `mantra`），
      // 导致同名单词被这条 usage 占住、手动加词永远被合并成「用法」。
      // 真笔记（含中文）改用整条文本做键。
      if (!_cjk.hasMatch(it.word)) {
        changed = true;
        return it.copyWith(kind: () => null);
      }
      final key = textKey(it.word);
      if (key.isNotEmpty && it.lemma != key) {
        changed = true;
        final list = renames.putIfAbsent(it.lemma, () => []);
        list.add((key: key, sentenceId: it.source?.sentenceId));
        return it.copyWith(id: 'vocab:$key', lemma: key);
      }
      return it;
    }

    if (!english.contains(' ')) {
      changed = true;
      return it.copyWith(kind: () => null);
    }
    return it;
  }).toList();

  if (!changed) return library;

  var articleEntries = library.articleEntries;
  if (articleEntries.isNotEmpty && renames.isNotEmpty) {
    // 同名单词已经存在时，按篇条目更可能指的是那个单词（旧数据无法区分），
    // 不要把它改挂到用法笔记上；只给「没有同名单词」的笔记改名。
    final wordKeys = <String>{
      for (final it in library.items)
        if (kindOfItem(it) == VocabKind.word ||
            (kindOfItem(it) != VocabKind.usage && !normalizeWord(it.word).contains(' ')))
          it.lemma,
    };
    articleEntries = articleEntries.map((e) {
      if (wordKeys.contains(e.lemma)) return e;
      final candidates = renames[e.lemma];
      if (candidates == null || candidates.isEmpty) return e;
      final hit = candidates.firstWhere(
        (c) => c.sentenceId != null && c.sentenceId == e.sentenceId,
        orElse: () => candidates.first,
      );
      return e.copyWith(lemma: hit.key);
    }).toList();
  }

  return library.copyWith(items: items, articleEntries: articleEntries);
}

/// 一条待收藏的语言点（从句子语言点里抽出来的中间结构）。
class LanguagePoint {
  const LanguagePoint({
    required this.kind,
    required this.word,
    required this.source,
    this.gloss,
  });

  final VocabKind kind;

  /// 词条正文（词组 / 习语是英文原文；用法笔记是中文说明）。
  final String word;

  /// 中文释义（词组 / 习语有；用法笔记没有）。
  final String? gloss;

  /// 出自哪篇文章的哪一句。
  final VocabSource source;
}

/// 从一批句子的语言点里抽出可**收藏**的条目（词组 / 习语 / 用法笔记），带来源句。
///
/// 词组/习语的写法是「英文 — 简短中文」，这里顺手拆成 词条 + 释义。
/// 用法是中文说明，**不拆**（否则会把中文当成词条）。
List<LanguagePoint> languagePointsOf(
  List<Sentence>? sentences, {
  required String articleId,
  String? fileName,
}) {
  if (sentences == null || sentences.isEmpty) return const [];
  final out = <LanguagePoint>[];
  void push(VocabKind kind, String raw, bool split, Sentence s) {
    final text = raw.trim();
    if (text.isEmpty) return;
    final (:word, :gloss) = split ? splitGlossText(text) : (word: text, gloss: null);
    if (word.trim().isEmpty) return;
    out.add(LanguagePoint(
      kind: kind,
      word: word.trim(),
      gloss: gloss == null || gloss.trim().isEmpty ? null : gloss.trim(),
      source: VocabSource(
        articleId: articleId,
        fileName: fileName,
        sentenceId: s.id,
        sentenceText: s.text,
      ),
    ));
  }

  for (final s in sentences) {
    for (final l in getSentenceLanguages(s)) {
      for (final p in l.phrases ?? const <String>[]) {
        push(VocabKind.phrase, p, true, s);
      }
      for (final i in l.idioms ?? const <String>[]) {
        push(VocabKind.idiom, i, true, s);
      }
      for (final u in l.usage ?? const <String>[]) {
        push(VocabKind.usage, u, false, s);
      }
    }
  }
  return out;
}

final RegExp _glossSplit = RegExp(r'\s+[—–-]\s+');

/// 把「英文 — 中文」拆成 `(word, gloss)`（也认 – / - 破折号）。
({String word, String? gloss}) splitGlossText(String raw) {
  final s = raw.trim();
  final parts = s.split(_glossSplit);
  if (parts.length >= 2) {
    final word = parts[0].trim();
    final gloss = parts.skip(1).join(' — ').trim();
    if (word.isNotEmpty) return (word: word, gloss: gloss.isEmpty ? null : gloss);
  }
  return (word: s, gloss: null);
}

/// 一条语言点在词库里的**键与类型**：
///   - 用法笔记 / 没有英文的说明 → 整条文本当键，类型 `usage`（不与单词、词组撞车）；
///   - 单个英文单词（AI 偶尔把单词写进「词组」栏）→ 当普通单词（走查词与词形归并）；
///   - 其余（真词组 / 习语）→ 按原形当键，类型照旧。
({String key, VocabKind? kind}) langPointKeyAndKind(LanguagePoint p) {
  final english = normalizeWord(p.word);
  if (isSingleEnglishWord(p.word)) {
    final key = lemmaOf(p.word);
    return (key: key.isNotEmpty ? key : textKey(p.word), kind: null);
  }
  final isNote = p.kind == VocabKind.usage || english.isEmpty;
  if (isNote) return (key: textKey(p.word), kind: VocabKind.usage);
  final key = lemmaOf(p.word);
  return (key: key.isNotEmpty ? key : textKey(p.word), kind: p.kind);
}

/// 这条语言点的稳定身份（同一篇、同一句、同一段文字只收一次）。
String langPointIdOf(LanguagePoint p) {
  final kind = langPointKeyAndKind(p).kind;
  final file = (p.source.fileName ?? '').trim().isNotEmpty
      ? p.source.fileName!.trim()
      : p.source.articleId;
  return '${kind?.name ?? 'word'}|$file|${p.source.sentenceId ?? ''}|${textKey(p.word)}';
}

/// 一篇文章的语言点内容签名（内容变了才需要重收）。
Map<String, String> langPointSignature(List<LanguagePoint> points) {
  final byArticle = <String, List<String>>{};
  for (final p in points) {
    final file = (p.source.fileName ?? '').trim().isNotEmpty
        ? p.source.fileName!.trim()
        : p.source.articleId;
    final line =
        '${p.kind.name}|${p.word}|${p.source.sentenceId ?? ''}|${p.gloss ?? ''}';
    byArticle.putIfAbsent(file, () => []).add(line);
  }
  return {
    for (final e in byArticle.entries)
      e.key: (List<String>.from(e.value)..sort()).join('\u0001'),
  };
}

bool _sourceHasText(VocabSource? s) =>
    s != null && (s.sentenceText.trim().isNotEmpty || (s.sentenceId ?? '').isNotEmpty);

/// 一条语言点造出的语境与例句。
({VocabContext context, VocabExample example}) _pointContextAndExample(
  LanguagePoint p,
  String word,
  String? gloss,
  String iso,
) {
  final context = contextFromSource(p.source, iso, meaning: gloss);
  final text = p.source.sentenceText.trim();
  final example = VocabExample(
    text: text.isNotEmpty ? text : word,
    articleId: p.source.articleId,
    fileName: p.source.fileName,
    sentenceId: p.source.sentenceId,
    origin: VocabExampleOrigin.article,
  );
  return (context: context, example: example);
}

VocabItemKind? _itemKindOf(VocabKind? kind) => switch (kind) {
      null || VocabKind.word => null,
      VocabKind.phrase => VocabItemKind.phrase,
      VocabKind.idiom => VocabItemKind.idiom,
      VocabKind.usage => VocabItemKind.usage,
    };

/// 把语言点批量收进词库（**幂等**）：
///   - 先按 `langPointId`（收藏标记）找，找不到再按键/原形找；
///   - 已有的只补语境、释义、类型与例句，绝不重复建条；一次建索引、单趟处理。
///
/// 幂等很关键：调用方可能在每次「词库/文章」变动时调用它。
VocabLibrary upsertLanguagePoints(
  VocabLibrary library,
  List<LanguagePoint> points, {
  DateTime? now,
}) {
  if (points.isEmpty) return library;
  final iso = (now ?? DateTime.now()).toUtc().toIso8601String();
  final byLemma = <String, int>{};
  final byId = <String, int>{};
  for (var i = 0; i < library.items.length; i++) {
    final it = library.items[i];
    byLemma.putIfAbsent(it.lemma, () => i);
    final pid = it.langPointId;
    if (pid != null && pid.isNotEmpty) byId.putIfAbsent(pid, () => i);
  }
  final items = [...library.items];
  var changed = false;
  final collected = <({LanguagePoint point, String key, String? gloss})>[];

  for (final p in points) {
    final word = p.word.trim();
    if (word.isEmpty) continue;
    final kk = langPointKeyAndKind(p);
    if (kk.key.isEmpty) continue;
    final pointId = langPointIdOf(p);
    final gloss = (p.gloss ?? '').trim();
    final glossOrNull = gloss.isEmpty ? null : gloss;
    collected.add((point: p, key: kk.key, gloss: glossOrNull));
    final ce = _pointContextAndExample(p, word, glossOrNull, iso);
    final at = byId[pointId] ?? byLemma[kk.key];

    if (at == null) {
      items.add(VocabItem(
        id: 'vocab:${kk.key}',
        word: word,
        lemma: kk.key,
        kind: _itemKindOf(kk.kind),
        langPointId: pointId,
        meaning: glossOrNull,
        fieldSources: glossOrNull == null
            ? null
            : const {VocabField.meaning: VocabFieldSource.ai},
        examples: [ce.example],
        source: p.source,
        status: VocabStatus.queried, // 语言点自带释义，没有「待查」这一步
        contexts: [ce.context],
        createdAt: iso,
        updatedAt: iso,
      ));
      byLemma[kk.key] = items.length - 1;
      byId[pointId] = items.length - 1;
      changed = true;
      continue;
    }

    final cur = items[at];
    final contexts = upsertContext(cur.contexts, ce.context);
    // 释义：语言点自己收进来的条目（带 langPointId）允许随 AI 重跑更新；
    // 手动改过（edited/mastered）的不动；普通单词条目的释义绝不覆盖（词典/用户优先）。
    final locked =
        cur.status == VocabStatus.edited || cur.status == VocabStatus.mastered;
    final mine = cur.langPointId != null;
    final String? meaning;
    if (locked) {
      meaning = cur.meaning;
    } else if (mine && glossOrNull != null) {
      meaning = glossOrNull;
    } else {
      meaning = cur.meaning ?? glossOrNull;
    }
    final meaningFromGloss =
        !locked && glossOrNull != null && (mine || cur.meaning == null);
    final fieldSources = meaningFromGloss &&
            cur.fieldSources?[VocabField.meaning] != VocabFieldSource.ai
        ? <VocabField, VocabFieldSource>{
            ...?cur.fieldSources,
            VocabField.meaning: VocabFieldSource.ai,
          }
        : cur.fieldSources;
    // 已存在就不改类型（单词被 AI 误列为词组时不误标）。
    final nextKind = cur.kind ?? _itemKindOf(kk.kind);
    final merged = mergeExamples(cur.examples, [ce.example]);
    // 长度没变说明例句已经在了 —— 保持原引用，否则下面「没变化」判断永远为假。
    final examples = merged.length == cur.examples.length ? cur.examples : merged;
    if (identical(contexts, cur.contexts) &&
        meaning == cur.meaning &&
        identical(fieldSources, cur.fieldSources) &&
        nextKind == cur.kind &&
        identical(examples, cur.examples) &&
        cur.langPointId != null && // 还没打标记 → 这次要补上
        _sourceHasText(cur.source)) {
      continue;
    }
    items[at] = cur.copyWith(
      kind: nextKind == null ? null : () => nextKind,
      langPointId: cur.langPointId == null ? () => pointId : null,
      meaning: () => meaning,
      fieldSources: () => fieldSources,
      contexts: () => contexts,
      examples: examples,
      source: () => betterSource(cur.source, p.source),
      updatedAt: iso,
    );
    changed = true;
  }

  var out = changed ? library.copyWith(items: items) : library;
  // 语言点也要有「按篇归属」：否则侧栏语言点页签 / 按篇打印看不到它们。
  // 它们照常不参与正文编号（`articleNums` 只看单词）。
  for (final c in collected) {
    final src = c.point.source;
    final articleId =
        (src.fileName ?? '').trim().isNotEmpty ? src.fileName!.trim() : src.articleId.trim();
    if (articleId.isEmpty) continue;
    out = addArticleEntry(
      out,
      articleId: articleId,
      lemma: c.key,
      origin: VocabOrigin.auto,
      via: VocabVia.language,
      sentenceId: src.sentenceId,
      sentenceText: src.sentenceText,
      meaning: c.gloss,
      meaningSource: c.gloss == null ? null : VocabMeaningSource.context,
      now: now,
    );
  }
  return out;
}

/// 视图用：把语言点按「词组 / 习语 / 用法」分好组（空组不返回）。
List<({VocabKind kind, List<VocabItem> items})> groupLangPoints(
    List<VocabItem> items) {
  final out = <({VocabKind kind, List<VocabItem> items})>[];
  for (final kind in const [VocabKind.phrase, VocabKind.idiom, VocabKind.usage]) {
    final list = items
        .where((it) => kindOf(kind: kindOfItem(it), word: it.word) == kind)
        .toList(growable: false);
    if (list.isNotEmpty) out.add((kind: kind, items: list));
  }
  return out;
}

