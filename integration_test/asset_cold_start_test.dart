// 真机（模拟器）上量 assets 的冷启动成本 —— 桌面 `flutter test` 量不准：
// 手机闪存的读速、单核主频、isolate 启动开销都不一样。
//
// 量的是「一键处理」依赖的两份大 asset（见 `docs/TODO.md` 第 5 条）：
//   1. ECDICT 三份 tsv（7.8 + 1.1 + 0.3 MB）读进来 + 后台 isolate 解析的耗时；
//   2. Tatoeba（6.5 MB）抽 300 个词的例句耗时。
//
// 跑法（要先起模拟器，`flutter devices` 里能看到）：
//   flutter test integration_test/asset_cold_start_test.dart -d emulator-5554
//
// 结论回填在 `docs/TODO.md` 第 5 条；断言只做「别退化到不可用」的下限，
// 具体毫秒数用 `[bench]` 打在日志里。
import 'dart:convert';

import 'package:flutter/services.dart' show ByteData, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:dlaoshi_app/core/ecdict.dart';
import 'package:dlaoshi_app/core/tatoeba.dart';
import 'package:dlaoshi_app/data/dictionary_loader.dart'
    show dictionary, dictionaryReady, loadDictionary, resetDictionary;

/// 读 asset 并解成 UTF-8 文本，返回 (文本, 耗时)。
Future<(String, Duration)> _readAsset(String path) async {
  final sw = Stopwatch()..start();
  final ByteData data = await rootBundle.load(path);
  final bytes =
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  final text = utf8.decode(bytes, allowMalformed: true);
  sw.stop();
  return (text, sw.elapsed);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('[bench] 真机上读 + 解析 ECDICT 要多久', (WidgetTester tester) async {
    // rootBundle 在 testWidgets 里要真跑 IO，用 runAsync 才不会被假时钟卡住。
    await tester.runAsync(() async {
      final words = await _readAsset('assets/ecdict/words.tsv');
      final forms = await _readAsset('assets/ecdict/forms.tsv');
      final near = await _readAsset('assets/ecdict/near.tsv');

      final swParse = Stopwatch()..start();
      final dict = parseEcdict(words.$1, forms.$1, near.$1);
      swParse.stop();

      // ignore: avoid_print
      print('[bench] ecdict words.tsv 读 ${words.$2.inMilliseconds} ms'
          '（${words.$1.length} 字符）');
      // ignore: avoid_print
      print('[bench] ecdict forms.tsv 读 ${forms.$2.inMilliseconds} ms');
      // ignore: avoid_print
      print('[bench] ecdict near.tsv  读 ${near.$2.inMilliseconds} ms');
      // ignore: avoid_print
      print('[bench] ecdict 解析（主 isolate）${swParse.elapsedMilliseconds} ms'
          ' → ${dict.entries.length} 词条 / ${dict.forms.length} 变体');

      // 主表不该是空的：空了说明 asset 没打进包，界面上会静默降级。
      expect(dict.entries.isNotEmpty, isTrue, reason: 'ECDICT 主表读出来是空的');
      expect(dict.forms.isNotEmpty, isTrue, reason: '变体表读出来是空的');
    });
  });

  testWidgets('[bench] 真机上给 300 个词抽 Tatoeba 例句要多久',
      (WidgetTester tester) async {
    await tester.runAsync(() async {
      final tatoeba = await _readAsset('assets/tatoeba/tatoeba-en.tsv');
      // 词表从 ECDICT 主表里均匀取样，覆盖整张表（不是只取 a 开头的怪词）。
      // 这样「命中率 / 带中文比例」就是真实的覆盖率，能直接回填 TODO 第 5 条。
      final wordsAsset = await _readAsset('assets/ecdict/words.tsv');
      final all = <String>[
        for (final line in wordsAsset.$1.split('\n'))
          if (line.split('\t').first.trim().isNotEmpty)
            line.split('\t').first.trim().toLowerCase(),
      ];
      final step = all.length ~/ 300;
      final words = <String>{for (var i = 0; i < 300; i++) all[i * step]};

      final sw = Stopwatch()..start();
      final found = examplesForWords(tatoeba.$1, words);
      sw.stop();

      var withZh = 0;
      var total = 0;
      for (final list in found.values) {
        for (final e in list) {
          total++;
          if (e.zh.trim().isNotEmpty) withZh++;
        }
      }
      final pct = (found.length / words.length * 100).toStringAsFixed(1);

      // ignore: avoid_print
      print('[bench] tatoeba 读 ${tatoeba.$2.inMilliseconds} ms'
          '（${tatoeba.$1.length} 字符）');
      // ignore: avoid_print
      print('[bench] tatoeba 抽 ${words.length} 个词 ${sw.elapsedMilliseconds} ms'
          ' → 命中 ${found.length} 个（$pct%） / $total 条例句，带中文 $withZh 条');

      expect(found.isNotEmpty, isTrue, reason: 'Tatoeba 一条都没抽到，asset 可能没打进包');
    });
  });

  testWidgets('[bench] 走 app 真实路径：loadDictionary() 冷启动要多久',
      (WidgetTester tester) async {
    // 上面两个用例量的是「主 isolate 解析」；app 真跑的是 `compute` 起后台
    // isolate 解析（`lib/data/dictionary_loader.dart`）。差别在 isolate 启动
    // 与跨 isolate 拷 9MB 字符串，所以这条必须单独量。
    await tester.runAsync(() async {
      resetDictionary();
      final sw = Stopwatch()..start();
      final ok = await loadDictionary();
      sw.stop();
      final dict = dictionary();
      final ready = dictionaryReady();

      // ignore: avoid_print
      print('[bench] loadDictionary() 全链路 ${sw.elapsedMilliseconds} ms'
          ' → $ok / ${dict?.entries.length ?? 0} 词条 / ready=$ready');

      expect(ok, isTrue, reason: 'loadDictionary() 返回 false：asset 没打包或解析失败');
      expect(ready, isTrue);
    });
  });
}

/// 抽样说明：Tatoeba 覆盖率那条用例从 ECDICT 主表均匀取样，
/// 因为那才是「一键处理」真实会查的词分布（生词本里的词来自阅读）。
/// 早期版本用一份手写难词表，只有 30 个词——测出来的命中率不代表整体。
