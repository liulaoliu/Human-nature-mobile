/// 目标 / 备忘：把「今天读完了几篇文章」这类可量化的小目标记账。
///
/// 「读完」的判定（见阅读页的接入）：
///   1) 主判据：**速读把这篇过完**（一句句推到结尾）—— 自动、无需 AI；
///   2) 兜底：在目标面板里**手动标记读完**（或撤销）；
///   3) **同一篇只记第一次读完的那天**（按 articleId 全局去重）：换一天重读不再计入，
///      第二天也不会又被列入。
///
/// 纯函数，零 IO。对应 Web 版 `src/core/goals.ts`（94 行）。
library;

/// 一条「读完」记录。
class ReadDone {
  const ReadDone({
    required this.day,
    required this.articleId,
    required this.title,
    required this.at,
  });

  /// 本地日期键 YYYY-MM-DD（**第一次**读完的那天）。
  final String day;

  /// 文章标识（articleIdentity）。
  final String articleId;

  final String title;

  /// ISO 时刻。
  final String at;

  ReadDone copyWith({String? day, String? articleId, String? title, String? at}) => ReadDone(
        day: day ?? this.day,
        articleId: articleId ?? this.articleId,
        title: title ?? this.title,
        at: at ?? this.at,
      );

  @override
  bool operator ==(Object other) =>
      other is ReadDone &&
      other.day == day &&
      other.articleId == articleId &&
      other.title == title &&
      other.at == at;

  @override
  int get hashCode => Object.hash(day, articleId, title, at);

  @override
  String toString() => 'ReadDone($articleId, $day)';
}

/// 记一次「读完」：**同一篇只记第一次**（换一天重读不再计入）。
/// 按上限截断（留最近的）。纯函数。
List<ReadDone> addReadDone(List<ReadDone> list, ReadDone entry, {int cap = 500}) {
  if (entry.articleId.isEmpty) return list;
  if (list.any((x) => x.articleId == entry.articleId)) return list;
  final next = [...list, entry];
  final keep = cap < 0 ? 0 : cap;
  return next.length <= keep ? next : next.sublist(next.length - keep);
}

/// 撤掉某篇的「读完」记录（不分哪天）。
List<ReadDone> removeReadDone(List<ReadDone> list, String articleId) =>
    [for (final x in list) if (x.articleId != articleId) x];

/// 某天读完的篇目（按时间升序）。
List<ReadDone> readDoneOn(List<ReadDone> list, String day) {
  final out = [for (final x in list) if (x.day == day) x];
  out.sort((a, b) => a.at.compareTo(b.at));
  return out;
}

/// 这篇**第一次**读完是哪天（没读过返回 null）。
String? readDayOf(List<ReadDone> list, String? articleId) {
  if (articleId == null || articleId.isEmpty) return null;
  for (final x in list) {
    if (x.articleId == articleId) return x.day;
  }
  return null;
}

/// 历史：按天分组（新的在前，组内按时间升序）。
class ReadDoneGroup {
  const ReadDoneGroup({required this.day, required this.items});

  final String day;
  final List<ReadDone> items;

  @override
  String toString() => 'ReadDoneGroup($day, ${items.length})';
}

List<ReadDoneGroup> groupReadDone(List<ReadDone> list) {
  final byDay = <String, List<ReadDone>>{};
  for (final r in list) {
    (byDay[r.day] ??= <ReadDone>[]).add(r);
  }
  final groups = [
    for (final e in byDay.entries)
      ReadDoneGroup(day: e.key, items: [...e.value]..sort((a, b) => a.at.compareTo(b.at))),
  ];
  groups.sort((a, b) => b.day.compareTo(a.day));
  return groups;
}

/// 累计：读过的篇数 / 有记录的天数。
class ReadDoneTotals {
  const ReadDoneTotals({required this.articles, required this.days});

  final int articles;
  final int days;

  @override
  bool operator ==(Object other) =>
      other is ReadDoneTotals && other.articles == articles && other.days == days;

  @override
  int get hashCode => Object.hash(articles, days);

  @override
  String toString() => 'ReadDoneTotals($articles, $days)';
}

ReadDoneTotals readDoneTotals(List<ReadDone> list) => ReadDoneTotals(
      articles: list.length,
      days: {for (final x in list) x.day}.length,
    );

/// 合并两份「读完」记录（按 articleId 去重，保留已有的）。
List<ReadDone> mergeReadDone(List<ReadDone> a, List<ReadDone> b) {
  final seen = {for (final x in a) x.articleId};
  final add = [
    for (final x in b)
      if (x.articleId.isNotEmpty && !seen.contains(x.articleId)) x,
  ];
  return [...a, ...add];
}

/// 目标热力图的色阶：一天读完几篇（0 空、1–3 逐级加深、≥4 满色）。
///
/// 篇数本来就个位数，用活动量那套阈值（1/2/3/6/10）会全是浅色。
int goalLevel(int count) {
  if (count <= 0) return 0;
  return count < 4 ? count : 4;
}

/// 目标进度百分比（0–100）。`target <= 0` 表示不设目标：读过就算 100，否则 0。
int goalPct(int done, int target) {
  if (target <= 0) return done > 0 ? 100 : 0;
  final pct = (done / target * 100).round();
  return pct > 100 ? 100 : pct;
}

/// 是否达成目标（不设目标 = 不做判定）。
bool goalReached(int done, int target) => target > 0 && done >= target;
