// 阅读页的词表：从右侧滑入的抽屉，每个词带一个复制按钮。
//
// 守两件事：
//   1. 词表不再是从底部弹出的 sheet，而是 `endDrawer`（AppBar 按钮能开，
//      右边缘左滑也能开）；
//   2. 每个词条右边的复制按钮真的把单词写进剪贴板，并给一条提示。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:dlaoshi_app/data/repositories/article_repository.dart';
import 'package:dlaoshi_app/data/repositories/vocab_repository.dart';
import 'package:dlaoshi_app/models/document.dart';
import 'package:dlaoshi_app/services/article_import_service.dart';
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

/// 开一篇 + 收一个词，返回装好的 VM。
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
    await vm.markCurrentWord(
      'morning',
      sentenceId: 's1',
      sentenceText: _body,
      meaning: '早上',
    );
  });
  return vm;
}

Widget _app(ReaderViewModel vm) =>
    ChangeNotifierProvider<ReaderViewModel>.value(
      value: vm,
      child: const MaterialApp(home: ReaderPage()),
    );

void main() {
  setUpAll(smokeInitFfi);

  testWidgets('词表是右侧抽屉，点 AppBar 按钮能滑出来', (tester) async {
    smokeUseTallScreen(tester);
    final vm = await _open(tester);

    await smokePump(tester, _app(vm));

    // 关着的时候看不到词表。
    expect(find.text('本篇词表（1）'), findsNothing);

    await tester.tap(find.byIcon(Icons.list_alt));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('本篇词表（1）'), findsOneWidget);
    expect(find.text('morning'), findsOneWidget);
    expect(find.text('早上'), findsOneWidget);
    // 抽屉是从右边滑进来的（`endDrawer`）。
    expect(find.byType(Drawer), findsOneWidget);

    await smokeFinish(tester);
    vm.dispose();
  });

  testWidgets('每个词右边的复制按钮把单词写进剪贴板并给反馈', (tester) async {
    smokeUseTallScreen(tester);
    final vm = await _open(tester);

    // 拦下剪贴板的平台调用，记下真的写进去了什么。
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await smokePump(tester, _app(vm));
    await tester.tap(find.byIcon(Icons.list_alt));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byIcon(Icons.copy), findsOneWidget);
    await tester.tap(find.byIcon(Icons.copy));
    await tester.pump();

    expect(copied, 'morning');
    // 反馈是「图标变对勾」而不是 SnackBar：抽屉盖住页面底部，SnackBar 看不见。
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.byIcon(Icons.copy), findsNothing);

    // 1.2 秒后恢复成复制图标。
    await tester.pump(const Duration(milliseconds: 1300));
    expect(find.byIcon(Icons.copy), findsOneWidget);

    await smokeFinish(tester);
    vm.dispose();
  });
}
