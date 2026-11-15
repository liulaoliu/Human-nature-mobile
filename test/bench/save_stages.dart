// 一次性探针：把「save 增量」拆成几段，看时间到底花在哪儿。
//
// 用法：flutter test test/bench/save_stages.dart
// 文件名故意不带 `_test`，全量测试不收；量完就删。
import 'dart:convert';
import 'dart:io';

import 'package:dlaoshi_app/core/backup_parse.dart';
import 'package:dlaoshi_app/core/vocab/sentence_texts.dart';
import 'package:dlaoshi_app/core/vocab/vocab_json.dart';
import 'package:dlaoshi_app/data/db/migrations.dart';
import 'package:dlaoshi_app/data/repositories/vocab_repository.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('save 增量拆段', () async {
    final sw = Stopwatch();
    void mark(String label) {
      // ignore: avoid_print
      print('[STAGE] ${label.padRight(34)} ${sw.elapsedMilliseconds} ms');
      sw.reset();
    }

    sw.start();
    final text = await File(
      'assets/data/economist-backup-2026-11-10.json',
    ).readAsString();
    mark('读文件');
    sw.start();
    final lib = parseBackupPayload(jsonDecode(text)).library!;
    mark('解析 ${lib.items.length} 词');

    sw.start();
    final compacted = compactSentenceTexts(lib);
    mark('compactSentenceTexts');

    sw.start();
    final payload = encodeVocabLibrary(compacted);
    mark('encodeVocabLibrary ${(payload.length / 1024 / 1024).toStringAsFixed(1)}MB');

    sw.start();
    final bytes = utf8.encode(payload);
    mark('utf8.encode');

    sw.start();
    final g6 = GZipCodec(level: 6).encode(bytes);
    mark('gzip level6 → ${(g6.length / 1024 / 1024).toStringAsFixed(2)}MB');

    sw.start();
    final g1 = GZipCodec(level: 1).encode(bytes);
    mark('gzip level1 → ${(g1.length / 1024 / 1024).toStringAsFixed(2)}MB');

    sw.start();
    final nextJson = vocabLibraryToJson(compacted);
    mark('vocabLibraryToJson');

    // 增量投影：把 prev/next 各 jsonEncode 一遍，是这里最贵的一段。
    sw.start();
    final prevItems = (nextJson['items'] as List).cast<Object?>();
    final a = <String, String>{
      for (var i = 0; i < prevItems.length; i++)
        (prevItems[i] as Map)['id'] as String: jsonEncode(prevItems[i]),
    };
    mark('prev 逐条 jsonEncode ${a.length}');

    sw.start();
    final b = <String, String>{
      for (var i = 0; i < prevItems.length; i++)
        (prevItems[i] as Map)['id'] as String: jsonEncode(prevItems[i]),
    };
    mark('next 逐条 jsonEncode');

    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await ensureSchema(db);
    final repo = VocabRepository(db);
    sw.start();
    final saved = await repo.save(lib);
    mark('save 首次（全量投影）');

    final touched = lib.copyWith(
      items: [
        lib.items.first.copyWith(
          reviewState: const ReviewState(repetitions: 1),
        ),
        ...lib.items.skip(1),
      ],
    );
    sw.start();
    await repo.save(touched, baseUpdatedAt: saved.updatedAt);
    mark('save 增量（改 1 条）');

    await db.close();
    expect(b.length, a.length);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
