import 'package:dlaoshi_app/core/golden.dart';
import 'package:dlaoshi_app/core/golden_article.dart';
import 'package:dlaoshi_app/models/document.dart';
import 'package:flutter_test/flutter_test.dart';

SavedArticle _article({
  Map<String, Object?>? golden,
  List<Sentence>? sentences,
}) {
  final list = sentences ??
      <Sentence>[
        const Sentence(
          id: 's1',
          paraId: 'p01',
          text: 'We keep up with the news every morning.',
          translation: '我们每天早上都跟上新闻。',
        ),
      ];
  return SavedArticle(
    id: 'a1',
    title: '测试篇',
    paragraphs: <Paragraph>[
      Paragraph(id: 'p01', sentenceIds: [for (final s in list) s.id]),
    ],
    sentences: list,
    golden: golden,
    updatedAt: '2026-11-09T00:00:00.000Z',
  );
}

Map<String, Object?> _lessonJson() => const GoldenLesson(
      source: GoldenSource.ai,
      summary: '讲习惯',
      outline: <GoldenSection>[
        GoldenSection(paraId: 'p01', role: GoldenSectionRole.intro, points: <String>['讲习惯']),
      ],
      sentences: <GoldenSentence>[
        GoldenSentence(
          id: 's1',
          zh: '我们每天早上都跟上新闻。',
          targets: <GoldenTarget>[
            GoldenTarget(en: 'keep up with', kind: GoldenTargetKind.collocation, zh: '跟上'),
          ],
        ),
      ],
      selected: <String>['s1'],
    ).toJson();

void main() {
  group('金句课与文章之间的转换', () {
    test('没有 golden 时读回 null', () {
      expect(goldenLessonOf(_article()), isNull);
      expect(goldenLessonOf(_article(golden: <String, Object?>{})), isNull);
    });

    test('正常内容读成强类型', () {
      final lesson = goldenLessonOf(_article(golden: _lessonJson()));
      expect(lesson, isNotNull);
      expect(lesson!.summary, '讲习惯');
      expect(lesson.sentences.single.id, 's1');
      expect(lesson.sentences.single.targets.single.en, 'keep up with');
      expect(lesson.source, GoldenSource.ai);
    });

    test('编造的目标读回来被丢掉（守卫生效）', () {
      final raw = _lessonJson();
      (raw['sentences']! as List).first as Map<String, Object?>;
      final sentences = raw['sentences']! as List;
      final first = Map<String, Object?>.from(sentences.first as Map);
      first['targets'] = <Object?>[
        <String, Object?>{'en': 'made up', 'kind': 'collocation'},
        <String, Object?>{'en': 'keep up with', 'kind': 'collocation', 'zh': '跟上'},
      ];
      sentences[0] = first;
      final lesson = goldenLessonOf(_article(golden: raw));
      expect(lesson!.sentences.single.targets, hasLength(1));
      expect(lesson.sentences.single.targets.single.en, 'keep up with');
    });

    test('句子 id 对不上时整课作废（返回 null，不抛异常）', () {
      final raw = _lessonJson();
      final sentences = raw['sentences']! as List;
      final first = Map<String, Object?>.from(sentences.first as Map);
      first['id'] = 's404';
      sentences[0] = first;
      expect(goldenLessonOf(_article(golden: raw)), isNull);
    });

    test('写回文章时存的是原始 JSON 形状', () {
      final lesson = goldenLessonOf(_article(golden: _lessonJson()))!;
      final next = withGoldenLesson(_article(), lesson);
      expect(next.golden, isNotNull);
      expect(next.golden!['sentences'], isA<List<Object?>>());
      expect(next.golden!['version'], 1);
      // 再读一遍还是同一份
      expect(goldenLessonOf(next)!.sentences.single.targets.single.en, 'keep up with');
    });

    test('传 null 写回等于清空', () {
      final next = withGoldenLesson(_article(golden: _lessonJson()), null);
      expect(next.golden, isNull);
    });

    test('改正文后 prune 掉对不上的目标', () {
      final lesson = goldenLessonOf(_article(golden: _lessonJson()))!;
      final edited = _article(
        golden: withGoldenLesson(_article(), lesson).golden,
        sentences: <Sentence>[
          const Sentence(id: 's1', paraId: 'p01', text: 'We keep going every morning.'),
        ],
      );
      final pruned = pruneGoldenOf(edited);
      expect(pruned.golden, isNull, reason: '目标逐字对不上，整句没了，整课也就作废');
    });

    test('正文没变时 prune 原样返回同一个对象', () {
      final article = _article(golden: _lessonJson());
      expect(identical(pruneGoldenOf(article), article), isTrue);
    });

    test('没有 golden 时 prune 不动它', () {
      final article = _article();
      expect(identical(pruneGoldenOf(article), article), isTrue);
    });

    test('坏到修不出来的 golden 被 prune 清掉', () {
      final article = _article(golden: <String, Object?>{'sentences': 'not a list'});
      expect(pruneGoldenOf(article).golden, isNull);
    });
  });
}
