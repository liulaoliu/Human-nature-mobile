import '../../models/vocab.dart';

/// 句子原文的共享存储。
///
/// 为什么：同一个词条会同时被 `source`、`contexts`、`articleEntries` 引用同一句；
/// 每个引用各存一份原文，整库会多出几 MB（2026-10-24 盘点约 6MB）。
/// 落盘时收进 `library.sentenceTexts`（一句一份），读出来再补回各字段。
///
/// 键 = `articleId || fileName` + NUL + `sentenceId`；没有 `sentenceId` 的引用不参与。
/// 与 Web 版 `src/core/vocab/sentenceTexts.ts` 一一对应。

/// 参与共享的引用（三张表各有一个自己的类型，靠这几个取值函数统一）。
class _Ref {
  const _Ref(this.key, this.text);

  final String key;
  final String text;
}

String _textOf(Object? ref) {
  if (ref is VocabSource) return ref.sentenceText;
  if (ref is VocabContext) return ref.sentenceText;
  if (ref is ArticleVocabEntry) return ref.sentenceText ?? '';
  return '';
}

String _sentenceIdOf(Object? ref) {
  if (ref is VocabSource) return ref.sentenceId ?? '';
  if (ref is VocabContext) return ref.sentenceId ?? '';
  if (ref is ArticleVocabEntry) return ref.sentenceId ?? '';
  return '';
}

String _articleOf(Object? ref) {
  if (ref is VocabSource) return (ref.articleId.isNotEmpty ? ref.articleId : (ref.fileName ?? ''));
  if (ref is VocabContext) return (ref.articleId.isNotEmpty ? ref.articleId : (ref.fileName ?? ''));
  if (ref is ArticleVocabEntry) return ref.articleId;
  return '';
}

/// 句子原文的共享键；缺 `sentenceId` 时返回 `''`（不参与共享）。
String sentenceTextKey(Object? ref) {
  if (ref == null) return '';
  final sentenceId = _sentenceIdOf(ref).trim();
  if (sentenceId.isEmpty) return '';
  final article = _articleOf(ref).trim();
  return '$article\u0000$sentenceId';
}

bool _isEmptyText(String text) => text.trim().isEmpty;

_Ref? _refOf(Object? ref) {
  if (ref == null) return null;
  final key = sentenceTextKey(ref);
  if (key.isEmpty) return null;
  return _Ref(key, _textOf(ref));
}

/// 收集全库所有句子原文；同一键文本不一致时记为冲突，冲突键保留各自原文、不进共享表。
({Map<String, String> texts, Set<String> conflicts}) _collect(VocabLibrary library) {
  final texts = <String, String>{};
  final conflicts = <String>{};

  void add(Object? ref) {
    final r = _refOf(ref);
    if (r == null) return;
    if (_isEmptyText(r.text)) return;
    final prev = texts[r.key];
    if (prev != null && prev != r.text) {
      conflicts.add(r.key);
      return;
    }
    texts[r.key] = r.text;
  }

  for (final entry in library.sentenceTexts.entries) {
    if (entry.key.isEmpty || _isEmptyText(entry.value)) continue;
    final prev = texts[entry.key];
    if (prev != null && prev != entry.value) {
      conflicts.add(entry.key);
    } else {
      texts[entry.key] = entry.value;
    }
  }
  for (final item in library.items) {
    add(item.source);
    for (final ctx in item.contexts ?? const <VocabContext>[]) {
      add(ctx);
    }
  }
  for (final entry in library.articleEntries) {
    add(entry);
  }
  for (final key in conflicts) {
    texts.remove(key);
  }
  return (texts: texts, conflicts: conflicts);
}

Set<String> _referencedKeys(VocabLibrary library) {
  final keys = <String>{};
  void add(Object? ref) {
    final key = sentenceTextKey(ref);
    if (key.isNotEmpty) keys.add(key);
  }

  for (final item in library.items) {
    add(item.source);
    for (final ctx in item.contexts ?? const <VocabContext>[]) {
      add(ctx);
    }
  }
  for (final entry in library.articleEntries) {
    add(entry);
  }
  return keys;
}

/// 落盘前调用：把能共享的原文收进 `sentenceTexts`，并把各引用里的原文清空。
///
/// 冲突（同键不同句）不共享，避免读回时把 A 句塞给 B 引用。
/// 没有任何可共享内容时返回原对象（保住引用，别让加载路径误判「有脏数据」）。
VocabLibrary compactSentenceTexts(VocabLibrary library) {
  final collected = _collect(library);
  final texts = collected.texts;
  final conflicts = collected.conflicts;
  final referenced = _referencedKeys(library);
  for (final key in texts.keys.toList()) {
    if (!referenced.contains(key)) texts.remove(key);
  }
  if (texts.isEmpty) {
    // 没有可共享的句子：只清掉旧 map 里没人引用的键
    if (library.sentenceTexts.isEmpty) return library;
    return library.copyWith(sentenceTexts: const {});
  }

  bool stripable(Object? ref) {
    final key = sentenceTextKey(ref);
    if (key.isEmpty || conflicts.contains(key) || !texts.containsKey(key)) return false;
    return !_isEmptyText(_textOf(ref));
  }

  final items = library.items.map((item) {
    final source = item.source;
    final nextSource = source != null && stripable(source)
        ? source.copyWith(sentenceText: '')
        : source;
    final contexts = item.contexts;
    final nextContexts = contexts?.map((ctx) => stripable(ctx) ? ctx.copyWith(sentenceText: '') : ctx).toList();
    if (identical(nextSource, source) && identical(nextContexts, contexts)) return item;
    return item.copyWith(
      source: () => nextSource,
      contexts: () => nextContexts,
    );
  }).toList();

  final articleEntries = library.articleEntries
      .map((entry) => stripable(entry) ? entry.copyWith(sentenceText: '') : entry)
      .toList();

  return library.copyWith(
    items: items,
    articleEntries: articleEntries,
    sentenceTexts: texts,
  );
}

/// 读出后调用：把共享表里的原文补回 `source` / `contexts` / `articleEntries`。
/// 已经有原文的引用不动；没有共享表时原样返回。
VocabLibrary hydrateSentenceTexts(VocabLibrary library) {
  final map = library.sentenceTexts;
  if (map.isEmpty) return library;

  String? textFor(Object? ref) {
    if (ref == null) return null;
    if (!_isEmptyText(_textOf(ref))) return null;
    final text = map[sentenceTextKey(ref)];
    if (text == null || text.isEmpty) return null;
    return text;
  }

  var changed = false;

  final items = library.items.map((item) {
    final source = item.source;
    final sourceText = textFor(source);
    final nextSource = sourceText != null ? source!.copyWith(sentenceText: sourceText) : source;
    final contexts = item.contexts;
    var contextsChanged = false;
    final nextContexts = contexts?.map((ctx) {
      final text = textFor(ctx);
      if (text == null) return ctx;
      contextsChanged = true;
      return ctx.copyWith(sentenceText: text);
    }).toList();
    if (identical(nextSource, source) && !contextsChanged) return item;
    changed = true;
    return item.copyWith(
      source: () => nextSource,
      contexts: () => nextContexts,
    );
  }).toList();

  final articleEntries = library.articleEntries.map((entry) {
    final text = textFor(entry);
    if (text == null) return entry;
    changed = true;
    return entry.copyWith(sentenceText: text);
  }).toList();

  if (!changed) return library;
  return library.copyWith(items: items, articleEntries: articleEntries);
}
