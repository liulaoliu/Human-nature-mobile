// 考试设置：默认值 / 坏数据回默认 / 序列化往返 / 自动切题与鞭打的判定。
import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/core/quiz.dart' show QuizKind;
import 'package:dlaoshi_app/core/quiz_pool.dart'
    show QuizMode, QuizScope, defaultQuizLimit;
import 'package:dlaoshi_app/core/quiz_settings.dart';

void main() {
  group('默认值', () {
    test('一份没存过的设置：词级 / 本篇 / 20 题 / 不自动切 / 答完朗读 / 不鞭打', () {
      const s = QuizSettings();
      expect(s.mode, QuizMode.vocab);
      expect(s.scope, QuizScope.article);
      expect(s.limit, defaultQuizLimit);
      expect(s.auto, isFalse);
      expect(s.speakAfter, isTrue);
      expect(s.loopWrong, isFalse);
      expect(s.unique, isTrue);
      expect(s.vocabKinds, [QuizKind.spell, QuizKind.cloze, QuizKind.usage]);
    });

    test('kindsForMode 跟着模式走', () {
      const s = QuizSettings();
      expect(s.kindsForMode, s.vocabKinds);
      expect(s.copyWith(mode: QuizMode.article).kindsForMode, s.articleKinds);
    });

    test('withMode 只重置进入那个模式的题型，另一套留着', () {
      final s = const QuizSettings()
          .copyWith(vocabKinds: const [QuizKind.ear])
          .withMode(QuizMode.article);
      expect(s.vocabKinds, const [QuizKind.ear]);
      expect(s.articleKinds, const [
        QuizKind.translate,
        QuizKind.translate2,
        QuizKind.functionWord,
        QuizKind.ordering,
        QuizKind.phraseBlank,
      ]);
    });

    test('withMode 同模式是恒等（不白改一次）', () {
      const s = QuizSettings();
      expect(identical(s.withMode(QuizMode.vocab), s), isTrue);
    });
  });

  group('坏数据回默认', () {
    test('不是 Map → 整套默认', () {
      for (final bad in <Object?>[null, '', 42, <String>['x']]) {
        expect(parseQuizSettings(bad).limit, defaultQuizLimit);
        expect(parseQuizSettings(bad).mode, QuizMode.vocab);
      }
    });

    test('题型表混进非法值只丢那一个', () {
      final s = parseQuizSettings(<String, Object?>{
        'vocabKinds': ['spell', 'not-a-kind', 'cloze'],
      });
      expect(s.vocabKinds, [QuizKind.spell, QuizKind.cloze]);
    });

    test('题型表整表非法 / 空表 → 回默认（空表出不了卷）', () {
      expect(
        parseQuizSettings(<String, Object?>{'vocabKinds': <String>[]}).vocabKinds,
        isNotEmpty,
      );
      expect(
        parseQuizSettings(<String, Object?>{
          'vocabKinds': ['nope'],
        }).vocabKinds,
        isNotEmpty,
      );
    });

    test('文章题型表里塞词级题型会被丢掉', () {
      final s = parseQuizSettings(<String, Object?>{
        'articleKinds': ['translate', 'spell'],
      });
      expect(s.articleKinds, [QuizKind.translate]);
    });

    test('题量不在档位里回 20', () {
      expect(parseQuizSettings(<String, Object?>{'limit': 7}).limit, 20);
      expect(parseQuizSettings(<String, Object?>{'limit': 0}).limit, 0);
      expect(parseQuizSettings(<String, Object?>{'limit': 30}).limit, 30);
    });

    test('布尔值认 bool 也认字符串', () {
      expect(parseQuizSettings(<String, Object?>{'auto': true}).auto, isTrue);
      expect(parseQuizSettings(<String, Object?>{'auto': 'true'}).auto, isTrue);
      expect(parseQuizSettings(<String, Object?>{'auto': 'false'}).auto, isFalse);
      expect(parseQuizSettings(<String, Object?>{'auto': 'x'}).auto, isFalse);
    });

    test('范围认不出回本篇', () {
      expect(parseQuizSettings(<String, Object?>{'scope': 'zzz'}).scope,
          QuizScope.article);
      expect(parseQuizSettings(<String, Object?>{'scope': 'due'}).scope,
          QuizScope.due);
    });
  });

  group('序列化往返', () {
    test('存了再读回来一模一样', () {
      final s = const QuizSettings().copyWith(
        mode: QuizMode.article,
        scope: QuizScope.due,
        limit: 30,
        auto: true,
        speakAfter: false,
        loopWrong: true,
        unique: false,
      );
      final back = parseQuizSettings(quizSettingsToJson(s));
      expect(back.mode, s.mode);
      expect(back.scope, s.scope);
      expect(back.limit, s.limit);
      expect(back.auto, s.auto);
      expect(back.speakAfter, s.speakAfter);
      expect(back.loopWrong, s.loopWrong);
      expect(back.unique, s.unique);
      expect(back.vocabKinds, s.vocabKinds);
      expect(back.articleKinds, s.articleKinds);
    });
  });

  group('自动切题', () {
    test('没开就不切', () {
      expect(
        quizAutoAdvanceDelay(auto: false, correct: true, spellingMiss: false),
        isNull,
      );
    });

    test('答对快切、答错慢切', () {
      expect(
        quizAutoAdvanceDelay(auto: true, correct: true, spellingMiss: false),
        const Duration(milliseconds: 650),
      );
      expect(
        quizAutoAdvanceDelay(auto: true, correct: false, spellingMiss: false),
        const Duration(milliseconds: 1400),
      );
    });

    test('拼写错要先确认，不自动切', () {
      expect(
        quizAutoAdvanceDelay(auto: true, correct: false, spellingMiss: true),
        isNull,
      );
    });
  });

  group('反复鞭打', () {
    test('开了 + 有错题 + 没到上限 → 重练', () {
      expect(
        quizShouldLoopWrong(loopWrong: true, drill: false, wrong: 2, round: 1),
        isTrue,
      );
    });

    test('没开 / 没错题 / 到上限 / 是拷打 → 不重练', () {
      expect(
        quizShouldLoopWrong(loopWrong: false, drill: false, wrong: 2, round: 1),
        isFalse,
      );
      expect(
        quizShouldLoopWrong(loopWrong: true, drill: false, wrong: 0, round: 1),
        isFalse,
      );
      expect(
        quizShouldLoopWrong(
          loopWrong: true,
          drill: false,
          wrong: 1,
          round: maxQuizDrillRounds,
        ),
        isFalse,
      );
      expect(
        quizShouldLoopWrong(loopWrong: true, drill: true, wrong: 1, round: 1),
        isFalse,
      );
    });
  });

  group('答完朗读', () {
    test('没开就不读', () {
      expect(
        quizSpeakText(
          speakAfter: false,
          kind: QuizKind.spell,
          word: 'alpha',
          answer: 'alpha',
        ),
        isNull,
      );
    });

    test('看词选义读单词，其余读答案', () {
      expect(
        quizSpeakText(
          speakAfter: true,
          kind: QuizKind.meaning,
          word: 'alpha',
          answer: '第一个',
        ),
        'alpha',
      );
      expect(
        quizSpeakText(
          speakAfter: true,
          kind: QuizKind.spell,
          word: 'alpha',
          answer: 'alpha',
        ),
        'alpha',
      );
    });

    test('语法标记不读（答案是可数 / 不可数这类中文标签）', () {
      expect(
        quizSpeakText(
          speakAfter: true,
          kind: QuizKind.mark,
          word: 'water',
          answer: '不可数',
        ),
        isNull,
      );
    });

    test('答案为空不读', () {
      expect(
        quizSpeakText(
          speakAfter: true,
          kind: QuizKind.spell,
          word: 'alpha',
          answer: '   ',
        ),
        isNull,
      );
    });
  });

  group('题型归属', () {
    test('词级 / 文章级各认自己的', () {
      expect(quizKindAllowed(QuizKind.spell, QuizMode.vocab), isTrue);
      expect(quizKindAllowed(QuizKind.spell, QuizMode.article), isFalse);
      expect(quizKindAllowed(QuizKind.translate, QuizMode.article), isTrue);
      expect(quizKindAllowed(QuizKind.translate, QuizMode.vocab), isFalse);
    });
  });
}
