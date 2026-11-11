import 'package:dlaoshi_app/core/speed_read.dart' show defaultWpm, maxWpm, minWpm;
import 'package:dlaoshi_app/core/speed_read_prefs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseSpeedWpm', () {
    test('没存过回默认', () {
      expect(parseSpeedWpm(null), defaultWpm);
      expect(parseSpeedWpm(''), defaultWpm);
      expect(parseSpeedWpm('   '), defaultWpm);
    });

    test('坏值回默认，不抛', () {
      expect(parseSpeedWpm('abc'), defaultWpm);
      expect(parseSpeedWpm('12.5'), defaultWpm);
    });

    test('正常值照读', () {
      expect(parseSpeedWpm('150'), 150);
      expect(parseSpeedWpm(' 90 '), 90);
    });

    test('超范围夹回去', () {
      expect(parseSpeedWpm('10'), minWpm);
      expect(parseSpeedWpm('9999'), maxWpm);
    });
  });

  group('parseSpeedAutoDrill', () {
    test('默认开', () {
      expect(parseSpeedAutoDrill(null), isTrue);
      expect(parseSpeedAutoDrill(''), isTrue);
      expect(parseSpeedAutoDrill('true'), isTrue);
      expect(parseSpeedAutoDrill('1'), isTrue);
    });

    test('明确写 false / 0 才算关', () {
      expect(parseSpeedAutoDrill('false'), isFalse);
      expect(parseSpeedAutoDrill('0'), isFalse);
      expect(parseSpeedAutoDrill(' FALSE '), isFalse);
    });

    test('看不懂的当开（宁可多练一次）', () {
      expect(parseSpeedAutoDrill('yes'), isTrue);
      expect(parseSpeedAutoDrill('off'), isTrue);
    });
  });

  group('parseSpeedCursor', () {
    test('没存过 / 坏值回 0', () {
      expect(parseSpeedCursor(null), 0);
      expect(parseSpeedCursor(''), 0);
      expect(parseSpeedCursor('abc'), 0);
      expect(parseSpeedCursor('-3'), 0);
    });

    test('正常值照读', () {
      expect(parseSpeedCursor('7'), 7);
      expect(parseSpeedCursor(' 0 '), 0);
    });
  });

  group('clampCursor', () {
    test('读到最后一句时停在最后一句', () {
      expect(clampCursor(9, 5), 4);
      expect(clampCursor(4, 5), 4);
    });

    test('负数回 0', () {
      expect(clampCursor(-1, 5), 0);
    });

    test('没有句子时回 0（不出现 -1）', () {
      expect(clampCursor(3, 0), 0);
      expect(clampCursor(0, 0), 0);
    });
  });

  group('键名', () {
    test('与 Web 版一致', () {
      expect(speedWpmKey, 'reader:speedWpm');
      expect(speedAutoDrillKey, 'reader:speedAutoDrill');
    });
  });
}
