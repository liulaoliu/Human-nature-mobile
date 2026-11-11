// 首页「背单词」那一行的快捷设置：点小按键弹出范围与牌组，改完立刻落盘。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:dlaoshi_app/core/study_pool.dart';
import 'package:dlaoshi_app/views/home_page.dart';
import 'package:dlaoshi_app/views/settings_page.dart';
import 'package:dlaoshi_app/viewmodels/study_view_model.dart';
import 'smoke_harness.dart';

void main() {
  setUpAll(smokeInitFfi);

  testWidgets('首页背单词行的小按键：弹出范围与牌组，选完就存住', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);

    await smokePump(tester, smokeApp(db, const HomePage()));

    expect(find.byIcon(Icons.tune), findsOneWidget);
    expect(find.text('背单词的范围与牌组'), findsNothing);

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('背单词的范围与牌组'), findsOneWidget);
    expect(find.text('范围'), findsOneWidget);
    expect(find.text('牌组'), findsOneWidget);

    // 改范围：点「全部」
    await tester.tap(find.text('全部'));
    await tester.pump();

    final vm =
        Provider.of<StudyViewModel>(tester.element(find.byType(HomePage)), listen: false);
    expect(vm.scope, StudyScope.all);

    // 关掉面板
    await tester.tap(find.text('好了'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('背单词的范围与牌组'), findsNothing);

    await smokeFinish(tester);
  });

  testWidgets('侧边栏进设置页，返回后抽屉还在（不是被打回首页）', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);

    await smokePump(tester, smokeApp(db, const HomePage()));

    // 打开抽屉
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(Drawer), findsOneWidget);

    // 点「设置」
    await tester.tap(find.text('设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(SettingsPage), findsOneWidget);

    // 返回：回到首页且抽屉仍开着
    Navigator.of(tester.element(find.byType(SettingsPage))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(SettingsPage), findsNothing);
    expect(find.byType(HomePage), findsOneWidget);
    expect(find.byType(Drawer), findsOneWidget);

    await smokeFinish(tester);
  });
}
