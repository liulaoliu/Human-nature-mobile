/// 仿写 / 产出 / 造句历史视图的筛选口径。
///
/// 存储仍是同一个 `writingHistory`（SQLite `writing_records`），这里只决定
/// 「这个面板看哪一段」：来源按 `source` 分组，范围按文章归属分「本篇 / 全库」。
/// 金句课记录有自己的入口，不混进这里的筛选。
///
/// 对应 Web 版 `src/core/writingHistory.ts`（98 行）。
library;

import 'writing_record.dart';

/// 来源分组。
enum WritingHistorySource { all, writing, production, drillSentence }

/// 范围：本篇 / 全库。
enum WritingHistoryScope { article, all }

/// 来源的中文名。
const Map<WritingHistorySource, String> writingHistorySourceLabel =
    <WritingHistorySource, String>{
  WritingHistorySource.all: '全部来源',
  WritingHistorySource.writing: '普通仿写',
  WritingHistorySource.production: '奶牛工棚',
  WritingHistorySource.drillSentence: '拷打造句',
};

/// 筛选条件。
class WritingHistoryFilter {
  const WritingHistoryFilter({
    this.source = WritingHistorySource.all,
    this.scope = WritingHistoryScope.all,
    this.articleId = '',
  });

  final WritingHistorySource source;
  final WritingHistoryScope scope;

  /// `scope = article` 时只看这篇；空串时本篇为空，不影响全库。
  final String articleId;

  WritingHistoryFilter copyWith({
    WritingHistorySource? source,
    WritingHistoryScope? scope,
    String? articleId,
  }) =>
      WritingHistoryFilter(
        source: source ?? this.source,
        scope: scope ?? this.scope,
        articleId: articleId ?? this.articleId,
      );
}

/// 一条记录在筛选器里归哪一组；旧记录没有 source 时按普通仿写算。
WritingHistorySource writingHistorySourceOf(WritingRecord rec) {
  switch (rec.source) {
    case WritingSource.production:
      return WritingHistorySource.production;
    case WritingSource.drillSentence:
      return WritingHistorySource.drillSentence;
    default:
      return WritingHistorySource.writing;
  }
}

/// 这条记录是否属于仿写训练的历史视图（金句课记录由金句课自己展示）。
bool isWritingHistoryVisible(WritingRecord rec) => !isGoldenWritingRecord(rec);

bool _matches(WritingRecord rec, WritingHistoryFilter filter) {
  if (!isWritingHistoryVisible(rec)) return false;
  if (filter.scope == WritingHistoryScope.article &&
      rec.articleId != filter.articleId) {
    return false;
  }
  return filter.source == WritingHistorySource.all ||
      writingHistorySourceOf(rec) == filter.source;
}

/// 按范围 + 来源筛选，并按时间倒序（最近的在前）。
List<WritingRecord> filterWritingHistory(
  List<WritingRecord> history,
  WritingHistoryFilter filter,
) {
  final out = <WritingRecord>[
    for (final rec in history)
      if (_matches(rec, filter)) rec,
  ];
  out.sort((WritingRecord a, WritingRecord b) => b.at.compareTo(a.at));
  return out;
}

/// 当前范围内各来源的条数；`all` 是总数，用于按钮和下拉的括号数字。
///
/// 只算仿写训练能看到的记录，金句课记录不参与。
Map<WritingHistorySource, int> writingHistoryCounts(
  List<WritingRecord> history,
  WritingHistoryScope scope,
  String articleId,
) {
  final counts = <WritingHistorySource, int>{
    WritingHistorySource.all: 0,
    WritingHistorySource.writing: 0,
    WritingHistorySource.production: 0,
    WritingHistorySource.drillSentence: 0,
  };
  for (final rec in history) {
    if (!isWritingHistoryVisible(rec)) continue;
    if (scope == WritingHistoryScope.article && rec.articleId != articleId) {
      continue;
    }
    counts[WritingHistorySource.all] = counts[WritingHistorySource.all]! + 1;
    final key = writingHistorySourceOf(rec);
    counts[key] = counts[key]! + 1;
  }
  return counts;
}

/// 删除当前筛选范围内的记录；金句课记录永远保留，不在这个面板里清。
///
/// 用来源 + 范围判定，而不是先取列表再按对象身份删：同步 / 合并后同一条记录
/// 可能换了对象引用，但 `source` / `articleId` / 时间这些字段不会变。
List<WritingRecord> removeWritingHistory(
  List<WritingRecord> history,
  WritingHistoryFilter filter,
) =>
    <WritingRecord>[
      for (final rec in history)
        if (isGoldenWritingRecord(rec) || !_matches(rec, filter)) rec,
    ];
