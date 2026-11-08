import 'package:dlaoshi_app/core/vocab/review.dart';
import 'package:dlaoshi_app/core/vocab/review_step.dart';
import 'package:flutter_test/flutter_test.dart';

/// 复习模式三键的落库口径：认识直接推进、模糊先不写库（等用户看过释义再决定）、
/// 忘记立刻判不认识并停卡。这里只测「按下去之后做什么」，不测排期算法（在 review_test）。
void main() {
  group('planReviewGrade：三键怎么落库', () {
    test('认识：写 good 并直接换下一张，不摊卡', () {
      final p = planReviewGrade(ReviewGrade.good);
      expect(p.commit, ReviewGrade.good);
      expect(p.advance, isTrue);
      expect(p.showCard, isFalse);
    });

    test('easy 也是直接推进（保留 SM-2 的第四档）', () {
      final p = planReviewGrade(ReviewGrade.easy);
      expect(p.commit, ReviewGrade.easy);
      expect(p.advance, isTrue);
      expect(p.showCard, isFalse);
    });

    test('模糊：先不写库、不推进，只摊开单词卡等用户选', () {
      final p = planReviewGrade(ReviewGrade.hard);
      expect(p.commit, isNull);
      expect(p.advance, isFalse);
      expect(p.showCard, isTrue);
    });

    test('忘记了：立刻判不认识（again），停在卡上让用户看一眼答案', () {
      final p = planReviewGrade(ReviewGrade.again);
      expect(p.commit, ReviewGrade.again);
      expect(p.advance, isFalse);
      expect(p.showCard, isTrue);
    });
  });

  group('planReviewFuzzyChoice：模糊之后的两个出口', () {
    test('「下一词」= 认下模糊：写 hard 并推进', () {
      final p = planReviewFuzzyChoice(ReviewFuzzyChoice.next);
      expect(p.commit, ReviewGrade.hard);
      expect(p.advance, isTrue);
      expect(p.showCard, isFalse);
    });

    test('「记错了」= 改成不认识：写 again，继续停在卡上看答案', () {
      final p = planReviewFuzzyChoice(ReviewFuzzyChoice.missed);
      expect(p.commit, ReviewGrade.again);
      expect(p.advance, isFalse);
      expect(p.showCard, isTrue);
    });

    test('两个出口一次只写一次库（不会 hard → again 连着写）', () {
      expect(planReviewGrade(ReviewGrade.hard).commit, isNull);
      expect(planReviewFuzzyChoice(ReviewFuzzyChoice.missed).commit, ReviewGrade.again);
    });
  });
}
