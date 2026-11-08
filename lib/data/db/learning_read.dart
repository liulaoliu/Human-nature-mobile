/// 学习记录读取侧：16 段行 → 一份 `LearningData`。
///
/// 逐段照搬 Web 版 `server/sqliteLearning.ts:512-761` 的 `loadLearning`，
/// 包括每段的 `ORDER BY`：它决定了同一毫秒内多条记录谁前谁后，换个顺序
/// 时间线就会跳，测试里也用它做断言。
///
/// 返回的是**强类型** [LearningData]：读出来就要给 UI 用，形状不对的直接丢，
/// 不往下游传 `Map`。五段长期资产（仿写 / 回译 / 金句 / 错因 / 工棚）仍是原始
/// JSON 列表 —— P5 才移植它们的强类型。
library;

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../core/activity/activity.dart';
import '../../core/answer_events.dart';
import '../../core/goals.dart';
import '../../core/kind_stats.dart';
import '../../core/learning.dart';
import '../../core/mistakes.dart';
import '../../core/practice.dart';
import '../../core/vocab_stats.dart';
import '../../models/listening.dart';
import 'sql_util.dart';

/// 读一份完整的学习记录。
Future<LearningData> loadLearning(DatabaseExecutor db) async {
  final out = emptyLearning();

  out.practice = _practice(await db.rawQuery(
    'SELECT at, kind, total, correct, seconds, article_id FROM practice_records '
    'ORDER BY at ASC, id ASC',
  ));

  out.mistakes = _mistakes(await db.rawQuery(
    'SELECT id, kind, at, count, label, item_id, question_json, article_id, text '
    'FROM mistake_records ORDER BY at DESC',
  ));

  out.readDone = _readDone(await db.rawQuery(
    'SELECT article_id, day, title, at FROM reading_progress ORDER BY at ASC',
  ));

  out.writingHistory = _writing(await db.rawQuery(
    'SELECT at, article_id, article_title, model, text, feedback_json, task_json, '
    'source, sentence_id, exam_id FROM writing_records ORDER BY at DESC, id DESC',
  ));

  out.backTranslations = _backTranslations(await db.rawQuery(
    'SELECT id, at, article_id, article_title, sentence_id, source_zh, context_zh, '
    'answer, reference, feedback_json, exact, ratio, graded_by '
    'FROM back_translation_records ORDER BY at DESC, id DESC',
  ));

  out.retells = _retells(await db.rawQuery(
    'SELECT at, article_id, text, words FROM retell_records ORDER BY at DESC, id DESC',
  ));

  out.activity = _activity(await db.rawQuery(
    'SELECT day, cat, count FROM activity_days ORDER BY day ASC, cat ASC',
  ));

  out.studyDays = _studyDays(await db.rawQuery(
    'SELECT day, seconds, cards FROM study_days ORDER BY day ASC',
  ));

  out.sessions = _sessions(await db.rawQuery(
    'SELECT at, seconds, picked FROM pick_sessions ORDER BY at ASC, id ASC',
  ));

  out.studiedDays = _studiedDays(await db.rawQuery(
    'SELECT day, word_id FROM study_word_days ORDER BY day ASC, ordinal ASC',
  ));

  out.skimmed = <String>[
    for (final r in await db.rawQuery(
      'SELECT article_id FROM skimmed_articles ORDER BY article_id ASC',
    ))
      asText(r['article_id']) ?? '',
  ].where((id) => id.isNotEmpty).toList();

  out.kindStats = _kindStats(await db.rawQuery(
    'SELECT article_id, kind, total, correct FROM kind_stats ORDER BY article_id ASC, kind ASC',
  ));

  out.answerEvents = _answerEvents(await db.rawQuery(
    'SELECT at, day, article_id, source, kind, cat, correct, question_id '
    'FROM answer_events ORDER BY at ASC, id ASC',
  ));

  out.goldenDrills = _goldenDrills(await db.rawQuery(
    'SELECT id, at, article_id, article_title, sentence_id, drill_key, fill_first, '
    'assemble_first, recall_first, fill_tries, assemble_tries, recall_tries, '
    'summary_seen, mastered, completed_at FROM golden_drill_records ORDER BY at ASC, id ASC',
  ));

  out.productionProgress = _productionProgress(await db.rawQuery(
    'SELECT key, item_id, kind, text, meaning, attempts, hits, misses, streak, '
    'last_at, due_at, last_article_id, last_mode, updated_at '
    'FROM production_progress ORDER BY updated_at DESC, key ASC',
  ));

  out.writingErrorProgress = _writingErrorProgress(await db.rawQuery(
    'SELECT id, rule, key, article_id, sentence_id, exam_id, focus, original, '
    'suggestion, reason, status, streak, reviews, last_at, last_correct, due_at, '
    'created_at, updated_at FROM writing_error_progress '
    'ORDER BY updated_at DESC, id ASC',
  ));

  return out;
}

