// 自动标词：按水平挑词 → 粘提示词 → 勾选 → 收进本篇。
//
// 这里只守界面接线（按钮在不在、点了出什么面板）；
// 「AI 不听话的写法怎么清理」全在 `test/core/auto_vocab_test.dart`。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart' show SingleChildWidget;

import 'package:dlaoshi_app/data/repositories/article_repository.dart';
import 'package:dlaoshi_app/data/repositories/vocab_repository.dart';
import 'package:dlaoshi_app/models/document.dart';
import 'package:dlaoshi_app/services/article_import_service.dart';
import 'package:dlaoshi_app/viewmodels/pick_mode_view_model.dart';
import 'package:dlaoshi_app/viewmodels/reader_view_model.dart';
import 'package:dlaoshi_app/views/reader_page.dart';
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
    MultiProvider(providers: providers, child: MaterialApp(home: home));

void main() {
  setUpAll(smokeInitFfi);

  testWidgets('精读页有「自动标词」入口，点了先让选词汇水平', (tester) async {
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

    expect(find.byTooltip('自动标词'), findsOneWidget);

    await tester.tap(find.byTooltip('自动标词'));
    await tester.pumpAndSettle();

    expect(find.text('按什么水平挑词'), findsOneWidget);
    // 五个水平都要能选。
    expect(find.text('四级以上'), findsOneWidget);
    expect(find.text('六级以上'), findsOneWidget);
    expect(find.text('考研以上'), findsOneWidget);
    expect(find.text('雅思 5.5+'), findsOneWidget);
    expect(find.text('雅思 6.5+'), findsOneWidget);

    // 选完水平进粘贴面板（提示词已经在里面了）。
    await tester.tap(find.text('六级以上'));
    await tester.pumpAndSettle();

    expect(find.text('自动标词（六级以上）'), findsOneWidget);
    expect(find.text('复制提示词'), findsOneWidget);
    expect(find.text('把 AI 的结果粘到这里'), findsOneWidget);

    // 空着点「应用」要拦住，而不是静默什么都不发生。
    await tester.tap(find.text('应用'));
    await tester.pump();
    expect(find.text('先把 AI 的结果粘进来'), findsOneWidget);
  });
}
