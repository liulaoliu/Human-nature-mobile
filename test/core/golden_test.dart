import 'package:dlaoshi_app/core/golden.dart';
import 'package:dlaoshi_app/models/document.dart';
import 'package:flutter_test/flutter_test.dart';

Sentence _s(
  String id,
  String text, {
  String? translation,
  SentenceLanguage? language,
  List<String> collocations = const <String>[],
  List<String> vocab = const <String>[],
}) =>
    Sentence(
      id: id,
      paraId: 'p01',
      text: text,
      translation: translation,
      language: language,
      collocations: collocations,
      vocab: vocab,
    );

const Map<String, Object?> _target = <String, Object?>{
  'en': 'in response to',
  'zh': '为了应对',
  'kind': 'collocation',
};

void main() {
  group('金句目标匹配', () {
    test('只匹配完整词，不允许命中词的一部分', () {
      expect(findGoldenTargetSpans('The new norm is normal.', 'norm'), hasLength(1));
      expect(findGoldenTargetSpans('The new norm is normal.', 'nor'), isEmpty);
    });

    test('容忍大小写、撇号和连字符变体', () {
      expect(findGoldenTargetSpans("Don't stop.", 'don’t'), hasLength(1));
      // U+2011（不换行连字符）不在 [-–—] 里，不该命中 ASCII 连字符。
      expect(findGoldenTargetSpans('A bad-tempered man.', 'bad‑tempered'), isEmpty);
      expect(findGoldenTargetSpans('A bad-tempered man.', 'bad–tempered'), hasLength(1));
    });

    test('目标上限按句长变化：短句少、长句最多 20', () {
      String words(int n) =>
          List<String>.generate(n, (i) => 'word$i').join(' ');
      expect(goldenTargetLimitFor('one two three'), 6);
      expect(goldenTargetLimitFor(words(10)), 10);
      expect(goldenTargetLimitFor(words(25)), 20);
      final raw = <Object?>[
        for (var i = 0; i < 25; i++)
          <String, Object?>{'en': 'word$i', 'kind': 'word'},
      ];
      expect(normalizeGoldenTargets(words(25), raw), hasLength(20));
    });

    test('重叠时长的优先，输出仍按原句顺序', () {
      const text = 'The committee will examine the draft.';
      final out = normalizeGoldenTargets(text, <Object?>[
        <String, Object?>{'en': 'will examine', 'kind': 'tense'},
        <String, Object?>{'en': 'examine the draft', 'kind': 'collocation'},
      ]);
      expect(out.map((t) => t.en), <String>['examine the draft']);
    });

    test('清洗目标：丢掉编造/重复/重叠，保留长目标', () {
      const text =
          'In response to the pandemic, remote collaboration has become the new norm.';
      final out = normalizeGoldenTargets(text, <Object?>[
        _target,
        <String, Object?>{'en': 'response', 'kind': 'word'},
        <String, Object?>{'en': 'remote collaboration', 'kind': 'collocation'},
        <String, Object?>{'en': 'in response to', 'kind': 'collocation'},
        <String, Object?>{'en': 'not in the sentence', 'kind': 'word'},
      ]);
      expect(out.map((t) => t.en),
          <String>['in response to', 'remote collaboration']);
    });

    test('本地目标不再卡 6 个；所有不重叠的语言点都保留', () {
      final s = _s(
        's1',
        'The committee examines the draft, the board considers the budget, and the staff publishes the report tomorrow.',
        language: const SentenceLanguage(
          phrases: <String>[
            'examines the draft',
            'considers the budget',
            'publishes the report',
          ],
          usage: <String>['正式场合用 committee', 'report 可数'],
        ),
        vocab: <String>['committee', 'board', 'staff', 'tomorrow'],
      );
      final out = buildLocalTargets(s);
      final ens = out.map((t) => t.en).toSet();
      expect(ens, containsAll(<String>[
        'examines the draft',
        'considers the budget',
        'publishes the report',
        'committee',
        'board',
        'staff',
        'tomorrow',
      ]));
      expect(out.length, greaterThan(6));
      final note = buildLocalGoldenSentence(s).note;
      expect(note, contains('正式场合用 committee'));
      expect(note, contains('report 可数'));
    });

    test('本地目标：语言点词组/习语优先，保守抽时态', () {
      final s = _s(
        's1',
        'In response to the pandemic, remote collaboration has become the new norm.',
        translation: '为了应对疫情，远程协作已经成为新常态。',
        language: const SentenceLanguage(
          structure: 'In response to + n., … has become …',
          grammar: '现在完成时 has become',
          phrases: <String>['in response to — 为了应对'],
          idioms: <String>['the new norm — 新常态'],
        ),
      );
      final ens = buildLocalTargets(s).map((t) => t.en).toList();
      expect(ens, contains('in response to'));
      expect(ens, contains('the new norm'));
      expect(ens, contains('has become'));
    });
  });

  group('金句课程', () {
    final sentences = <Sentence>[
      _s(
        's1',
        'In response to the pandemic, remote collaboration has become the new norm.',
        translation: '为了应对疫情，远程协作已经成为新常态。',
        language: const SentenceLanguage(
          phrases: <String>['in response to — 为了应对'],
          grammar: '现在完成时',
        ),
      ),
      _s(
        's2',
        'Team spirit is one of the main factors that contribute to success.',
        translation: '团队精神是促成成功的主要因素之一。',
        language: const SentenceLanguage(
          phrases: <String>['team spirit — 团队精神'],
          idioms: <String>['one of the main factors'],
        ),
      ),
      _s('s3', 'Short.', translation: '短。'),
    ];

    test('推荐金句优先语言点，并保持原文顺序', () {
      final picked = pickGoldenCandidates(sentences, 2);
      final ids = picked.map((x) => x.id).toList()..sort();
      expect(ids, <String>['s1', 's2']);
    });

    test('本地课程：开头/主体/结尾脉络 + 默认 10 句上限', () {
      final lesson = buildLocalGoldenLesson(
        List<Sentence>.generate(
          12,
          (i) => _s('s${i + 1}',
              'This is sentence number ${i + 1} with enough words.'),
        ),
        <Paragraph>[
          const Paragraph(id: 'p01', sentenceIds: <String>['s1', 's2']),
          const Paragraph(id: 'p02', sentenceIds: <String>['s3', 's4']),
          const Paragraph(id: 'p03', sentenceIds: <String>['s5']),
        ],
      );
      expect(lesson.sentences.length, lessThanOrEqualTo(10));
      expect(
        lesson.outline.map((x) => x.role),
        <GoldenSectionRole>[
          GoldenSectionRole.intro,
          GoldenSectionRole.body,
          GoldenSectionRole.conclusion,
        ],
      );
    });

    test('本课去重只影响取目标，不改课程内容（开关可关）', () {
      final lesson = buildLocalGoldenLesson(
        <Sentence>[
          _s('s1', 'Team spirit matters.',
              language: const SentenceLanguage(
                  phrases: <String>['team spirit'])),
          _s('s2', 'Team spirit wins.',
              language: const SentenceLanguage(
                  phrases: <String>['team spirit'])),
        ],
        null,
        const LocalGoldenOptions(
          selected: <String>['s1', 's2'],
          dedupe: true,
        ),
      );
      expect(lesson.sentences[0].targets.map((t) => t.en),
          <String>['team spirit']);
      expect(lesson.sentences[1].targets.map((t) => t.en),
          <String>['team spirit']);
      expect(goldenTargetsFor(lesson, 's1').map((t) => t.en),
          <String>['team spirit']);
      expect(goldenTargetsFor(lesson, 's2'), isEmpty);
      final reopened = lesson.copyWith(
        options: const GoldenLessonOptions(dedupe: false),
      );
      expect(goldenTargetsFor(reopened, 's2').map((t) => t.en),
          <String>['team spirit']);
    });
  });
}
