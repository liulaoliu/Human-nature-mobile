/// 打印 / 导出的**选片计划**（纯函数）：把「内容 + 范围 + 分组」算成
/// 「要打哪些条目、标题叫什么」。
///
/// 对应 Web 版 `src/core/printPlan.ts`。为什么从面板里抽出来：面板原本内联了
/// 150 行领域判断（按日期筛、未打印筛、多选文章归并、标题拼接……）。这类逻辑
/// 放进组件有三宗罪：测不了、和别的视图各写一份规矩会漂、组件越来越胖。
/// 现在面板只负责「收集用户选择 + 渲染」，判断全在这里，单测覆盖。
library;

import '../models/vocab.dart';
import 'activity/activity.dart';
import 'article_meaning.dart';
import 'article_vocab.dart';
import 'entry_kind.dart';

/// 分组方式（与打印模板一致）。
enum PrintGroupBy { alphabet, article, date, status }

/// 内容口径：只打单词 / 只要语言点 / 全都要。
enum PrintContent { all, word, phrases, usage }

/// 范围口径。
enum PrintScope { article, byArticle, date, unprinted, all }

const Map<PrintGroupBy, String> printGroupLabel = <PrintGroupBy, String>{
  PrintGroupBy.alphabet: '按字母',
  PrintGroupBy.article: '按文章',
  PrintGroupBy.date: '按加入日期',
  PrintGroupBy.status: '按状态',
};

const Map<PrintContent, String> printContentLabel = <PrintContent, String>{
  PrintContent.all: '全部',
  PrintContent.word: '单词',
  PrintContent.phrases: '词组 / 习语',
  PrintContent.usage: '用法笔记',
};

/// 「内容」→ 要保留的类型（null = 不过滤）。
List<VocabKind>? contentKinds(PrintContent c) => switch (c) {
      PrintContent.word => const [VocabKind.word],
      PrintContent.phrases => const [VocabKind.phrase, VocabKind.idiom],
      PrintContent.usage => const [VocabKind.usage],
      PrintContent.all => null,
    };

/// 一篇可参与「按文章」导出的文章。
class PrintArticleRef {
  const PrintArticleRef({
    required this.id,
    required this.title,
    this.aliases = const [],
    this.lemmas,
  });

  final String id;
  final String title;

  /// 同一篇文章的其他键（如保存 id / 书内 key），按篇条目可能用其中之一。
  final List<String> aliases;

  /// 老字段：正文里出现过的 lemma；没有按篇条目时兜底用。
  final Set<String>? lemmas;
}

/// 打印/导出的一行：同一词条在不同篇可以有不同编号，所以不能只传 `VocabItem`。
class PrintRow {
  const PrintRow({
    required this.item,
    required this.articleId,
    required this.articleTitle,
    this.number,
    this.meaning,
  });

  final VocabItem item;

  /// 这一行属于哪篇（全局范围可能为空）。
  final String articleId;
  final String articleTitle;

  /// 本篇编号（全局范围 / 语言点为空）。
  final int? number;

  /// 这一篇语境下的释义（没有则用 `item.meaning`）。
  final String? meaning;

  @override
  String toString() =>
      'PrintRow($articleId, ${item.lemma}, #$number, $meaning)';
}

/// 把「当前这一篇的条目」转成打印行。视图只传编号/语境释义取值器，
/// 行结构只在 core 里定义一次。
List<PrintRow> printRowsForItems(
  List<VocabItem> items, {
  required String articleId,
  required String articleTitle,
  int? Function(VocabItem item)? numberOf,
  String? Function(VocabItem item)? meaningOf,
}) {
  return [
    for (final item in items)
      PrintRow(
        item: item,
        articleId: articleId,
        articleTitle: articleTitle,
        number: numberOf?.call(item),
        meaning: meaningOf?.call(item),
      ),
  ];
}

/// 一次打印计划的输入。
class PrintPlanInput {
  const PrintPlanInput({
    required this.libraryItems,
    required this.articleItems,
    this.articleId,
    this.articleEntries,
    required this.articleTitle,
    this.articles = const [],
    this.pickedArticles = const {},
    this.pickedDates = const {},
    this.content = PrintContent.all,
    this.scope = PrintScope.all,
  });

  /// 整个词库。
  final List<VocabItem> libraryItems;

  /// 当前这篇的条目。
  final List<VocabItem> articleItems;

  /// 当前这篇的稳定标识。
  final String? articleId;

  /// 按篇收录表（null = 老调用方，按 `source` / `lemmas` 兜底）。
  final List<ArticleVocabEntry>? articleEntries;

  /// 当前这篇的标题（空则用兜底名）。
  final String articleTitle;

  final List<PrintArticleRef> articles;
  final Set<String> pickedArticles;
  final Set<String> pickedDates;
  final PrintContent content;
  final PrintScope scope;
}

