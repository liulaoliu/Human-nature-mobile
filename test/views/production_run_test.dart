// 产出训练练习页的界面测试：上方进度吸顶、下方操作吸底、手动批改入口。
//
// 这里刻意不测「点按钮之后 AI 回什么」——那是 core / ViewModel 单测的事。
// 只验证布局契约：工具条在滚动区外面，长批改也不跟着正文滚走。

import 'package:dlaoshi_app/core/production.dart';
import 'package:dlaoshi_app/data/db/migrations.dart';
import 'package:dlaoshi_app/data/prefs_store.dart';
import 'package:dlaoshi_app/data/repositories/learning_repository.dart';
import 'package:dlaoshi_app/data/repositories/vocab_repository.dart';
import 'package:dlaoshi_app/viewmodels/production_view_model.dart';
import 'package:dlaoshi_app/views/production_run.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 一份合法的「纯主题题」AI 回包，够出两题。
String _topicPack() =>
    '{"prompts":[{"zh":"第 1 个情境","goal":"说明进度"},'
    '{"zh":"第 2 个情境","goal":"讲一件事"}]}';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('有题目时：进度与操作条都不在滚动 ListView 内', (tester) async {
    late final Database db;
    await tester.runAsync(() async {
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      await ensureSchema(db);
    });
    addTearDown(() async => tester.runAsync(() => db.close()));

    final vm = ProductionViewModel(
      vocab: VocabRepository(db),
      learning: LearningRepository(db),
      prefsStore: PrefsStore.memory(),
    );
    addTearDown(vm.dispose);

    await tester.runAsync(() => vm.bootstrap());
    await tester.runAsync(() => vm.updateSettings(vm.settings.copyWith(
          mode: ProductionMode.skim,
          topic: '面试',
          scope: ProductionScope.all,
          promptCount: 2,
          skimUseChunks: false,
        )));
    expect(vm.applyPack(_topicPack()), isNull);
    expect(vm.session.hasPrompts, isTrue);

    await tester.pumpWidget(
      ChangeNotifierProvider<ProductionViewModel>.value(
        value: vm,
        child: MaterialApp(
          home: Scaffold(
            body: SafeArea(child: ProductionRunView(onGoSetup: () {})),
          ),
        ),
      ),
    );
    await tester.pump();

    // 上方进度、下方操作条各出现一次。
    expect(find.text('第 1/2 题 · 第 1 稿'), findsOneWidget);
    // 主路是「AI 批改这一稿」，手动粘贴（手动批改 / 复制提示词）留作兜底。
    expect(find.text('AI 批改这一稿'), findsOneWidget);
    expect(find.text('手动批改'), findsOneWidget);
    expect(find.text('复制提示词'), findsOneWidget);
    expect(find.text('重写'), findsOneWidget);
    expect(find.text('跳过这题'), findsOneWidget);
    expect(find.text('暂停'), findsOneWidget);

    // 核心契约：唯一的 ListView 只负责题干 / 作答 / 批改，
    // 进度与操作按钮都不是它的子节点（所以不跟着正文滚）。
    final scroll = find.byType(ListView);
    expect(scroll, findsOneWidget);
    for (final label in <String>[
      '第 1/2 题 · 第 1 稿',
      'AI 批改这一稿',
      '手动批改',
      '复制提示词',
      '重写',
      '跳过这题',
      '暂停',
    ]) {
      expect(
        find.ancestor(of: find.text(label), matching: scroll),
        findsNothing,
        reason: '「$label」不该长在滚动 ListView 里',
      );
    }

    // 反过来核一遍归属：作答框与题号 Chip 确实分别在中段和吸顶区。
    expect(
      find.descendant(of: scroll, matching: find.byType(TextField)),
      findsOneWidget,
    );
    expect(find.byType(ChoiceChip), findsNWidgets(2));
    expect(
      find.ancestor(
        of: find.byType(ChoiceChip).first,
        matching: scroll,
      ),
      findsNothing,
      reason: '题号 Chip 在吸顶区，不在滚动 ListView 里',
    );

    // 作答一动会排一次 250ms 的防抖草稿保存；把计时器走掉，
    // 否则测试框架会在拆树时报 "A Timer is still pending"。
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('没题目时：只给空态，不挂吸顶吸底', (tester) async {
    late final Database db;
    await tester.runAsync(() async {
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      await ensureSchema(db);
    });
    addTearDown(() async => tester.runAsync(() => db.close()));

    final vm = ProductionViewModel(
      vocab: VocabRepository(db),
      learning: LearningRepository(db),
      prefsStore: PrefsStore.memory(),
    );
    addTearDown(vm.dispose);
    await tester.runAsync(() => vm.bootstrap());

    await tester.pumpWidget(
      ChangeNotifierProvider<ProductionViewModel>.value(
        value: vm,
        child: MaterialApp(
          home: Scaffold(
            body: SafeArea(child: ProductionRunView(onGoSetup: () {})),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('这一组还没出题。'), findsOneWidget);
    expect(find.text('去出题'), findsOneWidget);
    expect(find.byType(ListView), findsNothing);
    expect(find.text('手动批改'), findsNothing);
    expect(find.text('暂停'), findsNothing);
  });

  testWidgets('点「暂停」：草稿落盘并退回出题页', (tester) async {
    late final Database db;
    await tester.runAsync(() async {
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      await ensureSchema(db);
    });
    addTearDown(() async => tester.runAsync(() => db.close()));

    final vm = ProductionViewModel(
      vocab: VocabRepository(db),
      learning: LearningRepository(db),
      prefsStore: PrefsStore.memory(),
    );
    addTearDown(vm.dispose);

    await tester.runAsync(() => vm.bootstrap());
    await tester.runAsync(() => vm.updateSettings(vm.settings.copyWith(
          mode: ProductionMode.skim,
          topic: '面试',
          scope: ProductionScope.all,
          promptCount: 2,
          skimUseChunks: false,
        )));
    expect(vm.applyPack(_topicPack()), isNull);
    vm.session.setAnswer('写到一半走人');

    var wentToSetup = false;
    await tester.pumpWidget(
      ChangeNotifierProvider<ProductionViewModel>.value(
        value: vm,
        child: MaterialApp(
          home: Scaffold(
            body: SafeArea(
              child: ProductionRunView(
                onGoSetup: () => wentToSetup = true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.runAsync(() async {
      await tester.tap(find.text('暂停'));
      await tester.pump();
    });
    await tester.pump();

    expect(wentToSetup, isTrue, reason: '暂停后应该退回出题页');
    expect(vm.resumableDraft, isNotNull, reason: '暂停必须把这一组存下来');
    expect(vm.resumableDraft!.answer, '写到一半走人');
  });
}
