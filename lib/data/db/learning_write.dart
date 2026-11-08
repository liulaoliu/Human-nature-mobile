/// 学习记录写入侧：每段一套「先清后插」的语句。
///
/// 逐函数照搬 Web 版 `server/sqliteLearningWrite.ts`（397 行），包括它对坏数据的
/// 处理口径：**收窄容器 → 过滤条目 → 单字段兜底**，任何坏形状都「当空 / 整条跳过」，
/// 绝不抛错。写库不该因为一条脏记录把整份学习记录挡在门外。
///
/// 输入刻意用 JSON 形状（`Object?`）而不是强类型：五段长期资产（仿写 / 回译 /
/// 金句 / 错因 / 工棚）在 P1 阶段本来就以原始 JSON 存着，用强类型反而要多写一遍守卫。
/// 强类型那侧由 `learning_json.dart` 摊平后再进来，两边共用同一套写入逻辑。
library;

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../core/learning.dart';
import 'sql_util.dart';

/// 长期资产：这些段**永不清表**，只按主键 upsert。
///
/// 理由各不相同，但结果一致 —— 它们记的都是「做过的痕迹」，整份保存或恢复旧快照
/// 时把表清掉就等于把历史抹了：
///  - 答题事件是 append-only 审计，同步只追加 / 去重；
///  - 回译存档按 id 去重，文章删了也要能回看；
///  - 金句进度、错因复习状态、工棚进度都是「改行」，暂停 / 掌握靠改字段，不靠删。
const Set<LearningSection> learningKeepSections = <LearningSection>{
  LearningSection.answerEvents,
  LearningSection.backTranslations,
  LearningSection.goldenDrills,
  LearningSection.writingErrorProgress,
  LearningSection.productionProgress,
};

/// 清掉指定段对应的表（长期资产那五段跳过）。
Future<void> clearLearningSections(
  DatabaseExecutor db,
  List<LearningSection> sections,
) async {
  final tables = <String>{};
  for (final section in sections) {
    if (learningKeepSections.contains(section)) continue;
    final table = _tables[section];
    if (table != null) tables.add(table);
  }
  for (final table in tables) {
    await db.rawDelete('DELETE FROM $table');
  }
}

/// 把一份学习记录写进表（调用方负责事务与快照）。
///
/// [sections] 为空时不出手：语义是「这几个段」，不是「全部」。
Future<void> writeSections(
  DatabaseExecutor db,
  Object? data,
  List<LearningSection> sections,
) async {
  if (sections.isEmpty) return;
  await clearLearningSections(db, sections);
  final rec = asRecord(data) ?? const <String, Object?>{};
  for (final section in sections) {
    final write = _writers[section];
    if (write != null) await write(db, rec);
  }
}

/// 各段 → 表名。与 `migrations.dart` 的 `learningSectionTables` 必须一致，
/// 那边是给读代码的人看的对照表，这边是写入真的要用。
const Map<LearningSection, String> _tables = <LearningSection, String>{
  LearningSection.practice: 'practice_records',
  LearningSection.mistakes: 'mistake_records',
  LearningSection.readDone: 'reading_progress',
  LearningSection.writingHistory: 'writing_records',
  LearningSection.backTranslations: 'back_translation_records',
  LearningSection.retells: 'retell_records',
  LearningSection.activity: 'activity_days',
  LearningSection.studyDays: 'study_days',
  LearningSection.sessions: 'pick_sessions',
  LearningSection.studiedDays: 'study_word_days',
  LearningSection.skimmed: 'skimmed_articles',
  LearningSection.kindStats: 'kind_stats',
  LearningSection.answerEvents: 'answer_events',
  LearningSection.goldenDrills: 'golden_drill_records',
  LearningSection.writingErrorProgress: 'writing_error_progress',
  LearningSection.productionProgress: 'production_progress',
};

/// 仿写来源白名单 —— **直接引用 core 的那一份**，别再抄一遍。
/// 坏值当普通仿写写 NULL，别让一条脏数据把金句课历史带歪。
const Set<String> _writingSources = writingSources;

