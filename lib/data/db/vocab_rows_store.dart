/// 词库**行级事实表**的读写（v15 起）。
///
/// v1–v14：`vocab.payload` 那一整段 JSON 是唯一事实来源，改一个词要重写整份
/// （真机 16.4MB / gzip 2.14MB / 一次 1.2 秒，见 `test/bench/save_gap.dart`）。
/// v15 起：每个词条一行 `vocab_items`，库级零碎与 `schemaVersion` 走
/// `vocab_extras`；`vocab.payload` 降级成**导出缓存**（生成它仍然走
/// `vocabLibraryToJson`，备份/导出口径一个字节都不变）。
///
/// 这里只碰表，不碰 `VocabLibrary` 模型 —— 模型 ↔ JSON 的换算与行键的算法都在
/// `lib/core/vocab/vocab_rows.dart`（那层不碰数据库，才好测），`DatabaseExecutor`
/// 与事务由调用方包（与 `projections.dart` 同一套约定）。
library;

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../core/vocab/vocab_rows.dart';
import 'payload_codec.dart';
import 'projections.dart' show parsePayload;
import 'sql_util.dart';

/// `schemaVersion` 在 `vocab_extras` 里的键（不会与库级三段撞）。
const String vocabSchemaRowKey = 'schemaVersion';

/// 上面那一行的 `ordinal`：负数保证排在最前，与 [assembleVocabPayload]
/// 先写 `schemaVersion` 的顺序一致。
const int vocabSchemaRowOrdinal = -1;

/// 「行级事实已经回填过」的标记行（`@` 开头，与库级三段的键不会撞）。
///
/// 不能拿「`vocab_items` 有没有行」当判据：**空词库也是合法状态**（用户清空了
/// 词库），那时行数为 0，读路径会误以为「还没回填」而退回 payload。标记行把
/// 「回填过但没有词条」和「没回填过」分开，`doc` 里存回填时的词条数便于对账。
const String vocabRowsMarkerKey = '@rows';
const int vocabRowsMarkerOrdinal = -2;

/// 「`vocab.payload` 停在哪个版本」的戳：值是 `vocab.updated_at` 的字符串。
///
/// 行表**每次保存都写**，`payload` 只在 [flushPayload]（退到后台 / 导出前）才
/// 追一次。于是两份数据天然会不同步，读的时候必须能分辨「payload 是新的」
/// 还是「payload 落后了若干个版本」。戳对得上就信 payload（省一次拼装），
/// 对不上就以行表为准 —— 不这样做的话，用户在后台刷十次卡再冷启动，
/// 词库会静默退回十个版本前。
const String vocabSyncedAtKey = '@synced';
const int vocabSyncedAtOrdinal = -3;

/// 「`vocab.payload` 停在哪个 `updated_at`」。没写过返回 null。
///
/// 单独一个函数（不塞进 [readVocabRows]）是为了让读路径能**先**问一句
/// 「payload 是不是最新的」，答案是要的话就完全不必读两万行。
Future<String?> readVocabSyncedAt(DatabaseExecutor db) async {
  final rows = await db.rawQuery(
    'SELECT doc FROM vocab_extras WHERE key = ?',
    <Object?>[vocabSyncedAtKey],
  );
  if (rows.isEmpty) return null;
  try {
    final value = jsonDecode(asText(rows.first['doc']) ?? 'null');
    return asText(value);
  } catch (_) {
    return null;
  }
}

/// 记下「`vocab.payload` 现在对应哪一版」。
Future<void> writeVocabSyncedAt(DatabaseExecutor db, String at) async {
  await db.rawInsert(
    'INSERT OR REPLACE INTO vocab_extras (key, ordinal, doc) VALUES (?, ?, ?)',
    <Object?>[vocabSyncedAtKey, vocabSyncedAtOrdinal, jsonEncode(at)],
  );
}

