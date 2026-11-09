import 'package:dlaoshi_app/core/golden.dart';
import 'package:dlaoshi_app/core/golden_drill.dart';
import 'package:flutter_test/flutter_test.dart';

const String _text =
    'In response to the pandemic, remote collaboration has become the new norm.';

const List<GoldenTarget> _targets = <GoldenTarget>[
  GoldenTarget(en: 'in response to', zh: '为了应对', kind: GoldenTargetKind.collocation),
  GoldenTarget(en: 'remote collaboration', zh: '远程协作', kind: GoldenTargetKind.collocation),
  GoldenTarget(en: 'has become', zh: '已经成为', kind: GoldenTargetKind.tense),
];

String _blankAnswers(GoldenCloze cloze) =>
    cloze.blanks.map((b) => b.answer).join(' ');

void main() {
  group('金句挖空 / 拼句 / 逆向默写', () {
    test('默认按语言点整块挖；同一目标重复出现共用一个空', () {
      final cloze = buildGoldenCloze('In response to this, in response to that.', <GoldenTarget>[
        const GoldenTarget(en: 'in response to', kind: GoldenTargetKind.collocation),
      ]);
      expect(cloze, isNotNull);
      expect(cloze!.blanks, hasLength(1));
      expect(cloze.parts.where((p) => p.blank), hasLength(2));
    });

    test('按词拆：for every day = 3 个空；大小写不敏感', () {
      final cloze = buildGoldenCloze(
        'We practice for every day.',
        <GoldenTarget>[
          const GoldenTarget(
            en: 'for every day',
            zh: '每一天',
            kind: GoldenTargetKind.collocation,
          ),
        ],
        const GoldenClozeOptions(splitWords: true),
      );
      expect(cloze, isNotNull);
      expect(cloze!.blanks.map((b) => b.answer).toList(), <String>['for', 'every', 'day']);
      expect(cloze.blanks.map((b) => b.index).toList(), <int>[1, 2, 3]);
      expect(cloze.blanks[0].hint, '每一天');
      expect(cloze.blanks[1].hint, isNull);
      expect(checkGoldenFill(cloze, <String>['FOR', 'Every', 'DAY']), <bool>[true, true, true]);
    });

    test('细碎轮次：keep up with → with → up with → keep up with', () {
      final rounds = buildGoldenFillRounds('We should keep up with the news.', <GoldenTarget>[
        const GoldenTarget(en: 'keep up with', zh: '跟上', kind: GoldenTargetKind.idiom),
      ]);
      expect(
        rounds.map((r) => _blankAnswers(r.cloze)).toList(),
        <String>['with', 'up with', 'keep up with'],
      );
    });

    test('整句渐进：一个词 → 全部目标词 → 整句', () {
      final rounds =
          buildGoldenSentenceFillRounds('We should keep up with the news.', <GoldenTarget>[
        const GoldenTarget(en: 'keep up with', zh: '跟上', kind: GoldenTargetKind.idiom),
      ]);
      expect(
        rounds.map((r) => _blankAnswers(r.cloze)).toList(),
        <String>['with', 'keep up with', 'We should keep up with the news'],
      );
      expect(rounds.every((r) => r.scope == 'sentence'), isTrue);
    });

    test('整句渐进：释义只挂在目标首词，不把第一个语言点的释义贴到无关空', () {
      final rounds =
          buildGoldenSentenceFillRounds('We should keep up with the news.', <GoldenTarget>[
        const GoldenTarget(en: 'keep up with', zh: '跟上', kind: GoldenTargetKind.idiom),
        const GoldenTarget(en: 'the news', zh: '新闻', kind: GoldenTargetKind.collocation),
      ]);
      final last = rounds.last.cloze;
      final hintOf = <String, String?>{
        for (final b in last.blanks) b.answer: b.hint,
      };
      expect(hintOf['keep'], '跟上');
      expect(hintOf['the'], '新闻');
      expect(hintOf['We'], isNull);
      expect(hintOf['should'], isNull);
      expect(hintOf['up'], isNull);
      expect(hintOf['with'], isNull);
      expect(hintOf['news'], isNull);
    });

    test('填空计划：target 模式 + 关闭整句只留语言点轮', () {
      final rounds = buildGoldenFillPlan(
        _text,
        _targets,
        const GoldenFillPlanOptions(blankUnit: 'target', sentenceFill: false),
      );
      expect(rounds, hasLength(1));
      expect(rounds.first.scope, 'target');
      expect(rounds.first.cloze.blanks, hasLength(_targets.length));
    });

    test('填空计划：开启整句时追加复述轮，且同一组空不重复', () {
      final rounds = buildGoldenFillPlan('We should keep up with the news.', <GoldenTarget>[
        const GoldenTarget(en: 'keep up with', zh: '跟上', kind: GoldenTargetKind.idiom),
      ]);
      expect(rounds.any((r) => r.scope == 'sentence'), isTrue);
      expect(rounds.map((r) => goldenClozeKey(r.cloze)).toSet(), hasLength(rounds.length));
    });

    test('长句最后一轮只挖目标所在的分句，避免一次填整段', () {
      const long =
          'The committee reviewed the draft, and the board considered the budget after the staff published the detailed report about the new plan for next year and the following season.';
      final rounds = buildGoldenSentenceFillRounds(long, <GoldenTarget>[
        const GoldenTarget(
          en: 'considered the budget',
          zh: '审议预算',
          kind: GoldenTargetKind.collocation,
        ),
      ]);
      expect(rounds, isNotEmpty);
      final last = rounds.last.cloze;
      expect(last.blanks.length, greaterThan(1));
      expect(last.blanks.length, lessThan(long.split(RegExp(r'\s+')).length));
      expect(_blankAnswers(last), contains('considered the budget'));
    });

    test('按词拆时重复目标共用同一组空', () {
      final cloze = buildGoldenCloze(
        'Day by day, day by day.',
        <GoldenTarget>[
          const GoldenTarget(en: 'day by day', kind: GoldenTargetKind.idiom),
        ],
        const GoldenClozeOptions(splitWords: true),
      );
      expect(cloze!.blanks, hasLength(3));
      expect(cloze.parts.where((p) => p.blank).length, 6);
    });

    test('填空判分忽略大小写/标点；拼句按顺序', () {
      final cloze = buildGoldenCloze(_text, _targets);
      expect(cloze, isNotNull);
      expect(
        checkGoldenFill(cloze!, <String>[
          'In response to',
          'remote collaboration',
          'has become',
        ]),
        <bool>[true, true, true],
      );
      expect(
        checkGoldenFill(cloze, <String>['response to', 'remote collaboration', 'has become']),
        <bool>[false, true, true],
      );
      final bank = buildGoldenAssembly(_text, _targets);
      expect(bank, isNotNull);
      expect(
        checkGoldenAssembly(
          bank!.cloze.targets,
          bank.cloze.targets.map((t) => t.en).toList(),
        ),
        isTrue,
      );
      expect(
        checkGoldenAssembly(bank.cloze.targets, <String>[
          'has become',
          'remote collaboration',
          'in response to',
        ]),
        isFalse,
      );
      // 种子固定：同一句两次拼句银行顺序一致
      expect(buildGoldenAssembly(_text, _targets)!.bank, bank.bank);
    });

    test('逆向默写：exact / near 算首次正确，loose 不算', () {
      expect(checkGoldenRecall(_text, _text).firstOk, isTrue);
      expect(
        checkGoldenRecall(
          'In response to the pandemic, remote collaboration has become the new norm',
          _text,
        ).firstOk,
        isTrue,
      );
      expect(checkGoldenRecall('Remote work is popular now.', _text).firstOk, isFalse);
      expect(checkGoldenRecall('   ', _text).firstOk, isFalse);
    });

    test('挖空全对判定：空列表不算通过', () {
      expect(goldenFillAllCorrect(<bool>[true, true]), isTrue);
      expect(goldenFillAllCorrect(<bool>[true, false]), isFalse);
      expect(goldenFillAllCorrect(<bool>[]), isFalse);
    });
  });
}