/// 工序表。顺序无所谓（每段各自清表），用 Map 只是为了少写一层 switch。
const Map<LearningSection, Future<void> Function(DatabaseExecutor, Map<String, Object?>)> _writers =
    <LearningSection, Future<void> Function(DatabaseExecutor, Map<String, Object?>)>{
  LearningSection.practice: _writePractice,
  LearningSection.mistakes: _writeMistakes,
  LearningSection.readDone: _writeReadDone,
  LearningSection.writingHistory: _writeWriting,
  LearningSection.backTranslations: _writeBackTranslations,
  LearningSection.retells: _writeRetells,
  LearningSection.activity: _writeActivity,
  LearningSection.studyDays: _writeStudyDays,
  LearningSection.sessions: _writeSessions,
  LearningSection.studiedDays: _writeStudiedDays,
  LearningSection.skimmed: _writeSkimmed,
  LearningSection.kindStats: _writeKindStats,
  LearningSection.answerEvents: _writeAnswerEvents,
  LearningSection.goldenDrills: _writeGoldenDrills,
  LearningSection.writingErrorProgress: _writeWritingErrorProgress,
  LearningSection.productionProgress: _writeProductionProgress,
};

String? _jsonText(Object? v) {
  if (v == null) return null;
  try {
    return jsonEncode(v);
  } catch (_) {
    return null;
  }
}

bool _nonEmpty(Object? v) => v is String && v.trim().isNotEmpty;

Future<void> _writePractice(DatabaseExecutor db, Map<String, Object?> data) async {
  for (final r in asList<Object?>(data['practice'])) {
    if (r is! Map) continue;
    final rec = _asMap(r);
    // seconds 非有限数一律存 NULL（0 与「没记录用时」不是一回事）。
    final seconds = rec['seconds'];
    final secs = seconds is num && seconds.isFinite ? seconds : num.tryParse('$seconds');
    await db.rawInsert(
      'INSERT INTO practice_records (at, kind, total, correct, seconds, article_id) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      [
        asText(rec['at']) ?? nowIso(),
        asText(rec['kind']) ?? 'quiz',
        asNum(rec['total']),
        asNum(rec['correct']),
        secs is num && secs.isFinite ? secs : null,
        asText(rec['articleId']),
      ],
    );
  }
}

Future<void> _writeMistakes(DatabaseExecutor db, Map<String, Object?> data) async {
  for (final r in asList<Object?>(data['mistakes'])) {
    if (r is! Map) continue;
    final rec = _asMap(r);
    if (!_nonEmpty(rec['id'])) continue;
    final count = asNum(rec['count'], 1);
    await db.rawInsert(
      'INSERT OR REPLACE INTO mistake_records '
      '(id, kind, at, count, label, item_id, question_json, article_id, text) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        asText(rec['id']),
        asText(rec['kind']) ?? 'vocab',
        asText(rec['at']) ?? nowIso(),
        // 错次数至少 1：0 次错不该出现在错题本里。
        count < 1 ? 1 : count.toInt(),
        asText(rec['label']) ?? '',
        asText(rec['itemId']),
        _jsonText(rec['question']),
        asText(rec['articleId']),
        asText(rec['text']),
      ],
    );
  }
}

Future<void> _writeReadDone(DatabaseExecutor db, Map<String, Object?> data) async {
  for (final r in asList<Object?>(data['readDone'])) {
    if (r is! Map) continue;
    final rec = _asMap(r);
    if (!_nonEmpty(rec['articleId'])) continue;
    await db.rawInsert(
      'INSERT OR REPLACE INTO reading_progress (article_id, day, title, at) '
      'VALUES (?, ?, ?, ?)',
      [
        asText(rec['articleId']),
        asText(rec['day']) ?? '',
        asText(rec['title']) ?? '',
        asText(rec['at']) ?? nowIso(),
      ],
    );
  }
}

