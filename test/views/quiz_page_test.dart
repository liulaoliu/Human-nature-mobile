// 整卷考试页 smoke：设置 → 作答 → 报告 → 改设置。
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dlaoshi_app/viewmodels/quiz_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/models/vocab.dart';
import 'package:dlaoshi_app/views/quiz_page.dart';
import 'smoke_harness.dart';

import '../support/vocab_fixture.dart';

void main() {
  setUpAll(smokeInitFfi);

  testWidgets('QuizPage：组卷、答题、交卷看报告、改设置', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);
    final vocab = smokeVocabRepo(db);
    await tester.runAsync(
      () => vocab.save(
        VocabLibrary(
          items: [
            vocabItem(word: 'mitigate', meaning: '减轻'),
            vocabItem(id: 'v2', word: 'harbor', lemma: 'harbor', meaning: '港口'),
          ],
        ),
      ),
    );

    await smokePump(tester, smokeApp(db, const QuizPage()));
    expect(find.text('整卷考试'), findsOneWidget);
    expect(find.text('考试模式'), findsOneWidget);

    final vm = Provider.of<QuizViewModel>(
      tester.element(find.byType(QuizPage)),
      listen: false,
    );
    // bootstrap 真读库：等它读完（按钮在 busy 时是禁用的）。
    for (var i = 0; i < 10 && vm.busy; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
    }
    expect(vm.busy, isFalse);

    await tester.tap(find.byKey(const ValueKey('quiz-start')));
    for (var i = 0; i < 10 && vm.busy; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
    }
    await tester.pump();

    // 默认词级卷（拼写 / 例句 / 搭配）：两三个词至少能出一道拼写题。
    expect(find.byType(TextField), findsOneWidget);

    // 一题一题答；每答完一题点「下一题」，直到出现报告。
    for (var i = 0; i < 8 && find.text('考试完成').evaluate().isEmpty; i++) {
      if (find.byKey(const ValueKey('quiz-submit')).evaluate().isNotEmpty) {
        await tester.enterText(find.byType(TextField), 'mitigate');
        await tester.tap(find.byKey(const ValueKey('quiz-submit')));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump();
      }
      if (find.byKey(const ValueKey('quiz-next')).evaluate().isNotEmpty) {
        await tester.tap(find.byKey(const ValueKey('quiz-next')));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump();
        await tester.pump();
      }
    }

    expect(find.text('考试完成'), findsOneWidget);
    expect(find.textContaining('正确率'), findsOneWidget);
    expect(find.textContaining('成绩已记录'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('quiz-back-setup')));
    await tester.pump();
    expect(find.text('整卷考试'), findsOneWidget);

    await smokeFinish(tester);
  });

  testWidgets('QuizPage 设置页：四个作答开关都在，点了真的改设置', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);

    await smokePump(tester, smokeApp(db, const QuizPage()));
    final vm = Provider.of<QuizViewModel>(
      tester.element(find.byType(QuizPage)),
      listen: false,
    );
    for (var i = 0; i < 10 && vm.busy; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
    }

    // 四个开关都在设置页（滚下去才看得到）。
    expect(find.byKey(const ValueKey('quiz-auto')), findsOneWidget);
    expect(find.byKey(const ValueKey('quiz-speak-after')), findsOneWidget);
    expect(find.byKey(const ValueKey('quiz-loop')), findsOneWidget);
    expect(find.byKey(const ValueKey('quiz-unique')), findsOneWidget);

    expect(vm.auto, isFalse);
    await tester.tap(find.byKey(const ValueKey('quiz-auto')));
    await tester.pump();
    expect(vm.auto, isTrue);

    expect(vm.speakAfter, isTrue);
    await tester.tap(find.byKey(const ValueKey('quiz-speak-after')));
    await tester.pump();
    expect(vm.speakAfter, isFalse);

    expect(vm.loopWrong, isFalse);
    await tester.tap(find.byKey(const ValueKey('quiz-loop')));
    await tester.pump();
    expect(vm.loopWrong, isTrue);

    expect(vm.unique, isTrue);
    await tester.tap(find.byKey(const ValueKey('quiz-unique')));
    await tester.pump();
    expect(vm.unique, isFalse);

    await smokeFinish(tester);
  });

  testWidgets('QuizPage：上次没考完，设置页能「继续上次考试」', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);
    final vocab = smokeVocabRepo(db);
    await tester.runAsync(
      () => vocab.save(
        VocabLibrary(
          items: [
            vocabItem(word: 'mitigate', meaning: '减轻'),
            vocabItem(id: 'v2', word: 'harbor', lemma: 'harbor', meaning: '港口'),
          ],
        ),
      ),
    );

    await smokePump(tester, smokeApp(db, const QuizPage()));
    final vm = Provider.of<QuizViewModel>(
      tester.element(find.byType(QuizPage)),
      listen: false,
    );
    for (var i = 0; i < 10 && vm.busy; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
    }

    await tester.runAsync(vm.start);
    await tester.pump();
    expect(vm.hasQueue, isTrue);
    vm.setInput(vm.question!.answer);
    await tester.runAsync(vm.submit);
    await tester.runAsync(vm.next);
    expect(vm.archive.hasSaved, isTrue);

    // 回设置页 → 应该出现「继续上次考试」。
    vm.reset();
    await tester.pump();
    expect(find.byKey(const ValueKey('quiz-resume')), findsOneWidget);
    expect(find.textContaining('上次考到第 2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('quiz-resume')));
    await tester.pump();
    expect(vm.hasQueue, isTrue);
    expect(find.byKey(const ValueKey('quiz-resume')), findsNothing);

    await smokeFinish(tester);
  });

  testWidgets('QuizPage：没有文章时文章卷不能开考', (tester) async {    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);

    await smokePump(tester, smokeApp(db, const QuizPage()));
    await tester.tap(find.text('文章卷'));
    await tester.pump();

    expect(find.textContaining('还没有文章'), findsOneWidget);
    final start = tester.widget<FilledButton>(
      find.byKey(const ValueKey('quiz-start')),
    );
    expect(start.onPressed, isNull);

    await smokeFinish(tester);
  });
}
