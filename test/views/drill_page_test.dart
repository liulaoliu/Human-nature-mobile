// 快速拷打页的界面用例：选档 → 出卷 → 判分 → 结算。
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

  Future<DrillViewModel> openPage(WidgetTester tester, Database db) async {
    final vm = DrillViewModel(
      vocab: VocabRepository(db),
      learning: smokeLearningRepo(db),
      articles: ArticleRepository(db),
      prefsStore: PrefsStore.memory(),
    );
    addTearDown(vm.dispose);
    await smokePump(tester, smokeApp(db, const DrillPage(), quickDrill: vm));
    return vm;
  }

  testWidgets('设置页：七档都在，没做的标「待开」并禁用', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);
    await seedWords(tester, db);

    await openPage(tester, db);

    for (final kind in QuizDrillKind.values) {
      expect(
        find.byKey(ValueKey<String>('drill-kind-${kind.name}')),
        findsOneWidget,
        reason: '${kind.name} 这一档应该看得见',
      );
      expect(find.text(quizDrillLabel[kind]!), findsOneWidget);
    }
    // 首批三档能跑，其余四档标「待开」。
    expect(find.text('待开'), findsNWidgets(4));
    // 题量档位五个都在。
    for (final n in drillLimitOptions) {
      expect(find.byKey(ValueKey<String>('drill-limit-$n')), findsOneWidget);
    }

    await smokeFinish(tester);
  });

  testWidgets('点「待开」的档位不换档', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);
    await seedWords(tester, db);
    final vm = await openPage(tester, db);

    expect(vm.kind, QuizDrillKind.memory);
    await tester.tap(find.byKey(const ValueKey<String>('drill-kind-deep')));
    await tester.pump();
    expect(vm.kind, QuizDrillKind.memory);

    await smokeFinish(tester);
  });

  testWidgets('开始后进答题界面：进度、题干、底栏都在', (tester) async {
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

    expect(vm.hasQueue, isTrue);
    expect(find.byKey(const ValueKey<String>('drill-next')), findsOneWidget);
    expect(find.text('收工'), findsOneWidget);
    expect(find.textContaining('第 1/'), findsOneWidget);

    await smokeFinish(tester);
  });

  testWidgets('答完最后一题给结算：对错数 + 错题重做', (tester) async {
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
}
