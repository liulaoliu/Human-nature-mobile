// 34.1 基准探针：背单词「评分 / 拼写」从手势到出结果到底要多久。
//
// 文件名故意不带 `_test`，全量测试不收（与 `test/bench/save_stages.dart` 同规矩）。
// 跑法：
//   I:\tools\flutter\bin\flutter.bat test test\bench\study_latency.dart
//
// 用真实体量的词库（`assets/data/economist-backup-2026-11-10.json`，36.5MB / 一万词），
// 因为延迟全在「整库序列化 + gzip + 重建派生表」上，小词库测不出来。
//
// 两个口径，别混：
//   - 同步段 = 调用 `vm.grade(...)` 到它把控制权交回来（首帧就能画了）；
//   - 完成段 = `await` 到 Future 落地（这条路目前还挂着落盘）。
// 34.1 要的是「同步段 < 100ms 且完成段也不用等落盘」。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:dlaoshi_app/core/backup_parse.dart';
import 'package:dlaoshi_app/core/vocab/review.dart';
import 'package:dlaoshi_app/data/db/migrations.dart';
import 'package:dlaoshi_app/data/repositories/learning_repository.dart';
import 'package:dlaoshi_app/data/repositories/vocab_repository.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:dlaoshi_app/viewmodels/study_view_model.dart';

/// 数落盘次数，并把每次 `save` 的耗时记下来。
class _CountingRepo extends VocabRepository {
  _CountingRepo(super.db);

  int saveCount = 0;
  final List<int> saveMs = <int>[];

  @override
  Future<SavedVocab> save(VocabLibrary library, {String? baseUpdatedAt}) async {
    saveCount += 1;
    final sw = Stopwatch()..start();
    final saved = await super.save(library, baseUpdatedAt: baseUpdatedAt);
    saveMs.add(sw.elapsedMilliseconds);
    return saved;
  }
}

