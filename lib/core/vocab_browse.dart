/// 生词浏览页的**筛选口径**（纯函数）。
///
/// 对应 Web 版 `src/core/vocabBrowse.ts`。为什么单独一个 core 模块：面板上有
/// 范围（全部 / 本篇 / 选篇）+ 类型 + 搜索 + 日期 + 状态，这些判断要是留在组件里，
/// 就只能挂 Flutter 才能测；而且「本篇 / 选篇」一换数据源，很容易又写一份
/// 「哪些词属于这篇」的规则。
///
/// 口径：
///   - 本篇 / 选篇只认 `articleEntries`，走 [articleEntryViewsFrom]
///     （和侧栏、打印同一份）；
///   - 日期用 `createdAt` + [dayKeyLocal]（入库日，04:00 结算），和打印 / 导出一致；
///   - 类型只分「生词（普通单词）/ 语言点（词组·习语·用法）」，细分交给 [kindOf]；
///   - 状态复用 `core/vocab/review.dart` 的 [isDue] / [isFresh]，
///     别在视图里另写一套「到期 / 新词」；
///   - 已掌握默认不出现，由 `includeMastered` 显式打开。
library;

import '../models/vocab.dart';
import 'activity/activity.dart';
import 'article_meaning.dart';
import 'article_vocab.dart';
import 'entry_kind.dart';
import 'print_plan.dart' show PrintRow;
import 'vocab/review.dart' show isDue, isFresh;

/// 范围口径。
enum BrowseScope { all, article, picked }

/// 类型口径。
enum BrowseKind { all, word, lang }

/// 复习状态口径。
enum BrowseStatus { all, due, fresh, lapsed, mastered }

/// 选篇列表里的一篇（只要归属键，标题给界面用）。
class BrowseArticleRef {
  const BrowseArticleRef({
    required this.id,
    required this.title,
    this.aliases = const [],
  });

  final String id;
  final String title;
  final List<String> aliases;
}

/// 浏览筛选的输入。
class VocabBrowseInput {
  const VocabBrowseInput({
    required this.items,
    this.scope = BrowseScope.all,
    this.articleId,
    this.articleEntries,
    this.articles = const [],
    this.pickedArticleIds = const {},
    this.kind = BrowseKind.all,
    this.query = '',
    this.days = const {},
    this.status = BrowseStatus.all,
    this.includeMastered = false,
    this.now,
  });

  /// 整个词库。
  final List<VocabItem> items;

  final BrowseScope scope;

  /// 当前篇的稳定标识（`articleIdentity`）。
  final String? articleId;

  /// 整库按篇收录表。
  final List<ArticleVocabEntry>? articleEntries;

  /// 已保存文章（选篇用）。
  final List<BrowseArticleRef> articles;

  /// 选篇勾选的文章 id。
  final Set<String> pickedArticleIds;

  final BrowseKind kind;

  /// 搜索词；空串 = 不过滤。
  final String query;

  /// 选中的入库日；空集合 = 全部日期。
  final Set<String> days;

  /// 复习状态筛选。
  final BrowseStatus status;

  /// 是否显示已掌握（`status == mastered` 时忽略）。
  final bool includeMastered;

  /// 判定「到期」的时刻（测试固定；null = now）。
  final DateTime? now;
}

/// 浏览筛选的结果。
class VocabBrowseResult {
  const VocabBrowseResult({
    required this.items,
    required this.days,
    required this.dayCounts,
    required this.articleCounts,
    required this.scopeCount,
  });

  /// 过滤后的条目（未排序；排序交给视图）。
  final List<VocabItem> items;

  /// 当前范围内有内容的日期（倒序）+ 条数。
  final List<({String day, int count})> days;

  final Map<String, int> dayCounts;

  /// 选篇列表每篇的条数（跟类型 / 搜索 / 日期 / 状态走；别的范围为空）。
  final Map<String, int> articleCounts;

  /// 范围 + 含已掌握之后、类型 / 搜索 / 日期 / 状态之前的条数。
  final int scopeCount;
}

