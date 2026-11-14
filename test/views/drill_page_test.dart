// 快速拷打页的界面用例：选档 → 预习 / 出卷 → 判分 → 结算。
//
// 规则与状态机在 `test/core/quiz_*`、`test/viewmodels/drill_view_model_test.dart`
// 已经覆盖；这里只验「界面把状态摆对、点得动」。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:dlaoshi_app/core/quiz_drill.dart';
import 'package:dlaoshi_app/data/prefs_store.dart';
import 'package:dlaoshi_app/data/repositories/article_repository.dart';
import 'package:dlaoshi_app/data/repositories/vocab_repository.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:dlaoshi_app/viewmodels/drill_view_model.dart';
import 'package:dlaoshi_app/views/drill_page.dart';
import 'smoke_harness.dart';

void main() {
  setUpAll(smokeInitFfi);

  /// 四个有释义的词，够选义题凑干扰项。
  Future<void> seedWords(WidgetTester tester, Database db) async {
    await tester.runAsync(() async {
      final repo = VocabRepository(db);
      await repo.save(
        VocabLibrary(
          items: <VocabItem>[
            for (final w in <String>['alpha', 'beta', 'gamma', 'delta'])
              VocabItem(
                id: 'v-$w',
                word: w,
                lemma: w,
                meaning: '$w 的意思',
                status: VocabStatus.queried,
                createdAt: '2026-01-01T00:00:00.000Z',
                updatedAt: '2026-01-01T00:00:00.000Z',
              ),
          ],
        ),
      );
    });
  }

  Future<DrillViewModel> openPage(
    WidgetTester tester,
    Database db, {
    QuizDrillKind? initialKind,
  }) async {
    final vm = DrillViewModel(
      vocab: VocabRepository(db),
      learning: smokeLearningRepo(db),
      articles: ArticleRepository(db),
      prefsStore: PrefsStore.memory(),
    );
    addTearDown(vm.dispose);
    await smokePump(
      tester,
      smokeApp(db, DrillPage(initialKind: initialKind), quickDrill: vm),
    );
    return vm;
  }

  /// 点「开始」并等到真正进答题页：记忆 / 词块档会先停在「先看一遍」，
  /// 要多点一下「看完了，开始拷打」（用户 m32314）。
  Future<void> startRound(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey<String>('drill-start')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
    await tester.pump();
    final warmStart = find.byKey(const ValueKey<String>('drill-warm-start'));
    if (warmStart.evaluate().isNotEmpty) {
      await tester.tap(warmStart);
      await tester.pump();
    }
  }

  testWidgets('设置页：七档都在，全部可点（没有「待开」）', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);
    await seedWords(tester, db);
    final vm = await openPage(tester, db);

    for (final kind in QuizDrillKind.values) {
      expect(
        find.byKey(ValueKey<String>('drill-kind-${kind.name}')),
        findsOneWidget,
        reason: '${kind.name} 这一档应该看得见',
      );
      expect(find.text(quizDrillLabel[kind]!), findsOneWidget);
    }
    // 七档全开：没有「待开」，题量档位五个都在。
    expect(find.text('待开'), findsNothing);
    for (final n in drillLimitOptions) {
      expect(find.byKey(ValueKey<String>('drill-limit-$n')), findsOneWidget);
    }
    // 以前点不动的 grammar 现在真能选中。
    await tester.tap(find.byKey(const ValueKey<String>('drill-kind-grammar')));
    await tester.pump();
    expect(vm.kind, QuizDrillKind.grammar);

    await smokeFinish(tester);
  });

  testWidgets('默认记忆档，点别的档真的能换', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);
    await seedWords(tester, db);
    final vm = await openPage(tester, db);

    expect(vm.kind, QuizDrillKind.memory);
    await tester.tap(find.byKey(const ValueKey<String>('drill-kind-chunk')));
    await tester.pump();
    expect(vm.kind, QuizDrillKind.chunk);

    await smokeFinish(tester);
  });

  testWidgets('记忆档先「先看一遍」，看完才开考', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);
    await seedWords(tester, db);
    final vm = await openPage(tester, db);

    await tester.tap(find.byKey(const ValueKey<String>('drill-limit-5')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('drill-start')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
    await tester.pump();

    // 停在预习页：题已出好但还没进队列。
    expect(vm.warmup, isTrue);
    expect(vm.hasQueue, isFalse, reason: '预习页不该直接开考');
    expect(find.text('记忆拷打 · 先看一遍'), findsOneWidget);
    expect(find.textContaining('这轮要考'), findsOneWidget);
    expect(find.text('alpha'), findsOneWidget, reason: '预习卡把词摊开了');
    expect(find.byKey(const ValueKey<String>('drill-warm-start')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('drill-next')), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('drill-warm-start')));
    await tester.pump();
    expect(vm.warmup, isFalse);
    expect(vm.hasQueue, isTrue);
    expect(find.byKey(const ValueKey<String>('drill-next')), findsOneWidget);

    await smokeFinish(tester);
  });

  testWidgets('预习页「取消」回设置页，这轮不出题', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);
    await seedWords(tester, db);
    final vm = await openPage(tester, db);

    await tester.tap(find.byKey(const ValueKey<String>('drill-start')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
    await tester.pump();
    expect(vm.warmup, isTrue);

    await tester.tap(find.byKey(const ValueKey<String>('drill-warm-cancel')));
    await tester.pump();
    expect(vm.warmup, isFalse);
    expect(vm.hasQueue, isFalse);
    expect(find.byKey(const ValueKey<String>('drill-start')), findsOneWidget);

    await smokeFinish(tester);
  });

  testWidgets('预习页换题量会重新抽卡，仍停在预习页', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);
    await seedWords(tester, db);
    final vm = await openPage(tester, db);

    await tester.tap(find.byKey(const ValueKey<String>('drill-start')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
    await tester.pump();
    expect(vm.warmup, isTrue);
    expect(vm.limit, defaultDrillLimit);

    await tester.tap(find.byKey(const ValueKey<String>('drill-warm-limit-5')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
    await tester.pump();
    expect(vm.limit, 5);
    expect(vm.warmup, isTrue, reason: '换题量重新抽卷，还是先看一遍');

    await smokeFinish(tester);
  });

  testWidgets('开始拷打后答案输入框自动聚焦', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);
    await seedWords(tester, db);
    await openPage(tester, db);

    await tester.tap(find.byKey(const ValueKey<String>('drill-limit-5')));
    await tester.pump();
    await startRound(tester);
    await tester.pump(); // 让 addPostFrameCallback 里的 requestFocus 生效

    final field = tester.widget<TextField>(
      find.byKey(const ValueKey<String>('drill-input')),
    );
    expect(field.focusNode?.hasFocus, isTrue, reason: '不用用户手动点输入框');

    await smokeFinish(tester);
  });

  testWidgets('开始后进答题界面：进度、题干、底栏都在', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);
    await seedWords(tester, db);
    final vm = await openPage(tester, db);

    await tester.tap(find.byKey(const ValueKey<String>('drill-limit-5')));
    await tester.pump();
    await startRound(tester);

    expect(vm.hasQueue, isTrue);
    expect(find.byKey(const ValueKey<String>('drill-next')), findsOneWidget);
    expect(find.text('收工'), findsOneWidget);
    expect(find.textContaining('第 1/'), findsOneWidget);

    await smokeFinish(tester);
  });

  testWidgets('进度条吸顶：滚题目区时它不动，底栏也还在', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);
    await seedWords(tester, db);
    await openPage(tester, db);

    await tester.tap(find.byKey(const ValueKey<String>('drill-limit-5')));
    await tester.pump();
    await startRound(tester);

    final progress = find.textContaining('第 1/');
    expect(progress, findsOneWidget);
    final before = tester.getTopLeft(progress);

    // 把题目区往上拖（滚动容器是 Expanded 里那个 ListView）。
    await tester.drag(
      find.byType(ListView).first,
      const Offset(0, -260),
    );
    await tester.pump();

    final after = tester.getTopLeft(progress);
    expect(after, before, reason: '进度条吸顶，不该跟着内容滚走');
    // 底栏还在原处。
    expect(find.text('收工'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('drill-next')), findsOneWidget);

    await smokeFinish(tester);
  });

  testWidgets('设置页功能区吸底：滚选档列表时题量与开始按钮不动', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);
    await seedWords(tester, db);
    await openPage(tester, db);

    final label = find.text('这一轮多少题');
    final start = find.byKey(const ValueKey<String>('drill-start'));
    expect(label, findsOneWidget);
    expect(start, findsOneWidget);
    final beforeLabel = tester.getTopLeft(label);
    final beforeStart = tester.getTopLeft(start);

    // 选档列表是 Expanded 里那个 ListView，往上拖；功能区挂在它外面。
    await tester.drag(
      find.byType(ListView).first,
      const Offset(0, -260),
    );
    await tester.pump();

    expect(tester.getTopLeft(label), beforeLabel, reason: '题量标题吸底，不该跟着滚');
    expect(tester.getTopLeft(start), beforeStart, reason: '开始按钮吸底');
    for (final n in drillLimitOptions) {
      expect(find.byKey(ValueKey<String>('drill-limit-$n')), findsOneWidget);
    }

    await smokeFinish(tester);
  });

  testWidgets('答完最后一题给结算：对错数 + 错题重做', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);
    await seedWords(tester, db);
    final vm = await openPage(tester, db);

    await tester.tap(find.byKey(const ValueKey<String>('drill-limit-5')));
    await tester.pump();
    await startRound(tester);

    // 全部故意答错，好让结算出现「错题重做」。
    while (vm.question != null) {
      await tester.runAsync(() => vm.submit('zzzz-wrong'));
      vm.next();
      await tester.pump();
    }
    await tester.pump();

    expect(find.text('这一轮做完了'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('drill-retry-wrong')),
      findsOneWidget,
    );

    await smokeFinish(tester);
  });

  testWidgets('从「语法专项」进来，直接落在 grammar 档', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);
    await seedWords(tester, db);
    final vm = await openPage(
      tester,
      db,
      initialKind: QuizDrillKind.grammar,
    );

    expect(vm.kind, QuizDrillKind.grammar);
    // 选档页上 grammar 那张卡是选中态，主按钮文案也跟着变。
    expect(find.text('开始（语法·结构）'), findsOneWidget);

    await smokeFinish(tester);
  });
}
