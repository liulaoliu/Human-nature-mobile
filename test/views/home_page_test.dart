// 首页的 smoke：第一条用例不需要 Provider / SQLite，第二条要（全局当前篇）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/data/repositories/article_repository.dart';
import 'package:dlaoshi_app/services/article_import_service.dart';
import 'package:dlaoshi_app/views/home_page.dart';
import 'smoke_harness.dart';

void main() {
  setUpAll(smokeInitFfi);

  testWidgets('HomePage 能渲染标题与十条入口', (tester) async {
    tester.view.physicalSize = const Size(1080, 3400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pump();

    expect(find.text('D哥帮你办'), findsOneWidget);
    expect(find.text('今天想练什么？'), findsOneWidget);
    expect(find.text('精读'), findsOneWidget);
    expect(find.text('速读'), findsOneWidget);
    expect(find.text('拷打'), findsOneWidget);
    expect(find.text('AI 跑批'), findsOneWidget);
    // 备份搬到「抽屉 → 设置」了，首页不再出现。
    expect(find.text('备份'), findsNothing);
    // 没有注入全局当前篇（纯组件测试）：按「还没选」显示，不炸。
    expect(find.text('还没有选文章'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNWidgets(10));
  });

  testWidgets('精读那行右边跟着全局当前篇换', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);
    String? id;
    await tester.runAsync(() async {
      final svc = ArticleImportService(ArticleRepository(db));
      id = (await svc.createFromText(raw: 'Global growth slowed.', title: 'Growth'))!.id;
    });

    await smokePump(tester, smokeApp(db, const HomePage()));
    expect(find.text('还没有选文章'), findsOneWidget);

    await tester.runAsync(() async {
      await smokeCurrent.bootstrap();
      await smokeCurrent.select(id);
    });
    await tester.pump();

    expect(find.text('Growth'), findsOneWidget);
    expect(find.text('还没有选文章'), findsNothing);

    await smokeFinish(tester);
  });
}
