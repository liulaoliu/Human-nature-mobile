/// schema 迁移链（对应 Web 版 `server/sqliteStore.ts` 的 `ensureSchema`）。
///
/// 用 `PRAGMA user_version` 记版本；**迁移只增不删**，旧库能直接打开。
/// 每一步都带着数据回填：v1 老库要补 `articles` 的查询列、v2 重建派生投影、
/// v7 要同时建 V8/V9/V11/V13 并写派生基线。老用户的备份要能直接导入，
/// 所以这 13 步一步都不能跳、也不能换顺序。
library;

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../core/learning.dart';
import 'projections.dart';
import 'schema.dart';
import 'sql_util.dart';

export 'schema.dart' show schemaVersion;

/// 在 [BEGIN IMMEDIATE] 事务里跑 [fn]；抛错就 ROLLBACK 后原样重抛。
///
/// sqflite 的 `transaction` 已经是 IMMEDIATE 语义（单写者），这里只是把
/// 「出错一定会回滚」这件事写死，别让调用方忘记。
Future<T> tx<T>(Database db, Future<T> Function() fn) async =>
    db.transaction<T>((t) => fn());

/// `articles` 补查询列。幂等：列已存在就跳过。
Future<void> addArticleColumns(DatabaseExecutor db) async {
  final cols = <String>{
    for (final r in await db.rawQuery('PRAGMA table_info(articles)')) asText(r['name']) ?? '',
  };
  Future<void> add(String name, String ddl) async {
    if (!cols.contains(name)) {
      await db.execute('ALTER TABLE articles ADD COLUMN $ddl');
    }
  }

  await add('book', 'book TEXT');
  await add('source_key', 'source_key TEXT');
  await add('created_at', 'created_at TEXT');
  await add('sentence_count', 'sentence_count INTEGER NOT NULL DEFAULT 0');
  await add('word_count', 'word_count INTEGER NOT NULL DEFAULT 0');
}

/// v10：`writing_records` 补 `source` / `sentence_id` / `exam_id`。
///
/// 必须在 v7 baseline 之前补：迁移过程会读 `writing_records`，
/// 等到 v10 才 ALTER 就会 `no such column: source`（2026-10-29 踩过）。幂等。
Future<void> addWritingColumns(DatabaseExecutor db) async {
  final exists = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'writing_records'",
  );
  if (exists.isEmpty) return;
  final cols = <String>{
    for (final r in await db.rawQuery('PRAGMA table_info(writing_records)')) asText(r['name']) ?? '',
  };
  Future<void> add(String name, String ddl) async {
    if (!cols.contains(name)) {
      await db.execute('ALTER TABLE writing_records ADD COLUMN $ddl');
    }
  }

  await add('source', 'source TEXT');
  await add('sentence_id', 'sentence_id TEXT');
  await add('exam_id', 'exam_id TEXT');
}

/// 从 JSON payload 回填 `articles` 的查询列；只在迁移时做一次。
///
/// `created_at` 回退顺序是 `createdAt → updatedAt → now`：老文章两者都可能没有。
Future<void> backfillArticleColumns(DatabaseExecutor db) async {
  final rows = await db.rawQuery('SELECT id, payload FROM articles');
  for (final row in rows) {
    final a = asRecord(parsePayload(row['payload'])) ?? const <String, Object?>{};
    final sentences = asList<Object?>(a['sentences']);
    final words = <String>{};
    for (final s in sentences) {
      for (final w in asList<Object?>(asRecord(s)?['vocab'])) {
        words.add(asText(w) ?? '');
      }
    }
    await db.rawUpdate(
      'UPDATE articles SET title = ?, book = ?, source_key = ?, created_at = ?, '
      'sentence_count = ?, word_count = ? WHERE id = ?',
      <Object?>[
        asText(a['title']) ?? '',
        asText(a['book']),
        asText(a['sourceKey']),
        asText(a['createdAt']) ?? asText(a['updatedAt']) ?? nowIso(),
        sentences.length,
        words.length,
        asText(row['id']),
      ],
    );
  }
}

