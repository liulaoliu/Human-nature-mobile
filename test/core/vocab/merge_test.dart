import 'package:dlaoshi_app/core/vocab/library.dart';
import 'package:dlaoshi_app/core/vocab/merge.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/vocab_fixture.dart';

final now = DateTime.parse('2026-10-02T00:00:00.000Z');

VocabLibrary one(VocabItem item) => createLibrary().copyWith(items: [item]);

VocabItem runItem({List<VocabExample> examples = const [], VocabSource? source}) =>
    vocabItem(id: 'vocab:run', word: 'run', lemma: 'run', examples: examples, source: source);

void main() {
  group('applyExamples', () {
    test('按 lemma / 词形并入例句，并去重', () {
      var lib = one(runItem());
      lib = applyExamples(lib, [
        (
          word: 'running',
          examples: [
            (text: 'I run every day.', translation: '我每天跑步。'),
            (text: 'I run every day.', translation: '重复'),
          ],
        ),
      ], now);
      expect(lib.items[0].examples.where((e) => e.text == 'I run every day.'), hasLength(1));
    });

    test('例句最多保留 6 条（避免反复查词越堆越多）', () {
      var lib = one(runItem(examples: const [VocabExample(text: 'run', origin: VocabExampleOrigin.article)]));
      for (var i = 0; i < 10; i++) {
        lib = applyExamples(lib, [
          (word: 'run', examples: [(text: 'He runs $i.', translation: null)]),
        ], now);
      }
      expect(lib.items[0].examples.length, lessThanOrEqualTo(6));
      // 最早的那条（来源句）保留
      expect(lib.items[0].examples.map((e) => e.text), contains('run'));
    });

    test('标记例句来源：ai / tatoeba', () {
      var lib = one(runItem());
      lib = applyExamples(lib, [
        (word: 'run', examples: [(text: 'Friendly words mitigate fury.', translation: null)]),
      ], now, VocabExampleOrigin.tatoeba);
      expect(
        lib.items[0].examples.firstWhere((e) => e.text.startsWith('Friendly')).origin,
        VocabExampleOrigin.tatoeba,
      );
      lib = applyExamples(lib, [
        (word: 'run', examples: [(text: 'I run daily.', translation: '我每天跑。')]),
      ], now);
      expect(
        lib.items[0].examples.firstWhere((e) => e.text == 'I run daily.').origin,
        VocabExampleOrigin.ai,
      );
    });

    test('pickOfflineExamples：目标 3 条、幂等', () {
      final it = vocabItem(examples: const [
        VocabExample(text: 'Src sentence.', origin: VocabExampleOrigin.article),
        VocabExample(text: 'AI example.', origin: VocabExampleOrigin.ai),
      ]);
      final cands = [
        (text: 'Off one.', translation: '一'),
        (text: 'Off two.', translation: null),
        (text: 'Off three.', translation: null),
        (text: 'Off four.', translation: null),
      ];
      // 空位 4（上限 6），目标补 3 条 → 取前 3
      expect(pickOfflineExamples(it, cands).map((e) => e.text), ['Off one.', 'Off two.', 'Off three.']);
      final done = vocabItem(examples: const [
        VocabExample(text: 'Src.', origin: VocabExampleOrigin.article),
        VocabExample(text: 'AI.', origin: VocabExampleOrigin.ai),
        VocabExample(text: 'O1.', origin: VocabExampleOrigin.tatoeba),
        VocabExample(text: 'O2.', origin: VocabExampleOrigin.tatoeba),
        VocabExample(text: 'O3.', origin: VocabExampleOrigin.tatoeba),
      ]);
      expect(pickOfflineExamples(done, cands), isEmpty);
    });

    test('pickOfflineExamples：跳过已有同句、受卡片上限约束', () {
      final it = vocabItem(examples: const [
        VocabExample(text: 'Src.', origin: VocabExampleOrigin.article),
        VocabExample(text: 'Already there.', origin: VocabExampleOrigin.ai),
      ]);
      final cands = [
        (text: 'Already there.', translation: null),
        (text: 'New one.', translation: null),
      ];
      expect(pickOfflineExamples(it, cands).map((e) => e.text), ['New one.']);
      final full = vocabItem(examples: [
        for (var i = 0; i < maxExamples; i++)
          VocabExample(text: 'e$i', origin: VocabExampleOrigin.ai),
      ]);
      expect(pickOfflineExamples(full, cands), isEmpty);
    });

    test('离线例句先到，AI 仍会认领（防死循环）', () {
      var lib = one(vocabItem(id: 'vocab:m', word: 'mitigate', lemma: 'mitigate'));
      lib = applyExamples(lib, [
        (word: 'mitigate', examples: [(text: 'Algeria needs to mitigate its vulnerabilities.', translation: null)]),
      ], now, VocabExampleOrigin.tatoeba);
      expect(needsAiExamples(lib.items[0]), isTrue); // 只有离线 → 还缺 AI 例句
      // AI 回了同一句（被去重）→ 也要认领成 ai，否则会一直排
      lib = applyExamples(lib, [
        (
          word: 'mitigate',
          examples: [
            (text: 'Algeria needs to mitigate its vulnerabilities.', translation: '阿尔及利亚需要降低其脆弱性。'),
          ],
        ),
      ], now);
      final ex = lib.items[0].examples.firstWhere((e) => e.text.startsWith('Algeria'));
      expect(ex.origin, VocabExampleOrigin.ai);
      expect(ex.translation, '阿尔及利亚需要降低其脆弱性。');
      expect(needsAiExamples(lib.items[0]), isFalse);
    });
  });

  group('applyPhrases', () {
    test('按 lemma 并入词组/习语，并去重', () {
      var lib = one(runItem());
      lib = applyPhrases(lib, [
        (word: 'running', phrases: ['run out', 'run out'], idioms: ['run in the family']),
      ], now);
      expect(lib.items[0].phrases, ['run out']);
      expect(lib.items[0].idioms, ['run in the family']);
    });

    test('已在「用法」里的词组不再重复写进「词组」', () {
      var lib = one(runItem().copyWith(usage: const ['run out']));
      lib = applyPhrases(lib, [
        (word: 'run', phrases: ['run out', 'run late'], idioms: const []),
      ], now);
      expect(lib.items[0].phrases, ['run late']);
    });

    test('匹配不到的词条不动', () {
      final lib = applyPhrases(createLibrary(), [
        (word: 'zzz', phrases: ['zzz out'], idioms: const []),
      ], now);
      expect(lib.items, isEmpty);
    });

    test('没有词组也写入空数组（=已标注，避免重复跑批）', () {
      var lib = one(vocabItem(id: 'vocab:mrs', word: 'mrs', lemma: 'mrs'));
      expect(lib.items[0].phrases, isNull);
      lib = applyPhrases(lib, [(word: 'mrs', phrases: const [], idioms: const [])], now);
      expect(lib.items[0].phrases, isEmpty);
      expect(lib.items[0].idioms, isEmpty);
    });
  });

  group('applyGrammarMarks / isMarkablePos', () {
    test('按 lemma 合并语法标记并去重', () {
      var lib = one(vocabItem(id: 'vocab:water', word: 'water', lemma: 'water', partOfSpeech: 'n.'));
      lib = applyGrammarMarks(lib, [
        (word: 'water', marks: ['不可数', '不可数']),
      ], now);
      expect(lib.items[0].grammarMarks, ['不可数']);
    });

    test('已标过的词再合并新标记（去重）', () {
      var lib = one(runItem());
      lib = applyGrammarMarks(lib, [
        (word: 'run', marks: ['及物']),
      ], now);
      lib = applyGrammarMarks(lib, [
        (word: 'runs', marks: ['及物', '不及物', '可数']),
      ], now);
      expect(lib.items[0].grammarMarks, ['及物', '不及物', '可数']);
    });

    test('匹配不到的词条不动', () {
      final lib = applyGrammarMarks(createLibrary(), [
        (word: 'zzz', marks: ['可数']),
      ], now);
      expect(lib.items, isEmpty);
    });

    test('没有可标项也写入空数组（=已标注，避免重复跑批）', () {
      var lib = one(vocabItem(id: 'vocab:mrs', word: 'mrs', lemma: 'mrs'));
      expect(lib.items[0].grammarMarks, isNull);
      lib = applyGrammarMarks(lib, [(word: 'mrs', marks: const [])], now);
      expect(lib.items[0].grammarMarks, isEmpty);
    });

    test('isMarkablePos 认名词/动词/形容词，不认介词/代词/数词', () {
      expect(isMarkablePos('n.'), isTrue);
      expect(isMarkablePos('noun'), isTrue);
      expect(isMarkablePos('v.'), isTrue);
      expect(isMarkablePos('n./v.'), isTrue);
      expect(isMarkablePos('adj.'), isTrue);
      expect(isMarkablePos('prep.'), isFalse);
      expect(isMarkablePos('pron.'), isFalse);
      expect(isMarkablePos('num.'), isFalse);
      expect(isMarkablePos('adv.'), isFalse);
      expect(isMarkablePos(null), isFalse);
    });
  });

  group('ownExamples / hasOwnExamples', () {
    test('排除与来源句相同的那条', () {
      final it = vocabItem(examples: const [
        VocabExample(text: 'He runs.'),
        VocabExample(text: 'I run every day.'),
      ], source: const VocabSource(articleId: 'a', sentenceId: 's1', sentenceText: 'He runs.'));
      expect(ownExamples(it).map((e) => e.text), ['I run every day.']);
      expect(hasOwnExamples(it), isTrue);
    });

    test('只有来源句时等于没有自己的例句', () {
      final it = vocabItem(
        examples: const [VocabExample(text: 'He runs.')],
        source: const VocabSource(articleId: 'a', sentenceId: 's1', sentenceText: 'He runs.'),
      );
      expect(hasOwnExamples(it), isFalse);
    });
  });

  group('vocabCardBlocks', () {
    test('按固定顺序输出带小标题的块，只含有内容的', () {
      final it = vocabItem(
        usage: const ['run a business'],
        phrases: const ['run out'],
        idioms: const ['run in the family'],
        examples: const [
          VocabExample(text: 'He runs.'),
          VocabExample(text: 'I run every day.', translation: '我每天跑步。'),
        ],
        source: const VocabSource(articleId: 'a', sentenceId: 's1', sentenceText: 'He runs.'),
        confusables: const [VocabConfusable(word: 'ran', meaning: '跑步')],
      );
      final blocks = vocabCardBlocks(it);
      expect(blocks.map((b) => b.label), ['用法', '词组', '习语', '例句', '来源', '易混']);
      expect(blocks.firstWhere((b) => b.label == '例句').lines, ['I run every day. — 我每天跑步。']);
      expect(blocks.firstWhere((b) => b.label == '易混').lines, ['ran（跑步）']);
    });

    test('易混块按来源加标签；旧数据没有来源就不标', () {
      final ai = vocabCardBlocks(vocabItem(
        confusables: const [VocabConfusable(word: 'adopt', meaning: '采用')],
        confusablesSource: VocabConfusableSource.ai,
      ));
      expect(ai.firstWhere((b) => b.key == 'confusables').lines, ['[AI] adopt（采用）']);

      final dict = vocabCardBlocks(vocabItem(
        confusables: const [VocabConfusable(word: 'adept')],
        confusablesSource: VocabConfusableSource.dict,
      ));
      expect(dict.firstWhere((b) => b.key == 'confusables').lines, ['[词典] adept']);

      final legacy = vocabCardBlocks(vocabItem(
        confusables: const [VocabConfusable(word: 'adopt')],
      ));
      expect(legacy.firstWhere((b) => b.key == 'confusables').lines, ['adopt']);
    });

    test('maxExamples 截断例句；没有内容的块不出现', () {
      final it = vocabItem(examples: const [
        VocabExample(text: 'a'),
        VocabExample(text: 'b'),
        VocabExample(text: 'c'),
      ]);
      final blocks = vocabCardBlocks(it, maxExamples: 2);
      expect(blocks.firstWhere((b) => b.key == 'examples').lines, ['a', 'b']);
      expect(blocks.where((b) => b.key == 'usage'), isEmpty);
    });
  });

  group('dedupeLibrary', () {
    test('同 lemma 合并，字段互补', () {
      final a = vocabItem(id: 'vocab:run', lemma: 'run', word: 'run', phonetic: '/rʌn/');
      final b = vocabItem(id: 'vocab:run2', lemma: 'run', word: 'running', meaning: '跑', usage: const ['run out']);
      final lib = dedupeLibrary(VocabLibrary(items: [a, b]));
      expect(lib.items, hasLength(1));
      expect(lib.items[0].phonetic, '/rʌn/');
      expect(lib.items[0].meaning, '跑');
      expect(lib.items[0].usage, ['run out']);
    });

    test('不同 lemma 不动', () {
      final lib = dedupeLibrary(VocabLibrary(items: [
        vocabItem(id: 'a', lemma: 'a'),
        vocabItem(id: 'b', lemma: 'b'),
      ]));
      expect(lib.items, hasLength(2));
    });

    test('合并易混项时保留「有内容那边」的来源', () {
      final a = vocabItem(id: 'vocab:run', lemma: 'run', word: 'run');
      final b = vocabItem(
        id: 'vocab:run2',
        lemma: 'run',
        word: 'running',
        confusables: const [VocabConfusable(word: 'ran')],
        confusablesSource: VocabConfusableSource.dict,
      );
      final lib = dedupeLibrary(VocabLibrary(items: [a, b]));
      expect(lib.items[0].confusables, hasLength(1));
      expect(lib.items[0].confusables!.first.word, 'ran');
      expect(lib.items[0].confusablesSource, VocabConfusableSource.dict);
    });

    test('合并核心字段时来源跟着值走', () {
      final a = vocabItem(
        id: 'vocab:run',
        lemma: 'run',
        word: 'run',
        phonetic: '/rʌn/',
        fieldSources: const {VocabField.phonetic: VocabFieldSource.ai},
      );
      final b = vocabItem(
        id: 'vocab:run2',
        lemma: 'run',
        word: 'running',
        meaning: '跑',
        fieldSources: const {VocabField.meaning: VocabFieldSource.dict},
      );
      final lib = dedupeLibrary(VocabLibrary(items: [a, b]));
      expect(lib.items[0].phonetic, '/rʌn/');
      expect(lib.items[0].meaning, '跑');
      expect(lib.items[0].fieldSources, {
        VocabField.phonetic: VocabFieldSource.ai,
        VocabField.meaning: VocabFieldSource.dict,
      });
    });

    test('两边易混项来源不同 → 不冒充单一来源', () {
      final a = vocabItem(
        id: 'vocab:run',
        lemma: 'run',
        word: 'run',
        confusables: const [VocabConfusable(word: 'ran')],
        confusablesSource: VocabConfusableSource.ai,
      );
      final b = vocabItem(
        id: 'vocab:run2',
        lemma: 'run',
        word: 'running',
        confusables: const [VocabConfusable(word: 'sprint')],
        confusablesSource: VocabConfusableSource.dict,
      );
      final lib = dedupeLibrary(VocabLibrary(items: [a, b]));
      expect(lib.items[0].confusables, hasLength(2));
      expect(lib.items[0].confusablesSource, isNull);
    });

    test('同 lemma 合并时保留「未标注」状态（grammarMarks/phrases 不被写成空数组）', () {
      final lib = dedupeLibrary(VocabLibrary(items: [
        vocabItem(id: 'vocab:run', lemma: 'run', word: 'run'),
        vocabItem(id: 'vocab:run2', lemma: 'run', word: 'running'),
      ]));
      expect(lib.items[0].grammarMarks, isNull);
      expect(lib.items[0].phrases, isNull);
    });

    test('一边已标注（空数组）也视为已标注，另一边的标记会补上', () {
      final lib = dedupeLibrary(VocabLibrary(items: [
        vocabItem(id: 'vocab:run', lemma: 'run', word: 'run', grammarMarks: const [], phrases: const []),
        vocabItem(
          id: 'vocab:run2',
          lemma: 'run',
          word: 'run',
          grammarMarks: const ['可数'],
          phrases: const ['run out'],
        ),
      ]));
      expect(lib.items[0].grammarMarks, ['可数']);
      expect(lib.items[0].phrases, ['run out']);
    });
  });

  group('marksForPos / normalizeGrammarMarks（按词性过滤语法标记）', () {
    test('可数性只对名词、及物性只对动词、可分级只对形容词', () {
      expect(marksForPos(const ['不可数'], 'v.'), isEmpty); // sprawl 是动词 → 不该标「不可数」
      expect(marksForPos(const ['可数', '不及物'], 'n./v.'), ['可数', '不及物']);
      expect(marksForPos(const ['及物'], 'adj.'), isEmpty);
      expect(marksForPos(const ['可分级'], 'adj.'), ['可分级']);
    });

    test('词性未知 → 先保留；不在受控词表里的扩展标记也保留', () {
      expect(marksForPos(const ['不可数'], null), ['不可数']);
      expect(marksForPos(const ['专有名词'], 'n.'), ['专有名词']);
    });

    test('normalizeGrammarMarks 一次清掉全库不匹配的', () {
      final lib = VocabLibrary(items: [
        vocabItem(partOfSpeech: 'v.', grammarMarks: const ['不可数', '不及物']),
      ]);
      expect(normalizeGrammarMarks(lib).items[0].grammarMarks, ['不及物']);
    });
  });

  group('upsertContext / betterSource（多篇语境 / 来源）', () {
    VocabContext ctx(String sentenceText, [String? meaning]) => VocabContext(
          articleId: 'a',
          fileName: 'a',
          sentenceText: sentenceText,
          meaning: meaning,
          at: now.toIso8601String(),
        );

    test('同篇同句只留一条；新句追加；带了新信息才更新', () {
      var list = upsertContext(null, ctx('One.'));
      expect(list, hasLength(1));
      expect(upsertContext(list, ctx('One.')), hasLength(1));
      list = upsertContext(list, ctx('One.', '此处：一'));
      expect(list[0].meaning, '此处：一');
      list = upsertContext(list, ctx('Two.'));
      expect(list.map((x) => x.sentenceText), ['One.', 'Two.']);
    });

    test('betterSource：有句子的优先，都空则用新的（来源不空）', () {
      VocabSource s(String fileName, String sentenceText) =>
          VocabSource(articleId: fileName, fileName: fileName, sentenceText: sentenceText);
      expect(betterSource(s('A', 'x'), s('B', '')).fileName, 'A');
      expect(betterSource(s('A', ''), s('B', 'y')).fileName, 'B');
    });
  });
}
