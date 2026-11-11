// 性能基准：量词库读写的关键数字，改完大功能跑一遍，看有没有退化。
//
// 用法：
//   flutter test test/bench/vocab_bench_test.dart
//   flutter test test/bench/vocab_bench_test.dart --dart-define=BACKUP=I:/path/x.json
//
// 为什么要这个文件：卡顿是「看不出来」的那类问题 —— 界面上只感觉「卡了一下」，
// 真因可能是整库解析、序列化、gzip 或派生表重建。有一份能随时跑的基准，
// 每次改动后跑一次就知道是哪一步变慢了，不用等用户来报。
//
// **这些数字只在同一台机器上横比有意义**（桌面 vs 桌面、模拟器 vs 模拟器），
// 跨机器比绝对值没意义。用例里只断言「缓存确实生效」这种逻辑性质，
// 不断言毫秒数 —— 否则换台机器就红。
import 'dart:convert';
import 'dart:io';

import 'package:dlaoshi_app/core/backup_parse.dart';
import 'package:dlaoshi_app/data/db/migrations.dart';
import 'package:dlaoshi_app/data/repositories/vocab_repository.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 用户放在 assets/data 下的真备份（未进 git）。
const String _defaultBackup = 'assets/data/economist-backup-2026-11-10.json';

String _backupPath() {
  const fromEnv = String.fromEnvironment('BACKUP');
  if (fromEnv.isNotEmpty) return fromEnv;
  return _defaultBackup;
}

Future<Database> _openMem() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await ensureSchema(db);
  return db;
}

void main() {
  test('词库读写基准（打印耗时，不断言毫秒数）', () async {
    final sw = Stopwatch();
    void mark(String label) {
      // ignore: avoid_print
      print('[BENCH] ${label.padRight(32)} ${sw.elapsedMilliseconds} ms');
      sw.reset();
    }

    // 1. 拿一份词库：有真备份就用真的，没有就造一份规模接近的。
    VocabLibrary? library;
    final path = _backupPath();
    final file = File(path);
    if (file.existsSync()) {
      // ignore: avoid_print
      print('[BENCH] 数据源：$path');
      sw.start();
      final text = await file.readAsString();
      mark('读备份文件 ${(text.length / 1024 / 1024).toStringAsFixed(1)}MB');

      sw.start();
      final decoded = jsonDecode(text);
      mark('jsonDecode');

      sw.start();
      library = parseBackupPayload(decoded).library;
      mark('parseBackupPayload ${library?.items.length ?? 0} 词');
    } else {
      // ignore: avoid_print
      print('[BENCH] 数据源：合成数据（找不到 $path）');
      sw.start();
      library = _syntheticLibrary(10000);
      mark('造合成词库 10000 词');
    }

    expect(library, isNotNull, reason: '备份里得有一份词库');
    final lib = library!;

    // 2. 落盘与读取。
    final db = await _openMem();
    final repo = VocabRepository(db);

    sw.start();
    final saved = await repo.save(lib);
    mark('save 首次（全量投影）');

    // 冷读要用**新实例**：同一个 repo 刚 save 过，缓存已经填好了，
    // 拿它测「冷」只会量到 1ms 的缓存命中。
    sw.start();
    final cold = await VocabRepository(db).load();
    mark('load 冷（新实例，解 gzip）');

    sw.start();
    final warm = await repo.load();
    mark('load 暖（走缓存）');
    // 缓存必须真的生效：同一个实例连读两次要拿到同一个对象。
    expect(identical(warm, await repo.load()), isTrue,
        reason: '同一个实例第二次 load 必须命中缓存');

    sw.start();
    await repo.meta();
    mark('meta（版本号）');

    // 增量保存：改一条词，量的就是「评分落盘」那条路径。
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

    sw.start();
    await repo.load();
    mark('load 写后再读');

    await db.close();

    // ignore: avoid_print
    print('[BENCH] 规模：${lib.items.length} 词 / '
        '${lib.articleEntries.length} 篇次关联');

    // 3. 只断言逻辑性质，不断言毫秒数（换台机器就红）。
    expect(cold, isNotNull);
    expect(identical(cold, warm), isFalse,
        reason: '新实例那份不是缓存对象，但内容应该一样');
    expect(cold!.items.length, warm!.items.length);
  }, timeout: const Timeout(Duration(minutes: 10)));
}

/// 造一份规模接近真库的合成词库。
VocabLibrary _syntheticLibrary(int count) {
  const at = '2026-01-01T00:00:00.000Z';
  return VocabLibrary(
    items: [
      for (var i = 0; i < count; i++)
        VocabItem(
          id: 'v$i',
          word: 'word$i',
          lemma: 'word$i',
          meaning: '这是第 $i 个词的释义，长度接近真实数据里的那种解释性文字。',
          partOfSpeech: 'n.',
          phonetic: '/wɜːd$i/',
          createdAt: at,
          updatedAt: at,
          contexts: [
            VocabContext(
              articleId: 'a${i % 50}',
              sentenceText: 'This is the context sentence number $i, '
                  'long enough to look like real article text.',
              at: at,
            ),
          ],
        ),
    ],
  );
}
