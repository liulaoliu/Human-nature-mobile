/// 背单词/选词的统计：今日选词、连续打卡、近 7 天、未来到期预测、按篇生词数。
///
/// 纯函数，零 IO。对应 Web 版 `src/core/vocabStats.ts`（114 行）。
library;

import '../models/vocab.dart';
import 'activity/activity.dart';

/// 一次选词会话（与阅读页 `sessions` 结构一致）。
class PickSession {
  const PickSession({required this.at, required this.seconds, required this.picked});

  /// ISO 时刻。
  final String at;
  final int seconds;
  final int picked;

  @override
  String toString() => 'PickSession($picked, ${seconds}s)';
}

/// 背单词按天的累计（与 `studyDays` 结构一致）。
class StudyDay {
  const StudyDay({required this.day, required this.seconds, required this.cards});

  final String day;
  final int seconds;
  final int cards;

  @override
  String toString() => 'StudyDay($day, ${cards}cards, ${seconds}s)';
}

/// 所有选词会话的累计（词数 / 秒数）。
class SessionTotals {
  const SessionTotals({this.picked = 0, this.seconds = 0});

  final int picked;
  final int seconds;

  @override
  bool operator ==(Object other) =>
      other is SessionTotals && other.picked == picked && other.seconds == seconds;

  @override
  int get hashCode => Object.hash(picked, seconds);

  @override
  String toString() => 'SessionTotals($picked, ${seconds}s)';
}

SessionTotals sessionTotals(List<PickSession> sessions) {
  var picked = 0;
  var seconds = 0;
  for (final s in sessions) {
    picked += s.picked;
    seconds += s.seconds;
  }
  return SessionTotals(picked: picked, seconds: seconds);
}

/// 背单词时长合计：累计秒 / 累计评分次数 / 今日秒。
class StudyTotals {
  const StudyTotals({this.totalSeconds = 0, this.totalCards = 0, this.todaySeconds = 0});

  final int totalSeconds;
  final int totalCards;
  final int todaySeconds;

  @override
  bool operator ==(Object other) =>
      other is StudyTotals &&
      other.totalSeconds == totalSeconds &&
      other.totalCards == totalCards &&
      other.todaySeconds == todaySeconds;

  @override
  int get hashCode => Object.hash(totalSeconds, totalCards, todaySeconds);

  @override
  String toString() => 'StudyTotals($totalSeconds s, $totalCards cards, today $todaySeconds s)';
}

StudyTotals studyTotals(List<StudyDay> days, {String? todayKey, DateTime? now}) {
  final key = todayKey ?? dayKeyLocal(now);
  var totalSeconds = 0;
  var totalCards = 0;
  var todaySeconds = 0;
  for (final d in days) {
    totalSeconds += d.seconds;
    totalCards += d.cards;
    if (d.day == key) todaySeconds = d.seconds;
  }
  return StudyTotals(
    totalSeconds: totalSeconds,
    totalCards: totalCards,
    todaySeconds: todaySeconds,
  );
}

/// 今天选了多少词 + 连续打卡天数（今天没选则从昨天起算）。
class PickDayStats {
  const PickDayStats({required this.todayPicked, required this.streak});

  final int todayPicked;
  final int streak;

  @override
  bool operator ==(Object other) =>
      other is PickDayStats && other.todayPicked == todayPicked && other.streak == streak;

  @override
  int get hashCode => Object.hash(todayPicked, streak);

  @override
  String toString() => 'PickDayStats(today $todayPicked, streak $streak)';
}

Map<String, int> _pickedByDay(List<PickSession> sessions) {
  final byDay = <String, int>{};
  for (final s in sessions) {
    final t = DateTime.tryParse(s.at);
    if (t == null) continue;
    final k = dayKeyLocal(t.toLocal());
    byDay[k] = (byDay[k] ?? 0) + s.picked;
  }
  return byDay;
}

