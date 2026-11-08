import 'package:dlaoshi_app/core/vocab/learn_step.dart';
import 'package:dlaoshi_app/core/vocab/review.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/vocab_fixture.dart';

VocabItem item({int? passes, String id = 'v1', String word = 'abandon'}) => vocabItem(
      id: id,
      word: word,
      lemma: word,
      meaning: '放弃',
      partOfSpeech: 'v.',
      reviewState: ReviewState(meaningPasses: passes ?? 0),
    );

VocabLibrary lib({int? passes}) => VocabLibrary(items: [
      item(passes: passes),
      item(id: 'v2', word: 'brave'),
    ]);

void main() {
  group('learnStep：学习模式「4 条释义」这一步的判定', () {
    test('点了「看答案」：判不认识，先高亮停留再自动进单词卡', () {
      final out = gradeLearnStep(action: LearnAction.reveal, passes: 3, canQuiz: true);
      expect(out.kind, LearnStepKind.hold);
      expect(out.grade, ReviewGrade.again);
      expect(out.auto, isTrue);
      expect(out.wrong, isFalse);
      expect(out.label, isNotEmpty);
      // 停留时长是个可打断的常量，别写死在 UI 里
      expect(learnRevealHold.inMilliseconds, greaterThan(0));
    });

    test('没看答案、选错：判不认识，停在释义页等「继续」（不自动进卡，且标出选错的那项）', () {
      final out = gradeLearnStep(action: LearnAction.wrong, passes: 0, canQuiz: true);
      expect(out.kind, LearnStepKind.hold);
      expect(out.grade, ReviewGrade.again);
      expect(out.auto, isFalse);
      expect(out.wrong, isTrue);
      expect(out.label, isNotEmpty);
    });

    test('没看答案、选对：首次判模糊（防蒙对），直接进单词卡', () {
      final out = gradeLearnStep(action: LearnAction.correct, passes: 0, canQuiz: true);
      expect(out.kind, LearnStepKind.card);
      expect(out.grade, ReviewGrade.hard);
      expect(out.pass, isTrue);
      expect(out.label, isNotEmpty);
    });

    test('没看答案、第二次选对：判认识', () {
      expect(gradeLearnStep(action: LearnAction.correct, passes: 1, canQuiz: true).grade, ReviewGrade.good);
      expect(gradeLearnStep(action: LearnAction.correct, passes: 5, canQuiz: true).grade, ReviewGrade.good);
    });

    test('词库不够 4 个选项：不做判定，退回普通卡流程', () {
      for (final action in LearnAction.values) {
        final out = gradeLearnStep(action: action, passes: 2, canQuiz: false);
        expect(out.kind, LearnStepKind.fallback);
        expect(out.grade, isNull);
      }
    });
  });

  group('learnStep：选对次数怎么记', () {
    test('脏值一律按「没选对过」算', () {
      expect(normPasses(null), 0);
      expect(normPasses(-1), 0);
      expect(normPasses(0), 0);
      expect(normPasses(4), 4);
    });

    test('选对 +1；判不认识归零（不再享受上次的信用）', () {
      expect(nextMeaningPasses(0, true), 1);
      expect(nextMeaningPasses(2, true), 3);
      expect(nextMeaningPasses(2, false), 0);
    });

    test('从词条上读：老数据（没这个字段）按 0', () {
      expect(meaningPassesOf(item()), 0);
      expect(meaningPassesOf(item(passes: 3)), 3);
    });
  });

  group('learnStep：把次数写回词库', () {
    test('选对写进 reviewState.meaningPasses，其它条目保持原引用', () {
      final before = lib();
      final other = before.items[1];
      final after = recordLearnPass(before, 'v1', true, DateTime.parse('2026-05-05T00:00:00.000Z'));
      expect(after.items[0].reviewState.meaningPasses, 1);
      expect(after.items[0].updatedAt, '2026-05-05T00:00:00.000Z');
      expect(identical(after.items[1], other), isTrue);
    });

    test('判不认识归零', () {
      final after = recordLearnPass(lib(passes: 3), 'v1', false);
      expect(after.items[0].reviewState.meaningPasses, 0);
    });

    test('次数没变（比如 0 → 0）就原样返回，别白写一次词库', () {
      final before = lib();
      expect(identical(recordLearnPass(before, 'v1', false), before), isTrue);
    });

    test('找不到这个词就原样返回', () {
      final before = lib();
      expect(identical(recordLearnPass(before, 'nope', true), before), isTrue);
    });

    test('再次选对累加（第二次起才判认识）', () {
      final once = recordLearnPass(lib(), 'v1', true);
      final twice = recordLearnPass(once, 'v1', true);
      expect(twice.items[0].reviewState.meaningPasses, 2);
      expect(
        gradeLearnStep(action: LearnAction.correct, passes: meaningPassesOf(twice.items[0]), canQuiz: true).grade,
        ReviewGrade.good,
      );
    });
  });
}
