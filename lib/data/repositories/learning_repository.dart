/// 学习记录仓储：16 段学习记录、快照、派生统计的唯一读写入口。
///
/// 与 Web 版对照：
///  - 读：`server/sqliteLearning.ts` 的 `loadLearning` → `db/learning_read.dart`；
///  - 写：`sqliteLearningWrite.ts` 的 `writeSections` → `db/learning_write.dart`；
///  - 快照 / 恢复 / 派生重建：`snapshotLearning` / `restoreLearningSnapshot` /
///    `rebuildLearningDerived` → 就在本文件（它们要跨段读写，放仓储这一层才顺）。
///
/// 一条硬语义：**答题事件、回译存档、金句进度、错因状态、工棚进度永不清表**。
/// 它们是「做过的痕迹」，整份保存或恢复旧快照时清掉就等于抹掉历史。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import '../../core/answer_events.dart';
import '../../core/learning.dart';
import '../../core/practice.dart';
import '../db/learning_json.dart';
import '../db/learning_read.dart';
import '../db/learning_write.dart';
import '../db/migrations.dart';
import '../db/sql_util.dart';

/// 正常保存最多 10 分钟拍一张；留 12 版 ≈ 最近两小时。
const int learningSnapshotMinIntervalMs = 10 * 60 * 1000;

/// 快照保留张数。
const int learningSnapshotKeep = 12;

/// 快照元信息（正文按需取，列表页只显示时间与体积）。
class LearningSnapshotRef {
  const LearningSnapshotRef({required this.at, required this.reason, required this.bytes});

  final String at;
  final String reason;
  final int bytes;
}

/// 派生统计的起点（迁移时把历史聚合存成 baseline）。
class DerivedBaseline {
  const DerivedBaseline({
    required this.activity,
    required this.kindStats,
    required this.at,
  });

  /// 活动聚合（原样保留，无法从事件重算）。
  final Object? activity;

  /// `文章 → 题型 → 累计`（事件出现之前的历史量）。
  final Object? kindStats;

  /// 存 baseline 的时刻；没有 baseline 时为 null。
  final String? at;
}

/// 学习记录读写。
class LearningRepository {
  LearningRepository(this._db);

  /// 打开仓储：先确保 schema 迁到当前版本。
  static Future<LearningRepository> open(DatabaseExecutor db) async {
    await ensureSchema(db);
    return LearningRepository(db);
  }

  final DatabaseExecutor _db;

  final GZipCodec _gzip = GZipCodec(level: 6);

  Future<T> _tx<T>(Future<T> Function(DatabaseExecutor t) fn) async {
    final db = _db;
    if (db is Database) return db.transaction<T>((t) => fn(t));
    return fn(db);
  }

  /// 读一份完整学习记录。
  Future<LearningData> load() => loadLearning(_db);

  /// 是否有任何一行学习记录。
  Future<bool> hasRows() => hasLearningRows(_db);

  /// 写指定段（[sections] 为空时什么都不做 —— 语义是「这几个段」，不是「全部」）。
  Future<void> write(LearningData data, List<LearningSection> sections) =>
      _tx((t) async {
        await writeSections(t, learningToJson(data), sections);
      });

  /// 整份覆盖写入（16 段全写）。
  Future<void> writeAll(LearningData data) => write(data, LearningSection.values);

  /// 只写一个段（增量保存时用；长期资产段同样是 upsert 语义）。
  Future<void> writeSection(LearningData data, LearningSection section) =>
      write(data, <LearningSection>[section]);

  /// 给当前学习记录拍一张快照，返回快照的 `at`；跳过时返回 null。
  ///
  /// - [minIntervalMs] > 0：离上一张不够久就跳过（正常保存走 10 分钟节流）；
  /// - 内容和上一张完全一样也跳过（dedupe）；
  /// - 一条学习记录都没有时不拍（空快照恢复回去等于什么都没变）。
  ///
  /// 只做**逻辑回滚**，不是异盘备份：磁盘坏了要靠「导出全部」。
  Future<String?> snapshot(
    String reason, {
    int minIntervalMs = 0,
  }) async {
    if (!await hasLearningRows(_db)) return null;

    final lastRows = await _db.rawQuery(
      'SELECT at, payload FROM learning_snapshots ORDER BY at DESC LIMIT 1',
    );
    if (lastRows.isNotEmpty && minIntervalMs > 0) {
      final lastAt = DateTime.tryParse(asText(lastRows.first['at']) ?? '');
      if (lastAt != null) {
        final elapsed = DateTime.now().difference(lastAt).inMilliseconds;
        // elapsed < 0：库里有个未来时间（改过系统时钟），别因此永久挡住快照。
        if (elapsed >= 0 && elapsed < minIntervalMs) return null;
      }
    }

    final json = jsonEncode(learningToJson(await load()));
    if (lastRows.isNotEmpty && _unpackOrNull(lastRows.first['payload']) == json) {
      return null;
    }

    final bytes = Uint8List.fromList(_gzip.encode(utf8.encode(json)));
    return _tx((t) async {
      final at = await _nextSnapshotAt(t);
      await t.rawInsert(
        'INSERT INTO learning_snapshots (at, reason, payload, bytes) VALUES (?, ?, ?, ?)',
        [at, reason, bytes, bytes.length],
      );
      await t.rawDelete(
        'DELETE FROM learning_snapshots WHERE at NOT IN '
        '(SELECT at FROM learning_snapshots ORDER BY at DESC LIMIT ?)',
        [learningSnapshotKeep],
      );
      return at;
    });
  }

