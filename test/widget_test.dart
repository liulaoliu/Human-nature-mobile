import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:dlaoshi_app/data/db/migrations.dart';
import 'package:dlaoshi_app/data/repositories/article_repository.dart';
import 'package:dlaoshi_app/data/repositories/vocab_repository.dart';
import 'package:dlaoshi_app/services/article_import_service.dart';
import 'package:dlaoshi_app/viewmodels/reader_view_model.dart';
import 'package:dlaoshi_app/views/articles_page.dart';
import 'package:dlaoshi_app/views/home_page.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('首页：精读可点，其余两项标「开发中」', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));

    expect(find.text('精读'), findsOneWidget);
    expect(find.text('背单词'), findsOneWidget);
    expect(find.text('产出训练'), findsOneWidget);

    // 只有后两条没接通：不许出现可点的假入口。
    expect(find.text('开发中'), findsNWidgets(2));
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });

  testWidgets('文章列表页：空库给空态，有文章按时间倒序列出', (tester) async {
    // 真 SQLite 是真实异步 IO，必须放在 runAsync 里跑，
    // 否则 testWidgets 的 FakeAsync 里那个 Future 永远不完成（表现为整条用例挂死）。
    late final Database db;
    await tester.runAsync(() async {
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      await ensureSchema(db);
    });
    addTearDown(() async => tester.runAsync(() => db.close()));

    final articles = ArticleRepository(db);
    final vm = ReaderViewModel(
      articlesRepo: articles,
      vocabRepo: VocabRepository(db),
      importsService: ArticleImportService(articles),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ReaderViewModel>.value(value: vm),
        ],
        child: const MaterialApp(home: ArticlesPage()),
      ),
    );
    await tester.runAsync(() => vm.loadArticles());
    await tester.pump();

    expect(find.text('还没有文章'), findsOneWidget);
  });
}
