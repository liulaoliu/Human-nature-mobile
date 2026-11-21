// 探针：把「一次评分保存」按 C 方案的行级路径拆开计时，看还有哪一段贵。
//
// 数据用真备份（10892 词），跑法与 `test/bench/row_write.dart` 一致：
//   flutter test test/bench/save_row.dart
//
// 想回答的问题：接线之后，`save` 里剩下的每一步（构建行 / 写一行 / 刷 payload /
// 增量投影）各要多少毫秒，哪一步还值得再优化。
import 'dart:convert';
import 'dart:io';

import 'package:dlaoshi_app/core/migrations.dart';
import 'package:dlaoshi_app/core/vocab/sentence_texts.dart';
import 'package:dlaoshi_app/core/vocab/vocab_json.dart';
import 'package:dlaoshi_app/core/vocab/vocab_rows.dart';
import 'package:dlaoshi_app/data/db/migrations.dart';
import 'package:dlaoshi_app/data/db/payload_codec.dart';
import 'package:dlaoshi_app/data/db/projections.dart';
import 'package:dlaoshi_app/data/db/vocab_rows_store.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const String _backup = 'assets/data/economist-backup-2026-11-10.json';

VocabLibrary _loadBackup() {
  final raw = jsonDecode(File(_backup).readAsStringSync()) as Map<String, Object?>;
  final lib = (raw['library'] ?? raw) as Map<String, Object?>;
  return migrateLibrary(lib);
}

int _ms(Stopwatch w) => w.elapsedMilliseconds;

Future<Database> _openMem() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await ensureSchema(db);
  return db;
}

void main() {
  test('一次评分保存各段耗时', () async {
    final base = _loadBackup();
    // 模拟「读到内存后评了一张卡」：只换第 0 条，其余对象原样带过来。
    final graded = base.copyWith(
      items: [
        base.items.first.copyWith(
          reviewState: base.items.first.reviewState.copyWith(
            ease: 2.7,
            due: () => DateTime.utc(2026, 12, 1).toIso8601String(),
            repetitions: 3,
          ),
        ),
        ...base.items.skip(1),
      ],
    );

    final w = Stopwatch()..start();
    final compacted = compactSentenceTexts(graded);
    final tCompact = _ms(w);

    w
      ..reset()
      ..start();
    final rows = nextVocabRows(compacted);
    final tRowsCold = _ms(w);

    final docsCold = rows.itemDocs.fold<int>(0, (n, d) => n + d.length);

    // 热路径：有了上一份行 + 上一份库（compact 前的那份）就能按引用复用。
    w
      ..reset()
      ..start();
    final again = compactSentenceTexts(graded);
    final rowsHot = nextVocabRows(again, prev: rows, prevSource: compacted);
    final tRowsHot = _ms(w);
    final hotBytes = rowsHot.itemDocs.fold<int>(0, (n, d) => n + d.length);

    final db = await _openMem();
    await replaceVocabRows(db, rows);

    // 写一行（评一张卡的真实代价）
    var tWrite = 0;
    w
      ..reset()
      ..start();
    await syncVocabRows(db, rowsHot, prev: rows);
    tWrite = _ms(w);

    // 再连写 5 次，看稳定值
    final writes = <int>[];
    for (var i = 0; i < 5; i++) {
      w
        ..reset()
        ..start();
      await syncVocabRows(db, rowsHot, prev: rows);
      writes.add(_ms(w));
    }

    // 刷 payload（导出缓存）：一次 16MB 拼接 + gzip
    final payload = encodeVocabRows(rows);
    w
      ..reset()
      ..start();
    final packed = packPayloadJson(payload);
    final tPayload = _ms(w);

    w
      ..reset()
      ..start();
    await db.rawUpdate(
      'INSERT OR REPLACE INTO vocab (id, payload, item_count, updated_at) VALUES (1, ?, ?, ?)',
      [packed, rows.itemDocs.length, '2026-11-21T00:00:00.000Z'],
    );
    final tWritePayload = _ms(w);

    // 增量投影：现在的 API（自己比指纹）
    final prevJson = vocabLibraryToJson(compacted);
    final nextJson = vocabLibraryToJson(again);
    w
      ..reset()
      ..start();
    await rebuildVocabProjection(db, nextJson, prevLib: prevJson);
    final tProjection = _ms(w);

    // 清空后全量投影做对照
    w
      ..reset()
      ..start();
    await rebuildVocabProjection(db, nextJson);
    final tProjectionFull = _ms(w);

    // ignore: avoid_print
    print('''
[save_row] 词条 ${rows.itemDocs.length} / 行 JSON ${(docsCold / 1024 / 1024).toStringAsFixed(1)}MB
  compactSentenceTexts        ${tCompact}ms
  nextVocabRows 冷（全编码）   ${tRowsCold}ms
  nextVocabRows 热（引用复用） ${tRowsHot}ms  （复用后 ${(hotBytes / 1024 / 1024).toStringAsFixed(1)}MB）
  syncVocabRows 首次           ${tWrite}ms
  syncVocabRows 稳定           ${writes.join('/')}ms
  encodeVocabRows + gzip      ${tPayload}ms  （${(packed.length / 1024 / 1024).toStringAsFixed(2)}MB）
  写 payload 行               ${tWritePayload}ms
  增量投影（比指纹 + 只写变化）${tProjection}ms
  全量投影（清空重建）         ${tProjectionFull}ms
''');
    await db.close();
  }, timeout: const Timeout(Duration(minutes: 10)));
}