PickDayStats pickDayStats(List<PickSession> sessions, {DateTime? now}) {
  final byDay = _pickedByDay(sessions);
  final t = now ?? DateTime.now();
  final todayKey = dayKeyLocal(t);
  var cursor = t;
  if (!byDay.containsKey(todayKey)) {
    cursor = t.subtract(const Duration(days: 1));
  }
  var streak = 0;
  while (byDay.containsKey(dayKeyLocal(cursor))) {
    streak += 1;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return PickDayStats(todayPicked: byDay[todayKey] ?? 0, streak: streak);
}

/// 一天一项（`last7Days` / `dueForecast` 都用它）。
class DayBar {
  const DayBar({required this.key, required this.label, required this.count});

  /// YYYY-MM-DD。
  final String key;

  /// 横轴标签（日期数字，或「今天」）。
  final String label;

  final int count;

  @override
  bool operator ==(Object other) =>
      other is DayBar && other.key == key && other.label == label && other.count == count;

  @override
  int get hashCode => Object.hash(key, label, count);

  @override
  String toString() => 'DayBar($key, $count)';
}

/// `2026-09-29` → `29`（标签不带前导零，与 Web 版一致）。
String _dayLabel(String key) {
  if (key.length < 10) return key;
  final n = int.tryParse(key.substring(8, 10));
  return n == null ? key : '$n';
}

/// 最近 7 天每天选了多少词（从 6 天前排到今天）。
List<DayBar> last7Days(List<PickSession> sessions, {DateTime? now}) {
  final byDay = _pickedByDay(sessions);
  final t = now ?? DateTime.now();
  final out = <DayBar>[];
  for (var i = 6; i >= 0; i--) {
    final k = dayKeyLocal(t.subtract(Duration(days: i)));
    out.add(DayBar(key: k, label: _dayLabel(k), count: byDay[k] ?? 0));
  }
  return out;
}

/// 未来 N 天每天的到期词数。
///
/// 逾期（`due <= today`）都算「今天到期」：以前按原日期分桶会把昨天到期的词落到
/// 昨天，首行「今天」比实际到期数少。
List<DayBar> dueForecast(List<VocabItem> items, {DateTime? now, int days = 30}) {
  final t = now ?? DateTime.now();
  final todayKey = dayKeyLocal(t);
  final byDay = <String, int>{};
  for (final it in items) {
    final due = it.reviewState.due;
    if (due == null || due.isEmpty) continue;
    final parsed = DateTime.tryParse(due);
    if (parsed == null) continue;
    final k = dayKeyLocal(parsed.toLocal());
    final bucket = k.compareTo(todayKey) <= 0 ? todayKey : k;
    byDay[bucket] = (byDay[bucket] ?? 0) + 1;
  }
  final out = <DayBar>[];
  for (var i = 0; i < days; i++) {
    final k = dayKeyLocal(t.add(Duration(days: i)));
    out.add(DayBar(key: k, label: i == 0 ? '今天' : _dayLabel(k), count: byDay[k] ?? 0));
  }
  return out;
}

/// 按来源文章统计生词数（从多到少取前 N；未标来源归一类）。
class ArticleWordCount {
  const ArticleWordCount({required this.articleId, required this.count});

  final String articleId;
  final int count;

  @override
  bool operator ==(Object other) =>
      other is ArticleWordCount && other.articleId == articleId && other.count == count;

  @override
  int get hashCode => Object.hash(articleId, count);

  @override
  String toString() => 'ArticleWordCount($articleId, $count)';
}

const String untaggedArticleId = '未标来源';

List<ArticleWordCount> wordsByArticle(List<VocabItem> items, {int top = 10}) {
  final m = <String, int>{};
  for (final it in items) {
    final raw = it.source?.articleId ?? '';
    final k = raw.isEmpty ? untaggedArticleId : raw;
    m[k] = (m[k] ?? 0) + 1;
  }
  final entries = m.entries.toList();
  // JS 的 sort 稳定：同数量保持插入顺序，这里用 index 兜一下。
  final order = {for (var i = 0; i < entries.length; i++) entries[i].key: i};
  entries.sort((a, b) {
    final byCount = b.value.compareTo(a.value);
    if (byCount != 0) return byCount;
    return order[a.key]!.compareTo(order[b.key]!);
  });
  final keep = top < 0 ? 0 : top;
  return [
    for (final e in entries.take(keep)) ArticleWordCount(articleId: e.key, count: e.value),
  ];
}