/// 入库日（逻辑日）；坏日期不参与分天，避免出现 "NaN-NaN-NaN"。
String _dayOf(VocabItem item) {
  final d = DateTime.tryParse(item.createdAt);
  if (d == null) return '';
  return dayKeyLocal(d.toLocal());
}

VocabKind _kind(VocabItem item) => kindOf(kind: kindOfItem(item), word: item.word);

bool _matchKind(VocabItem item, BrowseKind kind) {
  if (kind == BrowseKind.all) return true;
  return kind == BrowseKind.word
      ? _kind(item) == VocabKind.word
      : _kind(item) != VocabKind.word;
}

bool _matchQuery(VocabItem item, String q) {
  if (q.isEmpty) return true;
  return [item.word, item.lemma, item.meaning, item.note, item.definition]
      .any((v) => v != null && v.toLowerCase().contains(q));
}

/// 状态筛选。`mastered` 是明确的「只看已掌握」，不受 `includeMastered` 影响；
/// 其他状态仍然遵守 `includeMastered`（本篇 / 选篇默认不看已掌握）。
bool _matchStatus(VocabItem item, VocabBrowseInput input, DateTime now) {
  if (input.status == BrowseStatus.mastered) {
    return item.status == VocabStatus.mastered;
  }
  if (!input.includeMastered && item.status == VocabStatus.mastered) return false;
  switch (input.status) {
    case BrowseStatus.due:
      return isDue(item, now);
    case BrowseStatus.fresh:
      return item.status != VocabStatus.mastered && isFresh(item);
    case BrowseStatus.lapsed:
      return item.reviewState.lapses > 0;
    case BrowseStatus.all:
    case BrowseStatus.mastered:
      return true;
  }
}

bool _matchDays(VocabItem item, Set<String> days) {
  if (days.isEmpty) return true;
  return days.contains(_dayOf(item));
}

/// 某篇（可带别名）的条目。选篇时把选中篇的所有归属键并成一个集合，
/// 这样同 lemma 只出现一次（浏览页是「词条列表」，不是打印的「按篇行」）。
List<VocabItem> _sourceItems(VocabBrowseInput input) {
  final entries = input.articleEntries ?? const <ArticleVocabEntry>[];
  // 「只看已掌握」必须把 mastered 放进 source，否则 _matchStatus 永远看不到它们。
  final wantMastered =
      input.includeMastered || input.status == BrowseStatus.mastered;

  if (input.scope == BrowseScope.article) {
    final id = input.articleId ?? '';
    if (id.isEmpty) return const [];
    return [
      for (final v in articleEntryViewsFrom(
        input.items,
        entries,
        [id],
        includeLang: true,
        includeMastered: wantMastered,
      ))
        v.item,
    ];
  }

  if (input.scope == BrowseScope.picked) {
    if (input.pickedArticleIds.isEmpty) return const [];
    final ids = <String>{};
    for (final a in input.articles) {
      if (!input.pickedArticleIds.contains(a.id)) continue;
      ids.add(a.id);
      ids.addAll(a.aliases);
    }
    if (ids.isEmpty) return const [];
    return [
      for (final v in articleEntryViewsFrom(
        input.items,
        entries,
        ids.toList(growable: false),
        includeLang: true,
        includeMastered: wantMastered,
      ))
        v.item,
    ];
  }

  return wantMastered
      ? List<VocabItem>.of(input.items)
      : [
          for (final it in input.items)
            if (it.status != VocabStatus.mastered) it,
        ];
}