/// 是否至少有一行学习记录（偏好不算）。
///
/// 拍快照前用它挡一下：空库拍出来的快照恢复回去等于「什么都没变」，
/// 白占一个 12 版的名额。
Future<bool> hasLearningRows(DatabaseExecutor db) async {
  for (final table in _allTables) {
    final rows = await db.rawQuery('SELECT COUNT(*) AS n FROM $table');
    final n = rows.isEmpty ? 0 : asNum(rows.first['n']).toInt();
    if (n > 0) return true;
  }
  return false;
}

const List<String> _allTables = <String>[
  'practice_records',
  'mistake_records',
  'reading_progress',
  'writing_records',
  'back_translation_records',
  'retell_records',
  'activity_days',
  'study_days',
  'pick_sessions',
  'study_word_days',
  'skimmed_articles',
  'kind_stats',
  'answer_events',
  'golden_drill_records',
  'writing_error_progress',
  'production_progress',
];

List<PracticeRecord> _practice(List<Map<String, Object?>> rows) => <PracticeRecord>[
      for (final r in rows)
        PracticeRecord(
          at: asText(r['at']) ?? '',
          kind: parsePracticeKind(r['kind']) ?? PracticeKind.quiz,
          total: asNum(r['total']).toInt(),
          correct: asNum(r['correct']).toInt(),
          seconds: r['seconds'] == null ? null : asNum(r['seconds']).toInt(),
          articleId: asText(r['article_id']),
        ),
    ];

List<MistakeEntry> _mistakes(List<Map<String, Object?>> rows) => <MistakeEntry>[
      for (final r in rows)
        MistakeEntry(
          id: asText(r['id']) ?? '',
          kind: parseMistakeKind(r['kind']) ?? MistakeKind.vocab,
          at: asText(r['at']) ?? '',
          count: asNum(r['count']).toInt(),
          label: asText(r['label']) ?? '',
          itemId: asText(r['item_id']),
          question: listeningQuestionFromJson(_parseJson(r['question_json'])),
          articleId: asText(r['article_id']),
          text: asText(r['text']),
        ),
    ];

List<ReadDone> _readDone(List<Map<String, Object?>> rows) => <ReadDone>[
      for (final r in rows)
        ReadDone(
          day: asText(r['day']) ?? '',
          articleId: asText(r['article_id']) ?? '',
          title: asText(r['title']) ?? '',
          at: asText(r['at']) ?? '',
        ),
    ];

/// 仿写记录：**原文 JSON 形状**（`feedback` 展开成对象，不是字符串）。
///
/// 与写入侧对称：`feedback_json` 存字符串，读出来还原成对象，否则 UI 拿到的是
/// 一串带转义的 JSON；`source` 走白名单，坏值当没写。
List<Map<String, Object?>> _writing(List<Map<String, Object?>> rows) {
  final out = <Map<String, Object?>>[];
  for (final r in rows) {
    final rec = <String, Object?>{
      'at': asText(r['at']) ?? '',
      'articleId': asText(r['article_id']) ?? '',
      'model': asText(r['model']) ?? '',
      'text': asText(r['text']) ?? '',
      'feedback': _parseJson(r['feedback_json']) ?? <String, Object?>{},
    };
    _putIfPresent(rec, 'articleTitle', asText(r['article_title']));
    final task = _parseJson(r['task_json']);
    if (task != null) rec['task'] = task;
    final source = asText(r['source']);
    if (source != null && writingSources.contains(source)) rec['source'] = source;
    _putIfPresent(rec, 'sentenceId', asText(r['sentence_id']));
    _putIfPresent(rec, 'examId', asText(r['exam_id']));
    out.add(rec);
  }
  return out;
}

