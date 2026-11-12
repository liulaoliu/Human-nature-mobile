// 精读文章列表页：空态、当前文章标题、搜索栏、选文章后全局跟着换。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/data/repositories/article_repository.dart';
import 'package:dlaoshi_app/services/article_import_service.dart';
import 'package:dlaoshi_app/views/articles_page.dart';
import 'package:dlaoshi_app/views/reader_page.dart';
import 'smoke_harness.dart';

void main() {
  setUpAll(smokeInitFfi);

  testWidgets('ArticlesPage 空库：标题、粘贴新建与空态文案', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);

    await smokePump(tester, smokeApp(db, const ArticlesPage()));

    expect(find.text('精读'), findsOneWidget);
    expect(find.text('粘贴新建'), findsOneWidget);
    expect(find.text('还没有文章'), findsOneWidget);
    expect(find.text('点右下角「粘贴新建」，把一段英文贴进来就能开始精读。'),
        findsOneWidget);
    // 没选文章时标题栏直说「还没选文章」，不假装选了第一篇。
    expect(find.text('· 还没选文章'), findsOneWidget);

    await smokeFinish(tester);
  });

  testWidgets('有文章但没选：标题栏还是「还没选文章」；点进去就变成那一篇',
      (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);
    await tester.runAsync(() async {
      final svc = ArticleImportService(ArticleRepository(db));
      await svc.createFromText(raw: 'Global growth slowed.', title: 'Growth');
    });

    await smokePump(tester, smokeApp(db, const ArticlesPage()));
    expect(find.text('· 还没选文章'), findsOneWidget);
    expect(find.text('Growth'), findsOneWidget);

    await tester.tap(find.text('Growth'));
    // 选文章是真实 IO（写全局 + 读文章），得让 runAsync 走一段真时钟。
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ReaderPage), findsOneWidget);
    // 全局当前文章已经指向这一篇（别的模块据此拿「本篇」）。
    expect(smokeCurrent.title, 'Growth');
  });

  testWidgets('搜索栏默认收起；点开输入就只留匹配的文章', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);
    await tester.runAsync(() async {
      final svc = ArticleImportService(ArticleRepository(db));
      await svc.createFromText(raw: 'Alpha runs.', title: 'Alpha story');
      await svc.createFromText(raw: 'Beta walks.', title: 'Beta story');
    });

    await smokePump(tester, smokeApp(db, const ArticlesPage()));
    // 收着的时候没有搜索框，两篇都在。
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Alpha story'), findsOneWidget);
    expect(find.text('Beta story'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('articles-search-toggle')));
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'beta');
    await tester.pump();
    expect(find.text('Beta story'), findsOneWidget);
    expect(find.text('Alpha story'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();
    expect(find.text('没有标题匹配「zzz」。'), findsOneWidget);

    // 收起搜索栏就把过滤词清掉。
    await tester.tap(find.byKey(const ValueKey('articles-search-toggle')));
    await tester.pump();
    expect(find.text('Alpha story'), findsOneWidget);
    expect(find.text('Beta story'), findsOneWidget);
  });
}
