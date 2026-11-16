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

/// 两个学习点的课：用来试「顺序拼错」。
const GoldenLesson _lessonTwo = GoldenLesson(
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
        GoldenTarget(
          en: 'every morning',
          kind: GoldenTargetKind.word,
          zh: '每天早上',
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

    test('判分后再改答案：reopenFill 收起判分，轮次不动', () {
      final s = _session(lesson: _lesson).session;
      s.open('s1');
      final before = s.roundIndex;
      s.submitFill(<String>['错的']);
      expect(s.roundScored, isTrue);
      expect(s.roundResults, isNotEmpty);

      s.reopenFill();
      expect(s.roundScored, isFalse);
      expect(s.roundResults, isEmpty);
      expect(s.roundIndex, before, reason: '只是撤判分，不是换轮');

      // 没判分时重复调用是空操作。
      s.reopenFill();
      expect(s.roundScored, isFalse);
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

    test('拼句：点选 / 撤回 / 清空，拼对才记一步并进小结', () {
      final ctx = _session(lesson: _lesson);
      final s = ctx.session;
      s.open('s1');
      final bank = s.assembly!.bank;

      s.pick(bank.first);
      s.undo();
      expect(s.order, isEmpty);
      s.pick(bank.first);
      s.removeAt(0);
      expect(s.order, isEmpty);
      s.pick(bank.first);
      s.clearOrder();
      expect(s.order, isEmpty);

      // 银行里没有的词块不算数（拼句只能用给出的词块）。
      s.pick('not a chunk');
      expect(s.order, isEmpty);

      // 重拼，按正确顺序。
      for (final word in s.targets.map((t) => t.en)) {
        s.pick(word);
      }
      expect(s.submitAssembly(), isTrue);
      expect(ctx.log.where((e) => e.contains('assemble')), hasLength(1));
      expect(s.phase, GoldenDrillPhase.summary);
      expect(s.readyForSummary, isTrue);
    });

    test('拼句：同一个词块只能点一次（用户 2026-11-16 报的问题）', () {
      final s = _session(lesson: _lesson).session;
      s.open('s1');
      final word = s.assembly!.bank.first;

      expect(s.canPick(word), isTrue);
      s.pick(word);
      expect(s.order, <String>[word]);
      // 银行里只有一份，再点不接受。
      expect(s.canPick(word), isFalse);
      s.pick(word);
      expect(s.order, <String>[word]);
    });

    test('拼句：顺序拼错判错，重拼后按对顺序才记一步', () {
      final ctx = _session(lesson: _lessonTwo);
      final s = ctx.session;
      s.open('s1');
      final bank = s.assembly!.bank;
      expect(bank, hasLength(2));

      // 倒序拼（bank 是打乱的，直接取 targets 的倒序）。
      for (final word in s.targets.reversed.map((t) => t.en)) {
        s.pick(word);
      }
      expect(s.order, hasLength(2));
      expect(s.submitAssembly(), isFalse);
      expect(ctx.log.where((e) => e.contains('assemble')), isEmpty);
      expect(s.phase, GoldenDrillPhase.fill);

      s.retryAssembly();
      for (final word in s.targets.map((t) => t.en)) {
        s.pick(word);
      }
      expect(s.submitAssembly(), isTrue);
      expect(ctx.log.where((e) => e.contains('assemble')), hasLength(1));
    });

    test('拼句：词块全点齐才算完整', () {
      final s = _session(lesson: _lessonTwo).session;
      s.open('s1');
      expect(s.orderComplete, isFalse);
      s.pick(s.targets.first.en);
      expect(s.orderComplete, isFalse);
      s.pick(s.targets.last.en);
      expect(s.orderComplete, isTrue);
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

    test('旧课里存了整块挖空，练习仍严格一个词一个空', () {
      final s = _session(
        lesson: _lesson.copyWith(
          options: const GoldenLessonOptions(blankUnit: GoldenBlankUnit.target),
        ),
      ).session;
      s.open('s1');
      expect(s.hasRounds, isTrue);
      // 第一轮只挖目标最后一个词（with），不是把 keep up with 塞进一个空。
      expect(s.round!.blanks.map((b) => b.answer).toList(), <String>['with']);
      var guard = 0;
      while (s.round != null && guard++ < 20) {
        for (final b in s.round!.blanks) {
          expect(b.answer, isNot(matches(RegExp(r'\s'))));
        }
        if (s.roundIndex + 1 < s.roundCount) {
          s.nextRound();
        } else {
          break;
        }
      }
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