/// 把整份词库行**整表重写**（导入 / 合并 / 顺序变化时用）。
///
/// 日常评分走增量（见 `vocab_repository.dart` 的 `save`），这里是「结构变了」的
/// 兜底：先清空再灌，一次 `batch` 提交，避免一万次平台通道往返
/// （同 `projections.dart` 里 batch 的理由）。行键由 [VocabRows.itemKeys] 直接取，
/// 不在这里 `jsonDecode` 每个词条（实测一万词要 850ms）。
Future<void> replaceVocabRows(DatabaseExecutor db, VocabRows rows) async {
  await db.delete('vocab_items');
  await db.delete('vocab_extras');
  final batch = db.batch();
  batch.insert('vocab_extras', <String, Object?>{
    'key': vocabRowsMarkerKey,
    'ordinal': vocabRowsMarkerOrdinal,
    'doc': jsonEncode(<String, Object?>{'items': rows.itemDocs.length}),
  });
  batch.insert('vocab_extras', <String, Object?>{
    'key': vocabSchemaRowKey,
    'ordinal': vocabSchemaRowOrdinal,
    'doc': jsonEncode(rows.schemaVersion),
  });
  var extraOrdinal = 0;
  for (final e in rows.extras.entries) {
    batch.insert('vocab_extras', <String, Object?>{
      'key': e.key,
      'ordinal': extraOrdinal++,
      'doc': jsonEncode(e.value),
    });
  }
  for (var i = 0; i < rows.itemDocs.length; i++) {
    batch.insert('vocab_items', <String, Object?>{
      'id': rows.itemKeys[i],
      'ordinal': i,
      'doc': rows.itemDocs[i],
    });
  }
  await batch.commit(noResult: true);
}

/// 读回行级事实；**还没回填过时返回 null**（老库 / 迁移中途）。
///
/// 返回 null 的语义是「这张表还不可信，请回退去读 payload」—— 迁移回填前的库、
/// 或者被外部改坏的库，都靠这条兜底，不会让词库变成空的。
Future<VocabRows?> readVocabRows(DatabaseExecutor db) async {
  final marker = await db.rawQuery(
    'SELECT doc FROM vocab_extras WHERE key = ?',
    <Object?>[vocabRowsMarkerKey],
  );
  if (marker.isEmpty) return null;

  final itemRows = await db.rawQuery(
    'SELECT id, doc FROM vocab_items ORDER BY ordinal ASC',
  );
  // 只取键，`doc` 单独分块读。
  //
  // `sentenceTexts` 是**一整段 13MB** 存在一行里（句子原文按 `articleId\u0000
  // sentenceId` 汇总，拆不开），一次 `SELECT doc` 会撑爆 Android 的
  // CursorWindow（单行 2MB 上限）：
  //   DatabaseException(Row too big to fit into CursorWindow requiredPos=2,
  //   totalRows=3) sql 'SELECT key, doc FROM vocab_extras ORDER BY ordinal ASC'
  // 桌面 `sqflite_common_ffi` 没有这个窗口，所以单元测试测不出来 —— 2026-11-21
  // 在真机（vivo V1981A）上第一次发现。与 `vocab.payload` 用同一套分块读法。
  final extraRows = await db.rawQuery(
    'SELECT key FROM vocab_extras ORDER BY ordinal ASC',
  );
  var schemaVersion = 1;
  final extras = <String, Object?>{};
  for (final r in extraRows) {
    final key = asText(r['key']) ?? '';
    if (key.isEmpty) continue;
    if (key == vocabRowsMarkerKey) continue;
    final raw = await readBigPayload(
      db,
      table: 'vocab_extras',
      keyColumn: 'key',
      key: key,
      column: 'doc',
    );
    Object? value;
    try {
      value = jsonDecode(payloadJsonText(raw) ?? 'null');
    } catch (_) {
      continue;
    }
    if (key == vocabSchemaRowKey) {
      if (value is num) schemaVersion = value.toInt();
      continue;
    }
    // 同步戳只服务于「payload 是不是新的」，不属于词库内容，不能进 extras
    // （否则会被 [assembleVocabPayload] 当成库级字段写进导出的 JSON）。
    if (key == vocabSyncedAtKey) continue;
    extras[key] = value;
  }
  return VocabRows(
    schemaVersion: schemaVersion,
    itemKeys: <String>[for (final r in itemRows) asText(r['id']) ?? ''],
    itemDocs: <String>[for (final r in itemRows) asText(r['doc']) ?? ''],
    extras: extras,
  );
}