  /// 快照列表（新的在前）。
  Future<List<LearningSnapshotRef>> listSnapshots() async {
    final rows = await _db.rawQuery(
      'SELECT at, reason, bytes FROM learning_snapshots ORDER BY at DESC',
    );
    return <LearningSnapshotRef>[
      for (final r in rows)
        LearningSnapshotRef(
          at: asText(r['at']) ?? '',
          reason: asText(r['reason']) ?? '',
          bytes: asNum(r['bytes']).toInt(),
        ),
    ];
  }

  /// 恢复一张快照。
  ///
  /// 恢复前先给当前状态拍一张（`before-restore`），恢复错了还能回来；
  /// **答题事件按 append-only 语义取「旧快照 ∪ 当前」**，不丢新事件。
  /// 快照不存在返回 false；快照损坏抛 [FormatException]（明确报错，不静默变空库）。
  Future<bool> restore(String at) async {
    final rows = await _db.rawQuery(
      'SELECT payload FROM learning_snapshots WHERE at = ?',
      [at],
    );
    if (rows.isEmpty) return false;
    final json = _unpackOrNull(rows.first['payload']);
    if (json == null) {
      throw const FormatException('学习快照已损坏，无法恢复');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } catch (_) {
      throw const FormatException('学习快照已损坏，无法恢复');
    }
    if (decoded is! Map) {
      throw const FormatException('学习快照已损坏，无法恢复');
    }
    final old = normalizeLearning(decoded);

    await snapshot('before-restore');
    final current = await load();
    // 恢复 = 用快照覆盖当前（快照里没有的段保持不动，等价于 Web 版 `{...current, ...data}`）。
    final restored = _restoreOnto(decoded, current: current, snapshot: old);
    await writeAll(restored);
    return true;
  }

  /// 把「历史聚合」存成 baseline（迁移时调用一次）。
  ///
  /// 历史数据没有逐题事件，不能假装能重算；baseline 代表「事件出现之前的总量」。
  Future<String> saveDerivedBaseline({String? at}) async {
    final value = await load();
    final payload = jsonEncode(<String, Object?>{
      'activity': learningSectionJson(value, LearningSection.activity),
      'kindStats': learningSectionJson(value, LearningSection.kindStats),
    });
    final stamp = at ?? nowIso();
    await _db.rawInsert(
      'INSERT OR REPLACE INTO learning_derived_baseline (id, payload, at) VALUES (1, ?, ?)',
      [payload, stamp],
    );
    return payload;
  }

  /// 读 baseline；没有就返回空。
  Future<DerivedBaseline> loadDerivedBaseline() async {
    final rows = await _db.rawQuery(
      'SELECT payload, at FROM learning_derived_baseline WHERE id = 1',
    );
    if (rows.isEmpty) {
      return const DerivedBaseline(activity: null, kindStats: null, at: null);
    }
    Object? parsed;
    final json = asText(rows.first['payload']);
    if (json != null && json.isNotEmpty) {
      try {
        parsed = jsonDecode(json);
      } catch (_) {
        parsed = null;
      }
    }
    final rec = parsed is Map ? parsed : const <String, Object?>{};
    return DerivedBaseline(
      activity: rec['activity'],
      kindStats: rec['kindStats'],
      at: asText(rows.first['at']),
    );
  }

