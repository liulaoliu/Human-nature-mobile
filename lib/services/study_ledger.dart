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
        _today = dayKeyLocal(now ?? DateTime.now());

  /// 底稿（从 `LearningRepository.load()` 拿来的那份）。
  LearningData data;

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
