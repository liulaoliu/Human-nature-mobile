// 跟读 / 手动切块的旧数据守卫（对应 Web 版 `src/core/shadowingState.test.ts` 38 行）。
import 'package:dlaoshi_app/core/shadowing_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shadowingState：本机旧数据守卫', () {
    test('校准：只留下形状正确的条目，坏字段丢弃', () {
      final out = parseCalibrationMap(<String, Object?>{
        'good': <String, Object?>{
          'offsetWords': 2,
          'textStartChunk': 1,
          'anchors': <Object?>[
            <String, Object?>{'atSec': 1.5, 'startWord': 0, 'endWord': 2, 'text': 'hello world'},
            <String, Object?>{'atSec': 'x', 'startWord': 0, 'endWord': 2},
          ],
          'splits': <Object?>[1, 'x', 2],
          'merges': <Object?>[3],
        },
        // 字符串数字不算数字：整条丢
        'stringNumber': <String, Object?>{'offsetWords': '2', 'textStartChunk': 1},
        // 缺 textStartChunk：整条丢
        'missing': <String, Object?>{'offsetWords': 1},
        'nope': null,
      });

      expect(out.keys, <String>['good']);
      final good = out['good']!;
      expect(good.offsetWords, 2);
      expect(good.textStartChunk, 1);
      expect(good.anchors, hasLength(1));
      expect(good.anchors.single.atSec, 1.5);
      expect(good.anchors.single.startWord, 0);
      expect(good.anchors.single.endWord, 2);
      expect(good.anchors.single.text, 'hello world');
      expect(good.splits, <int>[1, 2]);
      expect(good.merges, <int>[3]);
    });

    test('非对象一律回空表，不抛异常', () {
      expect(parseCalibrationMap(null), isEmpty);
      expect(parseCalibrationMap(<Object?>[]), isEmpty);
      expect(parseCalibrationMap('nope'), isEmpty);
      expect(parseCalibrationMap(42), isEmpty);
    });

    test('校准里什么都没有时 splits / merges / anchors 回空列表', () {
      final out = parseCalibrationMap(<String, Object?>{
        'a': <String, Object?>{'offsetWords': 0, 'textStartChunk': 0},
      });
      final a = out['a']!;
      expect(a.anchors, isEmpty);
      expect(a.splits, isEmpty);
      expect(a.merges, isEmpty);
    });

    test('splits 不是数组时当没有（不因一个坏字段整条丢）', () {
      final out = parseCalibrationMap(<String, Object?>{
        'a': <String, Object?>{'offsetWords': 1, 'textStartChunk': 2, 'splits': 'nope'},
      });
      expect(out['a']!.splits, isEmpty);
    });

    test('手动改文：只保留字符串值', () {
      final out = parseScriptEditMap(<String, Object?>{
        'a': 'text',
        'b': 2,
        'c': null,
        'd': '',
      });
      expect(out, <String, String>{'a': 'text', 'd': ''});
      expect(parseScriptEditMap('nope'), isEmpty);
      expect(parseScriptEditMap(<Object?>[]), isEmpty);
    });

    test('写回 JSON 再读回来不丢东西', () {
      final before = <String, Calibration>{
        'a': const Calibration(
          offsetWords: 2,
          textStartChunk: 1,
          anchors: <ManualAnchor>[],
          splits: <int>[1, 2],
        ),
      };
      final back = parseCalibrationMap(calibrationMapToJson(before));
      expect(back['a']!.offsetWords, 2);
      expect(back['a']!.textStartChunk, 1);
      expect(back['a']!.splits, <int>[1, 2]);
      expect(back['a']!.merges, isEmpty);
    });

    test('锚点里的 text 是可选字段：没有就不写', () {
      final json = calibrationToJson(const Calibration(
        offsetWords: 0,
        textStartChunk: 0,
        anchors: <ManualAnchor>[ManualAnchor(atSec: 1.0, startWord: 0, endWord: 1)],
      ));
      final anchors = json['anchors']! as List<Object?>;
      expect((anchors.single! as Map).containsKey('text'), isFalse);
    });
  });
}
