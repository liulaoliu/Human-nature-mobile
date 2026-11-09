import 'package:dlaoshi_app/core/golden.dart';
import 'package:dlaoshi_app/core/golden_markdown.dart';
import 'package:dlaoshi_app/core/golden_progress.dart';
import 'package:dlaoshi_app/models/document.dart';
import 'package:flutter_test/flutter_test.dart';

Sentence _s() => Sentence(
      id: 's1',
      paraId: 'p01',
      text: 'In response to the pandemic, remote collaboration has become the new norm.',
      translation: '为了应对疫情，远程协作已经成为新常态。',
      language: const SentenceLanguage(
        phrases: <String>['in response to — 为了应对'],
        grammar: '现在完成时',
      ),
    );

void main() {
  group('goldenToMarkdown', () {
    test('导出主旨、金句、译文、学习点；带进度时打勾', () {
      final s = _s();
      final base = buildLocalGoldenLesson(
        <Sentence>[s],
        null,
        const LocalGoldenOptions(selected: <String>['s1']),
      );
      final lesson = base.copyWith(
        extraPoints: () => <GoldenExtraPoint>[
          const GoldenExtraPoint(
            sentenceId: 's1',
            en: 'come to an end',
            zh: '结束',
            kind: GoldenExtraPointKind.chunk,
            source: GoldenExtraPointSource.user,
          ),
        ],
      );
      final rec = emptyGoldenRecord(
        'a1',
        null,
        's1',
        goldenDrillKey(s.text, lesson.sentences.first.targets),
        '2026-10-27T00:00:00.000Z',
      ).copyWith(mastered: true);
      final md = goldenToMarkdown(
        lesson,
        title: 'Conditions for green growth',
        sentences: <GoldenTextMeta>[GoldenTextMeta(id: s.id, text: s.text)],
        records: <GoldenDrillRecord>[rec],
        articleId: 'a1',
        includeProgress: true,
      );
      expect(md, contains('# Conditions for green growth'));
      expect(md, contains('**In response to the pandemic'));
      expect(md, contains('为了应对疫情'));
      expect(md, contains('搭配：in response to'));
      expect(md, contains('**加练语言点**'));
      expect(md, contains('come to an end — 结束'));
      expect(md, contains('### s1 ✅'));
      expect(md, contains('## 金句'));
      expect(md, contains('## 本篇脉络'));
      expect(md.endsWith('\n'), isTrue);
    });

    test('默认不带进度勾，避免把学习状态混进素材', () {
      final s = _s();
      final lesson = buildLocalGoldenLesson(
        <Sentence>[s],
        null,
        const LocalGoldenOptions(selected: <String>['s1']),
      );
      final md = goldenToMarkdown(
        lesson,
        title: 'T',
        sentences: <GoldenTextMeta>[GoldenTextMeta(id: s.id, text: s.text)],
      );
      expect(md, isNot(contains('✅')));
      expect(md, startsWith('# T'));
    });

    test('段落角色翻成中文；没传 sentences 时不写正文', () {
      final s1 = Sentence(id: 's1', paraId: 'p01', text: 'First one here.');
      final s2 = Sentence(id: 's2', paraId: 'p02', text: 'Second one here.');
      final lesson = buildLocalGoldenLesson(
        <Sentence>[s1, s2],
        <Paragraph>[
          const Paragraph(id: 'p01', sentenceIds: <String>['s1']),
          const Paragraph(id: 'p02', sentenceIds: <String>['s2']),
        ],
        const LocalGoldenOptions(selected: <String>['s1', 's2']),
      );
      final md = goldenToMarkdown(lesson);
      expect(md, contains('### 开头段'));
      expect(md, contains('### 结尾段'));
      expect(md, isNot(contains('**First one here.**')));
    });

    test('反引号被转义，回车被去掉', () {
      final s = Sentence(
        id: 's1',
        paraId: 'p01',
        text: 'Use `code` here.\r\nNext line.',
      );
      final lesson = buildLocalGoldenLesson(
        <Sentence>[s],
        null,
        const LocalGoldenOptions(selected: <String>['s1']),
      );
      final md = goldenToMarkdown(
        lesson,
        sentences: <GoldenTextMeta>[GoldenTextMeta(id: s.id, text: s.text)],
      );
      expect(md, contains(r'\`code\`'));
      expect(md, isNot(contains('\r')));
    });
  });
}
