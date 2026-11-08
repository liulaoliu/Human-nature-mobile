/// 按篇收录层：「这篇文章收了哪些生词」——纯函数。
///
/// 与 `VocabItem` 的分工（对应 Web 版 `src/core/articleVocab.ts`）：
///   - `VocabItem`：这个词本身怎么背、释义、复习状态（全库一条，按 lemma 去重）；
///   - `ArticleVocabEntry`：这一篇什么时候收的、第几号、自动还是手动、这篇打没打印。
///
/// 为什么不能再用「正文里出现过 + 词库里有」来算本篇：
/// 那样每开一篇新文章，只要总词库里恰好有 the / is / are，就会自动变成本篇生词、
/// 带编号、进侧栏，用户并没有在这篇标过它们。本篇只认显式收录的条目。
library;

import '../models/vocab.dart';
import 'entry_kind.dart';
import 'vocab/tombstones.dart';

/// 一条按篇词条 + 它对应的全库词条。
class ArticleEntryView {
  const ArticleEntryView({required this.entry, required this.item});

  final ArticleVocabEntry entry;
  final VocabItem item;
}

/// 按篇取词条的选项。默认和侧栏/编号一致：只取普通单词、跳过已掌握。
class ArticleEntryViewOptions {
  const ArticleEntryViewOptions({
    this.includeLang = false,
    this.includeMastered = false,
  });

  /// 也包含词组 / 习语 / 用法（侧栏「语言点」页签用）。
  final bool includeLang;

  /// 也包含已掌握（浏览页「含已掌握」用；正文编号 / 复习永远不要）。
  final bool includeMastered;
}

/// 词库里所有按篇条目（老数据没有该字段时为空）。
List<ArticleVocabEntry> articleEntries(VocabLibrary library) =>
    library.articleEntries;

/// 某一篇的条目，保持加入顺序（编号 = 这个数组的下标 + 1）。
List<ArticleVocabEntry> articleEntriesOf(
    VocabLibrary library, String articleId) {
  if (articleId.isEmpty) return const [];
  return library.articleEntries
      .where((e) => e.articleId == articleId)
      .toList(growable: false);
}

/// 某一篇的 lemma → 条目。
Map<String, ArticleVocabEntry> articleEntryMap(
    VocabLibrary library, String articleId) {
  return {for (final e in articleEntriesOf(library, articleId)) e.lemma: e};
}

/// 某一篇真正要显示的词条：按加入顺序、去掉已掌握 / 已被全库删掉的。
///
/// 默认只取普通单词（正文编号 / 复习用）；`includeLang = true` 时也包含
/// 词组 / 习语 / 用法（侧栏「语言点」页签要显示，但不参与正文编号）。
/// 重复 lemma（历史脏数据）只保留第一条，避免同一词出现两个编号。
List<ArticleEntryView> articleEntryViews(
  VocabLibrary library,
  String articleId, {
  bool includeLang = false,
  bool includeMastered = false,
}) {
  return articleEntryViewsFrom(
    library.items,
    articleEntries(library),
    [articleId],
    includeLang: includeLang,
    includeMastered: includeMastered,
  );
}

/// 多篇 / 多归属键的按篇词条：同 lemma 只留第一条，保持 `entries` 的加入顺序。
///
/// 打印 / 导出和浏览页共用这一份口径 —— **别再各写一遍**
/// （别名、去重、跳过已掌握、语言点过滤这四条最容易分叉）。
List<ArticleEntryView> articleEntryViewsFrom(
  List<VocabItem> items,
  List<ArticleVocabEntry> entries,
  List<String> articleIds, {
  bool includeLang = false,
  bool includeMastered = false,
}) {
  final wanted = articleIds.toSet();
  if (wanted.isEmpty) return const [];
  final byLemma = <String, VocabItem>{};
  for (final it in items) {
    // 同一 lemma 理论上只有一条；脏数据取第一条，与 Web 版一致。
    byLemma.putIfAbsent(it.lemma, () => it);
  }

  final seen = <String>{};
  final out = <ArticleEntryView>[];
  for (final e in entries) {
    if (!wanted.contains(e.articleId) || seen.contains(e.lemma)) continue;
    final item = byLemma[e.lemma];
    if (item == null) continue; // 全库已删：本篇不再显示
    if (!includeMastered && item.status == VocabStatus.mastered) continue;
    if (!includeLang && !isWordEntry(kind: kindOfItem(item), word: item.word)) {
      continue;
    }
    seen.add(e.lemma);
    out.add(ArticleEntryView(entry: e, item: item));
  }
  return out;
}

/// 某一篇要显示 / 复习 / 打印的词条（与 `articleEntryViews` 同序）。
List<VocabItem> articleItemsOf(VocabLibrary library, String articleId) =>
    articleEntryViews(library, articleId)
        .map((x) => x.item)
        .toList(growable: false);

/// 本篇所有 lemma（含已掌握 / 语言点），用于「正文里哪些词已收」。
Set<String> articleLemmas(VocabLibrary library, String articleId) =>
    articleEntriesOf(library, articleId).map((e) => e.lemma).toSet();

