import 'package:dlaoshi_app/core/practice.dart';
import 'package:flutter_test/flutter_test.dart';

PracticeRecord rec(String at, int total, int correct, {PracticeKind kind = PracticeKind.quiz, int? seconds, String? articleId}) =>
    PracticeRecord(at: at, kind: kind, total: total, correct: correct, seconds: seconds, articleId: articleId);

void main() {
  group('addPracticeRecord', () {
    test('追加并保留最近 cap 条', () {
      var list = <PracticeRecord>[];
      for (var i = 0; i < 5; i++) {
        list = addPracticeRecord(list, rec('2026-10-0${i + 1}', 10, i), cap: 3);
      }
      expect(list, hasLength(3));
      expect(list.map((r) => r.at).toList(), ['2026-10-03', '2026-10-04', '2026-10-05']);
    });

    test('不足 cap 时原样追加', () {
      final list = addPracticeRecord(<PracticeRecord>[], rec('t', 1, 1), cap: 3);
      expect(list, hasLength(1));
    });
  });

  group('accuracy / recentPractice', () {
    test('正确率', () {
      expect(accuracy(rec('x', 4, 3)), closeTo(0.75, 1e-9));
      expect(accuracy(rec('x', 0, 0)), 0);
    });

    test('最近 n 条新的在前', () {
      final list = [rec('a', 1, 1), rec('b', 1, 0), rec('c', 1, 1)];
      expect(recentPractice(list, n: 2).map((r) => r.at).toList(), ['c', 'b']);
      expect(recentPractice(list, n: 99), hasLength(3));
      expect(recentPractice(list, n: 0), isEmpty);
    });
  });

  group('practiceByDay', () {
    test('按天汇总', () {
      String day(String iso) => iso.substring(0, 10);
      final m = practiceByDay([
        rec('2026-10-01T09:00:00Z', 4, 2),
        rec('2026-10-01T10:00:00Z', 6, 5),
        rec('2026-10-02T09:00:00Z', 2, 2),
      ], day);
      expect(m['2026-10-01'], const PracticeDayTotals(total: 10, correct: 7, count: 2));
      expect(m['2026-10-02'], const PracticeDayTotals(total: 2, correct: 2, count: 1));
    });
  });

  group('sumPractice / sumByKind', () {
    final list = [
      rec('a', 10, 6),
      rec('b', 4, 3, kind: PracticeKind.dictation),
      rec('c', 5, 5),
    ];

    test('合计', () {
      expect(sumPractice(list), const PracticeSum(total: 19, correct: 14));
      expect(sumPractice(const []), const PracticeSum());
    });

    test('按类型（缺席也给 0）', () {
      final byKind = sumByKind(list);
      expect(byKind[PracticeKind.quiz], const PracticeSum(total: 15, correct: 11));
      expect(byKind[PracticeKind.dictation], const PracticeSum(total: 4, correct: 3));
      expect(byKind[PracticeKind.listening], const PracticeSum());
      expect(byKind[PracticeKind.golden], const PracticeSum());
      expect(byKind.keys.toList(), practiceKinds);
    });
  });

  group('practiceForArticle', () {
    test('只留本篇，空 id 返回空', () {
      final list = [rec('a', 1, 1, articleId: 'A'), rec('b', 1, 0, articleId: 'B'), rec('c', 1, 1)];
      expect(practiceForArticle(list, 'A'), hasLength(1));
      expect(practiceForArticle(list, 'B').single.at, 'b');
      expect(practiceForArticle(list, ''), isEmpty);
    });
  });

  group('类型名与解析', () {
    test('label 与 parse', () {
      expect(practiceLabel[PracticeKind.golden], 'D老师小课堂');
      expect(parsePracticeKind('listening'), PracticeKind.listening);
      expect(parsePracticeKind('nope'), isNull);
      expect(parsePracticeKind(null), isNull);
    });
  });
}
