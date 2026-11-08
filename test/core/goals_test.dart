import 'package:dlaoshi_app/core/goals.dart';
import 'package:flutter_test/flutter_test.dart';

ReadDone e(String day, String articleId, [String? title, String? at]) => ReadDone(
      day: day,
      articleId: articleId,
      title: title ?? articleId,
      at: at ?? '${day}T10:00:00.000Z',
    );

void main() {
  group('addReadDone / readDoneOn / removeReadDone', () {
    test('同一篇只记第一次：换一天重读也不算', () {
      var list = addReadDone(<ReadDone>[], e('2026-10-15', 'a1'));
      list = addReadDone(list, e('2026-10-15', 'a1', 'again', '2026-10-15T11:00:00.000Z'));
      expect(list, hasLength(1));

      list = addReadDone(list, e('2026-10-16', 'a1'));
      expect(list, hasLength(1));
      expect(list.single.day, '2026-10-15');

      expect(addReadDone(list, e('2026-10-16', 'a2')), hasLength(2));
    });

    test('空 articleId 不记', () {
      expect(addReadDone(<ReadDone>[], e('2026-10-15', '')), isEmpty);
    });

    test('readDoneOn 只取那天、按时间排序；remove 可撤销（不分哪天）', () {
      final list = [
        e('2026-10-15', 'a2', 'B', '2026-10-15T12:00:00.000Z'),
        e('2026-10-15', 'a1', 'A'),
        e('2026-10-14', 'a0'),
      ];
      expect(readDoneOn(list, '2026-10-15').map((x) => x.articleId).toList(), ['a1', 'a2']);
      expect(removeReadDone(list, 'a1').map((x) => x.articleId).toList(), ['a2', 'a0']);
      expect(removeReadDone(list, 'zz'), hasLength(3));
    });

    test('readDayOf / groupReadDone / readDoneTotals', () {
      final list = [
        e('2026-10-15', 'a2'),
        e('2026-10-15', 'a1'),
        e('2026-10-13', 'a0'),
        e('2026-10-14', 'a3'),
      ];
      expect(readDayOf(list, 'a0'), '2026-10-13');
      expect(readDayOf(list, 'zz'), isNull);
      expect(readDayOf(list, null), isNull);
      expect(readDayOf(list, ''), isNull);

      final g = groupReadDone(list);
      expect(g.map((x) => [x.day, x.items.length]).toList(), [
        ['2026-10-15', 2],
        ['2026-10-14', 1],
        ['2026-10-13', 1],
      ]);
      expect(readDoneTotals(list), const ReadDoneTotals(articles: 4, days: 3));
    });

    test('goalLevel：一天读完几篇的色阶（0 空 / 1–3 / ≥4）', () {
      expect(goalLevel(0), 0);
      expect(goalLevel(1), 1);
      expect(goalLevel(3), 3);
      expect(goalLevel(9), 4);
    });

    test('mergeReadDone：按 articleId 合并去重，保留已有的', () {
      final a = [e('2026-10-15', 'a1')];
      final b = [e('2026-10-15', 'a1'), e('2026-10-16', 'a2')];
      expect(mergeReadDone(a, b).map((x) => x.articleId).toList(), ['a1', 'a2']);
      expect(mergeReadDone(a, [e('2026-10-20', 'a1')]).single.day, '2026-10-15');
      expect(mergeReadDone(const [], [e('2026-10-16', '')]), isEmpty);
    });

    test('超过上限时留最近的', () {
      var list = <ReadDone>[];
      for (var i = 0; i < 5; i++) {
        list = addReadDone(list, e('2026-10-15', 'a$i'), cap: 3);
      }
      expect(list.map((x) => x.articleId).toList(), ['a2', 'a3', 'a4']);
    });
  });

  group('goalPct / goalReached', () {
    test('按目标算百分比，封顶 100', () {
      expect(goalPct(0, 2), 0);
      expect(goalPct(1, 2), 50);
      expect(goalPct(3, 2), 100);
    });

    test('不设目标（0）：读过算满，没读算 0，且不判定达成', () {
      expect(goalPct(0, 0), 0);
      expect(goalPct(2, 0), 100);
      expect(goalReached(5, 0), isFalse);
      expect(goalReached(2, 2), isTrue);
      expect(goalReached(1, 2), isFalse);
    });
  });
}