  /// 重建 `kind_stats`：baseline + 有 `source == quiz` 的答题事件。
  ///
  /// `activity_days` 是聚合值（背词 / 快刷 / 阅读 / 写作 / 跟读只写聚合、不产生事件），
  /// 无法从事件可信重算，所以**原样保留**。不碰其它学习记录。
  /// 返回重建后的活动聚合，便于测试与排查。
  Future<List<Object?>> rebuildDerived() async {
    final base = await loadDerivedBaseline();
    final events = (await load()).answerEvents;

    final stats = <String, Map<String, List<int>>>{};
    void add(String articleId, String kind, bool correct) {
      if (articleId.isEmpty || kind.isEmpty) return;
      final byKind = stats.putIfAbsent(articleId, () => <String, List<int>>{});
      final cur = byKind.putIfAbsent(kind, () => <int>[0, 0]);
      cur[0] += 1;
      if (correct) cur[1] += 1;
    }

    // baseline 先铺底，再叠事件 —— 事件是增量，baseline 是「事件之前」。
    final baseStats = base.kindStats;
    if (baseStats is Map) {
      for (final article in baseStats.entries) {
        final byKind = article.value;
        if (byKind is! Map) continue;
        for (final kind in byKind.entries) {
          final stat = kind.value;
          if (stat is! Map) continue;
          final articleId = '${article.key}';
          final kindName = '${kind.key}';
          if (articleId.isEmpty || kindName.isEmpty) continue;
          stats.putIfAbsent(articleId, () => <String, List<int>>{})[kindName] =
              <int>[asNum(stat['total']).toInt(), asNum(stat['correct']).toInt()];
        }
      }
    }
    for (final ev in events) {
      if (ev.source != PracticeKind.quiz) continue;
      add(ev.articleId, ev.kind, ev.correct);
    }

    await _tx((t) async {
      await t.rawDelete('DELETE FROM kind_stats');
      for (final article in stats.entries) {
        for (final kind in article.value.entries) {
          await t.rawInsert(
            'INSERT OR REPLACE INTO kind_stats (article_id, kind, total, correct) '
            'VALUES (?, ?, ?, ?)',
            [article.key, kind.key, kind.value[0], kind.value[1]],
          );
        }
      }
    });

    final activity = base.activity;
    return activity is List ? activity : const <Object?>[];
  }

  /// 清空所有学习记录（长期资产段也一起清 —— 这是「删库」语义，不是「覆盖保存」）。
  Future<void> clearAll() async {
    await _tx((t) async {
      for (final table in const <String>[
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
      ]) {
        await t.rawDelete('DELETE FROM $table');
      }
    });
  }

  /// 把 WAL 并回主库并截断。关库前 / 导出前调用。
  Future<void> checkpoint() async {
    try {
      await _db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {
      // 还有别的连接在读时会被拒：不影响已提交的数据，下次再收。
    }
  }

  String? _unpackOrNull(Object? value) {
    try {
      if (value is String) return value;
      if (value is Uint8List) return utf8.decode(_gzip.decode(value));
      if (value is List<int>) return utf8.decode(_gzip.decode(value));
      final s = value?.toString();
      return s == null || s.isEmpty ? null : s;
    } catch (_) {
      return null;
    }
  }

  /// 答题事件 append-only：旧快照 ∪ 当前，按「时间 + 题号 + 题型 + 对错」去重。
  LearningData _mergeAnswerEvents(LearningData current, LearningData old) {
    String keyOf(AnswerEvent e) =>
        '${e.at}|${e.questionId ?? ''}|${e.kind}|${e.correct ? 1 : 0}';
    final seen = <String>{};
    final merged = <AnswerEvent>[];
    for (final e in <AnswerEvent>[...old.answerEvents, ...current.answerEvents]) {
      if (seen.add(keyOf(e))) merged.add(e);
    }
    merged.sort((a, b) => a.at.compareTo(b.at));
    return LearningData(
      practice: current.practice,
      mistakes: current.mistakes,
      readDone: current.readDone,
      writingHistory: current.writingHistory,
      backTranslations: current.backTranslations,
      retells: current.retells,
      activity: current.activity,
      studyDays: current.studyDays,
      sessions: current.sessions,
      studiedDays: current.studiedDays,
      skimmed: current.skimmed,
      kindStats: current.kindStats,
      answerEvents: merged,
      goldenDrills: current.goldenDrills,
      writingErrorProgress: current.writingErrorProgress,
      productionProgress: current.productionProgress,
    );
  }

  /// 快照覆盖当前：**快照里有的段覆盖当前，没有的段保持不动**。
  ///
  /// 等价于 Web 版 `restoreLearningSnapshot` 里的 `{...current, ...data}`；
  /// 答题事件例外——它是 append-only 的「做过的痕迹」，取「快照 ∪ 当前」。
  LearningData _restoreOnto(
    Map snapshotRaw, {
    required LearningData current,
    required LearningData snapshot,
  }) {
    final combined = <String, Object?>{...learningToJson(current)};
    for (final key in LearningSection.values) {
      final raw = snapshotRaw[key.name];
      if (raw == null) continue;
      combined[key.name] = raw;
    }
    final merged = _mergeAnswerEvents(current, snapshot);
    combined[LearningSection.answerEvents.name] =
        learningSectionJson(merged, LearningSection.answerEvents);
    return normalizeLearning(combined);
  }

  /// 同一毫秒内连续拍快照时主键也不能撞。
  Future<String> _nextSnapshotAt(DatabaseExecutor db) async {
    var at = nowIso();
    for (var i = 0; i < 100; i++) {
      final hit = await db.rawQuery(
        'SELECT 1 FROM learning_snapshots WHERE at = ?',
        [at],
      );
      if (hit.isEmpty) return at;
      final ms = DateTime.tryParse(at)?.millisecondsSinceEpoch;
      if (ms == null) break;
      at = DateTime.fromMillisecondsSinceEpoch(ms + 1, isUtc: true)
          .toIso8601String();
    }
    return '$at:${DateTime.now().microsecondsSinceEpoch}';
  }
}
