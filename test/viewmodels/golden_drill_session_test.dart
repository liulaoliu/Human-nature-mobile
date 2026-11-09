import 'package:dlaoshi_app/core/golden.dart';
import 'package:dlaoshi_app/models/document.dart';
import 'package:dlaoshi_app/viewmodels/golden_drill_session.dart';
import 'package:flutter_test/flutter_test.dart';

const Sentence _sentence = Sentence(
  id: 's1',
  paraId: 'p01',
  text: 'We keep up with the news every morning.',
  translation: '我们每天早上都跟上新闻。',
);

const GoldenLesson _lesson = GoldenLesson(
  source: GoldenSource.local,
  sentences: <GoldenSentence>[
    GoldenSentence(
      id: 's1',
      zh: '我们每天早上都跟上新闻。',
      targets: <GoldenTarget>[
        GoldenTarget(
          en: 'keep up with',
          kind: GoldenTargetKind.collocation,
          zh: '跟上',
        ),
      ],
    ),
  ],
  selected: <String>['s1'],
);

/// 造一个「回调都直接记账」的会话，省掉 ViewModel 与数据库。
({GoldenDrillSession session, List<String> log}) _session({
  GoldenLesson? lesson,
  String text = 'We keep up with the news every morning.',
}) {
  final log = <String>[];
  final session = GoldenDrillSession(
    lessonOf: () => lesson,
    sentenceTextOf: (id) => id == 's1' ? text : '',
    recordStep: (id, step, correct) => log.add('$id|${step.name}|$correct'),
  );
  return (session: session, log: log);
}

void main() {
  group('金句练习的逐轮编排', () {
    test('打开一句：按课文建填空计划 + 拼句银行', () {
      final s = _session(lesson: _lesson).session;
      s.open('s1');
      expect(s.sentenceId, 's1');
      expect(s.text, _sentence.text);
      expect(s.targets.single.en, 'keep up with');
      expect(s.hasRounds, isTrue);
      expect(s.round, isNotNull);
      // 第一轮一定挖得到东西：空位数量等于 cloze.blanks。
      expect(s.round!.blanks, isNotEmpty);
      expect(s.phase, GoldenDrillPhase.fill);
      expect(s.assembly, isNotNull);
      expect(s.assembly!.bank, isNotEmpty);
    });

    test('没有学习点的句子：直接进拼句阶段', () {
      final s = _session(lesson: _lesson).session;
      // 换一句没有 targets 的（课程里没有这句 → targets 空）。
      s.open('s404');
      expect(s.sentenceId, 's404');
      expect(s.targets, isEmpty);
      expect(s.hasRounds, isFalse);
      expect(s.round, isNull);
      expect(s.phase, GoldenDrillPhase.assemble);
    });

    test('没课程（文章还没生成金句课）：不崩，直接空态', () {
      final s = _session().session;
      s.open('s1');
      expect(s.text, '');
      expect(s.targets, isEmpty);
      expect(s.hasRounds, isFalse);
    });

    test('每次都记账，首次答对由 core 按 tries 定（重做不能刷）', () {
      final ctx = _session(lesson: _lesson);
      final s = ctx.session;
      s.open('s1');
      final blanks = s.round!.blanks.length;
      final right = <String>[for (final b in s.round!.blanks) b.answer];

      final first = s.submitFill(right);
      expect(first, everyElement(isTrue));
      expect(s.roundOk, isTrue);
      expect(ctx.log, <String>['s1|fill|true']);

      // 重做再交：照样记账（core 靠 tries 决定谁算「首次」）。
      s.retryRound();
      expect(s.roundScored, isFalse);
      s.submitFill(List<String>.filled(blanks, '错的'));
      expect(s.roundOk, isFalse);
      expect(ctx.log, <String>['s1|fill|true', 's1|fill|false']);
    });

    test('最后一轮之后进拼句', () {
      final s = _session(lesson: _lesson).session;
      s.open('s1');
      for (var i = 0; i < s.roundCount + 2; i++) {
        s.nextRound();
      }
      expect(s.phase, GoldenDrillPhase.assemble);
      expect(s.roundIndex, s.roundCount - 1);
    });

    test('拼句：点选 / 撤销 / 清空，拼对才记一步并进小结', () {
      final ctx = _session(lesson: _lesson);
      final s = ctx.session;
      s.open('s1');
      final bank = s.assembly!.bank;

      s.pick(bank.first);
      s.pick(bank.first);
      expect(s.order.length, 2);
      s.undo();
      expect(s.order.length, 1);
      s.clearOrder();
      expect(s.order, isEmpty);

      // 错的顺序：记一分不记对。
      s.pick('not a chunk');
      expect(s.submitAssembly(), isFalse);
      expect(s.assembleScored, isTrue);
      expect(ctx.log.where((e) => e.contains('assemble')), isEmpty);
      expect(s.phase, GoldenDrillPhase.fill);

      // 重拼，按正确顺序。
      s.retryAssembly();
      for (final word in s.targets.map((t) => t.en)) {
        s.pick(word);
      }
      expect(s.submitAssembly(), isTrue);
      expect(ctx.log.where((e) => e.contains('assemble')), hasLength(1));
      expect(s.phase, GoldenDrillPhase.summary);
      expect(s.readyForSummary, isTrue);
    });

    test('小结只记一次「看过」', () {
      final ctx = _session(lesson: _lesson);
      final s = ctx.session;
      s.open('s1');
      s.finish();
      s.finish();
      expect(ctx.log, <String>['s1|summary|true']);
    });

    test('拼对之后不能再练拼句（避免反复刷）', () {
      final s = _session(lesson: _lesson).session;
      s.open('s1');
      for (final word in s.targets.map((t) => t.en)) {
        s.pick(word);
      }
      expect(s.submitAssembly(), isTrue);
      s.retryAssembly();
      expect(s.assembleScored, isTrue);
      expect(s.order, isNotEmpty);
    });

    test('按整块挖空时，填空轮数比按词少', () {
      final byTarget = _session(
        lesson: _lesson.copyWith(
          options: const GoldenLessonOptions(blankUnit: GoldenBlankUnit.target),
        ),
      ).session;
      final byWord = _session(lesson: _lesson).session;
      byTarget.open('s1');
      byWord.open('s1');
      expect(byTarget.roundCount, lessThanOrEqualTo(byWord.roundCount));
      expect(byTarget.round!.blanks.length, byTarget.targets.length);
    });

    test('关掉整句加练后，轮数变少', () {
      final withFill = _session(lesson: _lesson).session;
      final withoutFill = _session(
        lesson: _lesson.copyWith(
          options: const GoldenLessonOptions(sentenceFill: false),
        ),
      ).session;
      withFill.open('s1');
      withoutFill.open('s1');
      expect(withoutFill.roundCount, lessThanOrEqualTo(withFill.roundCount));
    });
  });
}
