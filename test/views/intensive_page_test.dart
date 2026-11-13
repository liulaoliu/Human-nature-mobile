// 精读工作流页：七阶段渲染、下一步按钮、空态、勾通读。
//
// 规则与状态机在 `test/core/intensive_test.dart`、
// `test/viewmodels/intensive_view_model_test.dart` 已经覆盖；
// 这里只验「界面把状态摆对、点得动」。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:dlaoshi_app/core/intensive.dart';
import 'package:dlaoshi_app/data/repositories/article_repository.dart';
import 'package:dlaoshi_app/data/repositories/vocab_repository.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:dlaoshi_app/services/article_import_service.dart';
import 'package:dlaoshi_app/views/intensive_page.dart';
import 'package:dlaoshi_app/views/speed_read_page.dart';
import 'smoke_harness.dart';

void main() {
  setUpAll(smokeInitFfi);

  /// 造一篇带正文的文章 + 两个挂在本篇、有释义的词。
  Future<String> seedArticle(WidgetTester tester, Database db) async {
    late String id;
    await tester.runAsync(() async {
      final articles = ArticleRepository(db);
      final article = (await ArticleImportService(articles).createFromText(
        raw: 'Global growth slowed down. The outlook is uncertain.',
        title: 'Growth',
      ))!;
      id = article.id;
      await VocabRepository(db).save(
        VocabLibrary(
          items: [
            for (final w in const ['alpha', 'beta'])
              VocabItem(
                id: 'v-$w',
                word: w,
                lemma: w,
                meaning: '$w 的意思',
                status: VocabStatus.queried,
                createdAt: '2026-01-01T00:00:00.000Z',
                updatedAt: '2026-01-01T00:00:00.000Z',
                source: VocabSource(articleId: article.id, fileName: 'Growth'),
              ),
          ],
          articleEntries: [
            for (final w in const ['alpha', 'beta'])
              ArticleVocabEntry(
                articleId: article.id,
                lemma: w,
                origin: VocabOrigin.manual,
                addedAt: '2026-01-01T00:00:00.000Z',
              ),
          ],
        ),
      );
    });
    return id;
  }

  /// 装好页面并把全局当前篇指向 [id]（**必须在 smokePump 之后**：
  /// `smokeCurrent` 是 smokeApp 里赋值的，先 pump 才有值）。
  ///
  /// 选完还要再 `bootstrap()` 一次：页面 initState 里的那次读的是「还没选文章」，
  /// 换篇本身不会自动重算 plan。
  Future<void> openWithArticle(
    WidgetTester tester,
    Database db,
    String id,
  ) async {
    await smokePump(tester, smokeApp(db, const IntensivePage()));
    await tester.runAsync(() async {
      await smokeCurrent.bootstrap();
      await smokeCurrent.select(id);
      await smokeIntensive.bootstrap();
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
  }

  testWidgets('没选文章：空态给「挑一篇」', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);
    await smokePump(tester, smokeApp(db, const IntensivePage()));

    expect(find.text('精读工作流'), findsOneWidget);
    expect(find.text('还没选文章'), findsOneWidget);
    expect(find.byKey(const ValueKey('intensive-pick-empty')), findsOneWidget);
    // 没有文章时不画七阶段。
    expect(find.text('已通读（看懂大意）'), findsNothing);

    await smokeFinish(tester);
  });

  testWidgets('有文章：七阶段都画出来，状态徽章与通读开关都在', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);
    final id = await seedArticle(tester, db);
    await openWithArticle(tester, db, id);

    expect(find.text('还没选文章'), findsNothing);
    expect(find.text('Growth'), findsOneWidget);
    // 七阶段的中文标签。
    for (final label in const [
      '通读',
      '标词 / 查词',
      '词块',
      '句子理解',
      '达标拷打',
      '产出（仿写）',
      '语法专项',
    ]) {
      expect(find.text(label), findsOneWidget, reason: '阶段「$label」应该在');
    }
    expect(find.text('待做'), findsWidgets);
    expect(find.byKey(const ValueKey('intensive-skimmed')), findsOneWidget);
    expect(find.byKey(const ValueKey('intensive-next')), findsOneWidget);

    await smokeFinish(tester);
  });

  testWidgets('点「开始这一步」跳到对应页面（第 1 步是速读）', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);
    final id = await seedArticle(tester, db);
    await openWithArticle(tester, db, id);

    await tester.tap(find.byKey(const ValueKey('intensive-next')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(SpeedReadPage), findsOneWidget);

    await smokeFinish(tester);
  });

  testWidgets('勾上「已通读」：第 1 步变完成', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);
    final id = await seedArticle(tester, db);
    await openWithArticle(tester, db, id);

    expect(smokeIntensive.skimmed, isFalse);

    await tester.tap(find.byKey(const ValueKey('intensive-skimmed')));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump();
    await tester.pump();

    expect(smokeIntensive.skimmed, isTrue);
    expect(find.text('完成'), findsWidgets);

    await smokeFinish(tester);
  });

  testWidgets('每个阶段都有跳转按钮，key 齐全', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);
    final id = await seedArticle(tester, db);
    await openWithArticle(tester, db, id);

    for (final key in IntensiveStageKey.values) {
      expect(
        find.byKey(ValueKey('intensive-go-${key.name}')),
        findsOneWidget,
        reason: '阶段 ${key.name} 应该有跳转按钮',
      );
    }

    await smokeFinish(tester);
  });

  testWidgets('产出看板：七行指标都在，复述与历史两块也在', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);
    final id = await seedArticle(tester, db);
    await openWithArticle(tester, db, id);

    expect(find.text('产出看板'), findsOneWidget);
    for (final key in const [
      'chunkAcc',
      'grammarAcc',
      'chunkCover',
      'write',
      'retell',
      'memory',
      'streak',
    ]) {
      expect(
        find.byKey(ValueKey('intensive-board-$key')),
        findsOneWidget,
        reason: '看板行 $key 应该在',
      );
    }
    expect(find.text('复述打卡'), findsOneWidget);
    expect(find.text('练习历史'), findsOneWidget);
    expect(find.byKey(const ValueKey('intensive-retell-input')), findsOneWidget);

    await smokeFinish(tester);
  });

  testWidgets('复述：写一段点「记下来」，历史里就多一条', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);
    final id = await seedArticle(tester, db);
    await openWithArticle(tester, db, id);

    // 一开始没记录，按钮是禁用的。
    final before = tester.widget<FilledButton>(
      find.byKey(const ValueKey('intensive-retell-save')),
    );
    expect(before.onPressed, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('intensive-retell-input')),
      'Growth slowed down this quarter.',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('intensive-retell-save')));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pump();
    await tester.pump();

    expect(smokeIntensive.retells, hasLength(1));
    expect(find.text('已记录 1 条'), findsOneWidget);

    await smokeFinish(tester);
  });
}
