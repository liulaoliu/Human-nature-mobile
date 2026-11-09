// 仿写页的界面测试：词块输入框**不许吞掉用户敲下的分隔符**。
//
// 回归的是 review 里 P1-1：`build()` 里拿 `vm.mustUse.join('、')` 回写输入框，
// 而 `onChanged` 已经把刚敲的顿号切掉了 → 顿号被吞、光标顶到末尾，
// 用户实际打不出第二个词块，只能用粘贴。这里逐键打一遍，断言框里留得住。

import 'package:dlaoshi_app/data/db/migrations.dart';
import 'package:dlaoshi_app/data/prefs_store.dart';
import 'package:dlaoshi_app/data/repositories/learning_repository.dart';
import 'package:dlaoshi_app/viewmodels/writing_view_model.dart';
import 'package:dlaoshi_app/views/writing_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<WritingViewModel> boot(WidgetTester tester) async {
    late final Database db;
    await tester.runAsync(() async {
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      await ensureSchema(db);
    });
    addTearDown(() async => tester.runAsync(() => db.close()));

    final vm = WritingViewModel(
      learning: LearningRepository(db),
      prefsStore: PrefsStore.memory(),
    );
    addTearDown(vm.dispose);
    await tester.runAsync(() => vm.bootstrap());

    await tester.pumpWidget(
      ChangeNotifierProvider<WritingViewModel>.value(
        value: vm,
        child: const MaterialApp(
          home: Scaffold(body: SafeArea(child: WritingPanel())),
        ),
      ),
    );
    await tester.pump();
    return vm;
  }

  /// 第二个输入框是「必须用上的词块」（第一个是范句）。
  Finder wordsField() => find.byType(TextField).at(1);

  String wordsText(WidgetTester tester) =>
      tester.widget<TextField>(wordsField()).controller!.text;

  testWidgets('逐键打「run、up」：顿号与第二个词块都留得住', (tester) async {
    final vm = await boot(tester);

    for (final rune in 'run、up'.split('')) {
      await tester.enterText(wordsField(), '${wordsText(tester)}$rune');
      await tester.pump();
    }

    expect(wordsText(tester), 'run、up');
    expect(vm.mustUse, <String>['run', 'up']);
  });

  testWidgets('英文逗号当分隔符也不被吞', (tester) async {
    final vm = await boot(tester);

    for (final rune in 'run,up'.split('')) {
      await tester.enterText(wordsField(), '${wordsText(tester)}$rune');
      await tester.pump();
    }

    expect(wordsText(tester), 'run,up');
    expect(vm.mustUse, <String>['run', 'up']);
  });

  testWidgets('粘回任务改了词块：框里换成 ViewModel 那份', (tester) async {
    final vm = await boot(tester);

    // 先手打一个词块，再让 ViewModel 从外部改（粘回任务那条路径会这样）。
    await tester.enterText(wordsField(), 'run');
    await tester.pump();
    expect(vm.mustUse, <String>['run']);

    vm.setMustUse(<String>['come', 'with']);
    await tester.pump();
    expect(wordsText(tester), 'come、with');
  });

  testWidgets('动作条吸顶：① 生成任务不在滚动 ListView 里', (tester) async {
    await boot(tester);

    final scroll = find.byType(ListView);
    expect(scroll, findsOneWidget);
    expect(find.text('① 生成任务'), findsOneWidget);
    expect(
      find.ancestor(of: find.text('① 生成任务'), matching: scroll),
      findsNothing,
      reason: '生成任务按钮应该吸顶，不跟着正文滚走',
    );

    // 反过来：范句输入框确实在滚动区里。
    expect(
      find.descendant(of: scroll, matching: find.byType(TextField)),
      findsWidgets,
    );
  });
}
