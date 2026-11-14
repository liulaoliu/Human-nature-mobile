import 'package:dlaoshi_app/core/quiz.dart';
import 'package:dlaoshi_app/core/quiz_pool.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/vocab_fixture.dart';

VocabItem item({
  required String word,
  String? meaning = '释义',
  VocabStatus status = VocabStatus.queried,
  VocabSource? source,
  VocabItemKind? kind,
  ReviewState reviewState = defaultReviewState,
  List<String> usage = const [],
}) =>
    vocabItem(
      id: 'vocab:$word',
      word: word,
      lemma: word,
      kind: kind,
      meaning: meaning,
      status: status,
      source: source,
      reviewState: reviewState,
      usage: usage,
      definition: 'a definition of $word',
    );

VocabSource src(String fileName) => VocabSource(articleId: 'a1', fileName: fileName);

void main() {
  group('quizStudyableItems：能不能考', () {
    test('没释义的废卡不进池子', () {
      final pool = quizStudyableItems([
        item(word: 'run'),
        item(word: 'sharp', meaning: ''),
      ]);
      expect(pool.map((e) => e.word), ['run']);
    });

    test('用法笔记不进池子', () {
      final pool = quizStudyableItems([
        item(word: 'run'),
        item(word: 'keep up with', kind: VocabItemKind.usage),
      ]);
      expect(pool.map((e) => e.word), ['run']);
    });

    test('词组、习语照旧能考（只要标了类型且有释义）', () {
      final pool = quizStudyableItems([
        item(word: 'keep up with', kind: VocabItemKind.phrase),
        item(word: 'at the end of the day', kind: VocabItemKind.idiom),
      ]);
      expect(pool.length, 2);
    });
  });

  group('quizPool：范围', () {
    final all = [
      item(word: 'run', source: src('A')),
      item(word: 'sharp', source: src('B')),
      item(
        word: 'fade',
        reviewState: const ReviewState(lapses: 2, due: '2020-01-01T00:00:00.000Z'),
      ),
      item(word: 'mastered', status: VocabStatus.mastered),
    ];

    test('全库：一条不落', () {
      expect(quizPool(all, QuizScope.all, const QuizPoolContext()).length, 4);
    });

    test('本篇：只认 source.fileName 对得上的，加上正文词形', () {
      final pool = quizPool(
        all,
        QuizScope.article,
        const QuizPoolContext(articleIdentity: 'A', docLemmas: {'mastered'}),
      );
      expect(pool.map((e) => e.word).toSet(), {'run', 'mastered'});
    });

    test('本篇：articleId 对得上也算（老数据没有 fileName）', () {
      final withId = [
        vocabItem(id: 'v1', word: 'run', lemma: 'run', source: const VocabSource(articleId: 'a1')),
      ];
      final pool = quizPool(
        withId,
        QuizScope.article,
        const QuizPoolContext(articleIdentity: 'a1'),
      );
      expect(pool.length, 1);
    });

    test('未掌握：mastered 之外全算', () {
      expect(quizPool(all, QuizScope.unmastered, const QuizPoolContext()).length, 3);
    });

    test('到期：只认 isDue', () {
      final pool = quizPool(
        all,
        QuizScope.due,
        const QuizPoolContext(),
        now: DateTime.utc(2026, 1, 1),
      );
      expect(pool.map((e) => e.word), ['fade']);
    });

    test('常错：lapses > 0', () {
      final pool = quizPool(all, QuizScope.lapses, const QuizPoolContext());
      expect(pool.map((e) => e.word), ['fade']);
    });
  });

  group('buildQuizSet：出卷', () {
    final items = [
      item(word: 'run'),
      item(word: 'sharp'),
      item(word: 'fade'),
    ];

    test('每个词最多一题', () {
      final set = buildQuizSet(items, [QuizKind.spell, QuizKind.meaning]);
      expect(set.length, 3);
      expect(set.map((q) => q.itemId).toSet().length, 3);
    });

    test('题型数据不够时会换下一个题型', () {
      // 这三个词都没有 examples / usage，cloze 出不来，只能落到 spell。
      final set = buildQuizSet(items, [QuizKind.cloze, QuizKind.usage, QuizKind.spell]);
      expect(set.length, 3);
      expect(set.every((q) => q.kind == QuizKind.spell), isTrue);
    });

    test('unique 关掉：同词多题型都出', () {
      final set = buildQuizSet(
        items,
        [QuizKind.spell, QuizKind.meaning, QuizKind.choice],
        unique: false,
      );
      expect(set.length, greaterThan(3));
    });

    test('词库空：空卷', () {
      expect(buildQuizSet(const [], [QuizKind.spell]), isEmpty);
    });

    test('固定随机源：两次结果一致', () {
      double Function() seed() {
        var s = 7;
        return () {
          s = (s * 1103515245 + 12345) & 0x7FFFFFFF;
          return s / 0x7FFFFFFF;
        };
      }

      final a = buildQuizSet(items, [QuizKind.spell], rnd: seed());
      final b = buildQuizSet(items, [QuizKind.spell], rnd: seed());
      expect(a.map((q) => q.itemId), b.map((q) => q.itemId));
    });
  });

  group('limitQuizSet：截断', () {
    final set = buildQuizSet(
      [for (var i = 0; i < 8; i++) item(word: 'word$i')],
      [QuizKind.spell],
    );

    test('截到 limit', () {
      expect(limitQuizSet(set, 5).length, 5);
    });

    test('limit <= 0 不限', () {
      expect(limitQuizSet(set, 0).length, 8);
    });

    test('题比 limit 少：原样返回', () {
      expect(limitQuizSet(set, 30).length, 8);
    });
  });

  group('parseQuizScope：宽容解析', () {
    test('枚举名 / 枚举值都能认', () {
      expect(parseQuizScope('due'), QuizScope.due);
      expect(parseQuizScope(QuizScope.lapses), QuizScope.lapses);
    });

    test('坏值回本篇（拷打默认只看本篇）', () {
      expect(parseQuizScope('nope'), QuizScope.article);
      expect(parseQuizScope(null), QuizScope.article);
      expect(parseQuizScope(3), QuizScope.article);
    });
  });

  group('整卷考试的题量与默认题型', () {
    test('题量档位：5/10/20/30/不限', () {
      expect(quizLimitOptions, [5, 10, 20, 30, 0]);
      expect(defaultQuizLimit, 20);
      expect(quizLimitLabel(0), '不限');
      expect(quizLimitLabel(20), '20 题');
    });

    test('宽容解析：坏值回 20；0 保留为不限', () {
      expect(normalizeQuizLimit(10), 10);
      expect(normalizeQuizLimit(0), 0);
      expect(normalizeQuizLimit('30'), 30);
      expect(normalizeQuizLimit(7), 20);
      expect(normalizeQuizLimit(null), 20);
    });

    test('默认词级三题型 / 文章级五题型（不含 grammar）', () {
      expect(defaultQuizVocabKinds, [QuizKind.spell, QuizKind.cloze, QuizKind.usage]);
      expect(defaultQuizArticleKinds, [
        QuizKind.translate,
        QuizKind.translate2,
        QuizKind.functionWord,
        QuizKind.ordering,
        QuizKind.phraseBlank,
      ]);
      expect(defaultQuizArticleKinds.contains(QuizKind.grammar), isFalse);
    });
  });
}
