import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/core/entry_kind.dart';

/// 词条类型这一层的小工具：跨模块都要问「这条是哪一类」，所以行为必须钉住。
void main() {
  group('kindOf / 标签 / 顺序', () {
    test('老数据没有 kind → 当普通单词', () {
      expect(kindOf(), VocabKind.word);
      expect(kindOf(kind: null, word: null), VocabKind.word);
      expect(kindOf(kind: VocabKind.idiom), VocabKind.idiom);
    });

    test('单英文单词被标成语言点 → 仍按单词算（否则会从「本篇」消失）', () {
      expect(isSingleEnglishWord('conglomerate'), isTrue);
      expect(isSingleEnglishWord('take-off'), isTrue);
      expect(isSingleEnglishWord("don't"), isTrue);
      expect(isSingleEnglishWord('take off'), isFalse);
      expect(isSingleEnglishWord('conglomerate 企业集团'), isFalse);
      expect(isSingleEnglishWord('注意 purges 是名词'), isFalse);
      expect(isSingleEnglishWord(''), isFalse);

      expect(kindOf(kind: VocabKind.usage, word: 'conglomerate'), VocabKind.word);
      expect(kindOf(kind: VocabKind.phrase, word: 'reckon'), VocabKind.word);
      expect(kindOf(kind: VocabKind.usage, word: 'conglomerate 企业集团'),
          VocabKind.usage);
      expect(kindOf(kind: VocabKind.phrase, word: 'fall back on'),
          VocabKind.phrase);
      // 没有 word（只传 kind，测试/局部调用）时保持原类型
      expect(kindOf(kind: VocabKind.usage), VocabKind.usage);
    });

    test('标签与顺序是 SSOT（视图直接引用，不许各写一份）', () {
      expect(kindLabel, {
        VocabKind.word: '单词',
        VocabKind.phrase: '词组',
        VocabKind.idiom: '习语',
        VocabKind.usage: '用法',
      });
      expect(kindOrder, [
        VocabKind.word,
        VocabKind.phrase,
        VocabKind.idiom,
        VocabKind.usage,
      ]);
      expect(kindOrder.map((k) => kindLabel[k]).toList(),
          ['单词', '词组', '习语', '用法']);
    });
  });

  group('分类判断', () {
    // 类型要跟词形一致：单个英文单词本来就该是 word（见 kindOf 的兜底）。
    const shape = {
      VocabKind.word: 'test',
      VocabKind.phrase: 'run out',
      VocabKind.idiom: 'take its toll',
      VocabKind.usage: '注意 test 是名词',
    };

    test('isWordEntry / isLangPoint 互斥', () {
      for (final k in kindOrder) {
        final word = shape[k];
        expect(isWordEntry(kind: k, word: word), k == VocabKind.word,
            reason: '$k');
        expect(isLangPoint(kind: k), k != VocabKind.word, reason: '$k');
        expect(isWordEntry(kind: k, word: word) != isLangPoint(kind: k), isTrue);
      }
    });

    test('isStudyable：用法笔记不能背/考；无释义的卡也不能（废卡先去补释义）', () {
      final got = [
        for (final k in kindOrder)
          [k, isStudyable(kind: k, meaning: '义')],
      ];
      expect(got, [
        [VocabKind.word, true],
        [VocabKind.phrase, true],
        [VocabKind.idiom, true],
        [VocabKind.usage, false],
      ]);
      // 无释义：普通单词 / 词组 / 习语都不该进背词 / 考试池
      expect(isStudyable(kind: VocabKind.word, meaning: null), isFalse);
      expect(isStudyable(kind: VocabKind.phrase, meaning: null), isFalse);
      expect(isStudyable(kind: VocabKind.idiom, meaning: null), isFalse);
      // 空串等价于无释义（displayMeaning 也会落到「无释义」）
      expect(isStudyable(kind: VocabKind.word, meaning: ''), isFalse);
    });

    test('inStudyDeck：背单词只收单词，背搭配只收词组/习语，用法两边都不进', () {
      final wordDeck = [
        for (final k in kindOrder)
          [k, inStudyDeck(kind: k, meaning: '义', deck: StudyDeck.word)],
      ];
      expect(wordDeck, [
        [VocabKind.word, true],
        [VocabKind.phrase, false],
        [VocabKind.idiom, false],
        [VocabKind.usage, false],
      ]);
      final collocationDeck = [
        for (final k in kindOrder)
          [k, inStudyDeck(kind: k, meaning: '义', deck: StudyDeck.collocation)],
      ];
      expect(collocationDeck, [
        [VocabKind.word, false],
        [VocabKind.phrase, true],
        [VocabKind.idiom, true],
        [VocabKind.usage, false],
      ]);
    });
  });
}
