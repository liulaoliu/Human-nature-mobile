/// 背单词要记的两笔账：「今天学过哪些词」和「今天背了几个词」。
///
/// 为什么单独一个类：这两笔账以前散在 `useStudyGrading` 的 `tally` 里（React 的
/// `setState` + localStorage），而判分、拼错、组末验收三处都要记，写三遍迟早漏一处
/// （比如「新词第一次判到才计引入」漏了一处，今天的额度就少扣一次）。
///
/// 这里只做「内存里累加」，落盘交给调用方按需 flush——学一张卡就写一次库太吵，
/// 一轮结束 / 退出时写一次就够。
///
/// 注意 `LearningData` 里那些记录都是**不可变**的（`StudiedDay.ids`、`DayActivity.counts`
/// 都是 final），所以这里一律换新对象重建列表，别原地改。
library;

import '../core/activity/activity.dart';
import '../core/learning.dart';

/// 一轮（或一次会话）里的学习记账。
class StudyLedger {
  StudyLedger({LearningData? data, DateTime? now})
      : data = data ?? emptyLearning(),
        _anchor = now ?? DateTime.now(),
        _today = dayKeyLocal(now ?? DateTime.now());

  /// 底稿（从 `LearningRepository.load()` 拿来的那份）。
  LearningData data;

  /// 「现在」的锚点（测试里注入；[studiedIdsWithin] 从它往回数）。
  final DateTime _anchor;

  final String _today;

  /// 今天这个日期键（测试里可以注入）。
  String get today => _today;

  /// 记「今天背过这个词」。同一词重复调用只留一次（保留首次顺序）。
  void markStudied(String id) {
    if (id.isEmpty) return;
    final days = data.studiedDays;
    final at = days.indexWhere((d) => d.day == _today);
    if (at < 0) {
      data.studiedDays = [
        ...days,
        StudiedDay(day: _today, ids: [id]),
      ];
      return;
    }
    final cur = days[at];
    if (cur.ids.contains(id)) return;
    data.studiedDays = [
      for (var i = 0; i < days.length; i++)
        if (i != at) days[i] else StudiedDay(day: _today, ids: [...cur.ids, id]),
    ];
  }

  /// 记一次活动（背单词默认记 [ActivityCat.vocab]）。
  void recordActivity(ActivityCat cat, [int n = 1]) {
    if (n <= 0) return;
    final days = data.activity;
    final at = days.indexWhere((d) => d.day == _today);
    if (at < 0) {
      data.activity = [
        ...days,
        DayActivity(day: _today, counts: {cat: n}),
      ];
      return;
    }
    final cur = days[at];
    final counts = {...cur.counts, cat: cur.countOf(cat) + n};
    data.activity = [
      for (var i = 0; i < days.length; i++)
        if (i != at) days[i] else DayActivity(day: _today, counts: counts),
    ];
  }

  /// 今天背过多少个不重复的词。
  int get studiedCount {
    for (final d in data.studiedDays) {
      if (d.day == _today) return d.ids.length;
    }
    return 0;
  }

  /// 今天背过的词 id（保持首次顺序）。
  ///
  /// 给「今天背过的再过一遍」用：SRS 把这些词的 due 排到了明天以后，
  /// 当天不会进任何队列，想再看一遍只能走这个入口。
  List<String> get studiedIds {
    for (final d in data.studiedDays) {
      if (d.day == _today) return List<String>.unmodifiable(d.ids);
    }
    return const <String>[];
  }

  /// 最近 [days] 天（含今天）学过的词 id，按日期从新到旧去重。
  ///
  /// 给「回顾 · 最近 7 天」用。为什么不按 `updatedAt` 筛词条：词条被自动补全、
  /// 改释义都会动 `updatedAt`，那不是「学过」；学过只记在 `studiedDays` 里。
  Set<String> studiedIdsWithin(int days) {
    if (days <= 0) return const <String>{};
    final keys = <String>{
      for (var i = 0; i < days; i++) dayKeyLocal(_anchor.subtract(Duration(days: i))),
    };
    final out = <String>{};
    // 从新到旧：同一天里先出现的（首次顺序）优先，这里用倒序压平。
    for (var i = data.studiedDays.length - 1; i >= 0; i--) {
      final d = data.studiedDays[i];
      if (!keys.contains(d.day)) continue;
      out.addAll(d.ids);
    }
    return out;
  }

  /// 今天记了几次「词」这个活动。
  int get vocabCount {
    for (final d in data.activity) {
      if (d.day == _today) return d.countOf(ActivityCat.vocab);
    }
    return 0;
  }

  /// 这一轮到底记了没有——没记过就不用写库。
  bool get dirty => studiedCount > 0 || vocabCount > 0;
}
