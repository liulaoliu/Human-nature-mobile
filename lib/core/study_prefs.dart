/// 背单词的设置项：牌组 / 每组词数 / 每日新词额度 / 锤炼阈值 / 回顾筛选。
///
/// 为什么要单独一个模块：这些值既要**跨启动记住**（`shared_preferences`），又要
/// **跨结算点自动归零**（`newToday` 跟着 `dayKeyLocal` 走）。把「读回来的脏值怎么洗」
/// 和「跨天怎么归零」写成纯函数，仓储与 ViewModel 都只是搬运工。
///
/// 与 `schema.dart:214` 的分工一致：偏好 / 会话状态不进 SQLite —— 这几个字段丢了
/// 最多是回到默认，不影响词库与学习记录，所以走 SharedPreferences。
library;

import 'entry_kind.dart';
import 'study_pool.dart';

/// 背单词的设置（不可变）。
class StudyPrefs {
  const StudyPrefs({
    this.deck = StudyDeck.word,
    this.groupSize = 0,
    this.newLimit = 20,
    this.newToday = 0,
    this.newTodayDay = '',
    this.drillAfter = defaultDrillAfter,
    this.spelling = false,
    this.recallScope = RecallScope.article,
  });

  /// 牌组（只看单词 / 只看搭配）。
  final StudyDeck deck;

  /// 每组词数，0 = 跟随入口（学习 = 整篇，复习 / 回顾 = 20）。
  final int groupSize;

  /// 每天最多引入多少新词，0 = 不限。
  final int newLimit;

  /// 单卡停留超过多少秒算「该锤炼了」，0 = 不锤炼。
  final int drillAfter;

  /// 卡面拼写：给中文释义、让你拼英文（先拼后看，不给答案）。
  final bool spelling;

  /// 「回顾」默认按什么筛：本篇学过 / 最近 7 天。
  final RecallScope recallScope;

  /// 今天已经引入多少（配合 [newTodayDay] 判断是不是今天）。
  final int newToday;

  /// [newToday] 记的是哪一天（`dayKeyLocal` 口径）。
  final String newTodayDay;

  /// 今天还能引入几个新词；[newLimit] 为 0 时返回 0（表示不限，由调用方判断）。
  int get remainingNew {
    if (newLimit <= 0) return 0;
    final left = newLimit - newToday;
    return left < 0 ? 0 : left;
  }

  /// 到新的一天了就把「今天已引入」清零（其它字段不动）。
  StudyPrefs rollOver(String today) {
    if (newTodayDay == today) return this;
    if (newToday == 0 && newTodayDay.isEmpty) {
      return copyWith(newTodayDay: today);
    }
    return copyWith(newToday: 0, newTodayDay: today);
  }

  /// 记一次「引入了一个新词」。
  StudyPrefs bumpNewToday(String today) {
    final base = rollOver(today);
    return base.copyWith(newToday: base.newToday + 1);
  }

  StudyPrefs copyWith({
    StudyDeck? deck,
    int? groupSize,
    int? newLimit,
    int? newToday,
    String? newTodayDay,
    int? drillAfter,
    bool? spelling,
    RecallScope? recallScope,
  }) =>
      StudyPrefs(
        deck: deck ?? this.deck,
        groupSize: groupSize ?? this.groupSize,
        newLimit: newLimit ?? this.newLimit,
        newToday: newToday ?? this.newToday,
        newTodayDay: newTodayDay ?? this.newTodayDay,
        drillAfter: drillAfter ?? this.drillAfter,
        spelling: spelling ?? this.spelling,
        recallScope: recallScope ?? this.recallScope,
      );

  @override
  bool operator ==(Object other) =>
      other is StudyPrefs &&
      other.deck == deck &&
      other.groupSize == groupSize &&
      other.newLimit == newLimit &&
      other.newToday == newToday &&
      other.newTodayDay == newTodayDay &&
      other.drillAfter == drillAfter &&
      other.spelling == spelling &&
      other.recallScope == recallScope;

  @override
  int get hashCode => Object.hash(
        deck,
        groupSize,
        newLimit,
        newToday,
        newTodayDay,
        drillAfter,
        spelling,
        recallScope,
      );

  @override
  String toString() => 'StudyPrefs(deck: ${deck.name}, '
      'groupSize: $groupSize, newLimit: $newLimit, '
      'newToday: $newToday@$newTodayDay, drillAfter: $drillAfter, '
      'spelling: $spelling, recallScope: ${recallScope.name})';
}

/// 锤炼阈值默认值（秒）。与 Web 版 `reader:studyDrillAfter` 默认一致。
const int defaultDrillAfter = 60;

/// 可选的锤炼阈值（秒），0 = 不锤炼。
const List<int> drillAfterChoices = <int>[0, 30, 45, 60, 90];

/// 默认设置（牌组「单词」、每组跟随入口、每天 20 个新词、停 60 秒算锤炼、
/// 卡面拼写关、回顾默认看本篇）。
const StudyPrefs defaultStudyPrefs = StudyPrefs();

/// 序列化成落盘用的 JSON（键名固定，方便以后加字段）。
Map<String, Object?> studyPrefsToJson(StudyPrefs prefs) => <String, Object?>{
      'deck': prefs.deck.name,
      'groupSize': prefs.groupSize,
      'newLimit': prefs.newLimit,
      'newToday': prefs.newToday,
      'newTodayDay': prefs.newTodayDay,
      'drillAfter': prefs.drillAfter,
      'spelling': prefs.spelling,
      'recallScope': prefs.recallScope.name,
    };

/// 从落盘 JSON 洗回可用形状：认不出的枚举回默认，负数 / 非数字回默认。
///
/// 外部输入（旧版本、手改过的 prefs 文件）一律走这里，不做 `as` 强转。
StudyPrefs parseStudyPrefs(Object? raw) {
  if (raw is! Map) return defaultStudyPrefs;
  return StudyPrefs(
    deck: _deckOf(raw['deck']),
    groupSize: _intOf(raw['groupSize'], 0),
    newLimit: _intOf(raw['newLimit'], defaultStudyPrefs.newLimit),
    newToday: _intOf(raw['newToday'], 0),
    newTodayDay: raw['newTodayDay'] is String ? raw['newTodayDay'] as String : '',
    drillAfter: _intOf(raw['drillAfter'], defaultStudyPrefs.drillAfter),
    spelling: raw['spelling'] is bool ? raw['spelling'] as bool : defaultStudyPrefs.spelling,
    recallScope: _recallScopeOf(raw['recallScope']),
  );
}

StudyDeck _deckOf(Object? v) {
  if (v is! String) return defaultStudyPrefs.deck;
  for (final d in StudyDeck.values) {
    if (d.name == v) return d;
  }
  return defaultStudyPrefs.deck;
}

RecallScope _recallScopeOf(Object? v) {
  if (v is! String) return defaultStudyPrefs.recallScope;
  for (final s in RecallScope.values) {
    if (s.name == v) return s;
  }
  return defaultStudyPrefs.recallScope;
}

int _intOf(Object? v, int fallback) {
  final n = v is num ? v : num.tryParse('${v ?? ''}');
  if (n == null || !n.isFinite || n < 0) return fallback;
  return n.round();
}
