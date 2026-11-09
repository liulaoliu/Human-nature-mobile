/// 备份「合并导入」：把一份备份里的内容并进现有数据，而不是整片覆盖。
///
/// 对应 Web 版 `src/core/mergeBackup.ts`（260 行）。
///
/// 覆盖式导入的语义是「还原」—— 词库整库替换、统计整段替换。合并导入面向
/// 「另一台机器的数据想并过来」：
/// - 词库：按 lemma 去重互补（不丢字段、不丢词）；
/// - 文章：按 id upsert（不在这里做，本来就不会清空别的文章）；
/// - 统计：会话 / 练习 / 仿写按记录去重后拼接；背单词与活动按「天」累加；
///   错题按 id 累加次数（同一份备份再导一次不会重复计数）。
///
/// **全是纯函数**，落 core/，方便单测；落库由仓储负责。
library;

import '../models/vocab.dart';
import 'activity/activity.dart';
import 'answer_events.dart';
import 'article_vocab.dart';
import 'goals.dart' show ReadDone;
import 'golden_progress.dart';
import 'kind_stats.dart';
import 'learning.dart';
import 'mistakes.dart';
import 'practice.dart';
import 'vocab/merge.dart' show dedupeLibrary;
import 'vocab/tombstones.dart';
import 'vocab_stats.dart';

/// 各种记录的保留上限（与 Web 版逐字一致）。
const int mergeSessionCap = 500;
const int mergePracticeCap = 500;
const int mergeMistakeCap = 300;
const int mergeRetellCap = 200;
const int mergeActivityCap = 400;

/// 句子原文共享表：同键不同文时**本机优先**。
///
/// 键是 `articleId\0sentenceId`，两台机器上的同名文章可能已经被改过（换过句子、
/// 删过段），同一个键会指向不同原文。这里不能整表覆盖：覆盖了，本机那些引用
/// 该键的词条（`source` / `contexts` 的原文已收进共享表、自身是空串）会突然
/// 显示另一台机器的句子。合并导入的承诺是「不覆盖本机」，所以旧值留着，
/// 新键照常补进来。
Map<String, String> mergeSentenceTexts(
  Map<String, String> current,
  Map<String, String> incoming,
) {
  if (incoming.isEmpty) return current;
  if (current.isEmpty) return incoming;
  return <String, String>{...incoming, ...current};
}

/// 合并两套词库：按 lemma 去重互补，保留任一方已有的字段；按篇条目取并集。
VocabLibrary mergeLibraries(VocabLibrary current, VocabLibrary incoming) {
  final sentenceTexts = mergeSentenceTexts(current.sentenceTexts, incoming.sentenceTexts);
  final tombstones = mergeTombstones(current.tombstones, incoming.tombstones);
  return applyTombstones(dedupeLibrary(VocabLibrary(
    schemaVersion: current.schemaVersion,
    items: <VocabItem>[...current.items, ...incoming.items],
    articleEntries: mergeArticleEntries(current.articleEntries, incoming.articleEntries),
    sentenceTexts: sentenceTexts,
    tombstones: tombstones,
  )));
}

/// 合并选词会话：同一条记录去重，按时间升序，保留最近 [cap] 条。
List<PickSession> mergeSessions(
  List<PickSession> current,
  List<PickSession> incoming, {
  int cap = mergeSessionCap,
}) {
  String key(PickSession s) => '${s.at}|${s.seconds}|${s.picked}';
  final seen = <String>{for (final s in current) key(s)};
  final out = <PickSession>[...current];
  for (final s in incoming) {
    if (!seen.add(key(s))) continue;
    out.add(s);
  }
  out.sort((PickSession a, PickSession b) => a.at.compareTo(b.at));
  final keep = cap < 0 ? 0 : cap;
  return out.length <= keep ? out : out.sublist(out.length - keep);
}

/// 合并背单词按天累计：同一天的秒数与卡数相加。
List<StudyDay> mergeStudyDays(List<StudyDay> current, List<StudyDay> incoming) {
  final byDay = <String, StudyDay>{};
  for (final d in current) {
    byDay[d.day] = d;
  }
  for (final d in incoming) {
    final prev = byDay[d.day];
    byDay[d.day] = prev == null
        ? d
        : StudyDay(day: d.day, seconds: prev.seconds + d.seconds, cards: prev.cards + d.cards);
  }
  final out = byDay.values.toList(growable: false);
  out.sort((StudyDay a, StudyDay b) => a.day.compareTo(b.day));
  return out;
}