/// 把库里那份 `vocab.payload` 拆进行表（v15 迁移调用；幂等，可重复跑）。
///
/// **只加不改**：payload 一个字节都不动，拆失败也不删任何东西 —— 真出问题，
/// 读路径还能退回 payload（见 [readVocabRows] 的 null 语义）。
///
/// 返回写进去的词条行数；库里还没有词库时返回 0。
Future<int> backfillVocabRows(DatabaseExecutor db) async {
  final raw = await readBigPayload(db, table: 'vocab', keyColumn: 'id', key: 1);
  if (raw == null) return 0;
  final root = asRecord(parsePayload(payloadJsonText(raw)));
  if (root == null) return 0;
  final rows = splitVocabPayload(root);
  await replaceVocabRows(db, rows);
  return rows.itemDocs.length;
}

/// 把行表同步到 [next]：能增量就只写变了的行，结构变了才整表重写。
///
/// [prev] 是**内存里记住的上一份行**（调用方持有，不查库）。传 null 表示
/// 「不知道库里现在是什么形状」（刚启动、或别的仓储实例写过），这时退回
/// [replaceVocabRows] 全量重写 —— 安全第一，慢一点只在冷启动后的第一次保存。
///
/// 判「这一行变了」只比 `doc` 字符串：`doc` 是词条 JSON 的**唯一落库形态**，
/// 字符串相同就意味着派生出来的一切都相同（`_fingerprint` 那套是要落列才需要）。
Future<void> syncVocabRows(
  DatabaseExecutor db,
  VocabRows next, {
  VocabRows? prev,
}) async {
  final sameShape = prev != null &&
      prev.itemKeys.length == next.itemKeys.length &&
      _sameKeys(prev.itemKeys, next.itemKeys);
  if (!sameShape) {
    await replaceVocabRows(db, next);
    return;
  }

  var rowsDirty = false;
  final rowBatch = db.batch();
  for (var i = 0; i < next.itemDocs.length; i++) {
    if (next.itemDocs[i] == prev.itemDocs[i]) continue;
    rowBatch.update(
      'vocab_items',
      <String, Object?>{'doc': next.itemDocs[i]},
      where: 'id = ?',
      whereArgs: <Object?>[next.itemKeys[i]],
    );
    rowsDirty = true;
  }
  if (rowsDirty) await rowBatch.commit(noResult: true);

  // 库级零碎（articleEntries / tombstones / sentenceTexts）与 schemaVersion：
  // 它们本来就是「一整段」，变了就整段重写，但不动词条行。
  if (vocabExtrasUnchanged(prev, next)) return;

  await db.delete(
    'vocab_extras',
    where: 'key <> ? AND key <> ? AND key <> ?',
    whereArgs: <Object?>[
      vocabRowsMarkerKey,
      vocabSchemaRowKey,
      vocabSyncedAtKey,
    ],
  );
  final extraBatch = db.batch();
  extraBatch.update(
    'vocab_extras',
    <String, Object?>{'doc': jsonEncode(next.schemaVersion)},
    where: 'key = ?',
    whereArgs: <Object?>[vocabSchemaRowKey],
  );
  var ordinal = 0;
  for (final e in next.extras.entries) {
    extraBatch.insert('vocab_extras', <String, Object?>{
      'key': e.key,
      'ordinal': ordinal++,
      'doc': jsonEncode(e.value),
    });
  }
  await extraBatch.commit(noResult: true);
}

bool _sameKeys(List<String> a, List<String> b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// 两份行的「库级三段」（`articleEntries` / `tombstones` / `sentenceTexts`）
/// 及 `schemaVersion` 是否同一份。
///
/// 判据是**对象引用**：`nextVocabRows` 保证没变的段原对象搬运，所以 `identical`
/// 足够。以前这里写的是 `jsonEncode(a) == jsonEncode(b)` —— 13MB 的
/// `sentenceTexts` 编码两遍实测 ~100ms，正好是「只写一行却要 100ms」的全部来源。
bool vocabExtrasUnchanged(VocabRows a, VocabRows b) =>
    a.schemaVersion == b.schemaVersion && _sameExtras(a.extras, b.extras);

/// 库级三段是否「还是同一份」：先比键集合，再逐键 `identical`。
///
/// `nextVocabRows` 保证「没变的段」是原对象搬运，所以 `identical` 足够；
/// 万一调用方换了新的等价对象（比如从库里读回来重建），这里会判成「变了」
/// 而整段重写一次 —— 只是多写几行，不会错。
bool _sameExtras(Map<String, Object?> a, Map<String, Object?> b) {
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (!b.containsKey(e.key)) return false;
    if (!identical(e.value, b[e.key])) return false;
  }
  return true;
}