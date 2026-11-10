// 阅读页要显示「译文 + 语言点」，两个开关都能关。
//
// 这条用例守的是真机上报过的问题：导入备份后正文只有英文，
// 译文和语言点一句都没有 —— 数据一直在，是正文没渲染。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:dlaoshi_app/data/repositories/article_repository.dart';
import 'package:dlaoshi_app/data/repositories/vocab_repository.dart';
import 'package:dlaoshi_app/models/document.dart';
import 'package:dlaoshi_app/services/article_import_service.dart';
import 'package:dlaoshi_app/viewmodels/reader_view_model.dart';
import 'package:dlaoshi_app/views/reader_page.dart';
import 'smoke_harness.dart';

/// 一句带译文 + 一条完整语言点（五行各来一行，好逐个断言）。
Sentence _sentence() => const Sentence(
      id: 's1',
      paraId: 'p1',
      text: 'Global growth is slowing.',
      translation: '全球增长正在放缓。',
      languages: [
        SentenceLanguage(
          structure: '主语 Global growth + 谓语 is slowing',
          grammar: '现在进行时表示正在发生的趋势',
          idioms: ['slow down'],
          phrases: ['global growth'],
          usage: ['正式书面语，多见于报道'],
          source: LanguageSource.ai,
        ),
      ],
    );

SavedArticle _article() => SavedArticle(
      id: 'a1',
      title: 'Growth',
      sentences: [_sentence()],
      paragraphs: const [
        Paragraph(id: 'p1', sentenceIds: ['s1']),
      ],
      updatedAt: '2026-11-10T00:00:00.000Z',
    );

Future<ReaderViewModel> _open(WidgetTester tester) async {
  final db = await smokeOpenDb(tester);
  final articles = ArticleRepository(db);
  final vocab = VocabRepository(db);
  final vm = ReaderViewModel(
    articlesRepo: articles,
    vocabRepo: vocab,
    importsService: ArticleImportService(articles),
  );
  await tester.runAsync(() async {
    await articles.save(_article());
    await vm.bootstrap();
    await vm.openArticle('a1');
  });
  return vm;
}

Widget _app(ReaderViewModel vm) => ChangeNotifierProvider<ReaderViewModel>.value(
      value: vm,
      child: const MaterialApp(home: ReaderPage()),
    );

void main() {
  setUpAll(smokeInitFfi);

  testWidgets('正文下面显示译文与语言点五行', (tester) async {
    smokeUseTallScreen(tester);
    final vm = await _open(tester);

    await smokePump(tester, _app(vm));

    expect(find.text('Global growth is slowing. '), findsOneWidget);
    expect(find.text('全球增长正在放缓。'), findsOneWidget);
    expect(find.text('结构：主语 Global growth + 谓语 is slowing'), findsOneWidget);
    expect(find.text('语法：现在进行时表示正在发生的趋势'), findsOneWidget);
    expect(find.text('习语：slow down'), findsOneWidget);
    expect(find.text('词组：global growth'), findsOneWidget);
    expect(find.text('用法：正式书面语，多见于报道'), findsOneWidget);

    await smokeFinish(tester);
    vm.dispose();
  });

  testWidgets('两个开关分别关掉译文与语言点', (tester) async {
    smokeUseTallScreen(tester);
    final vm = await _open(tester);

    await smokePump(tester, _app(vm));

    // 关译文：译文没了，语言点还在。
    await tester.tap(find.byIcon(Icons.subtitles));
    await tester.pump();
    expect(find.text('全球增长正在放缓。'), findsNothing);
    expect(find.text('结构：主语 Global growth + 谓语 is slowing'), findsOneWidget);

    // 再关语言点：两样都没了，原文还在。
    await tester.tap(find.byIcon(Icons.notes));
    await tester.pump();
    expect(find.text('结构：主语 Global growth + 谓语 is slowing'), findsNothing);
    expect(find.text('Global growth is slowing. '), findsOneWidget);

    // 打开回来。
    await tester.tap(find.byIcon(Icons.subtitles_off));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.notes_outlined));
    await tester.pump();
    expect(find.text('全球增长正在放缓。'), findsOneWidget);
    expect(find.text('结构：主语 Global growth + 谓语 is slowing'), findsOneWidget);

    await smokeFinish(tester);
    vm.dispose();
  });

  testWidgets('没有译文也没有语言点的句子不插空块', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);
    final articles = ArticleRepository(db);
    final vm = ReaderViewModel(
      articlesRepo: articles,
      vocabRepo: VocabRepository(db),
      importsService: ArticleImportService(articles),
    );
    await tester.runAsync(() async {
      await articles.save(
        const SavedArticle(
          id: 'a2',
          title: 'Plain',
          sentences: [
            Sentence(id: 's1', paraId: 'p1', text: 'Just one line.'),
          ],
          paragraphs: [
            Paragraph(id: 'p1', sentenceIds: ['s1']),
          ],
          updatedAt: '2026-11-10T00:00:00.000Z',
        ),
      );
      await vm.bootstrap();
      await vm.openArticle('a2');
    });

    await smokePump(tester, _app(vm));

    expect(find.text('Just one line. '), findsOneWidget);
    expect(find.textContaining('结构：'), findsNothing);

    await smokeFinish(tester);
    vm.dispose();
  });
}
