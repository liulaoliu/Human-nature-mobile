import 'package:dlaoshi_app/core/vocab/extra.dart';
import 'package:dlaoshi_app/core/vocab/review.dart';
import 'package:flutter_test/flutter_test.dart';

/// 加练账本：忘记无上限地重排、模糊/认识收尾、重练每轮只发起一次。
/// 这组规则决定「一轮什么时候结束」，改了要同步 docs/TESTING.md。
void main() {
  group('beginExtraRound：新一轮的出场记账', () {
    test('队列里每出现一次记 1 次；重练标记为未用', () {
      final round = beginExtraRound(['a', 'b', 'a']);
      expect(round.appearances, {'a': 2, 'b': 1});
      expect(round.retried, isFalse);
      expect(emptyExtraRound().appearances, isEmpty);
      expect(emptyExtraRound().retried, isFalse);
    });
  });

  group('planExtra：忘记一直追加，模糊/认识收尾', () {
    test('连续评「忘记了」不封顶：每次追加，出场数一直涨', () {
      var round = beginExtraRound(['w1']);
      for (var n = 2; n <= 8; n++) {
        final d = planExtra(round, 'w1', ReviewGrade.again);
        expect(d.append, isTrue);
        expect(d.round.appearances['w1'], n);
        round = d.round;
      }
    });

    test('「模糊」是收尾条件：不再追加，也不动账本', () {
      final round = beginExtraRound(['w1']);
      final d = planExtra(round, 'w1', ReviewGrade.hard);
      expect(d.append, isFalse);
      expect(identical(d.round, round), isTrue);
      expect(d.round.appearances['w1'], 1);
    });

    test('认识 / 简单同样不追加', () {
      final round = beginExtraRound(['w1']);
      for (final g in [ReviewGrade.good, ReviewGrade.easy]) {
        final d = planExtra(round, 'w1', g);
        expect(d.append, isFalse);
        expect(identical(d.round, round), isTrue);
      }
    });

    test('没登记过的卡也能算（按 0 次出场起步）', () {
      final d = planExtra(emptyExtraRound(), 'x', ReviewGrade.again);
      expect(d.append, isTrue);
      expect(d.round.appearances['x'], 1);
    });
  });

  group('planRetryForgot：重练忘记的', () {
    test('忘记过的词全部进重练（不按旧上限剔除），去重并记一次出场', () {
      final round = beginExtraRound(['w1', 'w2']);
      final d = planRetryForgot(round, ['w1', 'w2', 'w1']);
      expect(d.blocked, isFalse);
      expect(d.ids, ['w1', 'w2']);
      expect(d.round.appearances['w1'], 2);
      expect(d.round.appearances['w2'], 2);
      expect(d.round.retried, isTrue);
    });

    test('每轮只发起一次', () {
      final first = planRetryForgot(beginExtraRound(['w1']), ['w1']);
      final second = planRetryForgot(first.round, ['w1']);
      expect(second.blocked, isTrue);
      expect(second.ids, isEmpty);
      expect(identical(second.round, first.round), isTrue);
    });
  });
}
