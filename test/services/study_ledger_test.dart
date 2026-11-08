import 'package:dlaoshi_app/core/activity/activity.dart';
import 'package:dlaoshi_app/core/learning.dart';
import 'package:dlaoshi_app/services/study_ledger.dart';
import 'package:flutter_test/flutter_test.dart';

/// 固定「现在」：2026-03-10 12:00（逻辑日就是 2026-03-10）。
final DateTime _now = DateTime(2026, 3, 10, 12);

void main() {
  test('逻辑日按 dayKeyLocal 算（凌晨 1 点算前一天）', () {
    final ledger = StudyLedger(now: DateTime(2026, 3, 10, 1));
    // dayRolloverHour = 4，凌晨 1 点减 4 小时回到 3-09
    expect(ledger.today, '2026-03-09');
  });

  test('markStudied：同一天不重复记，保留首次顺序', () {
    final ledger = StudyLedger(now: _now);
    ledger.markStudied('b');
    ledger.markStudied('a');
    ledger.markStudied('b');
    expect(ledger.studiedCount, 2);
    final day = ledger.data.studiedDays.single;
    expect(day.day, '2026-03-10');
    expect(day.ids, ['b', 'a']);
  });

  test('markStudied：空 id 忽略', () {
    final ledger = StudyLedger(now: _now);
    ledger.markStudied('');
    expect(ledger.studiedCount, 0);
    expect(ledger.data.studiedDays, isEmpty);
  });

  test('markStudied：已有别的日期时新起一天，旧的原样保留', () {
    final ledger = StudyLedger(
      data: emptyLearning()
        ..studiedDays = [const StudiedDay(day: '2026-03-09', ids: ['x'])],
      now: _now,
    );
    ledger.markStudied('a');
    expect(ledger.data.studiedDays.length, 2);
    expect(ledger.data.studiedDays.first.ids, ['x']);
    expect(ledger.data.studiedDays.last.ids, ['a']);
    expect(ledger.studiedCount, 1);
  });

  test('markStudied：换新对象，不原地改旧的那条 StudiedDay', () {
    final base = emptyLearning()
      ..studiedDays = [const StudiedDay(day: '2026-03-10', ids: ['x'])];
    final oldIds = base.studiedDays.single.ids;
    final ledger = StudyLedger(data: base, now: _now);
    ledger.markStudied('y');
    // 旧的 ids 列表没被原地改
    expect(oldIds, ['x']);
    // 新的那条是另一个对象，内容是旧的 + 新的
    expect(ledger.data.studiedDays.single.ids, ['x', 'y']);
    expect(identical(ledger.data.studiedDays.single.ids, oldIds), isFalse);
  });

  test('recordActivity：累加到同一天，不覆盖', () {
    final ledger = StudyLedger(now: _now);
    ledger.recordActivity(ActivityCat.vocab);
    ledger.recordActivity(ActivityCat.vocab, 2);
    ledger.recordActivity(ActivityCat.read);
    expect(ledger.vocabCount, 3);
    final day = ledger.data.activity.single;
    expect(day.countOf(ActivityCat.read), 1);
    expect(day.countOf(ActivityCat.speak), 0);
  });

  test('recordActivity：n <= 0 不记', () {
    final ledger = StudyLedger(now: _now);
    ledger.recordActivity(ActivityCat.vocab, 0);
    ledger.recordActivity(ActivityCat.vocab, -5);
    expect(ledger.data.activity, isEmpty);
    expect(ledger.dirty, isFalse);
  });

  test('recordActivity：已有别的日期时新起一天', () {
    final ledger = StudyLedger(
      data: emptyLearning()
        ..activity = [
          const DayActivity(day: '2026-03-09', counts: {ActivityCat.read: 4}),
        ],
      now: _now,
    );
    ledger.recordActivity(ActivityCat.vocab);
    expect(ledger.data.activity.length, 2);
    expect(ledger.data.activity.first.countOf(ActivityCat.read), 4);
    expect(ledger.vocabCount, 1);
  });

  test('dirty：什么都没记就是 false', () {
    final ledger = StudyLedger(now: _now);
    expect(ledger.dirty, isFalse);
    ledger.markStudied('a');
    expect(ledger.dirty, isTrue);
  });

  test('不传 data 时自带一份空记录', () {
    final ledger = StudyLedger(now: _now);
    expect(ledger.data.studiedDays, isEmpty);
    expect(ledger.data.activity, isEmpty);
  });
}