/// 词条在**这一篇**的序号（1 起）；不在本篇返回 0。
///
/// 序号只按「普通单词」算：语言点不占正文编号（与侧栏一致）。
int articleIndexIn(VocabLibrary library, String articleId, String lemma) {
  final views = articleEntryViews(library, articleId);
  final at = views.indexWhere((v) => v.entry.lemma == lemma);
  return at < 0 ? 0 : at + 1;
}

/// 收录一个词到某篇（单词 / 词组 / 习语 / 用法都可收，已掌握的不收）；
/// 已收过则只补空着的语境/释义，不改变加入顺序。
VocabLibrary addArticleEntry(
  VocabLibrary library, {
  required String articleId,
  required String lemma,
  required VocabOrigin origin,
  VocabVia? via,
  String? sentenceId,
  String? sentenceText,
  String? meaning,
  VocabMeaningSource? meaningSource,
  DateTime? now,
}) {
  final aid = articleId.trim();
  final lem = lemma.trim();
  if (aid.isEmpty || lem.isEmpty) return library;
  final item = library.items.where((it) => it.lemma == lem).firstOrNull;
  if (item == null || item.status == VocabStatus.mastered) return library;

  final list = library.articleEntries;
  final idx = list.indexWhere((e) => e.articleId == aid && e.lemma == lem);
  if (idx >= 0) {
    final prev = list[idx];
    // 旧条目没有 via 时，后来的动作可以补上；已有来源不覆盖（保留第一次收录方式）。
    final text = (prev.sentenceText ?? '').isNotEmpty
        ? prev.sentenceText!
        : (sentenceText ?? '');
    final next = prev.copyWith(
      via: prev.via ?? via,
      sentenceId: prev.sentenceId ?? sentenceId,
      sentenceText: text,
      meaning: (prev.meaning?.isNotEmpty ?? false)
          ? null
          : (meaning != null ? () => meaning : null),
      meaningSource: prev.meaningSource ?? meaningSource,
    );
    if (_sameEntry(next, prev)) return library;
    final out = [...list];
    out[idx] = next;
    return library.copyWith(articleEntries: out);
  }

  final entry = ArticleVocabEntry(
    articleId: aid,
    lemma: lem,
    origin: origin,
    via: via,
    addedAt: (now ?? DateTime.now()).toIso8601String(),
    sentenceId: sentenceId,
    sentenceText: sentenceText ?? '',
    meaning: meaning,
    meaningSource: meaning != null ? (meaningSource ?? VocabMeaningSource.manual) : null,
  );
  return library.copyWith(articleEntries: [...list, entry]);
}

/// 从某一篇移出（只删这篇的收录，不动全库词条，也不影响别的篇）。
VocabLibrary removeArticleEntry(
  VocabLibrary library,
  String articleId,
  String lemma,
) {
  final list = library.articleEntries;
  final next =
      list.where((e) => !(e.articleId == articleId && e.lemma == lemma)).toList();
  if (next.length == list.length) return library;
  // 记墓碑：备份合并 / 本机与服务端合并时不会把这篇的收录又并回来。
  return addArticleTombstone(
      library.copyWith(articleEntries: next), articleId, lemma);
}

/// 记录「这一篇的这几个词打印过」；打印状态按篇独立，不污染别的篇。
VocabLibrary markArticlePrinted(
  VocabLibrary library,
  String articleId,
  Iterable<String> lemmas, {
  DateTime? now,
}) {
  final set = lemmas.toSet();
  if (set.isEmpty) return library;
  final iso = (now ?? DateTime.now()).toIso8601String();
  var changed = false;
  final next = library.articleEntries.map((e) {
    if (e.articleId != articleId || !set.contains(e.lemma)) return e;
    changed = true;
    return e.copyWith(printedAt: () => iso);
  }).toList(growable: false);
  return changed ? library.copyWith(articleEntries: next) : library;
}

/// 合并两套按篇条目（备份合并用）：同篇同 lemma 保留本机已有的顺序与字段。
List<ArticleVocabEntry> mergeArticleEntries(
  List<ArticleVocabEntry> current,
  List<ArticleVocabEntry> incoming,
) {
  final seen = {for (final e in current) '${e.articleId}\u0000${e.lemma}'};
  final out = [...current];
  for (final e in incoming) {
    final key = '${e.articleId}\u0000${e.lemma}';
    if (!seen.add(key)) continue;
    out.add(e);
  }
  return out;
}

/// 模型里的 `VocabItemKind` → 判定层的 `VocabKind`（null = 普通单词）。
VocabKind? kindOfItem(VocabItem item) => switch (item.kind) {
      null || VocabItemKind.word => VocabKind.word,
      VocabItemKind.phrase => VocabKind.phrase,
      VocabItemKind.idiom => VocabKind.idiom,
      VocabItemKind.usage => VocabKind.usage,
    };

bool _sameEntry(ArticleVocabEntry a, ArticleVocabEntry b) =>
    a.via == b.via &&
    a.sentenceId == b.sentenceId &&
    a.sentenceText == b.sentenceText &&
    a.meaning == b.meaning &&
    a.meaningSource == b.meaningSource;