/// 算出来的打印计划。
class PrintPlan {
  const PrintPlan({
    required this.contentCounts,
    required this.pool,
    required this.articlePool,
    required this.items,
    required this.rows,
    required this.title,
    required this.dates,
    required this.articleCount,
    required this.unprinted,
    required this.isArticleOrder,
    required this.canAct,
  });

  /// 每个「内容」口径有多少条（面板上直接显示，免得用户猜）。
  final Map<PrintContent, int> contentCounts;

  /// 内容过滤后的全库 / 本篇。
  final List<VocabItem> pool;
  final List<VocabItem> articlePool;

  /// 最终要处理的条目。
  final List<VocabItem> items;

  /// 最终要处理的「行」：带篇名与篇内编号，按文章范围时允许跨篇重复。
  final List<PrintRow> rows;

  final String title;

  /// 有内容的日期（倒序，带条数）——热力图与日期列表用。
  final List<({String day, int count})> dates;

  /// 每篇的条数（「按文章」列表用）。
  final Map<String, int> articleCount;

  final List<VocabItem> unprinted;

  /// 本篇按正文顺序编号（不分组）。
  final bool isArticleOrder;

  final bool canAct;
}

String _dayOf(VocabItem it) {
  final d = DateTime.tryParse(it.createdAt);
  if (d == null) return '';
  return dayKeyLocal(d.toLocal());
}

