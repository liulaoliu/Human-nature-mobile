/// 词库仓储：SQLite 里那份「唯一的词库」怎么读写。
///
/// 事实来源始终是 `vocab.payload` 里的一段 JSON；`words` / `word_*` 那些派生表
/// 只服务于查询，写完主表就顺手重建（`projections.dart`）。
///
/// 与 Web 版 `server/sqliteStore.ts` 的 `loadVocab` / `saveVocab` / `migrateVocab`
/// 一一对应，但有三处**故意不同**：
///  1. **落盘前一定先 `compactSentenceTexts`**：Web 版把它放在 adapter 层
///     （`src/adapters/vocabRepo.ts:199`），Dart 侧本地存储只有一个入口，
///     放仓储里才不会有人绕过去写出「一句原文重复存几十份」的胖库；
///  2. **读出来一律过 `migrateLibrary`**：它负责补默认值、丢坏条目、
///     把共享句子原文补回各引用（即 Web 的 `hydrateSentenceTexts`）；
///  3. **gzip 用 `dart:io`**：服务端用 `zlib`，这里用 `GZipCodec`，压缩后的
///     BLOB 互不兼容 —— 但两边都不需要互相读对方的库，只要求**自己读自己**，
///     且读路径同时兼容老版本遗留的明文 TEXT。
///
/// 大小：本机实测整库 JSON 4.8MB → gzip 约 1.5MB，压一次 ~280ms；
/// 所以「内容没变」的快路径（比对明文）一定要留着，否则自动补全 effect 重跑
/// 一次就白压一次。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import '../../core/migrations.dart';
import '../../core/vocab/sentence_texts.dart';
import '../../core/vocab/vocab_json.dart';
import '../../models/vocab.dart';
import '../db/migrations.dart';
import '../db/projections.dart';
import '../db/sql_util.dart';

/// 历史快照保留张数（对应 Web 版 `SNAPSHOT_KEEP`）。
const int vocabSnapshotKeep = 12;

/// 乐观锁冲突：客户端读到的是 [updatedAt] 那一版，但库里已经更新了。
///
/// 单独一个类型是为了让 UI 能区分「保存失败」和「别人先改了」——
/// 后者要提示用户先刷新，而不是让他重试。
class VocabConflict implements Exception {
  const VocabConflict({required this.updatedAt, required this.count});

  /// 库里当前的版本号。
  final String updatedAt;

  /// 库里当前的条数（提示里给用户看）。
  final int count;

  @override
  String toString() => '词库已被更新（$updatedAt，$count 条），请先刷新再改';
}

/// 刚读到的那一版词库。
class LoadedVocab {
  const LoadedVocab({required this.json, required this.updatedAt, required this.count});

  /// 原始 JSON 文本（不做二次序列化；`GET /vocab` 那类场景直接发）。
  final String json;
  final String updatedAt;
  final int count;
}

/// 保存结果。
class SavedVocab {
  const SavedVocab({
    required this.updatedAt,
    required this.count,
    required this.changed,
  });

  final String updatedAt;
  final int count;

  /// false = 内容没变，什么都没写（调用方可以据此跳过「保存成功」提示）。
  final bool changed;
}

/// 快照条目（只列元信息，正文按需取）。
class VocabSnapshotRef {
  const VocabSnapshotRef({required this.at, required this.count});

  final String at;
  final int count;
}

/// 词库读写。
class VocabRepository {
  VocabRepository(this._db);

  /// 打开仓储：先确保 schema 迁到当前版本。
  static Future<VocabRepository> open(DatabaseExecutor db) async {
    await ensureSchema(db);
    return VocabRepository(db);
  }

  final DatabaseExecutor _db;

  final GZipCodec _gzip = GZipCodec(level: 6);

  Future<T> _tx<T>(Future<T> Function(DatabaseExecutor t) fn) async {
    final db = _db;
    if (db is Database) return db.transaction<T>((t) => fn(t));
    return fn(db);
  }

  Uint8List _pack(String json) =>
      Uint8List.fromList(_gzip.encode(utf8.encode(json)));

  /// 老数据可能是明文 TEXT，新写入是 gzip BLOB —— 两条都要认。
  String _unpack(Object? value) {
    if (value is String) return value;
    if (value is Uint8List) return utf8.decode(_gzip.decode(value));
    if (value is List<int>) return utf8.decode(_gzip.decode(value));
    return value?.toString() ?? '';
  }