Future<void> _writeWriting(DatabaseExecutor db, Map<String, Object?> data) async {
  for (final r in asList<Object?>(data['writingHistory'])) {
    if (r is! Map) continue;
    final rec = _asMap(r);
    final source = rec['source'];
    await db.rawInsert(
      'INSERT INTO writing_records '
      '(at, article_id, article_title, model, text, feedback_json, task_json, source, sentence_id, exam_id) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        asText(rec['at']) ?? nowIso(),
        asText(rec['articleId']) ?? '',
        asText(rec['articleTitle']),
        asText(rec['model']) ?? '',
        asText(rec['text']) ?? '',
        _jsonText(rec['feedback']) ?? '{}',
        _jsonText(rec['task']),
        source is String && _writingSources.contains(source) ? source : null,
        asText(rec['sentenceId']),
        asText(rec['examId']),
      ],
    );
  }
}

Future<void> _writeBackTranslations(DatabaseExecutor db, Map<String, Object?> data) async {
  for (final r in asList<Object?>(data['backTranslations'])) {
    if (r is! Map) continue;
    final rec = _asMap(r);
    if (!_nonEmpty(rec['id'])) continue;
    // at 与 sentenceId 必须是字符串才收：它们决定这条记录挂在哪句上。
    if (rec['at'] is! String || rec['sentenceId'] is! String) continue;
    final closeness = asRecord(rec['closeness']) ?? const <String, Object?>{};
    await db.rawInsert(
      'INSERT OR REPLACE INTO back_translation_records '
      '(id, at, article_id, article_title, sentence_id, source_zh, context_zh, answer, reference, '
      'feedback_json, exact, ratio, graded_by) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        asText(rec['id']),
        rec['at'],
        asText(rec['articleId']) ?? '',
        asText(rec['articleTitle']),
        rec['sentenceId'],
        asText(rec['sourceZh']) ?? '',
        asText(rec['contextZh']),
        asText(rec['answer']) ?? '',
        asText(rec['reference']) ?? '',
        _jsonText(rec['feedback']) ?? '{}',
        closeness['exact'] == true ? 1 : 0,
        asNum(closeness['ratio']),
        asText(rec['gradedBy']),
      ],
    );
  }
}

Future<void> _writeRetells(DatabaseExecutor db, Map<String, Object?> data) async {
  for (final r in asList<Object?>(data['retells'])) {
    if (r is! Map) continue;
    final rec = _asMap(r);
    if (rec['articleId'] is! String) continue;
    await db.rawInsert(
      'INSERT INTO retell_records (at, article_id, text, words) VALUES (?, ?, ?, ?)',
      [
        asText(rec['at']) ?? nowIso(),
        rec['articleId'],
        asText(rec['text']) ?? '',
        asNum(rec['words']),
      ],
    );
  }
}

Future<void> _writeActivity(DatabaseExecutor db, Map<String, Object?> data) async {
  for (final r in asList<Object?>(data['activity'])) {
    if (r is! Map) continue;
    final rec = _asMap(r);
    if (rec['day'] is! String) continue;
    final counts = asRecord(rec['counts']) ?? const <String, Object?>{};
    for (final e in counts.entries) {
      await db.rawInsert(
        'INSERT OR REPLACE INTO activity_days (day, cat, count) VALUES (?, ?, ?)',
        [rec['day'], e.key, asNum(e.value)],
      );
    }
  }
}

Future<void> _writeStudyDays(DatabaseExecutor db, Map<String, Object?> data) async {
  for (final r in asList<Object?>(data['studyDays'])) {
    if (r is! Map) continue;
    final rec = _asMap(r);
    if (rec['day'] is! String) continue;
    await db.rawInsert(
      'INSERT INTO study_days (day, seconds, cards) VALUES (?, ?, ?)',
      [rec['day'], asNum(rec['seconds']), asNum(rec['cards'])],
    );
  }
}

Future<void> _writeSessions(DatabaseExecutor db, Map<String, Object?> data) async {
  for (final r in asList<Object?>(data['sessions'])) {
    if (r is! Map) continue;
    final rec = _asMap(r);
    await db.rawInsert(
      'INSERT INTO pick_sessions (at, seconds, picked) VALUES (?, ?, ?)',
      [asText(rec['at']) ?? nowIso(), asNum(rec['seconds']), asNum(rec['picked'])],
    );
  }
}