/// 算出这次要打什么。**纯函数**：给同样的输入永远同样的输出。
///
/// `scope == article` 但本篇过滤后为空时保持空，**绝不降级成「全库」**
/// （否则新文章会白捡总词库的词）。
PrintPlan planPrint(PrintPlanInput input) {
  final kinds = contentKinds(input.content);
  final contentCounts = <PrintContent, int>{
    PrintContent.all: input.libraryItems.length,
    PrintContent.word: 0,
    PrintContent.phrases: 0,
    PrintContent.usage: 0,
  };
  for (final it in input.libraryItems) {
    switch (kindOf(kind: kindOfItem(it), word: it.word)) {
      case VocabKind.word:
        contentCounts[PrintContent.word] = contentCounts[PrintContent.word]! + 1;
      case VocabKind.usage:
        contentCounts[PrintContent.usage] = contentCounts[PrintContent.usage]! + 1;
      case VocabKind.phrase:
      case VocabKind.idiom:
        contentCounts[PrintContent.phrases] =
            contentCounts[PrintContent.phrases]! + 1;
    }
  }

  List<VocabItem> filterByKinds(List<VocabItem> list) {
    if (kinds == null) return List<VocabItem>.of(list);
    return [
      for (final it in list)
        if (kinds.contains(kindOf(kind: kindOfItem(it), word: it.word))) it,
    ];
  }

  final pool = filterByKinds(input.libraryItems);
  final articlePool = filterByKinds(input.articleItems);

  final dateCounts = <String, int>{};
  for (final it in pool) {
    final d = _dayOf(it);
    if (d.isEmpty) continue;
    dateCounts[d] = (dateCounts[d] ?? 0) + 1;
  }
  final datesSorted = [
    for (final e in dateCounts.entries) (day: e.key, count: e.value),
  ]..sort((a, b) => b.day.compareTo(a.day));

  final unprinted = [
    for (final it in pool)
      if ((it.lastPrintedAt ?? '').isEmpty) it,
  ];

  final articleTitleById = <String, String>{};
  for (final a in input.articles) {
    articleTitleById[a.id] = a.title;
    for (final alias in a.aliases) {
      articleTitleById[alias] = a.title;
    }
  }

  /// 某篇的行：按篇条目顺序、篇内 1..n；同一词在别的篇可以再出现一次。
  List<PrintRow> rowsForArticle(PrintArticleRef a) {
    final ids = <String>[a.id, ...a.aliases];
    final entriesTable = input.articleEntries;
    if (entriesTable != null) {
      final views = articleEntryViewsFrom(
        input.libraryItems,
        entriesTable,
        ids,
        includeLang: true,
        includeMastered: false,
      );
      final rows = <PrintRow>[];
      var wordNo = 0;
      for (final v in views) {
        final item = v.item;
        final k = kindOf(kind: kindOfItem(item), word: item.word);
        if (kinds != null && !kinds.contains(k)) continue;
        final resolved = resolveArticleMeaning(
          item,
          v.entry,
          v.entry.articleId,
          sentenceId: v.entry.sentenceId,
        );
        final isWord = k == VocabKind.word;
        if (isWord) wordNo += 1;
        rows.add(PrintRow(
          item: item,
          articleId: v.entry.articleId,
          articleTitle: a.title,
          number: isWord ? wordNo : null,
          meaning: resolved?.text,
        ));
      }
      return rows;
    }
    // 老调用方：没有按篇表时退回 source + 正文 lemma。
    final seen = <String>{};
    var wordNo = 0;
    final rows = <PrintRow>[];
    for (final item in pool) {
      if (seen.contains(item.lemma)) continue;
      final fromSource = item.source?.fileName == a.id;
      final fromLemmas = a.lemmas?.contains(item.lemma) ?? false;
      if (!fromSource && !fromLemmas) continue;
      seen.add(item.lemma);
      final isWord = kindOf(kind: kindOfItem(item), word: item.word) == VocabKind.word;
      if (isWord) wordNo += 1;
      rows.add(PrintRow(
        item: item,
        articleId: a.id,
        articleTitle: a.title,
        number: isWord ? wordNo : null,
      ));
    }
    return rows;
  }

  List<PrintRow> rowsForItems(List<VocabItem> items) => [
        for (final item in items)
          PrintRow(
            item: item,
            articleId: item.source?.fileName ?? '',
            articleTitle: articleTitleById[item.source?.fileName ?? ''] ??
                ((item.source?.fileName ?? '').isNotEmpty
                    ? item.source!.fileName!
                    : (input.articleTitle.isNotEmpty ? input.articleTitle : '未分类')),
          ),
      ];

  List<PrintRow> rows;
  switch (input.scope) {
    case PrintScope.article:
      final articleId = input.articleId ?? '';
      final currentEntries = <String, ArticleVocabEntry>{};
      for (final e in input.articleEntries ?? const <ArticleVocabEntry>[]) {
        if (articleId.isNotEmpty && e.articleId != articleId) continue;
        currentEntries.putIfAbsent(e.lemma, () => e);
      }
      rows = [
        for (final item in articlePool)
          () {
            final entry = currentEntries[item.lemma];
            final resolved = entry == null
                ? null
                : resolveArticleMeaning(
                    item,
                    entry,
                    entry.articleId,
                    sentenceId: entry.sentenceId,
                  );
            return PrintRow(
              item: item,
              articleId: articleId,
              articleTitle: input.articleTitle.isNotEmpty ? input.articleTitle : '本篇',
              meaning: resolved?.text,
            );
          }(),
      ];
      var wordNo = 0;
      rows = [
        for (final row in rows)
          kindOf(kind: kindOfItem(row.item), word: row.item.word) == VocabKind.word
              ? PrintRow(
                  item: row.item,
                  articleId: row.articleId,
                  articleTitle: row.articleTitle,
                  number: ++wordNo,
                  meaning: row.meaning,
                )
              : row,
      ];
    case PrintScope.byArticle:
      final picked = input.articles
          .where((a) => input.pickedArticles.contains(a.id))
          .toList(growable: false);
      rows = [for (final a in picked) ...rowsForArticle(a)];
    case PrintScope.date:
      rows = rowsForItems([
        for (final it in pool)
          if (input.pickedDates.contains(_dayOf(it))) it,
      ]);
    case PrintScope.unprinted:
      rows = rowsForItems(unprinted);
    case PrintScope.all:
      rows = rowsForItems(pool);
  }

  final items = [for (final r in rows) r.item];
  final articleCount = <String, int>{
    for (final a in input.articles) a.id: rowsForArticle(a).length,
  };

  final base = input.content == PrintContent.phrases
      ? '词组习语表'
      : input.content == PrintContent.usage
          ? '用法笔记'
          : '词表';
  String title;
  switch (input.scope) {
    case PrintScope.article:
      title = input.content == PrintContent.all
          ? (input.articleTitle.isNotEmpty ? input.articleTitle : '本篇生词')
          : '${input.articleTitle.isNotEmpty ? input.articleTitle : '本篇'}·$base';
    case PrintScope.byArticle:
      final names = input.articles
          .where((a) => input.pickedArticles.contains(a.id))
          .map((a) => a.title)
          .toList(growable: false);
      title = names.length == 1 ? '$base-${names.first}' : '$base-${names.length}篇';
    case PrintScope.date:
      final ds = input.pickedDates.toList()..sort();
      title = ds.length == 1 ? '$base-新增-${ds.first}' : '$base-新增-${ds.length}天';
    case PrintScope.unprinted:
      title =
          '全部${input.content == PrintContent.all ? '生词' : printContentLabel[input.content]}（未打印）';
    case PrintScope.all:
      title =
          '全部${input.content == PrintContent.all ? '生词' : printContentLabel[input.content]}';
  }

  return PrintPlan(
    contentCounts: contentCounts,
    pool: pool,
    articlePool: articlePool,
    items: items,
    rows: rows,
    title: title,
    dates: datesSorted,
    articleCount: articleCount,
    unprinted: unprinted,
    isArticleOrder:
        input.scope == PrintScope.article || input.scope == PrintScope.byArticle,
    canAct: rows.isNotEmpty,
  );
}