  /// 词库的原始 JSON 与版本号；没有词库返回 null。
  Future<LoadedVocab?> loadJson() async {
    final rows = await _db.rawQuery(
      'SELECT payload, item_count, updated_at FROM vocab WHERE id = 1',
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return LoadedVocab(
      json: _unpack(row['payload']),
      updatedAt: asText(row['updated_at']) ?? '',
      count: asNum(row['item_count']).toInt(),
    );
  }

  /// 读出词库并迁移到当前结构；没有则返回 null（**不是空库**）。
  ///
  /// 返回 null 与「空库」语义不同：null 表示这台设备第一次用，
  /// 调用方据此决定要不要从备份/服务端灌一份进来。
  Future<VocabLibrary?> load() async {
    final loaded = await loadJson();
    if (loaded == null) return null;
    final decoded = parsePayload(loaded.json);
    if (decoded == null) return null;
    return migrateLibrary(decoded);
  }

  /// 版本号与条数（乐观锁的令牌）。
  Future<VocabSnapshotRef?> meta() async {
    final rows = await _db.rawQuery(
      'SELECT item_count, updated_at FROM vocab WHERE id = 1',
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return VocabSnapshotRef(
      at: asText(row['updated_at']) ?? '',
      count: asNum(row['item_count']).toInt(),
    );
  }

  /// 历史快照列表（新的在前）。
  Future<List<VocabSnapshotRef>> listSnapshots() async {
    final rows = await _db.rawQuery(
      'SELECT at, item_count FROM vocab_snapshots ORDER BY at DESC',
    );
    return [
      for (final row in rows)
        VocabSnapshotRef(
          at: asText(row['at']) ?? '',
          count: asNum(row['item_count']).toInt(),
        ),
    ];
  }

  /// 读某一版快照。
  Future<VocabLibrary?> loadSnapshot(String at) async {
    final rows = await _db.rawQuery(
      'SELECT payload FROM vocab_snapshots WHERE at = ?',
      [at],
    );
    if (rows.isEmpty) return null;
    final decoded = parsePayload(_unpack(rows.first['payload']));
    if (decoded == null) return null;
    return migrateLibrary(decoded);
  }

  /// 保存词库。
  ///
  /// [baseUpdatedAt] 是调用方**读到的那一版**：传了就必须和库里当前版本一致，
  /// 否则抛 [VocabConflict]（不传 = 强制写，留给迁移/工具）。
  ///
  /// 步骤与 Web 版一致：事务外判冲突 → 事务外判「内容没变」→ 事务外压 gzip →
  /// 事务内重读一次再判冲突 → 写主表 + 快照 + 重建派生表。
  Future<SavedVocab> save(VocabLibrary library, {String? baseUpdatedAt}) async {
    final compacted = compactSentenceTexts(library);
    final payload = encodeVocabLibrary(compacted);
    final count = compacted.items.length;
    final base = baseUpdatedAt ?? '';

    final prevRow = await _selectPrev();
    if (base.isNotEmpty && prevRow != null && prevRow.updatedAt != base) {
      throw VocabConflict(updatedAt: prevRow.updatedAt, count: prevRow.count);
    }
    if (prevRow != null && prevRow.json == payload) {
      return SavedVocab(
        updatedAt: prevRow.updatedAt,
        count: prevRow.count,
        changed: false,
      );
    }

    final packed = _pack(payload);
    // 上一版解析一次，事务里交给投影做增量：没变的词条保住 rowid，
    // 不然后台保存一次就把整张 words 表重写一遍（几万行）。
    final prevLib = prevRow?.json == null ? null : parsePayload(prevRow!.json);
    return _tx((t) async {
      final prev = await _selectPrev(t);
      if (base.isNotEmpty && prev != null && prev.updatedAt != base) {
        throw VocabConflict(updatedAt: prev.updatedAt, count: prev.count);
      }
      final at = await _nextUpdatedAt(t);
      await t.rawInsert(
        'INSERT OR REPLACE INTO vocab (id, payload, item_count, updated_at) '
        'VALUES (1, ?, ?, ?)',
        [packed, count, at],
      );
      // 快照复用同一份压缩结果：一次保存只付一次 gzip 的代价。
      await t.rawInsert(
        'INSERT OR REPLACE INTO vocab_snapshots (at, payload, item_count) '
        'VALUES (?, ?, ?)',
        [await _nextSnapshotAt(t), packed, count],
      );
      await _pruneSnapshots(t);
      // 投影吃的是**落盘那份形状**（已 compact），不是内存里的库对象：
      // 内存对象里的 sentenceText 已补回，跟库里不一致，增量比对会误判「全变了」。
      await rebuildVocabProjection(
        t,
        vocabLibraryToJson(compacted),
        prevLib: prevLib,
      );
      return SavedVocab(updatedAt: at, count: count, changed: true);
    });
  }

  /// 首次从备份/浏览器迁上来时用：**只有库里还没有词库才写**。
  ///
  /// 放在一个写事务里检查，两个入口同时迁移也不会互相覆盖。
  Future<({bool migrated, VocabLibrary value})> migrate(
    VocabLibrary library, {
    DateTime? now,
  }) async {
    final compacted = compactSentenceTexts(library);
    final payload = encodeVocabLibrary(compacted);
    final count = compacted.items.length;
    final at = (now ?? DateTime.now()).toUtc().toIso8601String();
    final packed = _pack(payload);

    return _tx((t) async {
      final existing = await t.rawQuery('SELECT payload FROM vocab WHERE id = 1');
      if (existing.isNotEmpty) {
        final decoded = parsePayload(_unpack(existing.first['payload']));
        return (migrated: false, value: migrateLibrary(decoded));
      }
      await t.rawInsert(
        'INSERT INTO vocab (id, payload, item_count, updated_at) VALUES (1, ?, ?, ?)',
        [packed, count, at],
      );
      await t.rawInsert(
        'INSERT OR REPLACE INTO vocab_snapshots (at, payload, item_count) '
        'VALUES (?, ?, ?)',
        [await _nextSnapshotAt(t), packed, count],
      );
      await rebuildVocabProjection(t, vocabLibraryToJson(compacted));
      return (migrated: true, value: compacted);
    });
  }

  /// 清空词库（派生表一起清）。
  Future<void> clear() async {
    await _tx((t) async {
      await t.rawDelete('DELETE FROM vocab WHERE id = 1');
      await rebuildVocabProjection(t, null);
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

  Future<({String updatedAt, int count, String? json})?> _selectPrev([
    DatabaseExecutor? db,
  ]) async {
    final rows = await (db ?? _db).rawQuery(
      'SELECT payload, item_count, updated_at FROM vocab WHERE id = 1',
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    String? json;
    try {
      json = _unpack(row['payload']);
    } catch (_) {
      // 旧 payload 坏了：当作「没有上一版」，别让脏数据挡住这次保存。
      json = null;
    }
    return (
      updatedAt: asText(row['updated_at']) ?? '',
      count: asNum(row['item_count']).toInt(),
      json: json,
    );
  }

  /// 版本号必须严格递增：乐观锁拿它当令牌，同一毫秒连存两次会得到相同令牌，
  /// 旧客户端就能蒙混过关。宁可变慢 1ms。
  Future<String> _nextUpdatedAt(DatabaseExecutor db) async {
    final rows = await db.rawQuery('SELECT updated_at FROM vocab WHERE id = 1');
    final prevAt = rows.isEmpty ? '' : (asText(rows.first['updated_at']) ?? '');
    final now = nowIso();
    if (prevAt.isEmpty) return now;
    if (now.compareTo(prevAt) > 0) return now;
    final prevMs = DateTime.tryParse(prevAt)?.millisecondsSinceEpoch;
    if (prevMs == null) return now;
    return DateTime.fromMillisecondsSinceEpoch(prevMs + 1, isUtc: true)
        .toIso8601String();
  }

  /// 同一毫秒内连续保存时快照主键也要唯一，否则会覆盖上一版。
  Future<String> _nextSnapshotAt(DatabaseExecutor db) async {
    var at = nowIso();
    for (var i = 0; i < 100; i++) {
      final hit = await db.rawQuery(
        'SELECT 1 FROM vocab_snapshots WHERE at = ?',
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

  Future<void> _pruneSnapshots(DatabaseExecutor db) async {
    await db.rawDelete(
      'DELETE FROM vocab_snapshots WHERE at NOT IN '
      '(SELECT at FROM vocab_snapshots ORDER BY at DESC LIMIT ?)',
      [vocabSnapshotKeep],
    );
  }
}