Future<void> _writeStudiedDays(DatabaseExecutor db, Map<String, Object?> data) async {
  for (final r in asList<Object?>(data['studiedDays'])) {
    if (r is! Map) continue;
    final rec = _asMap(r);
    if (rec['day'] is! String) continue;
    final day = rec['day'];
    final ids = asList<Object?>(rec['ids']);
    for (var i = 0; i < ids.length; i++) {
      final id = ids[i];
      if (id is! String || id.isEmpty) continue;
      // OR IGNORE：同一天重复背同一个词只留第一次的序号。
      await db.rawInsert(
        'INSERT OR IGNORE INTO study_word_days (day, word_id, ordinal) VALUES (?, ?, ?)',
        [day, id, i],
      );
    }
  }
}

Future<void> _writeSkimmed(DatabaseExecutor db, Map<String, Object?> data) async {
  for (final id in asList<Object?>(data['skimmed'])) {
    if (id is! String || id.isEmpty) continue;
    await db.rawInsert(
      'INSERT OR IGNORE INTO skimmed_articles (article_id) VALUES (?)',
      [id],
    );
  }
}

Future<void> _writeKindStats(DatabaseExecutor db, Map<String, Object?> data) async {
  final stats = asRecord(data['kindStats']);
  if (stats == null) return;
  for (final article in stats.entries) {
    final byKind = asRecord(article.value);
    if (byKind == null) continue;
    for (final kind in byKind.entries) {
      final stat = asRecord(kind.value);
      if (stat == null) continue;
      await db.rawInsert(
        'INSERT OR REPLACE INTO kind_stats (article_id, kind, total, correct) '
        'VALUES (?, ?, ?, ?)',
        [article.key, kind.key, asNum(stat['total']), asNum(stat['correct'])],
      );
    }
  }
}

Future<void> _writeAnswerEvents(DatabaseExecutor db, Map<String, Object?> data) async {
  for (final r in asList<Object?>(data['answerEvents'])) {
    if (r is! Map) continue;
    final rec = _asMap(r);
    // 四个分类字段缺一个就没法对账，整条跳过。
    if (rec['at'] is! String || rec['source'] is! String) continue;
    if (rec['kind'] is! String || rec['cat'] is! String) continue;
    await db.rawInsert(
      'INSERT OR IGNORE INTO answer_events '
      '(at, day, article_id, source, kind, cat, correct, question_id) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [
        rec['at'],
        asText(rec['day']) ?? '',
        asText(rec['articleId']) ?? '',
        rec['source'],
        rec['kind'],
        rec['cat'],
        rec['correct'] == true ? 1 : 0,
        asText(rec['questionId']),
      ],
    );
  }
}

/// 布尔列在库里存 0/1。写 `int` 而不是 `bool`：sqflite 的 bool 支持依赖版本，
/// 而且读了要跟 Web 版（`=== true ? 1 : 0`）对齐 —— `'true'` 这种脏值要当 false。
int _flag(Object? v) => v == true ? 1 : 0;

Future<void> _writeGoldenDrills(DatabaseExecutor db, Map<String, Object?> data) async {
  for (final r in asList<Object?>(data['goldenDrills'])) {
    if (r is! Map) continue;
    final rec = _asMap(r);
    if (!_nonEmpty(rec['id'])) continue;
    final articleId = asText(rec['articleId']);
    final sentenceId = asText(rec['sentenceId']);
    final drillKey = asText(rec['drillKey']);
    if (articleId == null || sentenceId == null || drillKey == null) continue;
    await db.rawInsert(
      'INSERT OR REPLACE INTO golden_drill_records '
      '(id, at, article_id, article_title, sentence_id, drill_key, '
      'fill_first, assemble_first, recall_first, fill_tries, assemble_tries, recall_tries, '
      'summary_seen, mastered, completed_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        asText(rec['id']),
        asText(rec['at']) ?? nowIso(),
        articleId,
        asText(rec['articleTitle']),
        sentenceId,
        drillKey,
        _flag(rec['fillFirst']),
        _flag(rec['assembleFirst']),
        _flag(rec['recallFirst']),
        asNum(rec['fillTries']),
        asNum(rec['assembleTries']),
        asNum(rec['recallTries']),
        _flag(rec['summarySeen']),
        _flag(rec['mastered']),
        asText(rec['completedAt']),
      ],
    );
  }
}