/// v5 的 `learning_snapshots` 是 `id` 主键 + `record_count` + 明文 payload；
/// v12 换成了 `at` 主键 + `bytes` + BLOB。老表不能靠 `CREATE TABLE IF NOT EXISTS`
/// 混过去，否则第一次拍快照就会 `no such column: bytes`。
/// 这里把老表改名归档（不删数据），再让 v12 建新表。
Future<void> archiveLegacyLearningSnapshots(DatabaseExecutor db) async {
  final exists = await db.rawQuery(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'learning_snapshots'",
  );
  if (exists.isEmpty) return;
  final cols = <String>{
    for (final r in await db.rawQuery('PRAGMA table_info(learning_snapshots)'))
      asText(r['name']) ?? '',
  };
  if (cols.contains('bytes')) return;
  final archived = await db.rawQuery(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'learning_snapshots_v5'",
  );
  if (archived.isNotEmpty) {
    await db.execute('DROP TABLE learning_snapshots');
  } else {
    await db.execute('ALTER TABLE learning_snapshots RENAME TO learning_snapshots_v5');
  }
}

/// 迁移 v7 时把「历史聚合」存成 baseline。
///
/// 历史数据没有逐题事件，不能假装能重算；baseline 代表「事件出现之前的总量」，
/// 以后用 baseline + answer_events 重建，口径才诚实。
Future<String> saveDerivedBaseline(DatabaseExecutor db, [String? at]) async {
  final activity = <Map<String, Object?>>[];
  final byDay = <String, Map<String, Object?>>{};
  for (final r in await db.rawQuery('SELECT day, cat, count FROM activity_days ORDER BY day ASC, cat ASC')) {
    final day = asText(r['day']) ?? '';
    final row = byDay.putIfAbsent(day, () {
      final created = <String, Object?>{'day': day, 'counts': <String, Object?>{}};
      activity.add(created);
      return created;
    });
    (row['counts']! as Map<String, Object?>)[asText(r['cat']) ?? ''] = asNum(r['count']);
  }

  final kindStats = <String, Object?>{};
  for (final r in await db.rawQuery(
    'SELECT article_id, kind, total, correct FROM kind_stats ORDER BY article_id ASC, kind ASC',
  )) {
    final articleId = asText(r['article_id']) ?? '';
    final byKind = kindStats.putIfAbsent(articleId, () => <String, Object?>{})! as Map<String, Object?>;
    byKind[asText(r['kind']) ?? ''] = <String, Object?>{
      'total': asNum(r['total']),
      'correct': asNum(r['correct']),
    };
  }

  final payload = jsonEncode(<String, Object?>{'activity': activity, 'kindStats': kindStats});
  await db.rawInsert(
    'INSERT OR REPLACE INTO learning_derived_baseline (id, payload, at) VALUES (1, ?, ?)',
    <Object?>[payload, at ?? nowIso()],
  );
  return payload;
}

