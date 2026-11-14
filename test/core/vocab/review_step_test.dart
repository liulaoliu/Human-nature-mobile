import 'package:dlaoshi_app/core/vocab/review.dart';
import 'package:dlaoshi_app/core/vocab/review_step.dart';
import 'package:flutter_test/flutter_test.dart';

/// 复习模式三键的口径（用户 2026-11-14 定，App 刻意偏离 Web）：
/// **任何一档按下去都先摊卡停住、不写库**，等用户在卡上选出口时才落一次库。
void main() {
  group('planReviewGrade：三键一律先摊卡停住', () {
    for (final grade in ReviewGrade.values) {
      test('$grade：不写库、不推进、摊卡', () {
        final p = planReviewGrade(grade);
        expect(p.commit, isNull);
        expect(p.advance, isFalse);
        expect(p.showCard, isTrue);
      });
    }
  });

  group('reviewExitAllowsMistake：哪几档允许反悔', () {
    test('认识 / 模糊可以点「记错了」', () {
      expect(reviewExitAllowsMistake(ReviewGrade.good), isTrue);
      expect(reviewExitAllowsMistake(ReviewGrade.hard), isTrue);
      expect(reviewExitAllowsMistake(ReviewGrade.easy), isTrue);
    });

    test('忘记了只给「下一词」', () {
      expect(reviewExitAllowsMistake(ReviewGrade.again), isFalse);
    });
  });

  group('planReviewExit：摊卡之后的两个出口', () {
    test('认识 → 下一词：写 good 并推进', () {
      final p = planReviewExit(ReviewGrade.good, ReviewExitChoice.next);
      expect(p.commit, ReviewGrade.good);
      expect(p.advance, isTrue);
      expect(p.showCard, isFalse);
    });

    test('模糊 → 下一词：写 hard 并推进', () {
      final p = planReviewExit(ReviewGrade.hard, ReviewExitChoice.next);
      expect(p.commit, ReviewGrade.hard);
      expect(p.advance, isTrue);
    });

    test('忘记了 → 下一词：写 again 并推进', () {
      final p = planReviewExit(ReviewGrade.again, ReviewExitChoice.next);
      expect(p.commit, ReviewGrade.again);
      expect(p.advance, isTrue);
    });

    test('任何档 → 记错了：改成 again，继续停在卡上', () {
      for (final grade in ReviewGrade.values) {
        final p = planReviewExit(grade, ReviewExitChoice.missed);
        expect(p.commit, ReviewGrade.again);
        expect(p.advance, isFalse);
        expect(p.showCard, isTrue);
      }
    });

    test('「认识 → 记错了」只落一次 again（不双写 good）', () {
      expect(planReviewGrade(ReviewGrade.good).commit, isNull);
      expect(
        planReviewExit(ReviewGrade.good, ReviewExitChoice.missed).commit,
        ReviewGrade.again,
      );
    });
  });

  group('planReviewFuzzyChoice：旧名兼容', () {
    test('下一词 = hard 推进；记错了 = again 停卡', () {
      expect(planReviewFuzzyChoice(ReviewExitChoice.next).commit, ReviewGrade.hard);
      expect(planReviewFuzzyChoice(ReviewExitChoice.next).advance, isTrue);
      expect(planReviewFuzzyChoice(ReviewExitChoice.missed).commit, ReviewGrade.again);
      expect(planReviewFuzzyChoice(ReviewExitChoice.missed).advance, isFalse);
    });
  });
}
