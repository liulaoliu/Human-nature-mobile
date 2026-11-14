// 拷打预习卡：由题目反查词条，不另写筛选规则。
import 'package:dlaoshi_app/core/quiz.dart';
import 'package:dlaoshi_app/core/quiz_drill.dart';
import 'package:dlaoshi_app/core/quiz_warmup.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/vocab_fixture.dart';

QuizQuestion _q(String itemId, String word, {QuizKind kind = QuizKind.spell}) =>
    QuizQuestion(
      id: '$itemId:${kind.name}',
      itemId: itemId,
      lemma: word,
      kind: kind,
      word: word,
      prompt: '$word 的意思',
      answer: word,
      accept: <String>[word],
    );

void main() {
  group('buildWarmupCards', () {
    test('题目是唯一事实来源：按 itemId 去重、保序', () {
      final items = <VocabItem>[
        vocabItem(id: 'v1', word: 'alpha', meaning: '甲'),
        vocabItem(id: 'v2', word: 'beta', meaning: '乙'),
      ];
      final qs = <QuizQuestion>[
        _q('v1', 'alpha'),
        _q('v1', 'alpha', kind: QuizKind.meaning), // 同词第二题，不重复出卡
        _q('v2', 'beta'),
      ];
      final cards = buildWarmupCards(items, qs, QuizDrillKind.memory);
      expect(cards.map((c) => c.id), <String>['v1', 'v2']);
      expect(cards.first.word, 'alpha');
      expect(cards.first.meaning, '甲');
    });

    test('查不到词条的题目（文章级 itemId 是句子 id）跳过', () {
      final cards = buildWarmupCards(
        <VocabItem>[vocabItem(id: 'v1', word: 'alpha')],
        <QuizQuestion>[_q('s1', 'whatever'), _q('v1', 'alpha')],
        QuizDrillKind.memory,
      );
      expect(cards.map((c) => c.id), <String>['v1']);
    });

    test('记忆档：给一条非空例句，不摊词块', () {
      final items = <VocabItem>[
        vocabItem(
          id: 'v1',
          word: 'alpha',
          phonetic: '/ˈælfə/',
          examples: const <VocabExample>[
            VocabExample(text: ''),
            VocabExample(text: 'Alpha is the first letter.'),
          ],
          phrases: const <String>['alpha beta'],
        ),
      ];
      final card = buildWarmupCards(
        items,
        <QuizQuestion>[_q('v1', 'alpha')],
        QuizDrillKind.memory,
      ).single;
      expect(card.phonetic, '/ˈælfə/');
      expect(card.example, 'Alpha is the first letter.');
      expect(card.chunks, isEmpty);
    });

    test('词块档：词组 / 习语 / 用法合并去空、最多 6 条，不给例句', () {
      final items = <VocabItem>[
        vocabItem(
          id: 'v1',
          word: 'alpha',
          phrases: const <String>['keep up', ''],
          idioms: const <String>['once in a blue moon'],
          usage: const <String>['alpha and omega'],
          examples: const <VocabExample>[VocabExample(text: 'Alpha example.')],
        ),
      ];
      final card = buildWarmupCards(
        items,
        <QuizQuestion>[_q('v1', 'alpha')],
        QuizDrillKind.chunk,
      ).single;
      expect(card.chunks, <String>[
        'keep up',
        'once in a blue moon',
        'alpha and omega',
      ]);
      expect(card.example, isNull);
    });

    test('词块档最多 6 条', () {
      final items = <VocabItem>[
        vocabItem(
          id: 'v1',
          word: 'alpha',
          phrases: <String>[for (var i = 0; i < 10; i++) 'chunk $i'],
        ),
      ];
      final card = buildWarmupCards(
        items,
        <QuizQuestion>[_q('v1', 'alpha')],
        QuizDrillKind.chunk,
      ).single;
      expect(card.chunks.length, 6);
    });

    test('没有题目就没有卡', () {
      expect(
        buildWarmupCards(
          <VocabItem>[vocabItem(id: 'v1', word: 'alpha')],
          const <QuizQuestion>[],
          QuizDrillKind.memory,
        ),
        isEmpty,
      );
    });
  });

  group('预习页文案', () {
    test('标题按档位分', () {
      expect(warmupTitle(QuizDrillKind.chunk), contains('词块拷打'));
      expect(warmupTitle(QuizDrillKind.memory), contains('记忆拷打'));
    });

    test('提示按档位分且都不空', () {
      expect(warmupHint(QuizDrillKind.chunk), contains('词块'));
      expect(warmupHint(QuizDrillKind.memory), contains('释义'));
    });
  });
}
