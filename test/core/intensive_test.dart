import 'package:dlaoshi_app/core/intensive.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:flutter_test/flutter_test.dart';

IntensiveWords _words({
  int total = 10,
  int withMeaning = 10,
  int withChunks = 10,
  int? chunksAsked,
  int withMarks = 8,
  int studied = 10,
  int stable = 6,
  int due = 0,
  int noExample = 0,
}) =>
    IntensiveWords(
      total: total,
      withMeaning: withMeaning,
      withChunks: withChunks,
      chunksAsked: chunksAsked,
      withMarks: withMarks,
      studied: studied,
      stable: stable,
      due: due,
      noExample: noExample,
    );

IntensiveInput _base({
  bool hasDoc = true,
  bool skimmed = true,
  IntensiveWords? words,
  IntensiveSentences? sentences,
  SkillStat? quiz = const SkillStat(total: 20, correct: 18),
  int writes = 1,
}) =>
    IntensiveInput(
      hasDoc: hasDoc,
      skimmed: skimmed,
      words: words ?? _words(),
      sentences: sentences ?? const IntensiveSentences(total: 10, translated: 10, language: 10),
      quiz: quiz,
      writes: writes,
    );

IntensiveStage _stage(IntensivePlan plan, IntensiveStageKey key) =>
    plan.stages.firstWhere((s) => s.key == key);

VocabItem _item({
  required String word,
  String? meaning = '释义',
  List<String> usage = const <String>[],
  List<String>? phrases,
  List<String>? idioms,
  List<String>? grammarMarks,
  int repetitions = 0,
  int interval = 0,
  int lapses = 0,
  String? due,
}) =>
    VocabItem(
      id: 'vocab:$word',
      word: word,
      lemma: word,
      meaning: meaning,
      usage: usage,
      phrases: phrases,
      idioms: idioms,
      grammarMarks: grammarMarks,
      reviewState: ReviewState(
        repetitions: repetitions,
        interval: interval,
        lapses: lapses,
        due: due,
      ),
      createdAt: '2026-11-01T00:00:00.000Z',
      updatedAt: '2026-11-01T00:00:00.000Z',
    );

