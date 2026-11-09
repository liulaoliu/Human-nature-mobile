import 'package:dlaoshi_app/core/golden.dart';
import 'package:dlaoshi_app/core/golden_bank.dart';
import 'package:dlaoshi_app/core/golden_progress.dart';
import 'package:dlaoshi_app/models/document.dart';
import 'package:flutter_test/flutter_test.dart';

Sentence _s(
  String id,
  String text, {
  String? translation,
  SentenceLanguage? language,
}) =>
    Sentence(
      id: id,
      paraId: 'p01',
      text: text,
      translation: translation,
      language: language,
    );

final Sentence _sentence = _s(
  's1',
  'In response to the pandemic, remote collaboration has become the new norm.',
  translation: '为了应对疫情，远程协作已经成为新常态。',
  language: const SentenceLanguage(
    phrases: <String>['in response to — 为了应对'],
    grammar: '现在完成时',
  ),
);

GoldenLesson _lesson() => buildLocalGoldenLesson(
      <Sentence>[_sentence],
      null,
      const LocalGoldenOptions(selected: <String>['s1']),
    );

List<GoldenBankSource> _sources() => <GoldenBankSource>[
      GoldenBankSource(
        id: 'a1',
        title: 'A 篇',
        sentences: <GoldenTextMeta>[
          GoldenTextMeta(
            id: 's1',
            text: _sentence.text,
            translation: _sentence.translation,
          ),
        ],
        golden: _lesson(),
      ),
    ];

void main() {
  group('全库金句本', () {
    test('摊平金句并带上掌握状态', () {
      final lesson = _lesson();
      final rec = emptyGoldenRecord(
        'a1',
        'A 篇',
        's1',
        goldenDrillKey(_sentence.text, lesson.sentences.first.targets),
        '2026-01-01T00:00:00.000Z',
      ).copyWith(
        mastered: true,
        fillFirst: () => true,
        assembleFirst: () => true,
        recallFirst: () => true,
        summarySeen: () => true,
      );
      final rows = buildGoldenBank(
        _sources(),
        <GoldenDrillRecord>[rec],
        DateTime.parse('2026-01-02T00:00:00.000Z'),
      );
      expect(rows, hasLength(1));
      final row = rows.first;
      expect(row.articleId, 'a1');
      expect(row.articleTitle, 'A 篇');
      expect(row.sentenceId, 's1');
      expect(row.mastered, isTrue);
      expect(row.due, isTrue);
      expect(row.zh, '为了应对疫情，远程协作已经成为新常态。');
      expect(row.targets, isNotEmpty);
    });

    test('没有 golden 的文章不出现', () {
      final rows = buildGoldenBank(
        <GoldenBankSource>[
          const GoldenBankSource(
            id: 'a2',
            title: 'B 篇',
            sentences: <GoldenTextMeta>[
              GoldenTextMeta(id: 's1', text: 'Nothing here.'),
            ],
          ),
        ],
        const <GoldenDrillRecord>[],
      );
      expect(rows, isEmpty);
    });

    test('搜索 / 状态筛选', () {
      final rows = buildGoldenBank(
        _sources(),
        const <GoldenDrillRecord>[],
        DateTime.parse('2026-01-02T00:00:00.000Z'),
      );
      expect(filterGoldenBank(rows, query: '远程'), hasLength(1));
      expect(filterGoldenBank(rows, query: '不存在的词'), isEmpty);
      expect(filterGoldenBank(rows, status: GoldenBankStatus.todo), hasLength(1));
      expect(filterGoldenBank(rows, status: GoldenBankStatus.mastered), isEmpty);
      expect(filterGoldenBank(rows, status: GoldenBankStatus.due), isEmpty);
    });

    test('按学习点类型筛：句子里有该类型才命中', () {
      final rows = buildGoldenBank(
        _sources(),
        const <GoldenDrillRecord>[],
        DateTime.parse('2026-01-02T00:00:00.000Z'),
      );
      final kinds = rows.first.targets.map((t) => t.kind).toSet();
      expect(kinds, isNotEmpty);
      final hit = kinds.first;
      final bankKind = GoldenBankKind.values.firstWhere(
        (k) => goldenBankKindOf(k) == hit,
      );
      expect(filterGoldenBank(rows, kind: bankKind), hasLength(1));
      expect(filterGoldenBank(rows, kind: GoldenBankKind.all), hasLength(1));
      expect(
        filterGoldenBank(rows, kind: bankKind, query: '远程'),
        hasLength(1),
      );
      expect(
        filterGoldenBank(rows, kind: bankKind, query: '不存在的词'),
        isEmpty,
      );
    });

    test('Markdown / Anki / 打印导出', () {
      final rows = buildGoldenBank(
        _sources(),
        const <GoldenDrillRecord>[],
        DateTime.parse('2026-01-02T00:00:00.000Z'),
      );
      final md = goldenBankToMarkdown(rows);
      expect(md, contains('# 全库金句本'));
      expect(md, contains('## A 篇'));
      expect(md, contains('In response to the pandemic'));
      expect(md, contains('共 1 句 · 0 句已掌握'));

      final csv = goldenBankToAnkiCsv(rows);
      expect(csv.split('\n').first, 'Front,Back,Tags');
      expect(csv, contains('In response to the pandemic'));
      expect(goldenBankToAnkiCsv(rows, header: false), isNot(contains('Front,')));

      final html = goldenBankToPrintHtml(rows);
      expect(html, contains('<title>全库金句本</title>'));
      expect(html, contains('In response to the pandemic'));
      expect(html, contains('columns: 2'));
    });

    test('CSV 里带逗号 / 引号的字段被正确转义', () {
      final lesson = buildLocalGoldenLesson(
        <Sentence>[
          _s('s1', 'He said "hello, world" loudly.'),
        ],
        null,
        const LocalGoldenOptions(selected: <String>['s1']),
      );
      final rows = buildGoldenBank(
        <GoldenBankSource>[
          GoldenBankSource(
            id: 'a1',
            title: 'A, 篇',
            sentences: const <GoldenTextMeta>[
              GoldenTextMeta(id: 's1', text: 'He said "hello, world" loudly.'),
            ],
            golden: lesson,
          ),
        ],
        const <GoldenDrillRecord>[],
      );
      final csv = goldenBankToAnkiCsv(rows);
      expect(csv, contains('"He said ""hello, world"" loudly."'));
      expect(csv, contains('A__篇'));
    });
  });
}
