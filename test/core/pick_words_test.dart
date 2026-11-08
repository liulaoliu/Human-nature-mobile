// 选字定块：选区 → 词序号区间。用例逐条对齐 Web 版 `src/core/pickWords.test.ts`。

import 'package:dlaoshi_app/core/pick_words.dart';
import 'package:flutter_test/flutter_test.dart';

const String _text = 'aa bb cc dd ';

void main() {
  group('caretWordIndex', () {
    test('空串是 0', () {
      expect(caretWordIndex(''), 0);
    });

    test('落在词里/词尾 = 这个词的下标', () {
      expect(caretWordIndex('aa'), 0);
      expect(caretWordIndex('aa bb'), 1);
      expect(caretWordIndex('aa bb cc'), 2);
    });

    test('以空格结尾 = 已经跨过前一个词', () {
      expect(caretWordIndex('aa '), 1);
      expect(caretWordIndex('aa bb '), 2);
      expect(caretWordIndex('   '), 0);
    });
  });

  group('wordRangeFromText', () {
    test('选完整的两个词（终点在空格后）', () {
      // "aa bb" 的下标是 [0,5)，到空格 [0,6)
      expect(wordRangeFromText(_text, 0, 5), (start: 0, end: 2));
      expect(wordRangeFromText(_text, 0, 6), (start: 0, end: 2));
    });

    test('终点落在词中间时把那个词算进来', () {
      expect(wordRangeFromText(_text, 0, 4), (start: 0, end: 2)); // "aa b"
    });

    test('起点落在词中间时从那个词开始', () {
      expect(wordRangeFromText(_text, 1, 6), (start: 0, end: 2)); // "a" 起到 "bb"
    });

    test('起点在空格后 = 从下一个词开始', () {
      expect(wordRangeFromText(_text, 3, 6), (start: 1, end: 2)); // "bb"
    });

    test('取中间两个词', () {
      expect(wordRangeFromText(_text, 3, 9), (start: 1, end: 3)); // "bb cc"
    });

    test('一直选到末尾', () {
      expect(wordRangeFromText(_text, 3, _text.length), (start: 1, end: 4));
    });

    test('下标越界会夹住，不报错', () {
      expect(wordRangeFromText(_text, -10, 999), (start: 0, end: 4));
    });

    test('端点顺序反了也能纠正', () {
      expect(wordRangeFromText(_text, 6, 0), (start: 0, end: 2));
    });

    test('光标 / 空选区返回 null', () {
      expect(wordRangeFromText(_text, 3, 3), isNull);
      expect(wordRangeFromText(_text, 0, 0), isNull);
    });

    test('只选到一段空白也算不出词', () {
      expect(wordRangeFromText('   ', 0, 3), isNull);
    });

    test('结果始终单调且落在词数内', () {
      final total = _text.trim().split(RegExp(r'\s+')).length;
      for (var a = 0; a <= _text.length; a++) {
        for (var b = a; b <= _text.length; b++) {
          final r = wordRangeFromText(_text, a, b);
          if (r == null) continue;
          expect(r.start, lessThan(r.end));
          expect(r.start, greaterThanOrEqualTo(0));
          expect(r.end, lessThanOrEqualTo(total));
        }
      }
    });
  });
}