/// 合并活动热力图数据：同一天同类相加（复用 [addActivity] 的排序与上限）。
///
/// 为什么不能直接拼列表：同一天两份数据拼在一起会出现两条 `day` 相同的记录，
/// 热力图会把那天的格子画两遍。这里逐类累加后交给 [addActivity] 归并。
List<DayActivity> mergeActivity(
  List<DayActivity> current,
  List<DayActivity> incoming, {
  int cap = mergeActivityCap,
}) {
  var out = current;
  for (final day in incoming) {
    for (final cat in activityCats) {
      final n = day.countOf(cat);
      if (n > 0) out = addActivity(out, day.day, cat, n: n, cap: cap);
    }
  }
  return out;
}

/// 合并仿写记录（**强类型**）：按「时间 + 文章 + 范句 + 作答」去重，按时间倒序。
///
/// 注意与 `writingAttemptKey` 的区别：那个不含 `at`、管的是「同一稿重复粘回」；
/// 这里是两份**不同机器**的备份合并，`at` 是区分两边的唯一依据，必须带上。
List<Map<String, Object?>> mergeWritingHistoryJson(
  List<Map<String, Object?>> current,
  List<Map<String, Object?>> incoming, {
  int cap = -1,
}) {
  String key(Map<String, Object?> w) =>
      '${w['at']}|${w['articleId']}|${w['model']}|${w['text']}';
  final seen = <String>{for (final w in current) key(w)};
  final out = <Map<String, Object?>>[...current];
  for (final w in incoming) {
    if (!seen.add(key(w))) continue;
    out.add(w);
  }
  out.sort((Map<String, Object?> a, Map<String, Object?> b) =>
      '${b['at']}'.compareTo('${a['at']}'));
  if (cap < 0) return out;
  return out.length <= cap ? out : out.sublist(0, cap);
}

/// 合并回译存档：按 id 去重后拼接，按时间倒序。
///
/// 这是长期资产，**不设「只留最近 N 条」的上限**；同一份备份重复导入也不会重复。
List<Map<String, Object?>> mergeBackTranslations(
  List<Map<String, Object?>> current,
  List<Map<String, Object?>> incoming,
) {
  final byId = <String, Map<String, Object?>>{};
  for (final r in <Map<String, Object?>>[...current, ...incoming]) {
    final id = r['id'];
    if (id is String && id.isNotEmpty) {
      byId[id] = r;
    }
  }
  final out = byId.values.toList();
  out.sort((Map<String, Object?> a, Map<String, Object?> b) =>
      '${b['at']}'.compareTo('${a['at']}'));
  return out;
}

/// 合并练习记录：按字段去重，按时间升序，保留最近 [cap] 条。
List<PracticeRecord> mergePractice(
  List<PracticeRecord> current,
  List<PracticeRecord> incoming, {
  int cap = mergePracticeCap,
}) {
  String key(PracticeRecord p) =>
      '${p.at}|${p.kind.name}|${p.total}|${p.correct}|${p.seconds ?? ''}|${p.articleId ?? ''}';
  final seen = <String>{for (final p in current) key(p)};
  final out = <PracticeRecord>[...current];
  for (final p in incoming) {
    if (!seen.add(key(p))) continue;
    out.add(p);
  }
  out.sort((PracticeRecord a, PracticeRecord b) => a.at.compareTo(b.at));
  final keep = cap < 0 ? 0 : cap;
  return out.length <= keep ? out : out.sublist(out.length - keep);
}

/// 合并答题事件：按「时间 + 文章 + 题型 + 题目」去重，按时间升序，保留最近 [cap] 条。
List<AnswerEvent> mergeAnswerEvents(
  List<AnswerEvent> current,
  List<AnswerEvent> incoming, {
  int cap = answerEventCap,
}) {
  String key(AnswerEvent e) =>
      '${e.at}|${e.articleId}|${e.source.name}|${e.kind}|${e.correct ? 1 : 0}|${e.questionId ?? ''}';
  final seen = <String>{for (final e in current) key(e)};
  final out = <AnswerEvent>[...current];
  for (final e in incoming) {
    if (!seen.add(key(e))) continue;
    out.add(e);
  }
  out.sort((AnswerEvent a, AnswerEvent b) => a.at.compareTo(b.at));
  final keep = cap < 0 ? 0 : cap;
  return out.length <= keep ? out : out.sublist(out.length - keep);
}

