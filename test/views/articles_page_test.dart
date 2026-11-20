// 精读文章列表页：空态、当前文章标题、搜索栏、选文章后全局跟着换。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/data/repositories/article_repository.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:dlaoshi_app/services/article_import_service.dart';
import 'package:dlaoshi_app/views/articles_page.dart';
import 'package:dlaoshi_app/views/reader_page.dart';
import '../support/vocab_fixture.dart';
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

  testWidgets('列表里的「N 个生词」按词库的按篇条目算，不看 payload', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);
    late String id;
    await tester.runAsync(() async {
      final svc = ArticleImportService(ArticleRepository(db));
      final article =
          await svc.createFromText(raw: 'Alpha runs. Beta walks.', title: 'Growth');
      id = article!.id;
      // 词库里给这一篇收两条：一条普通单词 + 一条语言点（语言点不算生词数）。
      await smokeVocabRepo(db).save(
        VocabLibrary(
          items: [
            vocabItem(id: 'v-alpha', word: 'Alpha', lemma: 'alpha'),
            vocabItem(id: 'v-beta', word: 'Beta', lemma: 'beta'),
            vocabItem(
              id: 'v-take',
              word: 'take off',
              lemma: 'take off',
              kind: VocabItemKind.phrase,
            ),
          ],
          articleEntries: [
            articleEntry(articleId: id, lemma: 'alpha'),
            articleEntry(articleId: id, lemma: 'beta'),
            articleEntry(articleId: id, lemma: 'take off'),
          ],
        ),
      );
    });

    await smokePump(tester, smokeApp(db, const ArticlesPage()));
    // 首屏要等真 SQLite 读完列表与词库（假时钟下 IO 不会自己完成）。
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // payload 里 sentences[].vocab 是空的（Web 备份就是这样），
    // 照它数会显示 0；这里必须数出 2。
    expect(find.textContaining('2 个生词'), findsOneWidget);
    expect(find.textContaining('0 个生词'), findsNothing);
  });

  testWidgets('进列表自动滚到「本篇」，不用自己滑（m12872）', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);
    late String targetId;
    // 一屏装不下才需要滚：1080×3000 的竖屏大约容得下 40 行，造 60 篇。
    const int total = 60;
    await tester.runAsync(() async {
      final svc = ArticleImportService(ArticleRepository(db));
      final base = DateTime.utc(2026, 11, 1, 9);
      // 列表按 updated_at 倒序，所以 i 越大排越前；「最早那篇」（i = 0）
      // 会沉到列表末尾，正好是需要滚才能看到的位置。
      for (var i = 0; i < total; i++) {
        final article = await svc.createFromText(
          raw: 'Sentence number $i runs.',
          title: 'Article ${i.toString().padLeft(2, '0')}',
          now: base.add(Duration(minutes: i)),
        );
        if (i == 0) targetId = article!.id;
      }
    });

    final app = smokeApp(db, const ArticlesPage());
    // 进来之前「本篇」就已经是最早那篇（在别处选过），列表要自己滚过去。
    await tester.runAsync(() => smokeCurrent.select(targetId));
    await smokePump(tester, app);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump();
    // 定位是「先按估算位置跳过去 → 等一帧建出目标行 → 再精确对齐」的分帧流程，
    // 多推几帧把它走完（含 220ms 的对齐动画）。
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    final listView = tester.widget<ListView>(find.byType(ListView));
    final controller = listView.controller;
    expect(controller, isNotNull, reason: '列表要挂 ScrollController 才定位得了');
    expect(controller!.offset, greaterThan(0), reason: '没滚就是没定位');

    // 目标那行真的进了视口，不是只滚了个大概位置。
    expect(find.text('Article 00'), findsOneWidget);
    final viewport = tester.getRect(find.byType(ListView));
    final row = tester.getRect(find.text('Article 00'));
    expect(row.top, greaterThanOrEqualTo(viewport.top - 1));
    expect(row.bottom, lessThanOrEqualTo(viewport.bottom + 1));

    await smokeFinish(tester);
  });
}