void main() {
  group('buildIntensivePlan', () {
    test('空文章：全是 todo，等级 0，七个阶段', () {
      final plan = buildIntensivePlan(
        _base(
          hasDoc: false,
          skimmed: false,
          words: _words(total: 0),
          sentences: const IntensiveSentences(total: 0, translated: 0, language: 0),
          quiz: null,
          writes: 0,
        ),
      );
      expect(plan.level, 0);
      expect(plan.stages.every((s) => s.status == IntensiveStageStatus.todo), isTrue);
      expect(plan.stages, hasLength(7));
    });

    test('只通读 → 及格，下一步是标词/查词', () {
      final plan = buildIntensivePlan(
        _base(
          words: _words(total: 0),
          sentences: const IntensiveSentences(total: 0, translated: 0, language: 0),
          quiz: null,
          writes: 0,
        ),
      );
      expect(_stage(plan, IntensiveStageKey.skim).status, IntensiveStageStatus.done);
      expect(plan.level, 0);
      expect(plan.levelLabel, '及格');
      expect(plan.nextKey, IntensiveStageKey.vocab);
    });

    test('词/句都齐 + 考过 → 达标', () {
      final plan = buildIntensivePlan(
        _base(words: _words(studied: 5, stable: 2), writes: 0),
      );
      expect(plan.level, 1);
      expect(plan.levelLabel, '达标');
    });

    test('仿写过 → 产出', () {
      final plan = buildIntensivePlan(_base(words: _words(studied: 5, stable: 2)));
      expect(plan.level, 2);
      expect(plan.levelLabel, '产出');
    });

    test('全部到位 → 精通', () {
      final plan = buildIntensivePlan(_base());
      expect(plan.level, 3);
      expect(plan.levelLabel, '精通');
      expect(plan.nextKey, isNull);
      expect(plan.progress, 100);
    });

    test('达标拷打要学过全部词、且正确率 >= 80%', () {
      final low = buildIntensivePlan(_base(quiz: const SkillStat(total: 10, correct: 5)));
      expect(_stage(low, IntensiveStageKey.recall).status, isNot(IntensiveStageStatus.done));
      final ok = buildIntensivePlan(_base(quiz: const SkillStat(total: 10, correct: 9)));
      expect(_stage(ok, IntensiveStageKey.recall).status, IntensiveStageStatus.done);
    });

    test('下一步取第一个未完成阶段', () {
      final plan = buildIntensivePlan(_base(words: _words(withChunks: 3)));
      expect(plan.nextKey, IntensiveStageKey.chunks);
      expect(plan.nextLabel, contains('词块'));
    });

    test('词块进度按「问过」算：真的没有搭配的词不该把这一阶段永远卡住', () {
      // 3 个词有搭配、10 个都问过了（其余 7 个 AI 明确说「无」）→ 这一阶段算完成，
      // 否则「精通」永远拿不到，面板还一直催你补根本不存在的搭配。
      final plan = buildIntensivePlan(_base(words: _words(withChunks: 3, chunksAsked: 10)));
      final chunks = _stage(plan, IntensiveStageKey.chunks);
      expect(chunks.progress, 100);
      expect(chunks.status, IntensiveStageStatus.done);
      expect(chunks.detail, contains('已问过 10'));
      // 不传 chunksAsked 时退回覆盖率（老口径）
      final old = buildIntensivePlan(_base(words: _words(withChunks: 3)));
      expect(_stage(old, IntensiveStageKey.chunks).progress, 30);
    });

    test('阶段按钮文案说的是「点下去会发生什么」', () {
      final plan = buildIntensivePlan(_base());
      expect(_stage(plan, IntensiveStageKey.skim).action, '去速读');
      expect(_stage(plan, IntensiveStageKey.vocab).action, '跑批补音标 / 释义');
      expect(_stage(plan, IntensiveStageKey.produce).action, '去仿写');
    });
  });

  group('hasVocabChunks', () {
    test('用法 / 词组 / 习语任一非空就算有', () {
      expect(hasVocabChunks(usage: const ['u']), isTrue);
      expect(hasVocabChunks(usage: const [], phrases: const ['p']), isTrue);
      expect(hasVocabChunks(usage: const [], idioms: const ['i']), isTrue);
      expect(hasVocabChunks(usage: const [], phrases: const [], idioms: const []), isFalse);
      expect(hasVocabChunks(usage: const []), isFalse);
    });
  });

  group('isStableItem', () {
    test('复习够 2 次、间隔够 6 天、没出错才算稳定', () {
      expect(isStableItem(repetitions: 2, interval: 6), isTrue);
      expect(isStableItem(repetitions: 1, interval: 30), isFalse);
      expect(isStableItem(repetitions: 5, interval: 3), isFalse);
      expect(isStableItem(repetitions: 5, interval: 30, lapses: 1), isFalse);
    });
  });

  group('intensiveWordsOf', () {
    test('按口径数出八个数字', () {
      final items = <VocabItem>[
        _item(word: 'a', grammarMarks: const ['及物']),
        _item(word: 'b', meaning: null),
        _item(word: 'c', usage: const ['要点']),
        _item(word: 'd', phrases: const ['keep up']),
        _item(word: 'e', repetitions: 3, interval: 10),
        _item(word: 'f', repetitions: 3, interval: 10, lapses: 1),
        _item(word: 'g', due: '2020-01-01T00:00:00.000Z'),
      ];
      final w = intensiveWordsOf(items, now: DateTime.utc(2026, 11, 13));
      expect(w.total, 7);
      expect(w.withMeaning, 6); // b 没有释义
      expect(w.withChunks, 2); // c 用法、d 词组（g 没有词块）
      expect(w.withMarks, 1);
      // e、f 有 repetitions，g 有 due —— 三个都算「学过」
      expect(w.studied, 3);
      expect(w.stable, 1); // 只有 e
      expect(w.due, greaterThanOrEqualTo(1));
    });

    test('phrases 是空数组也算「问过」，但要和「有内容」分开', () {
      final items = <VocabItem>[
        _item(word: 'a', phrases: const []),
        _item(word: 'b'),
      ];
      final w = intensiveWordsOf(items);
      expect(w.withChunks, 0);
      expect(w.chunksAsked, 1); // 只有 a 的 phrases 字段存在
    });

    test('空列表：全零，不炸', () {
      final w = intensiveWordsOf(const <VocabItem>[]);
      expect(w.total, 0);
      expect(w.withMeaning, 0);
      expect(w.noExample, 0);
    });
  });
}