/// 合并错题本：同 id 累加次数、保留更近的一条；完全相同的一份记录不重复计数。
List<MistakeEntry> mergeMistakes(
  List<MistakeEntry> current,
  List<MistakeEntry> incoming, {
  int cap = mergeMistakeCap,
}) {
  final byId = <String, MistakeEntry>{};
  for (final m in current) {
    byId[m.id] = m;
  }
  for (final m in incoming) {
    final prev = byId[m.id];
    if (prev == null) {
      byId[m.id] = m;
      continue;
    }
    // 同一份备份再导一次：字段完全一致，视作重复，不累加。
    if (prev.at == m.at && prev.count == m.count) continue;
    final newer = prev.at.compareTo(m.at) >= 0 ? prev : m;
    byId[m.id] = newer.copyWith(count: prev.count + m.count);
  }
  final out = byId.values.toList();
  out.sort((MistakeEntry a, MistakeEntry b) => b.at.compareTo(a.at));
  final keep = cap < 0 ? 0 : cap;
  return out.length <= keep ? out : out.sublist(0, keep);
}

/// 合并复述：按「时间 + 文章 + 正文」去重，按时间倒序，保留最近 [cap] 条。
List<RetellRecord> mergeRetells(
  List<RetellRecord> current,
  List<RetellRecord> incoming, {
  int cap = mergeRetellCap,
}) {
  String key(RetellRecord r) => '${r.at}|${r.articleId}|${r.text}';
  final seen = <String>{for (final r in current) key(r)};
  final out = <RetellRecord>[...current];
  for (final r in incoming) {
    if (!seen.add(key(r))) continue;
    out.add(r);
  }
  out.sort((RetellRecord a, RetellRecord b) => b.at.compareTo(a.at));
  final keep = cap < 0 ? 0 : cap;
  return out.length <= keep ? out : out.sublist(0, keep);
}

/// 合并「每天背过哪些词」：同一天取 id 并集，不重复计数。
List<StudiedDay> mergeStudiedDays(
  List<StudiedDay> current,
  List<StudiedDay> incoming,
) {
  final byDay = <String, Set<String>>{};
  for (final d in <StudiedDay>[...current, ...incoming]) {
    final ids = byDay[d.day] ?? <String>{};
    ids.addAll(d.ids);
    byDay[d.day] = ids;
  }
  final days = byDay.keys.toList()..sort();
  return <StudiedDay>[
    for (final day in days) StudiedDay(day: day, ids: byDay[day]!.toList()),
  ];
}

/// 合并精读「略读」标记：按文章 id 取并集。
List<String> mergeSkimmed(List<String> current, List<String> incoming) =>
    <String>{...current, ...incoming}.toList();

/// 合并按篇/题型正确率。
///
/// 这份数据只有 total/correct，没有时间戳或事件 id，无法判断两份是不是同一批
/// 答题；因此取「题数更多的那个口径」，保证同一份备份重复导入不会把正确率翻倍。
KindStats mergeKindStats(KindStats current, KindStats incoming) {
  final out = <String, Map<String, KindStat>>{
    for (final entry in current.entries)
      entry.key: <String, KindStat>{...entry.value},
  };
  for (final entry in incoming.entries) {
    final target = out.putIfAbsent(entry.key, () => <String, KindStat>{});
    for (final sub in entry.value.entries) {
      final prev = target[sub.key];
      final next = sub.value;
      if (prev == null || next.total > prev.total ||
          (next.total == prev.total && next.correct > prev.correct)) {
        target[sub.key] = next;
      }
    }
  }
  return out;
}

