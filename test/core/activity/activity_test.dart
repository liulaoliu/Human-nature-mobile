import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/core/activity/activity.dart';

void main() {
  group('dayKeyLocal / calendarDayKey（结算点 04:00）', () {
    test('白天用当天；凌晨（00:00–03:59）算前一天', () {
      expect(dayKeyLocal(DateTime(2026, 10, 3, 10)), '2026-10-03');
      expect(dayKeyLocal(DateTime(2026, 10, 3, 3, 59)), '2026-10-02'); // 凌晨 → 前一天
      expect(dayKeyLocal(DateTime(2026, 10, 3, 4)), '2026-10-03'); // 4 点整 → 新的一天
      expect(dayKeyLocal(DateTime(2026, 10, 3, 0)), '2026-10-02');
    });

    test('calendarDayKey 就是那一天（不做结算偏移）', () {
      expect(calendarDayKey(DateTime(2026, 10, 3, 0)), '2026-10-03');
      expect(calendarDayKey(DateTime(2026, 10, 3, 23, 59)), '2026-10-03');
    });

    test('nextStudyDayStart：凌晨归到当天 04:00，白天归到下一天 04:00', () {
      expect(
        nextStudyDayStart(DateTime(2026, 10, 3, 3, 59)),
        DateTime(2026, 10, 3, 4),
      );
      expect(
        nextStudyDayStart(DateTime(2026, 10, 3, 4)),
        DateTime(2026, 10, 4, 4),
      );
      expect(
        nextStudyDayStart(DateTime(2026, 10, 3, 23, 30)),
        DateTime(2026, 10, 4, 4),
      );
    });
  });

  group('addActivity', () {
    test('新增一天', () {
      final out = addActivity(const [], '2026-10-03', ActivityCat.vocab, n: 2);
      expect(out.length, 1);
      expect(out.first.day, '2026-10-03');
      expect(out.first.counts, {ActivityCat.vocab: 2});
    });

    test('同一天同类累加、不同类并存', () {
      var list = const <DayActivity>[];
      list = addActivity(list, '2026-10-03', ActivityCat.vocab, n: 2);
      list = addActivity(list, '2026-10-03', ActivityCat.vocab, n: 3);
      list = addActivity(list, '2026-10-03', ActivityCat.listen);
      expect(list.single.counts, {ActivityCat.vocab: 5, ActivityCat.listen: 1});
    });

    test('按日期排序、按上限截断', () {
      var list = const <DayActivity>[];
      list = addActivity(list, '2026-10-03', ActivityCat.vocab);
      list = addActivity(list, '2026-10-01', ActivityCat.vocab);
      list = addActivity(list, '2026-10-02', ActivityCat.vocab);
      expect(list.map((a) => a.day).toList(),
          ['2026-10-01', '2026-10-02', '2026-10-03']);

      var capped = const <DayActivity>[];
      for (var i = 0; i < 5; i++) {
        capped = addActivity(capped, '2026-10-0${i + 1}', ActivityCat.vocab,
            cap: 3);
      }
      expect(capped.length, 3);
      expect(capped.map((a) => a.day).toList(),
          ['2026-10-03', '2026-10-04', '2026-10-05']);
    });

    test('n<=0 或空日期不动', () {
      expect(addActivity(const [], '2026-10-03', ActivityCat.vocab, n: 0),
          isEmpty);
      expect(addActivity(const [], '', ActivityCat.vocab), isEmpty);
    });
  });

  group('dayTotal / sumCats', () {
    const list = [
      DayActivity(day: '2026-10-01', counts: {
        ActivityCat.read: 2,
        ActivityCat.vocab: 3,
      }),
      DayActivity(day: '2026-10-02', counts: {ActivityCat.listen: 1}),
      DayActivity(day: '2026-10-03', counts: {
        ActivityCat.write: 4,
        ActivityCat.speak: 1,
      }),
    ];

    test('dayTotal 求和', () {
      expect(dayTotal(list.first), 5);
    });

    test('sumCats 按区间合计', () {
      expect(sumCats(list, '2026-10-01', '2026-10-02'), {
        ActivityCat.read: 2,
        ActivityCat.vocab: 3,
        ActivityCat.listen: 1,
        ActivityCat.write: 0,
        ActivityCat.speak: 0,
      });
      expect(sumCats(list, '2026-10-03', '2026-10-03')[ActivityCat.write], 4);
    });
  });

  group('activityStreak', () {
    test('从今天/昨天往前数连续天数', () {
      const list = [
        DayActivity(day: '2026-10-01', counts: {ActivityCat.vocab: 1}),
        DayActivity(day: '2026-10-02', counts: {ActivityCat.vocab: 1}),
        DayActivity(day: '2026-10-03', counts: {ActivityCat.vocab: 1}),
      ];
      expect(activityStreak(list, DateTime(2026, 10, 3, 10)), 3);
      // 今天还没记，但昨天有 → 从昨天数
      expect(activityStreak(list, DateTime(2026, 10, 4, 10)), 3);
      // 断档
      expect(activityStreak(list, DateTime(2026, 10, 6, 10)), 0);
    });
  });

  group('levelFor', () {
    test('色阶阈值', () {
      expect(levelFor(0), 0);
      expect(levelFor(1), 1);
      expect(levelFor(2), 1);
      expect(levelFor(3), 2);
      expect(levelFor(6), 3);
      expect(levelFor(10), 4);
    });
  });

  group('buildHeatmap', () {
    final today = DateTime(2026, 10, 3, 10); // 2026-10-03（白天，逻辑日=日历日）
    final todayWeekday = today.weekday % 7; // 0=周日

    test('列数 / 行数正确，今天落在最后一列', () {
      final hm = buildHeatmap(const {}, now: today);
      expect(hm.columns, 13);
      expect(hm.cells.length, 13);
      expect(hm.cells.every((c) => c.length == 7), isTrue);
      final last = hm.cells[12];
      final todayCell = last[todayWeekday];
      expect(todayCell.key, calendarDayKey(today));
      expect(todayCell.future, isFalse);
    });

    test('未来日期留空', () {
      final hm = buildHeatmap(const {}, now: today);
      final last = hm.cells[12];
      final future = last.where((c) => c.future).toList();
      expect(future.length, 6 - todayWeekday);
      expect(future.every((c) => c.count == 0 && c.level == 0), isTrue);
    });

    test('counts 映射到色阶与 max', () {
      final hm = buildHeatmap({dayKeyLocal(today): 6}, now: today);
      final cell = hm.cells[12][todayWeekday];
      expect(cell.count, 6);
      expect(cell.level, 3);
      expect(hm.max, 6);
    });

    test('可以自定义色阶函数（如目标：1/2/3/4+ 篇）', () {
      final hm = buildHeatmap(
        {calendarDayKey(today): 2},
        now: today,
        levelFn: (n) => n > 4 ? 4 : n,
      );
      final cell = hm.cells[12][todayWeekday];
      expect(cell.count, 2);
      expect(cell.level, 2);
    });

    test('凌晨 1 点的活动算前一天（04:00 结算），落在前一天的格子里', () {
      final at1am = DateTime(2026, 10, 16, 1);
      expect(dayKeyLocal(at1am), '2026-10-15');
      final hm = buildHeatmap(
        {dayKeyLocal(at1am): 5},
        now: DateTime(2026, 10, 16, 10),
      );
      final cell = hm.cells
          .expand((c) => c)
          .firstWhere((c) => c.key == '2026-10-15');
      expect(cell.count, 5);
      final next = hm.cells
          .expand((c) => c)
          .firstWhere((c) => c.key == '2026-10-16');
      expect(next.count, 0);
    });

    test('有月份标注', () {
      final hm = buildHeatmap(const {}, now: today);
      expect(hm.monthLabels, isNotEmpty);
      expect(hm.monthLabels.every((m) => m.col >= 0 && m.col < 13), isTrue);
    });

    test('日期与格子的对应关系锁死：最后一列 = 本周，行 = 周几', () {
      final thu = DateTime(2026, 10, 15); // 2026-10-15 周四
      expect(thu.weekday % 7, 4);
      final hm = buildHeatmap({'2026-07-19': 1, '2026-10-15': 2}, now: thu);
      expect(hm.cells[0][0].key, '2026-07-19'); // 13 周前那个周日
      expect(hm.cells[12][4].key, '2026-10-15'); // 本周（最后一列）第 4 行 = 周四
      expect(hm.cells[12][4].count, 2);
      expect(hm.cells[12][5].future, isTrue); // 周五还没到
      // 每一列的 7 格必须是连续 7 天
      for (var c = 0; c < 13; c++) {
        final days = hm.cells[c].map((x) => x.key).toSet();
        expect(days.length, 7, reason: '第 $c 列不是 7 个不同日期');
      }
    });
  });

  group('normalizeActivity（元素级守卫）', () {
    test('丢掉 null / day 非字符串 / counts 非对象，好的照常保留', () {
      final out = normalizeActivity([
        null,
        'x',
        {'day': 5, 'counts': {'speak': 2}},
        {'day': '2026-10-01', 'counts': null},
        {
          'day': '2026-10-02',
          'counts': {'speak': 2, 'bad': 1, 'read': -1},
        },
      ]);
      expect(out.length, 1);
      expect(out.single.day, '2026-10-02');
      expect(out.single.counts, {ActivityCat.speak: 2});
    });

    test('非数组 → 空数组', () {
      expect(
        normalizeActivity({'day': '2026-10-01', 'counts': <String, int>{}}),
        isEmpty,
      );
    });
  });
}
