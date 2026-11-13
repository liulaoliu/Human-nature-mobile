// 产出训练出题页的布局契约：设置项在滚动区里，主按钮吸底。
//
// 出题页很长（三种吃法 + 五六个下拉 + 目标块类型 + 最近产出），
// 主按钮一旦长在滚动区里，滚到「最近的产出」就得滚回去找它。
// 这里只验证归属，不测设置项本身怎么改（那是 ViewModel 单测的事）。

import 'package:dlaoshi_app/data/db/migrations.dart';
import 'package:dlaoshi_app/data/prefs_store.dart';
import 'package:dlaoshi_app/data/repositories/learning_repository.dart';
import 'package:dlaoshi_app/data/repositories/vocab_repository.dart';
import 'package:dlaoshi_app/viewmodels/production_view_model.dart';
import 'package:dlaoshi_app/views/production_setup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('主按钮吸底：不在滚动 ListView 里，且排在设置项之后', (tester) async {
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
        child: const MaterialApp(
          home: Scaffold(
            body: SafeArea(
              child: ProductionSetupView(onStarted: _noop),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final scroll = find.byType(ListView);
    expect(scroll, findsOneWidget);

    // 主按钮都在吸底条上，不是滚动的子节点。
    // 主路是「AI 出题」，手动粘贴留作「自己粘结果」的兜底。
    for (final label in <String>['AI 出题', '选目标块', '自己粘结果']) {
      expect(find.text(label), findsOneWidget);
      expect(
        find.ancestor(of: find.text(label), matching: scroll),
        findsNothing,
        reason: '「$label」不该长在滚动 ListView 里',
      );
    }

    // 反过来：主题输入框在滚动区里，说明滚动区确实装的是设置项。
    expect(
      find.descendant(of: scroll, matching: find.byType(TextField)),
      findsWidgets,
    );

    // 吸底条在屏幕纵向靠下的位置（不是列表中间）。
    final bar = tester.getTopLeft(find.text('AI 出题')).dy;
    final screenHeight = tester.getSize(find.byType(Scaffold)).height;
    expect(bar, greaterThan(screenHeight * 0.7));
  });
}

void _noop() {}