/// 打开库后调用：把库迁到 [schemaVersion]，返回最终版本号。
///
/// 版本比程序高时**必须抛错**，不能「凑合打开」—— 新版本的表结构老程序读不懂，
/// 硬开等于让写入把新数据弄坏。
Future<int> ensureSchema(DatabaseExecutor db) async {
  final rows = await db.rawQuery('PRAGMA user_version');
  var version = asNum(rows.isEmpty ? null : rows.first['user_version']).toInt();
  if (version > schemaVersion) {
    throw StateError('数据库版本 $version 高于当前程序支持的 $schemaVersion');
  }

  /// 跑一步：`Database` 上开事务，`t` 是事务内的 executor；
  /// 已经在事务里（`Transaction`）就直接用自己，不再嵌套。
  ///
  /// **闭包里必须用 `t`，不能用外层 `db`**：在事务进行中拿外层连接发语句，
  /// sqflite 会排队等事务结束，而事务又在等这条语句 —— 直接死锁（2026-11-08 踩过）。
  Future<void> step(Future<void> Function(DatabaseExecutor t) fn) async {
    if (db is Database) {
      await db.transaction((t) => fn(t));
    } else {
      await fn(db);
    }
  }

  if (version < 1) {
    await step((t) async {
      await _execAll(t, schemaV1);
      await t.execute('PRAGMA user_version = 1');
    });
    version = 1;
  }
  if (version < 2) {
    await step((t) async {
      await _execAll(t, schemaV2);
      await addArticleColumns(t);
      await backfillArticleColumns(t);
      await rebuildAllProjections(t);
      await t.execute('PRAGMA user_version = 2');
    });
    version = 2;
  }
  if (version < 3) {
    await step((t) async {
      await _execAll(t, schemaV3);
      await t.execute('PRAGMA user_version = 3');
    });
    version = 3;
  }
  // v10 的列要在 v7 baseline 之前就位（迁移会读 writing_records）。
  // 这一步不属于任何版本号，必须在 v4 之前跑，所以放在事务外（都是幂等 ALTER）。
  await addWritingColumns(db);
  if (version < 4) {
    await step((t) async {
      await normalizeLegacySourceIds(t);
      await t.execute('PRAGMA user_version = 4');
    });
    version = 4;
  }
  if (version < 5) {
    // v5（原学习记录快照）已退役：不建表，只把版本号推过去。
    await step((t) async {
      await t.execute('PRAGMA user_version = 5');
    });
    version = 5;
  }
  if (version < 6) {
    // v6（原文章上一版）已退役：不建表，只把版本号推过去。
    await step((t) async {
      await t.execute('PRAGMA user_version = 6');
    });
    version = 6;
  }
  if (version < 7) {
    await step((t) async {
      await _execAll(t, schemaV7);
      // v8 回译表 / v9 金句进度表 / v11 错因复习表要先建：baseline 会读整份学习记录。
      await _execAll(t, schemaV8);
      await _execAll(t, schemaV9);
      await _execAll(t, schemaV11);
      await _execAll(t, schemaV13);
      await saveDerivedBaseline(t);
      await t.execute('PRAGMA user_version = 7');
    });
    version = 7;
  }
  if (version < 8) {
    await step((t) async {
      await _execAll(t, schemaV8);
      await t.execute('PRAGMA user_version = 8');
    });
    version = 8;
  }
  if (version < 9) {
    await step((t) async {
      await _execAll(t, schemaV9);
      await t.execute('PRAGMA user_version = 9');
    });
    version = 9;
  }
  if (version < 10) {
    await step((t) async {
      await addWritingColumns(t);
      await t.execute('PRAGMA user_version = 10');
    });
    version = 10;
  }
  if (version < 11) {
    await step((t) async {
      await _execAll(t, schemaV11);
      await t.execute('PRAGMA user_version = 11');
    });
    version = 11;
  }
  if (version < 12) {
    await step((t) async {
      await archiveLegacyLearningSnapshots(t);
      await _execAll(t, schemaV12);
      await t.execute('PRAGMA user_version = 12');
    });
    version = 12;
  }
  if (version < 13) {
    await step((t) async {
      await _execAll(t, schemaV13);
      await t.execute('PRAGMA user_version = 13');
    });
    version = 13;
  }
  return version;
}

/// 把一段多语句 DDL 拆开逐条执行。
///
/// 空串（已退役版本的常量）直接跳过；sqflite 的 `execute` 不接受多语句。
Future<void> _execAll(DatabaseExecutor db, String ddl) async {
  if (ddl.trim().isEmpty) return;
  for (final stmt in _splitStatements(ddl)) {
    await db.execute(stmt);
  }
}

/// 按分号切 DDL，忽略空语句。DDL 里没有字符串字面量含分号，够用。
List<String> _splitStatements(String ddl) {
  final out = <String>[];
  final buf = StringBuffer();
  for (final line in ddl.split('\n')) {
    final t = line.trim();
    if (t.isEmpty || t.startsWith('--')) continue;
    buf.writeln(t);
  }
  for (final part in buf.toString().split(';')) {
    final s = part.trim();
    if (s.isNotEmpty) out.add(s);
  }
  return out;
}

/// 仅供编译期确认：learning.dart 的 section 表与 SQLite 表名一一对应，
/// 迁移时用不到但读代码的人要能对上。
const Map<LearningSection, String> learningSectionTables = <LearningSection, String>{
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
