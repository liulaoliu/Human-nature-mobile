import '../models/vocab.dart';
import 'article_vocab.dart';
import 'entry_kind.dart';
import 'text_norm.dart';
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