/// 选篇列表的每篇条数：跟当前类型 / 搜索 / 日期 / 状态一致，
/// 用户看到的就是能点出来的数。
Map<String, int> _countByArticle(
  VocabBrowseInput input,
  String q,
  DateTime now,
) {
  final counts = <String, int>{};
  final entries = input.articleEntries ?? const <ArticleVocabEntry>[];
  final refs = input.articles;
  if (refs.isEmpty) return counts;

  final byLemma = <String, VocabItem>{};
  for (final it in input.items) {
    byLemma.putIfAbsent(it.lemma, () => it);
  }
  final aliasTo = <String, String>{};
  for (final a in refs) {
    aliasTo.putIfAbsent(a.id, () => a.id);
    for (final alias in a.aliases) {
      aliasTo.putIfAbsent(alias, () => a.id);
    }
  }
  final seen = <String, Set<String>>{};
  for (final a in refs) {
    counts[a.id] = 0;
  }

  for (final entry in entries) {
    final refId = aliasTo[entry.articleId];
    if (refId == null) continue;
    final item = byLemma[entry.lemma];
    if (item == null) continue;
    final got = seen.putIfAbsent(refId, () => <String>{});
    if (got.contains(entry.lemma)) continue;
    if (!_matchStatus(item, input, now) ||
        !_matchKind(item, input.kind) ||
        !_matchQuery(item, q) ||
        !_matchDays(item, input.days)) {
      continue;
    }
    got.add(entry.lemma);
    counts[refId] = (counts[refId] ?? 0) + 1;
  }
  return counts;
}

/// 按范围 + 类型 + 搜索 + 日期 + 状态筛出要显示的条目。
VocabBrowseResult browseVocab(VocabBrowseInput input) {
  final q = input.query.trim().toLowerCase();
  final now = input.now ?? DateTime.now();
  final source = _sourceItems(input);

  final dayCounts = <String, int>{};
  for (final item in source) {
    final day = _dayOf(item);
    if (day.isEmpty) continue;
    dayCounts[day] = (dayCounts[day] ?? 0) + 1;
  }
  final days = [
    for (final e in dayCounts.entries) (day: e.key, count: e.value),
  ]..sort((a, b) => b.day.compareTo(a.day));

  final items = [
    for (final it in source)
      if (_matchStatus(it, input, now) &&
          _matchKind(it, input.kind) &&
          _matchQuery(it, q) &&
          _matchDays(it, input.days))
        it,
  ];

  return VocabBrowseResult(
    items: items,
    days: days,
    dayCounts: dayCounts,
    articleCounts:
        input.scope == BrowseScope.picked ? _countByArticle(input, q, now) : const {},
    scopeCount: source.length,
  );
}

/// 「选篇」A4 的行：一个词在 A/B 各一篇就各出一行（打印允许跨篇重复），
/// 编号按该篇条目顺序 1..n，释义用该篇语境。
///
/// 为什么不复用 `planPrint`：那边拿的是打印面板的 `content` 口径，
/// 这里要跟浏览页的类型 / 搜索 / 日期 / 状态筛选一致；两边共用
/// [articleEntryViewsFrom]，归属规则只留一份。
///
/// 只有 `scope == picked` 有意义：本篇有正文编号，全部是普通词表。
List<PrintRow> browseA4Rows(VocabBrowseInput input) {
  if (input.scope != BrowseScope.picked) return const [];
  if (input.pickedArticleIds.isEmpty) return const [];
  final refs = [
    for (final a in input.articles)
      if (input.pickedArticleIds.contains(a.id)) a,
  ];
  if (refs.isEmpty) return const [];

  final entries = input.articleEntries ?? const <ArticleVocabEntry>[];
  final wantMastered =
      input.includeMastered || input.status == BrowseStatus.mastered;
  final q = input.query.trim().toLowerCase();
  final now = input.now ?? DateTime.now();
  final rows = <PrintRow>[];

  for (final ref in refs) {
    final ids = <String>[ref.id, ...ref.aliases];
    final views = articleEntryViewsFrom(
      input.items,
      entries,
      ids,
      includeLang: true,
      includeMastered: wantMastered,
    );
    var wordNo = 0;
    for (final v in views) {
      final item = v.item;
      if (!_matchStatus(item, input, now) ||
          !_matchKind(item, input.kind) ||
          !_matchQuery(item, q) ||
          !_matchDays(item, input.days)) {
        continue;
      }
      final isWord = _kind(item) == VocabKind.word;
      if (isWord) wordNo += 1;
      final resolved = resolveArticleMeaning(
        item,
        v.entry,
        v.entry.articleId,
        sentenceId: v.entry.sentenceId,
      );
      rows.add(PrintRow(
        item: item,
        articleId: v.entry.articleId,
        articleTitle: ref.title,
        number: isWord ? wordNo : null,
        meaning: resolved?.text,
      ));
    }
  }
  return rows;
}