List<Map<String, Object?>> _backTranslations(List<Map<String, Object?>> rows) {
  final out = <Map<String, Object?>>[];
  for (final r in rows) {
    final rec = <String, Object?>{
      'id': asText(r['id']) ?? '',
      'at': asText(r['at']) ?? '',
      'articleId': asText(r['article_id']) ?? '',
      'sentenceId': asText(r['sentence_id']) ?? '',
      'sourceZh': asText(r['source_zh']) ?? '',
      'answer': asText(r['answer']) ?? '',
      'reference': asText(r['reference']) ?? '',
      'feedback': _parseJson(r['feedback_json']) ?? <String, Object?>{},
      // 列里是 0/1 整数，读回成 bool + 比例（与 Web 版 closeness 形状一致）。
      'closeness': <String, Object?>{
        'exact': asNum(r['exact']).toInt() == 1,
        'ratio': asNum(r['ratio']).toDouble(),
      },
    };
    _putIfPresent(rec, 'articleTitle', asText(r['article_title']));
    _putIfPresent(rec, 'contextZh', asText(r['context_zh']));
    _putIfPresent(rec, 'gradedBy', asText(r['graded_by']));
    out.add(rec);
  }
  return out;
}

List<RetellRecord> _retells(List<Map<String, Object?>> rows) => <RetellRecord>[
      for (final r in rows)
        RetellRecord(
          at: asText(r['at']) ?? '',
          articleId: asText(r['article_id']) ?? '',
          text: asText(r['text']) ?? '',
          words: asNum(r['words']).toInt(),
        ),
    ];

/// 活动聚合：一行一个 (day, cat)，按 day 折成一天一条。
List<DayActivity> _activity(List<Map<String, Object?>> rows) {
  final order = <String>[];
  final byDay = <String, Map<ActivityCat, int>>{};
  for (final r in rows) {
    final day = asText(r['day']) ?? '';
    if (day.isEmpty) continue;
    final cat = _catByName(asText(r['cat']));
    if (cat == null) continue;
    final counts = byDay.putIfAbsent(day, () {
      order.add(day);
      return <ActivityCat, int>{};
    });
    counts[cat] = asNum(r['count']).toInt();
  }
  return <DayActivity>[
    for (final day in order) DayActivity(day: day, counts: byDay[day]!),
  ];
}

ActivityCat? _catByName(String? name) {
  if (name == null) return null;
  for (final cat in activityCats) {
    if (cat.name == name) return cat;
  }
  return null;
}

List<StudyDay> _studyDays(List<Map<String, Object?>> rows) => <StudyDay>[
      for (final r in rows)
        StudyDay(
          day: asText(r['day']) ?? '',
          seconds: asNum(r['seconds']).toInt(),
          cards: asNum(r['cards']).toInt(),
        ),
    ];

List<PickSession> _sessions(List<Map<String, Object?>> rows) => <PickSession>[
      for (final r in rows)
        PickSession(
          at: asText(r['at']) ?? '',
          seconds: asNum(r['seconds']).toInt(),
          picked: asNum(r['picked']).toInt(),
        ),
    ];

/// 一行一个 (day, word_id)，按 day 折回去，ids 保持 ordinal 顺序。
List<StudiedDay> _studiedDays(List<Map<String, Object?>> rows) {
  final order = <String>[];
  final byDay = <String, List<String>>{};
  for (final r in rows) {
    final day = asText(r['day']) ?? '';
    final id = asText(r['word_id']) ?? '';
    if (day.isEmpty || id.isEmpty) continue;
    byDay.putIfAbsent(day, () {
      order.add(day);
      return <String>[];
    }).add(id);
  }
  return <StudiedDay>[
    for (final day in order) StudiedDay(day: day, ids: byDay[day]!),
  ];
}

KindStats _kindStats(List<Map<String, Object?>> rows) {
  final out = emptyKindStats();
  for (final r in rows) {
    final articleId = asText(r['article_id']) ?? '';
    final kind = asText(r['kind']) ?? '';
    if (articleId.isEmpty || kind.isEmpty) continue;
    out.putIfAbsent(articleId, () => <String, KindStat>{})[kind] = KindStat(
      total: asNum(r['total']).toInt(),
      correct: asNum(r['correct']).toInt(),
    );
  }
  return out;
}

List<AnswerEvent> _answerEvents(List<Map<String, Object?>> rows) {
  final out = <AnswerEvent>[];
  for (final r in rows) {
    final source = parsePracticeKind(r['source']);
    final cat = _catByName(asText(r['cat']));
    // source / cat 认不出来就丢：这条事件无法归到任何会话或分类。
    if (source == null || cat == null) continue;
    out.add(AnswerEvent(
      at: asText(r['at']) ?? '',
      day: asText(r['day']) ?? '',
      articleId: asText(r['article_id']) ?? '',
      source: source,
      kind: asText(r['kind']) ?? '',
      cat: cat,
      correct: asNum(r['correct']).toInt() != 0,
      questionId: asText(r['question_id']),
    ));
  }
  return out;
}

