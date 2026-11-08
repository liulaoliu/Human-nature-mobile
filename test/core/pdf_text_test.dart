import 'package:dlaoshi_app/core/pdf_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parsePageRange', () {
    test('空 = 全部页', () {
      expect(parsePageRange('', 3), [1, 2, 3]);
      expect(parsePageRange(null, 2), [1, 2]);
      expect(parsePageRange('   ', 4), [1, 2, 3, 4]);
    });

    test('区间与单页混用，去重排序', () {
      expect(parsePageRange('2-4,6,3', 8), [2, 3, 4, 6]);
    });

    test('越界被夹住', () {
      expect(parsePageRange('0-99', 3), [1, 2, 3]);
      expect(parsePageRange('9', 3), isEmpty);
    });

    test('认不出的片段忽略，不抛错', () {
      expect(parsePageRange('abc,2', 5), [2]);
      expect(parsePageRange('3-1', 5), isEmpty);
    });
  });

  group('pdfItemsToText', () {
    test('hasEOL 断行，纵向大间距当段落', () {
      final items = <Object?>[
        {'str': 'Hello', 'transform': [0, 0, 0, 0, 0, 100], 'height': 10, 'hasEOL': false},
        {'str': ' world', 'transform': [0, 0, 0, 0, 0, 100], 'height': 10, 'hasEOL': true},
        {'str': 'Second para', 'transform': [0, 0, 0, 0, 0, 80], 'height': 10, 'hasEOL': true},
      ];
      expect(pdfItemsToText(items), 'Hello world\n\nSecond para');
    });

    test('忽略没有 str 的项', () {
      expect(
        pdfItemsToText(<Object?>[
          {'transform': [0, 0, 0, 0, 0, 0]},
          {'str': 'ok', 'hasEOL': true},
        ]),
        'ok',
      );
    });

    test('同一行的小间距不断行', () {
      expect(
        pdfItemsToText(<Object?>[
          {'str': 'a', 'transform': [0, 0, 0, 0, 0, 100], 'height': 10},
          {'str': 'b', 'transform': [0, 0, 0, 0, 0, 99], 'height': 10},
        ]),
        'ab',
      );
    });

    test('空输入返回空串', () {
      expect(pdfItemsToText(const []), '');
    });
  });
}