Future<void> _writeWritingErrorProgress(DatabaseExecutor db, Map<String, Object?> data) async {
  for (final r in asList<Object?>(data['writingErrorProgress'])) {
    if (r is! Map) continue;
    final rec = _asMap(r);
    if (!_nonEmpty(rec['id'])) continue;
    final rule = asText(rec['rule']);
    final key = asText(rec['key']);
    if (rule == null || key == null) continue;
    final status = rec['status'];
    final created = asText(rec['createdAt']) ?? nowIso();
    final lastCorrect = rec['lastCorrect'];
    await db.rawInsert(
      'INSERT OR REPLACE INTO writing_error_progress '
      '(id, rule, key, article_id, sentence_id, exam_id, focus, original, suggestion, reason, '
      'status, streak, reviews, last_at, last_correct, due_at, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        asText(rec['id']),
        rule,
        key,
        asText(rec['articleId']) ?? '',
        asText(rec['sentenceId']),
        asText(rec['examId']),
        asText(rec['focus']),
        asText(rec['original']) ?? '',
        asText(rec['suggestion']) ?? '',
        asText(rec['reason']),
        // 只认 paused / mastered，其它状态（含拼错的）一律 active：
        // 误判成 paused 会让这张卡永远不出现，比当作 active 更糟。
        status == 'paused' || status == 'mastered' ? status as String : 'active',
        asNum(rec['streak']),
        asNum(rec['reviews']),
        asText(rec['lastAt']),
        // 三态：没考过是 NULL，不能写 0（0 表示「上次答错」）。
        lastCorrect is bool ? (lastCorrect ? 1 : 0) : null,
        asText(rec['dueAt']),
        created,
        asText(rec['updatedAt']) ?? created,
      ],
    );
  }
}

Future<void> _writeProductionProgress(DatabaseExecutor db, Map<String, Object?> data) async {
  if (data['productionProgress'] is! List) return;
  final keys = <String>[];
  for (final r in asList<Object?>(data['productionProgress'])) {
    if (r is! Map) continue;
    final rec = _asMap(r);
    final key = asText(rec['key']);
    final kind = rec['kind'];
    final body = asText(rec['text']);
    if (key == null || body == null) continue;
    if (kind != 'word' && kind != 'phrase' && kind != 'idiom') continue;
    keys.add(key);
    final lastAt = asText(rec['lastAt']) ?? nowIso();
    await db.rawInsert(
      'INSERT OR REPLACE INTO production_progress '
      '(key, item_id, kind, text, meaning, attempts, hits, misses, streak, '
      'last_at, due_at, last_article_id, last_mode, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        key,
        asText(rec['itemId']),
        kind,
        body,
        asText(rec['meaning']) ?? '',
        asNum(rec['attempts']),
        asNum(rec['hits']),
        asNum(rec['misses']),
        asNum(rec['streak']),
        lastAt,
        asText(rec['dueAt']) ?? lastAt,
        asText(rec['lastArticleId']),
        asText(rec['lastMode']),
        asText(rec['updatedAt']) ?? lastAt,
      ],
    );
  }
  // 这份快照就是工棚的全部进度：不在里面的 key 视为已删。
  if (keys.isEmpty) {
    await db.rawDelete('DELETE FROM production_progress');
    return;
  }
  final marks = List<String>.filled(keys.length, '?').join(', ');
  await db.rawDelete('DELETE FROM production_progress WHERE key NOT IN ($marks)', keys);
}

Map<String, Object?> _asMap(Map raw) => <String, Object?>{
      for (final e in raw.entries) '${e.key}': e.value,
    };