void main() {
  test('背单词评分 / 拼写的延迟基准', () async {
    final total = Stopwatch()..start();

    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await ensureSchema(db);

    // 1) 造一个真体量的词库：从真备份里读。
    final text = File(
      'assets/data/economist-backup-2026-11-10.json',
    ).readAsStringSync();
    final lib = parseBackupPayload(jsonDecode(text)).library!;
    // ignore: avoid_print
    print('[BENCH] 词库 ${lib.items.length} 词，读+解析 ${total.elapsedMilliseconds} ms');

    final repo = _CountingRepo(db);
    await repo.save(lib);
    // ignore: avoid_print
    print('[BENCH] 首次落盘（全量投影） ${total.elapsedMilliseconds} ms');
    repo.saveCount = 0;
    repo.saveMs.clear();

    final vm = StudyViewModel(
      vocab: repo,
      learning: LearningRepository(db),
    );
    await vm.bootstrap();
    await vm.settings.setNewLimit(0); // 0 = 不限额度，保证队列够 20 张
    final round = vm.startRound();
    // ignore: avoid_print
    print('[BENCH] startRound 发了 $round 张卡');

    // 2) 一次一张：连点 20 次「下一个」，逐次记同步段 / 完成段。
    // ignore: avoid_print
    print('[BENCH] --- 逐次评分（等上一次完成再点） ---');
    final syncUs = <int>[];
    final doneUs = <int>[];
    for (var i = 0; i < 20; i++) {
      final t0 = total.elapsedMicroseconds;
      final pending = vm.grade(ReviewGrade.good);
      final sync = total.elapsedMicroseconds - t0;
      await pending;
      final done = total.elapsedMicroseconds - t0;
      syncUs.add(sync);
      doneUs.add(done);
      // ignore: avoid_print
      print(
        '[BENCH]   #${i + 1}  到内存 ${(sync / 1000).toStringAsFixed(1)} ms'
        '  到完成 ${(done / 1000).toStringAsFixed(1)} ms',
      );
    }
    // ignore: avoid_print
    print(
      '[BENCH] 逐次小结：到内存 中位 ${_medianMs(syncUs)} ms / 最大 ${_maxMs(syncUs)} ms'
      '；到完成 中位 ${_medianMs(doneUs)} ms / 最大 ${_maxMs(doneUs)} ms',
    );

    await vm.flushWrites();
    // ignore: avoid_print
    print('[BENCH] 20 次评分共落盘 ${repo.saveCount} 次，'
        '单次 ${repo.saveMs.isEmpty ? '-' : '${_medianMs(repo.saveMs.map((e) => e * 1000))} ms（中位）'}');

    // 3) 连点：20 次一口气发出去（模拟「手指没停」），看总墙钟与落盘次数。
    vm.endRound();
    await vm.flushWrites();
    repo.saveCount = 0;
    repo.saveMs.clear();
    vm.startRound();
    final burst = Stopwatch()..start();
    final futures = <Future<void>>[
      for (var i = 0; i < 20; i++) vm.grade(ReviewGrade.hard),
    ];
    final burstSync = burst.elapsedMilliseconds;
    await Future.wait(futures);
    final burstDone = burst.elapsedMilliseconds;
    await vm.flushWrites();
    final burstAll = burst.elapsedMilliseconds;
    // ignore: avoid_print
    print(
      '[BENCH] --- 连点 20 次：发完 $burstSync ms，完成 $burstDone ms，含 flush $burstAll ms，'
      '落盘 $repo.saveCount 次 ---',
    );

    // 4) 拼写：判分要多久才拿得到 true/false。
    vm.endRound();
    await vm.flushWrites();
    repo.saveCount = 0;
    repo.saveMs.clear();
    await vm.settings.setGroupSize(2);
    vm.startRound();
    await vm.grade(ReviewGrade.good);
    await vm.grade(ReviewGrade.good);
    final spelling = vm.session?.spelling;
    // ignore: avoid_print
    print('[BENCH] 组末拼写激活=${spelling?.active}，index=${spelling?.index}');
    final word = spelling?.card?.word;
    if (spelling != null && spelling.active && word != null) {
      final t0 = total.elapsedMicroseconds;
      final pending = vm.checkSpelling(word);
      final sync = total.elapsedMicroseconds - t0;
      final ok = await pending;
      final done = total.elapsedMicroseconds - t0;
      // ignore: avoid_print
      print(
        '[BENCH] 拼写「$word」：调用返回 ${(sync / 1000).toStringAsFixed(1)} ms，'
        '拿到判分 ${(done / 1000).toStringAsFixed(1)} ms，结果 $ok',
      );
      // 拼错一次：这条要多写「不认识」标签 + 队尾重排。
      final t1 = total.elapsedMicroseconds;
      final pendingWrong = vm.checkSpelling('zzz');
      final sync2 = total.elapsedMicroseconds - t1;
      final ok2 = await pendingWrong;
      final done2 = total.elapsedMicroseconds - t1;
      // ignore: avoid_print
      print(
        '[BENCH] 拼错：调用返回 ${(sync2 / 1000).toStringAsFixed(1)} ms，'
        '拿到判分 ${(done2 / 1000).toStringAsFixed(1)} ms，结果 $ok2',
      );
    }
    await vm.flushWrites();
    // ignore: avoid_print
    print('[BENCH] 拼写阶段落盘 ${repo.saveCount} 次');
    // ignore: avoid_print
    print('[BENCH] 总耗时 ${(total.elapsedMilliseconds / 1000).toStringAsFixed(1)} s');

    await db.close();
  }, timeout: const Timeout(Duration(minutes: 10)));
}

String _medianMs(Iterable<int> us) {
  final list = us.toList()..sort();
  if (list.isEmpty) return '-';
  final mid = list[list.length ~/ 2];
  return (mid / 1000).toStringAsFixed(1);
}

String _maxMs(Iterable<int> us) {
  final list = us.toList()..sort();
  if (list.isEmpty) return '-';
  return (list.last / 1000).toStringAsFixed(1);
}
