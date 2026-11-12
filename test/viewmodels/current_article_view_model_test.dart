import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:dlaoshi_app/core/current_article.dart';
import 'package:dlaoshi_app/data/db/migrations.dart';
import 'package:dlaoshi_app/data/prefs_store.dart';
import 'package:dlaoshi_app/data/repositories/article_repository.dart';
import 'package:dlaoshi_app/services/article_import_service.dart';
import 'package:dlaoshi_app/viewmodels/current_article_view_model.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late ArticleRepository articles;
  late PrefsStore store;

  Future<String> seed(String title) async {
    final saved = await ArticleImportService(articles).createFromText(
      title: title,
      raw: 'Global growth slowed down. The outlook is uncertain.',
    );
    return saved!.id;
  }

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await ensureSchema(db);
    articles = ArticleRepository(db);
    store = PrefsStore.memory();
  });

  tearDown(() async {
    await db.close();
  });

  group('当前文章：默认与持久化', () {
    test('空库：没选文章，标题给一句提示，不假装选了第一篇', () async {
      final vm = CurrentArticleViewModel(articlesRepo: articles, prefsStore: store);
      await vm.bootstrap();
      expect(vm.articles, isEmpty);
      expect(vm.articleId, isNull);
      expect(vm.hasArticle, isFalse);
      expect(vm.title, '还没选文章');
      vm.dispose();
    });

    test('有文章但没选过：仍然是 null（不自动选第一篇）', () async {
      await seed('A');
      await seed('B');
      final vm = CurrentArticleViewModel(articlesRepo: articles, prefsStore: store);
      await vm.bootstrap();
      expect(vm.articles.length, 2);
      expect(vm.articleId, isNull);
      vm.dispose();
    });

    test('选一篇：内存立刻生效，落盘；新实例读得回来', () async {
      final id = await seed('Growth');
      final vm = CurrentArticleViewModel(articlesRepo: articles, prefsStore: store);
      await vm.bootstrap();
      expect(await vm.select(id), isTrue);
      expect(vm.articleId, id);
      expect(vm.article?.title, 'Growth');
      expect(store.loadCurrentArticleId(), id);

      final again = CurrentArticleViewModel(articlesRepo: articles, prefsStore: store);
      await again.bootstrap();
      expect(again.articleId, id);
      again.dispose();
      vm.dispose();
    });

    test('选 null：清掉当前文章，键也从盘上删掉', () async {
      final id = await seed('Growth');
      final vm = CurrentArticleViewModel(articlesRepo: articles, prefsStore: store);
      await vm.bootstrap();
      await vm.select(id);
      expect(await vm.select(null), isTrue);
      expect(vm.articleId, isNull);
      expect(store.loadCurrentArticleId(), isNull);
      vm.dispose();
    });

    test('选同一篇两次：第二次返回 false，不重复通知', () async {
      final id = await seed('Growth');
      final vm = CurrentArticleViewModel(articlesRepo: articles, prefsStore: store);
      await vm.bootstrap();
      await vm.select(id);
      var notified = 0;
      vm.addListener(() => notified++);
      expect(await vm.select(id), isFalse);
      expect(notified, 0);
      vm.dispose();
    });
  });

  group('文章被删 / 库变空', () {
    test('存着的那篇被删了：启动时当没选，并把脏 id 清掉', () async {
      final id = await seed('Growth');
      await store.saveCurrentArticleId(id);
      await ArticleRepository(db).remove(id);

      final vm = CurrentArticleViewModel(articlesRepo: articles, prefsStore: store);
      await vm.bootstrap();
      expect(vm.articleId, isNull);
      expect(store.loadCurrentArticleId(), isNull);
      vm.dispose();
    });

    test('refresh 时当前那篇没了：回落 null，不自动换第一篇', () async {
      final a = await seed('A');
      await seed('B');
      final vm = CurrentArticleViewModel(articlesRepo: articles, prefsStore: store);
      await vm.bootstrap();
      await vm.select(a);
      await ArticleRepository(db).remove(a);

      await vm.refresh();
      expect(vm.articles.length, 1);
      expect(vm.articleId, isNull);
      vm.dispose();
    });
  });

  group('键名', () {
    test('偏好键与 core 里的常量一致', () {
      expect(currentArticleKey, 'reader:currentArticle');
    });
  });
}
