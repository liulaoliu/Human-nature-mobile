// 阅读页：空态文案 + 一条真交互（关掉选词模式把会话记进 learning.sessions）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart' show SingleChildWidget;

import 'package:dlaoshi_app/data/repositories/article_repository.dart';
import 'package:dlaoshi_app/data/repositories/learning_repository.dart';
import 'package:dlaoshi_app/data/repositories/vocab_repository.dart';
import 'package:dlaoshi_app/models/document.dart';
import 'package:dlaoshi_app/services/article_import_service.dart';
import 'package:dlaoshi_app/viewmodels/pick_mode_view_model.dart';
import 'package:dlaoshi_app/viewmodels/reader_view_model.dart';
import 'package:dlaoshi_app/views/reader_page.dart';
import 'smoke_harness.dart';

const String _body = 'We keep up with the news every morning.';

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

Widget _wrap(Widget home, List<SingleChildWidget> providers) => MultiProvider(
      providers: providers,
      child: MaterialApp(home: home),
    );

void main() {
  setUpAll(smokeInitFfi);

  testWidgets('ReaderPage 空态：没有打开的文章', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);

    await smokePump(tester, smokeApp(db, const ReaderPage()));

    // 该页特有的空态文案（不是只 find.byType）。
    expect(find.text('没有打开的文章'), findsOneWidget);

    await smokeFinish(tester);
  });

  testWidgets('关掉选词模式：这一轮真的记进 learning.sessions', (tester) async {
    // 这条链路跨三层：AppBar 按钮 → PickModeViewModel.takeSession() →
    // LearningRepository.writeSection。上面那条空态用例与 pick_mode_test
    // 都没有提供 LearningRepository，所以以前一直是「界面对了就算过」。
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);
    final articles = ArticleRepository(db);
    final vocab = smokeVocabRepo(db);
    final learning = smokeLearningRepo(db);
    final vm = ReaderViewModel(
      articlesRepo: articles,
      vocabRepo: vocab,
      importsService: ArticleImportService(articles),
    );
    addTearDown(vm.dispose);
    final pick = PickModeViewModel();
    addTearDown(pick.dispose);
    await tester.runAsync(() async {
      await articles.save(_article());
      await vm.bootstrap();
      await vm.openArticle('a1');
    });

    await smokePump(
      tester,
      _wrap(const ReaderPage(), [
        Provider<VocabRepository>.value(value: vocab),
        Provider<LearningRepository>.value(value: learning),
        ChangeNotifierProvider<ReaderViewModel>.value(value: vm),
        ChangeNotifierProvider<PickModeViewModel>.value(value: pick),
      ]),
    );

    // 开选词 → 点一个词（让这一轮有「收了几个」可记）→ 关掉选词。
    await tester.tap(find.byTooltip('选词模式'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pick-s1-0')));
    await tester.pump();
    expect(pick.count, 1);

    await tester.tap(find.byTooltip('关闭选词模式'));
    // 落盘是真实 IO：真时钟与假时钟交替推着走，只在一侧等会互相死锁。
    for (var i = 0; i < 25; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }

    expect(pick.enabled, isFalse);
    expect(pick.count, 0, reason: '关掉选词要清空选中');

    final data = await tester.runAsync(learning.load);
    expect(data, isNotNull);
    expect(data!.sessions, hasLength(1));
    final session = data.sessions.single;
    expect(session.picked, 1);
    expect(session.at, isNotEmpty);
  });
}
