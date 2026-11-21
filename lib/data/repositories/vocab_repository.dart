/// 词库仓储：SQLite 里那份「唯一的词库」怎么读写。
///
/// **v15 起事实来源是行级表**：每个词条一行 `vocab_items`，库级零碎
/// （`articleEntries` / `tombstones` / `sentenceTexts` / `schemaVersion`）走
/// `vocab_extras`（见 `db/vocab_rows_store.dart`）。`vocab.payload` 降级成
/// **导出缓存**：备份、`loadJson()`、老库兜底还读它，但它不再是一天改几十次的
/// 那条写路径 —— 以前评一张卡要重写整份 16.4MB（真机 1.2 秒/张），现在只写
/// 一行。
///
/// `words` / `word_*` 那些派生表（`projections.dart`）与事实来源无关，只服务
/// 查询，写完行表就跟着刷受影响的那几条。
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
/// 大小：本机实测整库 JSON 16.4MB → gzip 约 2.1MB（level 1，见 [_pack]），
/// 压一次 ~85ms；这条代价现在只在 [flushPayload] 与导出时付。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import '../../core/migrations.dart';
import '../../core/vocab/sentence_texts.dart';
import '../../core/vocab/vocab_rows.dart';
import '../../models/vocab.dart';
import '../db/migrations.dart';
import '../db/payload_codec.dart';
import '../db/projections.dart';
import '../db/sql_util.dart';
import '../db/vocab_rows_store.dart';

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

  /// gzip 用**最快档**（level 1），打包/解包/分块读都在 `payload_codec.dart`。
  ///
  /// 词库 JSON 真机数据 16.4MB：level 6 压 250ms 得 1.83MB，level 1 压 83ms 得
  /// 2.14MB。省下的 170ms 每次保存都要付，而多出来的 0.3MB 只落在本机 SQLite
  /// 里（一张主表 + 12 张快照 ≈ 27MB → 32MB），换过来很划算。
  /// 文章的 `_pack` 不走这里，那边是几十 KB 的小 JSON，压缩率更值钱。
  ///
  /// ⚠️ 2.14MB 正好**超过 Android `CursorWindow` 的 2MB 单行上限**，一次
  /// `SELECT payload` 会抛 `Row too big to fit into CursorWindow`（2026-11-15
  /// 用户报的「奶牛工棚等六处都报错」）。所以这里读 payload 一律走
  /// [readBigPayload] 分块取、自己拼，**不要再写 `SELECT payload`**。

  /// 上一次 `load()` 解析出来的词库。
  ///
  /// 一次读要「拼行 → jsonDecode → migrate」，本机实测约 0.9 秒（以前读整份
  /// payload 要 1.2–1.5 秒）。而每个页面的 `bootstrap()` 都会读一次，
  /// 用户看到的就是「点哪个按钮都卡一秒」。
  ///
  /// 按 `vocab.updated_at` 失效：版本号没变就直接把上次那份对象还回去（查版本号
  /// 只要 1ms）。写入路径（[save] / [migrate] / [clear]）成功后顺手更新缓存，
  /// 所以「存完再读」也不会白解析一次。
  VocabLibrary? _cached;

  /// 上一次读到的那批行。写路径拿它当 [nextVocabRows] 的 `prev`：
  /// 一万词的逐行 `identical` 比对是微秒级，比重新序列化整库便宜三个数量级。
  VocabRows? _cachedRows;

  String? _cachedAt;
  bool _hasCached = false;

  void _remember(VocabLibrary? library, String? at, {VocabRows? rows}) {
    _hasCached = true;
    _cached = library;
    _cachedRows = rows;
    _cachedAt = at;
  }

  Future<T> _tx<T>(Future<T> Function(DatabaseExecutor t) fn) async {
    final db = _db;
    if (db is Database) return db.transaction<T>((t) => fn(t));
    return fn(db);
  }

  Uint8List _pack(String json) => packPayloadJson(json);

  /// 老数据可能是明文 TEXT，新写入是 gzip BLOB —— 两条都要认。
  String _unpack(Object? value) => payloadJsonText(value) ?? '';

  /// 读一行 payload（**分块**，见 [readBigPayload]）。
  Future<Object?> _payloadOf(
    DatabaseExecutor db, {
    String table = 'vocab',
    String keyColumn = 'id',
    Object key = 1,
  }) => readBigPayload(db, table: table, keyColumn: keyColumn, key: key);

  /// 词库的原始 JSON 与版本号；没有词库返回 null。
  ///
  /// 行表可信就直接由行拼回（与导出共用 [encodeVocabRows]）；行表不可信
  /// （老库、拆行失败）才退回读 `vocab.payload`。
  Future<LoadedVocab?> loadJson() async {
    final ref = await meta();
    if (ref == null) return null;
    final rows = await readVocabRows(_db);
    if (rows != null) {
      return LoadedVocab(json: encodeVocabRows(rows), updatedAt: ref.at, count: ref.count);
    }
    final raw = await _payloadOf(_db);
    if (raw == null) return null;
    return LoadedVocab(json: _unpack(raw), updatedAt: ref.at, count: ref.count);
  }

  /// 读出词库并迁移到当前结构；没有则返回 null（**不是空库**）。
  ///
  /// 返回 null 与「空库」语义不同：null 表示这台设备第一次用，
  /// 调用方据此决定要不要从备份/服务端灌一份进来。
  ///
  /// **带内存缓存**：先只查版本号（`vocab.updated_at`，实测 1ms），跟上次解析
  /// 的那一版对得上就直接返回，**连行都不用读**。整库解析一次要 1 秒左右，
  /// 页面切换全靠这一层不卡。
  Future<VocabLibrary?> load() async {
    final ref = await meta();
    if (ref == null) {
      _remember(null, null);
      return null;
    }
    if (_hasCached && _cachedAt == ref.at) return _cached;
    final store = await readVocabRows(_db);
    if (store != null) {
      final decoded = parsePayload(encodeVocabRows(store));
      if (decoded == null) {
        _remember(null, null);
        return null;
      }
      final migrated = migrateLibrary(decoded);
      _remember(migrated, ref.at, rows: store);
      return migrated;
    }
    final text = await _payloadText();
    final decoded = parsePayload(text);
    if (decoded == null) {
      _remember(null, null);
      return null;
    }
    final migrated = migrateLibrary(decoded);
    _remember(migrated, ref.at);
    return migrated;
  }

  /// 把行表追平成 `vocab.payload` + 一条快照。
  ///
  /// 热路径（[save]）只写行表，`payload` 会停在最后一次追平的内容上；这里负责
  /// 补上，并写 [vocabSyncedAtKey] 记「行表对应哪一版」。调用点在用户看不见的
  /// 时刻（退到后台、离开背单词页、导出前）——一次 200ms 以上，不能压在主线程
  /// 的点击链上。
  ///
  /// **幂等**：同步戳已等于当前版本号就直接返回，重复调用不重复写。
  Future<void> flushPayload() async {
    final ref = await meta();
    if (ref == null) return;
    if (await readVocabSyncedAt(_db) == ref.at) return;
    final rows = _hasCached && _cachedAt == ref.at
        ? (_cachedRows ?? await readVocabRows(_db))
        : await readVocabRows(_db);
    if (rows == null) return;
    final packed = _pack(encodeVocabRows(rows));
    await _tx((t) async {
      final cur = await _selectPrevMeta(t);
      // 拼 payload 这两百毫秒里用户又评了几张：那版等下一次追。
      if (cur == null || cur.updatedAt != ref.at) return;
      await t.rawUpdate('UPDATE vocab SET payload = ? WHERE id = 1', <Object?>[packed]);
      await t.rawInsert(
        'INSERT OR REPLACE INTO vocab_snapshots (at, payload, item_count) VALUES (?, ?, ?)',
        <Object?>[await _nextSnapshotAt(t), packed, cur.count],
      );
      await _pruneSnapshots(t);
      await writeVocabSyncedAt(t, ref.at);
    });
  }

  /// 解出 `vocab.payload` 的明文 JSON（只有缓存没命中时才需要）。
  Future<String> _payloadText([DatabaseExecutor? db]) async {
    final raw = await _payloadOf(db ?? _db);
    if (raw == null) return '';
    return _unpack(raw);
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
      'SELECT at FROM vocab_snapshots WHERE at = ?',
      [at],
    );
    if (rows.isEmpty) return null;
    final raw = await _payloadOf(
      _db,
      table: 'vocab_snapshots',
      keyColumn: 'at',
      key: at,
    );
    if (raw == null) return null;
    final decoded = parsePayload(_unpack(raw));
    if (decoded == null) return null;
    return migrateLibrary(decoded);
  }

  /// 保存词库。
  ///
  /// [baseUpdatedAt] 是调用方**读到的那一版**：传了就必须和库里当前版本一致，
  /// 否则抛 [VocabConflict]（不传 = 强制写，留给迁移/工具）。
  ///
  /// **v15 起写的是行级事实**：只 `syncVocabRows` 变化的那几行 + 一条
  /// `UPDATE vocab SET item_count, updated_at`，投影也只补变化的那几条。
  /// `vocab.payload` 与快照**留到 [flushPayload] 再追** —— 以前每次评分都要
  /// 重编码 16.4MB JSON（500ms）+ gzip（160ms）+ 写 2.14MB BLOB（真机 1.2 秒/
  /// 张），现在整条写路径是「一行 UPDATE + 一条派生表写」的量级。
  ///
  /// 版本号（`updated_at`）仍然每次真写都严格递增：乐观锁、快照、同步戳全靠它。
  Future<SavedVocab> save(VocabLibrary library, {String? baseUpdatedAt}) async {
    final compacted = compactSentenceTexts(library);
    final count = compacted.items.length;
    final base = baseUpdatedAt ?? '';

    final prev = await _selectPrevMeta();
    if (base.isNotEmpty && prev != null && prev.updatedAt != base) {
      throw VocabConflict(updatedAt: prev.updatedAt, count: prev.count);
    }

    // 上一版的行与库（增量写要用）。缓存对得上就不查库。
    final hit = prev != null && _hasCached && _cachedAt == prev.updatedAt;
    final prevRows = hit
        ? _cachedRows
        : (prev == null ? null : await readVocabRows(_db));
    final prevLib = hit ? _cached : null;

    // 哪些下标的词条还是**同一个对象**：比的是调用方传进来的 [library]，不是
    // [compacted] —— compact 会给每个「句子原文被抽进共享表」的词条造新对象
    // （真机一万词里三千多条），拿 compact 后的比，一条都命不中。
    Set<int>? reuseIndexes;
    if (prevRows != null && prevLib != null) {
      reuseIndexes = <int>{};
      final before = prevLib.items;
      final after = library.items;
      final limit = count < before.length ? count : before.length;
      for (var i = 0; i < limit; i++) {
        if (i < after.length && identical(before[i], after[i])) reuseIndexes.add(i);
      }
    }

    final rows = nextVocabRows(
      compacted,
      prev: prevRows,
      prevSource: prevLib,
      reuseIndexes: reuseIndexes,
      // 库级三段（句子原文表 / 文章条目 / 墓碑）没换对象就原样沿用：
      // 13MB 的 `sentenceTexts` 重新编码一次要几十毫秒。
      reuseExtras:
          prevRows != null && prevLib != null && sameVocabExtras(prevLib, library),
    );

    if (prevRows != null && prev != null && vocabRowsUnchanged(prevRows, rows)) {
      // 内容一个字都没变：不写盘，版本号也不动（与 Web 版同语义）。
      _remember(library, prev.updatedAt, rows: rows);
      return SavedVocab(
        updatedAt: prev.updatedAt,
        count: prev.count,
        changed: false,
      );
    }

    return _tx((t) async {
      // 事务内只判冲突，不做任何序列化（那要几百毫秒，会卡住整个写）。
      final cur = await _selectPrevMeta(t);
      if (base.isNotEmpty && cur != null && cur.updatedAt != base) {
        throw VocabConflict(updatedAt: cur.updatedAt, count: cur.count);
      }
      final at = await _nextUpdatedAt(t);
      await syncVocabRows(t, rows, prev: prevRows);
      if (cur == null) {
        // 建库这一次：payload、同步戳、第一张快照一起写齐（反正 payload 已经
        // 压过了），之后就走增量，快照交给 [flushPayload] 按需追。
        final payload = encodeVocabRows(rows);
        final packed = _pack(payload);
        await t.rawInsert(
          'INSERT INTO vocab (id, payload, item_count, updated_at) VALUES (1, ?, ?, ?)',
          <Object?>[packed, count, at],
        );
        await t.rawInsert(
          'INSERT OR REPLACE INTO vocab_snapshots (at, payload, item_count) '
          'VALUES (?, ?, ?)',
          <Object?>[await _nextSnapshotAt(t), packed, count],
        );
        await writeVocabSyncedAt(t, at);
      } else {
        await t.rawUpdate(
          'UPDATE vocab SET item_count = ?, updated_at = ? WHERE id = 1',
          <Object?>[count, at],
        );
      }

      // 派生表（`words` / `word_*`）只服务查询：能定位到「哪几条变了」就只补
      // 那几条（单条 0.6ms），定位不到（条数变了、没有上一版行）才整表重建。
      if (cur == null || cur.count != count || reuseIndexes == null) {
        await rebuildVocabProjection(t, parsePayload(encodeVocabRows(rows)));
      } else {
        for (var i = 0; i < count; i++) {
          if (reuseIndexes.contains(i)) continue;
          await writeVocabItemProjection(t, jsonDecode(rows.itemDocs[i]), i);
        }
      }

      // 落盘的就是 [library]（compact 只改句子原文的存法，读回等价）：
      // 存完立刻缓存，页面切走再回来不用再解析一次。
      _remember(library, at, rows: rows);
      return SavedVocab(updatedAt: at, count: count, changed: true);
    });
  }

  /// 原子读改写：读最新一版 → 交给 [transform] 改 → 带锁写回；冲突就重读再改。
  ///
  /// 给「等了几秒才写库」的路径用（AI 跑批落库、备份导入、字典工具）。它们
  /// 原来是「先 load 一份快照 → 等网络/等解析 → 再 save」，中途用户在背单词
  /// 或精读页标了词，那份旧快照就把整库盖回去，而且因为没传版本号，连
  /// [VocabConflict] 都不会抛（33.3）。这里把「读 → 改 → 带上刚才读到的版本号
  /// 写」放进同一个重试环：别人抢先写过就重读一遍，[transform] 拿到的是最新
  /// 那份，改完再写。
  ///
  /// [transform] 必须是「基于 current 算出 next」的纯函数：它可能被调用多次
  /// （每次冲突一次），不能带「只做一次」的副作用。允许 `async`（有的调用方
  /// 改完还要顺手写别的表），但**别在里面再调本仓储的写接口**。
  Future<SavedVocab> mergeAndSave(
    FutureOr<VocabLibrary> Function(VocabLibrary current) transform, {
    int maxAttempts = 3,
  }) async {
    for (var attempt = 1; ; attempt++) {
      // 版本号必须**先读**：反过来的话，别人在「读数据」与「读版本号」之间
      // 写了一次，我们就会拿着新版本号去写那份旧数据 —— 冲突检测形同虚设，
      // 反而比不传版本号更糟。先读版本号时，那种情况会让 [save] 抛
      // [VocabConflict]（版本比手上这份新），重来一次即可。
      final base = (await meta())?.at;
      final current = await load() ?? const VocabLibrary();
      try {
        return await save(await transform(current), baseUpdatedAt: base);
      } on VocabConflict {
        // 别人在我们读完版本号之后写过：重读再改一遍。重试几次还不行就往上抛，
        // 让调用方把「词库写不进去」显示出来，别静默丢数据。
        if (attempt >= maxAttempts) rethrow;
      }
    }
  }

  /// 首次从备份/浏览器迁上来时用：**只有库里还没有词库才写**。
  ///
  /// 放在一个写事务里检查，两个入口同时迁移也不会互相覆盖。
  Future<({bool migrated, VocabLibrary value})> migrate(
    VocabLibrary library, {
    DateTime? now,
  }) async {
    final compacted = compactSentenceTexts(library);
    final rows = nextVocabRows(compacted);
    final payload = encodeVocabRows(rows);
    final count = compacted.items.length;
    final at = (now ?? DateTime.now()).toUtc().toIso8601String();
    final packed = _pack(payload);

    return _tx((t) async {
      final existing = await t.rawQuery('SELECT id FROM vocab WHERE id = 1');
      if (existing.isNotEmpty) {
        final stored = await readVocabRows(t);
        final decoded = stored != null
            ? parsePayload(encodeVocabRows(stored))
            : parsePayload(_unpack(await _payloadOf(t)));
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
      await syncVocabRows(t, rows);
      await writeVocabSyncedAt(t, at);
      await rebuildVocabProjection(t, parsePayload(payload));
      _remember(compacted, at, rows: rows);
      return (migrated: true, value: compacted);
    });
  }

  /// 清空词库（行表与派生表一起清）。
  Future<void> clear() async {
    await _tx((t) async {
      await t.rawDelete('DELETE FROM vocab WHERE id = 1');
      await t.rawDelete('DELETE FROM vocab_items');
      await t.rawDelete('DELETE FROM vocab_extras');
      await rebuildVocabProjection(t, null);
    });
    _remember(null, null);
  }

  /// 把 WAL 并回主库并截断。关库前 / 导出前调用。
  Future<void> checkpoint() async {
    try {
      await _db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {
      // 还有别的连接在读时会被拒：不影响已提交的数据，下次再收。
    }
  }

  /// 只查版本号与条数（不解 payload）：判冲突、判缓存用，实测 1ms。
  Future<({String updatedAt, int count})?> _selectPrevMeta([
    DatabaseExecutor? db,
  ]) async {
    final rows = await (db ?? _db).rawQuery(
      'SELECT item_count, updated_at FROM vocab WHERE id = 1',
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return (
      updatedAt: asText(row['updated_at']) ?? '',
      count: asNum(row['item_count']).toInt(),
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