List<Map<String, Object?>> _goldenDrills(List<Map<String, Object?>> rows) {
  final out = <Map<String, Object?>>[];
  for (final r in rows) {
    final rec = <String, Object?>{
      'id': asText(r['id']) ?? '',
      'at': asText(r['at']) ?? '',
      'articleId': asText(r['article_id']) ?? '',
      'sentenceId': asText(r['sentence_id']) ?? '',
      'drillKey': asText(r['drill_key']) ?? '',
      'fillTries': asNum(r['fill_tries']).toInt(),
      'assembleTries': asNum(r['assemble_tries']).toInt(),
      'recallTries': asNum(r['recall_tries']).toInt(),
      'mastered': asNum(r['mastered']).toInt() != 0,
    };
    _putIfPresent(rec, 'articleTitle', asText(r['article_title']));
    // 布尔列在库里是 0/1，只把 true 写回去：与 Web 版「非 0 才给 true」一致，
    // 少一个 `false` 键就少一份噪音。
    if (asNum(r['fill_first']).toInt() != 0) rec['fillFirst'] = true;
    if (asNum(r['assemble_first']).toInt() != 0) rec['assembleFirst'] = true;
    if (asNum(r['recall_first']).toInt() != 0) rec['recallFirst'] = true;
    if (asNum(r['summary_seen']).toInt() != 0) rec['summarySeen'] = true;
    _putIfPresent(rec, 'completedAt', asText(r['completed_at']));
    out.add(rec);
  }
  return out;
}

List<Map<String, Object?>> _productionProgress(List<Map<String, Object?>> rows) {
  final out = <Map<String, Object?>>[];
  for (final r in rows) {
    final rec = <String, Object?>{
      'key': asText(r['key']) ?? '',
      'kind': asText(r['kind']) ?? 'word',
      'text': asText(r['text']) ?? '',
      'meaning': asText(r['meaning']) ?? '',
      'attempts': asNum(r['attempts']).toInt(),
      'hits': asNum(r['hits']).toInt(),
      'misses': asNum(r['misses']).toInt(),
      'streak': asNum(r['streak']).toInt(),
      'lastAt': asText(r['last_at']) ?? '',
      'dueAt': asText(r['due_at']) ?? '',
    };
    _putIfPresent(rec, 'itemId', asText(r['item_id']));
    _putIfPresent(rec, 'lastArticleId', asText(r['last_article_id']));
    _putIfPresent(rec, 'lastMode', asText(r['last_mode']));
    _putIfPresent(rec, 'updatedAt', asText(r['updated_at']));
    out.add(rec);
  }
  return out;
}

List<Map<String, Object?>> _writingErrorProgress(List<Map<String, Object?>> rows) {
  final out = <Map<String, Object?>>[];
  for (final r in rows) {
    final rec = <String, Object?>{
      'id': asText(r['id']) ?? '',
      'rule': asText(r['rule']) ?? '',
      'key': asText(r['key']) ?? '',
      'articleId': asText(r['article_id']) ?? '',
      'original': asText(r['original']) ?? '',
      'suggestion': asText(r['suggestion']) ?? '',
      'status': asText(r['status']) ?? 'active',
      'streak': asNum(r['streak']).toInt(),
      'reviews': asNum(r['reviews']).toInt(),
      'createdAt': asText(r['created_at']) ?? '',
      'updatedAt': asText(r['updated_at']) ?? '',
    };
    _putIfPresent(rec, 'sentenceId', asText(r['sentence_id']));
    _putIfPresent(rec, 'examId', asText(r['exam_id']));
    _putIfPresent(rec, 'focus', asText(r['focus']));
    _putIfPresent(rec, 'reason', asText(r['reason']));
    _putIfPresent(rec, 'lastAt', asText(r['last_at']));
    // 三态：NULL = 没考过。这里不能用 `!= 0`，否则 NULL 会被读成 false。
    final lastCorrect = r['last_correct'];
    if (lastCorrect != null) rec['lastCorrect'] = asNum(lastCorrect).toInt() != 0;
    _putIfPresent(rec, 'dueAt', asText(r['due_at']));
    out.add(rec);
  }
  return out;
}

/// 坏 JSON 当「没有」：单条脏字段不该让整份学习记录读不出来。
Object? _parseJson(Object? v) {
  if (v == null) return null;
  if (v is! String) return v;
  if (v.isEmpty) return null;
  try {
    return jsonDecode(v);
  } catch (_) {
    return null;
  }
}

void _putIfPresent(Map<String, Object?> rec, String key, Object? value) {
  if (value != null) rec[key] = value;
}
