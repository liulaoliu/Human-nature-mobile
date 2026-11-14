import 'package:dlaoshi_app/core/quiz.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/vocab_fixture.dart';

VocabItem item({
  String id = 'vocab:run',
  String word = 'run',
  String? lemma,
  String? meaning = '跑；经营',
  String? phonetic = '/rʌn/',
  String? partOfSpeech = 'v.',
  String? definition,
  List<String> usage = const [],
  List<VocabExample> examples = const [],
  VocabSource? source,
  List<String>? idioms,
  List<String>? phrases,
  List<String>? grammarMarks,
  List<VocabConfusable>? confusables,
}) =>
    vocabItem(
      id: id,
      word: word,
      lemma: lemma ?? word,
      meaning: meaning,
      phonetic: phonetic,
      partOfSpeech: partOfSpeech,
      definition: definition,
      usage: usage,
      examples: examples,
      source: source,
      idioms: idioms,
      phrases: phrases,
      grammarMarks: grammarMarks,
      confusables: confusables,
      status: VocabStatus.queried,
    );

double half() => 0.5;

void main() {
  group('normalizeAnswer', () {
    test('大小写 / 首尾标点 / 空白', () {
      expect(normalizeAnswer('  Running, '), 'running');
      expect(normalizeAnswer('a  business.'), 'a business');
    });
  });

  group('blankWord', () {
    test('按 lemma 匹配词形并挖空', () {
      final r = blankWord('He is running fast.', 'run')!;
      expect(r.blanked, 'He is ____ fast.');
      expect(r.surface, 'running');
    });

    test('短语整段匹配', () {
      final r = blankWord('The human rights record is poor.', 'human rights')!;
      expect(r.blanked, 'The ____ record is poor.');
      expect(r.surface, 'human rights');
    });

    test('找不到返回 null', () {
      expect(blankWord('nothing here', 'run'), isNull);
    });
  });

  group('makeQuestion', () {
    test('拼写：需要释义', () {
      expect(makeQuestion(item(), QuizKind.spell)?.prompt, '跑；经营');
      expect(makeQuestion(item(meaning: null), QuizKind.spell), isNull);
    });

    test('例句填空：从例句挖空', () {
      final it = item(examples: [
        const VocabExample(text: 'They run a business together.', translation: '他们一起经营生意。'),
      ]);
      final q = makeQuestion(it, QuizKind.cloze)!;
      expect(q.prompt, 'They ____ a business together.');
      expect(q.answer, 'run');
      expect(q.translation, '他们一起经营生意。');
    });

    test('例句填空：例句没命中就退回来源句', () {
      final it = item(
        examples: [const VocabExample(text: 'No target here.')],
        source: const VocabSource(articleId: 'a1', sentenceId: 's1', sentenceText: 'She runs daily.'),
      );
      expect(makeQuestion(it, QuizKind.cloze)?.prompt, 'She ____ daily.');
    });

    test('搭配填空：从 usage 挖空', () {
      final it = item(usage: ['run a business', 'run out']);
      final q = makeQuestion(it, QuizKind.usage)!;
      expect(q.prompt, '____ a business');
      expect(q.answer, 'run');
    });

    test('搭配填空：usage 不含该词则为 null', () {
      expect(makeQuestion(item(usage: ['a business']), QuizKind.usage), isNull);
    });

    test('听力填空：隐藏句子、带朗读文本', () {
      final it = item(examples: [
        const VocabExample(text: 'They run a business together.', translation: '他们一起经营生意。'),
      ]);
      final q = makeQuestion(it, QuizKind.listen)!;
      expect(q.prompt, '');
      expect(q.audioText, 'They run a business together.');
      expect(q.context, 'They run a business together.');
      expect(q.answer, 'run');
    });

    test('听力填空：没有句子则为 null', () {
      expect(makeQuestion(item(examples: const [], source: null), QuizKind.listen), isNull);
    });

    test('听音拼词：隐藏文字、读单词、答案为原词', () {
      final q = makeQuestion(item(word: 'slide', lemma: 'slide'), QuizKind.ear)!;
      expect(q.prompt, '');
      expect(q.meaning, isNull);
      expect(q.audioText, 'slide');
      expect(q.answer, 'slide');
    });

    test('词形辨析：给释义、选项含正确答案与干扰项', () {
      final pool = [
        item(id: 'a', word: 'adapt', meaning: '适应'),
        item(id: 'b', word: 'adopt', meaning: '采用'),
        item(id: 'c', word: 'adept', meaning: '熟练的'),
        item(id: 'd', word: 'zebra', meaning: '斑马'),
      ];
      final q = makeQuestion(pool[0], QuizKind.choice, pool)!;
      expect(q.prompt, '适应');
      expect(q.options, contains('adapt'));
      expect(q.options!.length, greaterThanOrEqualTo(2));
    });

    test('词形辨析：没有干扰项则为 null', () {
      expect(makeQuestion(item(meaning: '适应'), QuizKind.choice, const []), isNull);
    });

    test('看词选义：题干是英文、选项是中文释义', () {
      final pool = [
        item(id: 'a', word: 'adapt', meaning: '适应'),
        item(id: 'b', word: 'adopt', meaning: '采用'),
        item(id: 'c', word: 'adept', meaning: '熟练的'),
      ];
      final q = makeQuestion(pool[0], QuizKind.meaning, pool)!;
      expect(q.prompt, 'adapt');
      expect(q.answer, '适应');
      expect(q.options, contains('适应'));
      expect(q.options!.length, greaterThanOrEqualTo(2));
      expect(isCorrect(q, '适应'), isTrue);
      expect(isCorrect(q, '采用'), isFalse);
    });

    test('看词选义：没有释义则为 null', () {
      expect(makeQuestion(item(meaning: null), QuizKind.meaning, [item(id: 'b', meaning: 'x')]), isNull);
    });
  });

  group('pickMeaningDistractors', () {
    test('排除同释义、去重', () {
      final pool = [
        item(id: 'a', meaning: '适应'),
        item(id: 'b', meaning: '采用'),
        item(id: 'c', meaning: '采用'),
        item(id: 'd', meaning: '斑马'),
      ];
      final out = pickMeaningDistractors(pool[0], pool, 3, half);
      expect(out, isNot(contains('适应')));
      expect(out.toSet().length, out.length);
      expect(out, contains('采用'));
    });

    test('优先用 AI 混淆项的释义', () {
      final me = item(id: 'a', meaning: '适应', confusables: const [
        VocabConfusable(word: 'adopt', meaning: '采用'),
        VocabConfusable(word: 'adept', meaning: '熟练的'),
      ]);
      final out = pickMeaningDistractors(me, const [], 3, half);
      expect(out.take(2).toList(), ['采用', '熟练的']);
    });

    test('近义 / 包含关系的释义会被剔除', () {
      final me = item(id: 'a', meaning: '调整', confusables: const [
        VocabConfusable(word: 'x', meaning: '微调，调整'),
        VocabConfusable(word: 'y', meaning: '采纳'),
      ]);
      expect(pickMeaningDistractors(me, const [], 3, half), ['采纳']);
    });
  });

  group('maskAnswer', () {
    test('字母变下划线，保留空格 / 连字符 / 撇号', () {
      expect(maskAnswer('run'), '___');
      expect(maskAnswer('bad-temperedly'), '___-${'_' * 10}');
      expect(maskAnswer('run a business'), '___ _ ${'_' * 8}');
      expect(maskAnswer("don't"), "___'_");
    });
  });

  group('countQuestions', () {
    test('按题型与数据判定', () {
      final items = [
        item(id: 'a', word: 'run', meaning: '跑'),
        item(id: 'b', word: 'go', meaning: null, examples: [const VocabExample(text: 'go fast')]),
        item(id: 'c', word: 'x', meaning: null, examples: const [], source: null),
      ];
      expect(countQuestions(items, [QuizKind.spell]), 1);
      expect(countQuestions(items, [QuizKind.cloze]), 1);
      expect(countQuestions(items, [QuizKind.ear]), 3);
    });
  });

  group('精读专用题型：英英释义 / 搭配 / 介词 / 语法标记', () {
    test('define：英英释义 → 写单词；无释义则不出题', () {
      final q = makeQuestion(item(definition: 'to move quickly on foot'), QuizKind.define)!;
      expect(q.prompt, 'to move quickly on foot');
      expect(q.answer, 'run');
      expect(makeQuestion(item(definition: null), QuizKind.define), isNull);
    });

    test('defineChoice：英英释义 → 选单词（带干扰项）', () {
      final me = item(definition: 'to move quickly', confusables: const [VocabConfusable(word: 'ran')]);
      final q = makeQuestion(me, QuizKind.defineChoice, [me])!;
      expect(q.options, contains('run'));
      expect(q.options!.length, greaterThan(1));
    });

    test('collocation：给词写搭配；只写光杆单词不算对', () {
      final me = item(usage: ['run out of', 'run a business'], phrases: ['run late']);
      final q = makeQuestion(me, QuizKind.collocation)!;
      expect(q.answer, 'run out of');
      expect(q.accept, containsAll(<String>['run a business', 'run late']));
      // 换了搭配也算对
      expect(isCorrect(q, 'run a business'), isTrue);
      expect(isCorrect(q, 'run late'), isTrue);
      // 光杆单词不算
      expect(isCorrect(q, 'run'), isFalse);
    });

    test('prep：从搭配里挖掉介词/小品词，选项含正确答案', () {
      final me = item(meaning: '用完', usage: ['run out of']);
      final q = makeQuestion(me, QuizKind.prep)!;
      expect(q.prompt, 'run out ____');
      expect(q.answer, 'of');
      expect(q.options, contains('of'));
      expect(makeQuestion(item(usage: ['run a business']), QuizKind.prep), isNull);
    });

    test('mark：可数/不可数等成对判断；兼类/无标记不出题', () {
      final q = makeQuestion(item(word: 'water', lemma: 'water', grammarMarks: ['不可数']), QuizKind.mark)!;
      expect(q.answer, '不可数');
      expect(q.options!.toSet(), {'不可数', '可数'});
      expect(makeQuestion(item(grammarMarks: ['可数', '不可数']), QuizKind.mark), isNull);
      expect(makeQuestion(item(grammarMarks: const []), QuizKind.mark), isNull);
    });

    test('blankParticle：挖最后一个介词', () {
      final b = blankParticle('depend on')!;
      expect(b.blanked, 'depend ____');
      expect(b.particle, 'on');
      expect(blankParticle('run a business'), isNull);
    });

    test('idiom：习语里挖掉目标词；不含该词则不出题', () {
      final q = makeQuestion(item(idioms: ['run in the family']), QuizKind.idiom)!;
      expect(q.prompt, '____ in the family');
      expect(q.answer, 'run');
      expect(makeQuestion(item(idioms: ['a piece of cake']), QuizKind.idiom), isNull);
    });

    test('countQuestions 统计新题型', () {
      final items = [
        item(id: 'a', definition: 'x', usage: ['run out'], grammarMarks: ['不可数']),
        item(id: 'b', definition: null, usage: const [], grammarMarks: const []),
      ];
      expect(countQuestions(items, [QuizKind.define]), 1);
      expect(countQuestions(items, [QuizKind.collocation]), 1);
      expect(countQuestions(items, [QuizKind.mark]), 1);
    });
  });

  group('pickDistractors', () {
    test('排除自身、优先形近', () {
      final pool = [
        item(id: 'a', word: 'adapt'),
        item(id: 'b', word: 'adopt'),
        item(id: 'c', word: 'adept'),
        item(id: 'd', word: 'zebra'),
      ];
      final out = pickDistractors(pool[0], pool, 2, half);
      expect(out, isNot(contains('adapt')));
      expect(out, contains('adopt'));
    });

    test('优先用 AI 混淆项', () {
      final me = item(id: 'a', word: 'adapt', confusables: const [
        VocabConfusable(word: 'adopt'),
        VocabConfusable(word: 'adept'),
      ]);
      final out = pickDistractors(me, const [], 3, half);
      expect(out.take(2).toList(), ['adopt', 'adept']);
    });

    test('与目标近义的易混词会被剔除', () {
      final me = item(id: 'a', word: 'adapt', meaning: '适应', confusables: const [
        VocabConfusable(word: 'adjust', meaning: '适应'),
        VocabConfusable(word: 'adopt', meaning: '收养'),
      ]);
      expect(pickDistractors(me, const [], 3, half), ['adopt']);
    });
  });

  group('makeDictationQuestion', () {
    test('按给定句子挖空目标词', () {
      final it = item(word: 'run', meaning: '跑');
      final q = makeDictationQuestion(it, 'She runs daily.')!;
      expect(q.kind, QuizKind.listen);
      expect(q.audioText, 'She runs daily.');
      expect(q.answer, 'runs');
    });

    test('句子里没有该词则为 null', () {
      expect(makeDictationQuestion(item(), 'Nothing here.'), isNull);
    });
  });

  group('buildQuizQuestions', () {
    test('按选题型出题，每种题型最多一题', () {
      final it = item(usage: ['run a business'], examples: [const VocabExample(text: 'They run fast.')]);
      final qs = buildQuizQuestions([it], [QuizKind.spell, QuizKind.cloze, QuizKind.usage]);
      expect(qs.map((q) => q.kind).toList(), [QuizKind.spell, QuizKind.cloze, QuizKind.usage]);
    });

    test('数据不足的题型会跳过', () {
      final it = item(meaning: '跑', usage: const [], examples: const [], source: null);
      final qs = buildQuizQuestions([it], [QuizKind.spell, QuizKind.cloze, QuizKind.usage]);
      expect(qs.map((q) => q.kind).toList(), [QuizKind.spell]);
    });

    test('题 id 唯一', () {
      final a = item(id: 'a', word: 'run', examples: [const VocabExample(text: 'run fast')]);
      final b = item(id: 'b', word: 'go', examples: [const VocabExample(text: 'go fast')]);
      final qs = buildQuizQuestions([a, b], [QuizKind.cloze]);
      expect(qs.map((q) => q.id).toSet().length, qs.length);
    });
  });

  group('isCorrect', () {
    const q = QuizQuestion(
      id: 'x',
      itemId: 'x',
      lemma: 'run',
      kind: QuizKind.cloze,
      word: 'run',
      prompt: 'They ____ fast.',
      meaning: '跑',
      answer: 'running',
      accept: ['running', 'run'],
    );

    test('精确 / 大小写 / 标点都对', () {
      expect(isCorrect(q, 'running'), isTrue);
      expect(isCorrect(q, ' Running. '), isTrue);
      expect(isCorrect(q, 'run'), isTrue);
    });

    test('词形还原一致也算对', () {
      expect(isCorrect(q, 'runs'), isTrue);
    });

    test('错误答案判错 / 空答判错', () {
      expect(isCorrect(q, 'walk'), isFalse);
      expect(isCorrect(q, '   '), isFalse);
    });
  });

  group('shuffleQuiz', () {
    test('不改原数组，元素不丢', () {
      final src = [1, 2, 3, 4, 5];
      final out = shuffleQuiz(src, half);
      expect(src, [1, 2, 3, 4, 5]);
      expect(out.toList()..sort(), [1, 2, 3, 4, 5]);
    });
  });

  group('连字符 / 撇号宽容', () {
    const q = QuizQuestion(
      id: 'x',
      itemId: 'x',
      lemma: 'bad-temperedly',
      kind: QuizKind.spell,
      word: 'bad-temperedly',
      prompt: '脾气坏地',
      meaning: '脾气坏地',
      answer: 'bad-temperedly',
      accept: ['bad-temperedly'],
    );

    test('不打连字符也判对', () {
      expect(isCorrect(q, 'badtemperedly'), isTrue);
      expect(isCorrect(q, 'bad temperedly'), isTrue);
      expect(isCorrect(q, 'bad-temperedly'), isTrue);
      expect(isCorrect(q, 'bad'), isFalse);
    });

    test('formatAnswerInput 自动补连字符 / 撇号', () {
      expect(formatAnswerInput('bad', 'bad-temperedly'), 'bad');
      expect(formatAnswerInput('badt', 'bad-temperedly'), 'bad-t');
      expect(formatAnswerInput('badtemp', 'bad-temperedly'), 'bad-temp');
      expect(formatAnswerInput('badtemperedly', 'bad-temperedly'), 'bad-temperedly');
      expect(formatAnswerInput('dont', "don't"), "don't");
      expect(formatAnswerInput('xyz', 'bad-temperedly'), 'xyz');
      expect(formatAnswerInput('', 'bad-temperedly'), '');
    });
  });

  group('isArticleKind：分「文章级」与「词级」题型', () {
    test('文章级题型认出来', () {
      for (final k in articleKinds) {
        expect(isArticleKind(k), isTrue);
      }
    });

    test('词级题型不算（含听力/拼写/搭配）', () {
      for (final k in [QuizKind.spell, QuizKind.cloze, QuizKind.usage, QuizKind.listen, QuizKind.ear, QuizKind.meaning, QuizKind.idiom]) {
        expect(isArticleKind(k), isFalse);
      }
    });
  });

  group('拼写题判分：不做词形兜底', () {
    test('run 的拼写题：Run 对，ran / runs 都算错', () {
      final it = item(id: 'v1', word: 'run', meaning: '跑');
      final q = makeQuestion(it, QuizKind.spell)!;
      expect(isCorrect(q, 'Run'), isTrue);
      expect(isCorrect(q, 'ran'), isFalse);
      expect(isCorrect(q, 'runs'), isFalse);
    });

    test('填空 / 搭配题仍宽容词形（语境里 running 可以填 run）', () {
      final it = item(id: 'v2', word: 'run', meaning: '跑', examples: [const VocabExample(text: 'They run fast.')]);
      final q = makeQuestion(it, QuizKind.cloze)!;
      expect(isCorrect(q, 'runs'), isTrue);
    });
  });

  group('isArticleQuestion：判分落盘用它挡住文章题污染词库', () {
    test('词级题（source 为 null）不算文章题', () {
      final q = makeQuestion(item(), QuizKind.spell)!;
      expect(isArticleQuestion(q), isFalse);
    });

    test('source == article 算', () {
      const q = QuizQuestion(
        id: 'article:translate:s1',
        itemId: 's1',
        lemma: '',
        kind: QuizKind.translate,
        source: 'article',
        word: '',
        prompt: 'Hello.',
        answer: '你好。',
        accept: <String>[],
      );
      expect(isArticleQuestion(q), isTrue);
    });

    test('source 缺失但 kind 是文章级，也算（不能只看 source）', () {
      const q = QuizQuestion(
        id: 'article:ordering:p1',
        itemId: 'p1',
        lemma: '',
        kind: QuizKind.ordering,
        word: '',
        prompt: 'A\\nB',
        answer: 'A B',
        accept: <String>[],
      );
      expect(isArticleQuestion(q), isTrue);
    });
  });
}
