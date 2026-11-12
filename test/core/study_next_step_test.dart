// 结算页的「接下来」建议：有生词就继续学，学完了就给「去复习」，都没有就老实说。
//
// 用户口径（m25031）：学完进复习最好，但**不要自动跳** —— 跳走会把结算数字盖掉。
import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/core/study_pool.dart';
import 'package:dlaoshi_app/core/study_next_step.dart';

void main() {
  group('还有生词', () {
    test('建议继续学，数字带进文案', () {
      final next = roundNextStep(learn: 12, review: 30, articleId: 'a1');

      expect(next.entry, StudyEntry.learn);
      expect(next.count, 12);
      expect(next.label, '继续学这 12 个');
      expect(next.hint, contains('12'));
    });

    test('生词优先于到期：先学完这一篇再说', () {
      final next = roundNextStep(learn: 3, review: 99, articleId: 'a1');

      expect(next.entry, StudyEntry.learn);
    });
  });

  group('生词学完了', () {
    test('有到期的就给「去复习」', () {
      final next = roundNextStep(learn: 0, review: 21, articleId: 'a1');

      expect(next.entry, StudyEntry.review);
      expect(next.count, 21);
      expect(next.label, '去复习这 21 个');
      expect(next.hint, contains('21'));
    });
  });

  group('都没有', () {
    test('打开过文章：指回去换一篇', () {
      final next = roundNextStep(learn: 0, review: 0, articleId: 'a1');

      expect(next.entry, isNull);
      expect(next.label, isEmpty);
      expect(next.hint, contains('换一篇'));
    });

    test('还没打开过文章：说全库都没有', () {
      final next = roundNextStep(learn: 0, review: 0, articleId: null);

      expect(next.entry, isNull);
      expect(next.hint, contains('全库'));
    });
  });
}
