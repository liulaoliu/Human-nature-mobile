// 选词模式：精读页与速读页共用同一个开关（`PickModeViewModel`）。
//
// 守三件事：
//   1. 精读页开了选词，正文逐词可点，点一下计数 +1，底栏显示「已选 1 个词」；
//   2. 速读页有同款开关，在精读页开的开关到速读页仍然是开的
//      —— 用户明确要求两页共用，不然切页面开关会自己关掉；
//   3. 点「加入生词本」真的把词收进本篇（`addWordsToArticle`）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart' show SingleChildWidget;

import 'package:dlaoshi_app/data/prefs_store.dart';
import 'package:dlaoshi_app/data/repositories/article_repository.dart';
import 'package:dlaoshi_app/data/repositories/learning_repository.dart';
import 'package:dlaoshi_app/data/repositories/vocab_repository.dart';
import 'package:dlaoshi_app/models/document.dart';
import 'package:dlaoshi_app/services/article_import_service.dart';
import 'package:dlaoshi_app/viewmodels/pick_mode_view_model.dart';
import 'package:dlaoshi_app/viewmodels/reader_view_model.dart';
import 'package:dlaoshi_app/viewmodels/speed_read_view_model.dart';
import 'package:dlaoshi_app/views/reader_page.dart';
import 'package:dlaoshi_app/views/speed_read_page.dart';
import 'smoke_harness.dart';

const String _body = 'We keep up with the news every morning. '
    'It helps us stay sharp.';

SavedArticle _article() => const SavedArticle(
      id: 'a1',
      title: 'Growth',
      sentences: [
        Sentence(id: 's1', paraId: 'p1', text: _body),
      ],
      paragraphs: [
        Paragraph(id: 'p1', sentenceIds: ['s1']),
      ],
      updatedAt: '2026-11-10T00:00:00.000Z',
    );

Widget _wrap(Widget home, {required List<SingleChildWidget> providers}) =>
    MultiProvider(
      providers: providers,
      child: MaterialApp(home: home),
    );

void main() {
  setUpAll(smokeInitFfi);

  testWidgets('精读页：开选词后点词计数，底栏出现「加入生词本」', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);
    final articles = ArticleRepository(db);
    final vocab = VocabRepository(db);
    final vm = ReaderViewModel(
      articlesRepo: articles,
      vocabRepo: vocab,
      importsService: ArticleImportService(articles),
    );
    final pick = PickModeViewModel();
    addTearDown(pick.dispose);
    await tester.runAsync(() async {
      await articles.save(_article());
      await vm.bootstrap();
      await vm.openArticle('a1');
    });

    await smokePump(
      tester,
      _wrap(
        const ReaderPage(),
        providers: [
          Provider<VocabRepository>.value(value: vocab),
          ChangeNotifierProvider<ReaderViewModel>.value(value: vm),
          ChangeNotifierProvider<PickModeViewModel>.value(value: pick),
        ],
      ),
    );

    // 没开之前：正文是普通文本，没有逐词热区。
    expect(find.byKey(const ValueKey('pick-s1-0')), findsNothing);

    await tester.tap(find.byTooltip('选词模式'));
    await tester.pump();

    expect(pick.enabled, isTrue);
    // 第一个词的主键必须出现（词热区按句子 id + 词下标编号）。
    expect(find.byKey(const ValueKey('pick-s1-0')), findsOneWidget);
    expect(find.text('点正文里的词选中'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pick-s1-0')));
    await tester.pump();

    expect(pick.count, 1);
    expect(find.text('已选 1 个词'), findsOneWidget);
    expect(find.text('加入生词本'), findsOneWidget);

    // 再点一次取消选中。
    await tester.tap(find.byKey(const ValueKey('pick-s1-0')));
    await tester.pump();
    expect(pick.count, 0);
    expect(find.text('点正文里的词选中'), findsOneWidget);
  });

  testWidgets('精读页：加入生词本后真的收进本篇', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);
    final articles = ArticleRepository(db);
    final vocab = VocabRepository(db);
    final vm = ReaderViewModel(
      articlesRepo: articles,
      vocabRepo: vocab,
      importsService: ArticleImportService(articles),
    );
    final pick = PickModeViewModel();
    addTearDown(pick.dispose);
    await tester.runAsync(() async {
      await articles.save(_article());
      await vm.bootstrap();
      await vm.openArticle('a1');
    });

    await smokePump(
      tester,
      _wrap(
        const ReaderPage(),
        providers: [
          Provider<VocabRepository>.value(value: vocab),
          ChangeNotifierProvider<ReaderViewModel>.value(value: vm),
          ChangeNotifierProvider<PickModeViewModel>.value(value: pick),
        ],
      ),
    );

    await tester.tap(find.byTooltip('选词模式'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pick-s1-0')));
    await tester.pump();

    await tester.tap(find.text('加入生词本'));
    // 落库是真实 IO，要走异步。
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump();

    expect(pick.count, 0, reason: '加完要清空选中');
    final library = await tester.runAsync(vocab.load);
    expect(library!.items, isNotEmpty);
    expect(
      library.articleEntries.where((e) => e.articleId == 'a1'),
      isNotEmpty,
    );
  });

  testWidgets('速读页：开关与精读页是同一份状态', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);
    final articles = ArticleRepository(db);
    final vocab = VocabRepository(db);
    final learning = LearningRepository(db);
    final pick = PickModeViewModel();
    addTearDown(pick.dispose);
    final speed = SpeedReadViewModel(
      articles: articles,
      prefsStore: PrefsStore.memory(),
    );
    addTearDown(speed.dispose);
    late String id;
    await tester.runAsync(() async {
      id = (await ArticleImportService(articles).createFromText(raw: _body))!
          .id;
      await speed.bootstrap();
      await speed.openArticle(id);
    });

    // 在「另一页」先开好开关：速读页应当直接就是开着的。
    pick.setEnabled(true);

    await smokePump(
      tester,
      _wrap(
        const SpeedReadPage(),
        providers: [
          Provider<VocabRepository>.value(value: vocab),
          Provider<LearningRepository>.value(value: learning),
          ChangeNotifierProvider<SpeedReadViewModel>.value(value: speed),
          ChangeNotifierProvider<PickModeViewModel>.value(value: pick),
        ],
      ),
    );

    expect(speed.hasArticle, isTrue);
    expect(pick.enabled, isTrue);
    expect(find.text('点正文里的词选中'), findsOneWidget);

    // 速读页的开关也能关掉同一份状态。
    await tester.tap(find.byKey(const ValueKey('speed-pick-toggle')));
    await tester.pump();
    expect(pick.enabled, isFalse);
  });
}