/// 合并「读完」记录：同一篇只留最早的一天（与 `addReadDone` 口径一致）。
///
/// 不能直接取并集：`ReadDone` 的相等还包括 `day` 与 `at`，同一篇文章在另一台
/// 机器上晚一天读完会产生第二条，而「读完」这件事一篇只该记一次 —— 否则
/// 目标里的「共读完几篇」会被两份备份放大。
List<ReadDone> mergeReadDone(List<ReadDone> current, List<ReadDone> incoming) {
  final byArticle = <String, ReadDone>{};
  for (final r in <ReadDone>[...current, ...incoming]) {
    if (r.articleId.isEmpty) continue;
    final prev = byArticle[r.articleId];
    if (prev == null || r.at.compareTo(prev.at) < 0) byArticle[r.articleId] = r;
  }
  final out = byArticle.values.toList();
  out.sort((ReadDone a, ReadDone b) => a.at.compareTo(b.at));
  return out;
}

/// 合并金句锤炼记录（**原始 JSON 版**）：按 id 取「更完整」的一份。
///
/// 强类型版在 [mergeGoldenDrills]（`golden_progress.dart`），那边的合并会重算
/// `mastered`、两边 OR 首次标记。备份导入走的是原始 JSON（`LearningData` 里
/// 这几段按原样存），所以这里先还原成强类型、合并、再写回 JSON。
List<Map<String, Object?>> mergeGoldenDrillsJson(
  List<Map<String, Object?>> current,
  List<Map<String, Object?>> incoming,
) => <Map<String, Object?>>[
      for (final r in mergeGoldenDrills(
        normalizeGoldenDrills(current),
        normalizeGoldenDrills(incoming),
      ))
        r.toJson(),
    ];

/// 合并「错因复习状态」：按 key 取更晚更新的那条。
///
/// 这是派生自仿写记录的复习进度（`writingErrorProgress`），没有跨机合并的历史口径；
/// 这里按 `updatedAt`/`at` 取较新的一条，同键不重复计数。
List<Map<String, Object?>> mergeKeyedProgress(
  List<Map<String, Object?>> current,
  List<Map<String, Object?>> incoming, {
  String keyField = 'key',
  String atField = 'updatedAt',
}) {
  final byKey = <String, Map<String, Object?>>{};
  for (final row in <Map<String, Object?>>[...current, ...incoming]) {
    final key = row[keyField];
    if (key is! String || key.isEmpty) continue;
    final prev = byKey[key];
    if (prev == null) {
      byKey[key] = row;
      continue;
    }
    // 较晚的那条优先；相同时保留本机（current 先写进来，这里不动）。
    final prevAt = '${prev[atField] ?? ''}';
    final nextAt = '${row[atField] ?? ''}';
    if (nextAt.compareTo(prevAt) > 0) byKey[key] = row;
  }
  return byKey.values.toList();
}

/// 把一份备份的学习记录并进现有记录（**整段合并**，不覆盖）。
///
/// 这是「合并导入」的核心：12 段各按自己的口径去重/累加，任何一段坏了都不影响
/// 别的段（调用方负责先过 `parseBackupPayload` 的守卫）。
LearningData mergeLearningData(LearningData current, LearningData incoming) =>
    LearningData(
      practice: mergePractice(current.practice, incoming.practice),
      mistakes: mergeMistakes(current.mistakes, incoming.mistakes),
      readDone: mergeReadDone(current.readDone, incoming.readDone),
      writingHistory:
          mergeWritingHistoryJson(current.writingHistory, incoming.writingHistory),
      backTranslations:
          mergeBackTranslations(current.backTranslations, incoming.backTranslations),
      retells: mergeRetells(current.retells, incoming.retells),
      activity: mergeActivity(current.activity, incoming.activity),
      studyDays: mergeStudyDays(current.studyDays, incoming.studyDays),
      sessions: mergeSessions(current.sessions, incoming.sessions),
      studiedDays: mergeStudiedDays(current.studiedDays, incoming.studiedDays),
      skimmed: mergeSkimmed(current.skimmed, incoming.skimmed),
      kindStats: mergeKindStats(current.kindStats, incoming.kindStats),
      answerEvents: mergeAnswerEvents(current.answerEvents, incoming.answerEvents),
      goldenDrills: mergeGoldenDrillsJson(current.goldenDrills, incoming.goldenDrills),
      writingErrorProgress: mergeKeyedProgress(
        current.writingErrorProgress,
        incoming.writingErrorProgress,
      ),
      productionProgress: mergeKeyedProgress(
        current.productionProgress,
        incoming.productionProgress,
      ),
    );
