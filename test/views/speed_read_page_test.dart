// 速读页的 smoke + 四条真交互（选文章 → 读 → 超时拷打 → 结算 → 回上一句）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:dlaoshi_app/data/prefs_store.dart';
import 'package:dlaoshi_app/data/repositories/article_repository.dart';
import 'package:dlaoshi_app/models/document.dart';
import 'package:dlaoshi_app/services/article_import_service.dart';
import 'package:dlaoshi_app/viewmodels/speed_read_view_model.dart';
import 'package:dlaoshi_app/views/speed_read_page.dart';
import 'smoke_harness.dart';

const String _body = 'We keep up with the news every morning. '
    'It helps us stay sharp. '
    'Small habits compound over time.';

void main() {
  setUpAll(smokeInitFfi);

  testWidgets('SpeedReadPage：空库给空态与语速设置', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);

    await smokePump(tester, smokeApp(db, const SpeedReadPage()));

    expect(find.text('速读'), findsOneWidget);
    expect(find.text('挑一篇来读'), findsOneWidget);
    expect(find.text('还没有文章'), findsOneWidget);
    expect(find.text('超时就拷打'), findsOneWidget);

    await smokeFinish(tester);
  });

  testWidgets('有文章时列出来，点进去进逐句界面', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);
    final articles = ArticleRepository(db);
    late String id;
    await tester.runAsync(() async {
      id = (await ArticleImportService(articles).createFromText(raw: _body))!.id;
    });

    final vm = SpeedReadViewModel(articles: articles, prefsStore: PrefsStore.memory());
    addTearDown(vm.dispose);
    await smokePump(
      tester,
      ChangeNotifierProvider<SpeedReadViewModel>.value(
        value: vm,
        child: const MaterialApp(home: SpeedReadPage()),
      ),
    );

    expect(find.text('第 1 / 3 句'), findsNothing);
    await tester.tap(find.text('3 句'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump();

    expect(vm.hasArticle, isTrue);
    expect(vm.article!.id, id);
    expect(find.text('第 1 / 3 句'), findsOneWidget);
    expect(find.text('下一句'), findsOneWidget);
    expect(find.text('上一句'), findsOneWidget);
    expect(find.textContaining('keep up with the news'), findsOneWidget);

    await smokeFinish(tester);
  });

  testWidgets('读超时会进拷打，选错也给出正确答案', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);
    final articles = ArticleRepository(db);
    await tester.runAsync(
      () => ArticleImportService(articles).createFromText(raw: _body),
    );

    // 语速压到最低、再人为把时钟往后拨，稳过目标时长。
    var clock = DateTime(2026, 11, 11, 9);
    final vm = SpeedReadViewModel(
      articles: articles,
      prefsStore: PrefsStore.memory(),
      now: () => clock,
    );
    addTearDown(vm.dispose);
    await smokePump(
      tester,
      ChangeNotifierProvider<SpeedReadViewModel>.value(
        value: vm,
        child: const MaterialApp(home: SpeedReadPage()),
      ),
    );
    await tester.runAsync(() async {
      await vm.openArticle((await articles.list()).single.id);
      await vm.setWpm(50);
    });
    await tester.pump();

    // 读很久：把注入的时钟拨到目标时长之外。
    clock = clock.add(const Duration(minutes: 5));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('下一句'));
    await tester.pump();

    // 超时 + 开了自动拷打：按「下一句」直接进拷打，不用再点一次。
    expect(vm.phase.name, 'drill');
    expect(vm.slow, isTrue);
    expect(find.textContaining('把空里的词选回来'), findsOneWidget);

    final drill = vm.drill!;
    final wrong = drill.options.firstWhere((o) => o != drill.answer);
    await tester.tap(find.text(wrong));
    await tester.pump();
    expect(find.textContaining('应该是：${drill.answer}'), findsOneWidget);

    await smokeFinish(tester);
  });

  testWidgets('读完最后一句给结算', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);
    final articles = ArticleRepository(db);
    await tester.runAsync(
      () => ArticleImportService(articles).createFromText(raw: _body),
    );

    final vm = SpeedReadViewModel(articles: articles, prefsStore: PrefsStore.memory());
    addTearDown(vm.dispose);
    await smokePump(
      tester,
      ChangeNotifierProvider<SpeedReadViewModel>.value(
        value: vm,
        child: const MaterialApp(home: SpeedReadPage()),
      ),
    );
    await tester.runAsync(() async {
      await vm.openArticle((await articles.list()).single.id);
      await vm.setAutoDrill(false);
    });
    await tester.pump();

    // 三句都读完（关了自动拷打，读多快都只翻句）。
    // 底部只有「下一句」：read 阶段按它 = 读完并揭晓，reveal 阶段按它 = 翻句。
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('下一句'));
      await tester.pump();
      await tester.tap(find.text('下一句'));
      await tester.pump();
    }

    expect(vm.rows, hasLength(3));
    expect(find.text('这一篇读完了'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('再读一遍'), findsOneWidget);

    await smokeFinish(tester);
  });

  testWidgets('揭晓阶段停住并显示译文与语言点', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);
    final articles = ArticleRepository(db);
    await tester.runAsync(() async {
      final raw = (await ArticleImportService(articles).createFromText(raw: _body))!;
      await articles.save(
        raw.copyWith(
          sentences: <Sentence>[
            raw.sentences.first.copyWith(
              translation: () => '我们每天早上都跟上新闻。',
              languages: () => const <SentenceLanguage>[
                SentenceLanguage(
                  structure: '主语 + keep up with + 宾语',
                  grammar: '一般现在时表示习惯',
                  phrases: <String>['keep up with'],
                ),
              ],
            ),
            ...raw.sentences.skip(1),
          ],
        ),
      );
    });

    final vm = SpeedReadViewModel(articles: articles, prefsStore: PrefsStore.memory());
    addTearDown(vm.dispose);
    await smokePump(
      tester,
      ChangeNotifierProvider<SpeedReadViewModel>.value(
        value: vm,
        child: const MaterialApp(home: SpeedReadPage()),
      ),
    );
    await tester.runAsync(() async {
      await vm.openArticle((await articles.list()).single.id);
      await vm.setAutoDrill(false);
    });
    await tester.pump();

    // 读之前不给译文（等于开卷）。
    expect(find.text('我们每天早上都跟上新闻。'), findsNothing);

    await tester.tap(find.text('下一句'));
    await tester.pump();

    expect(vm.phase.name, 'reveal');
    expect(find.text('我们每天早上都跟上新闻。'), findsOneWidget);
    expect(find.textContaining('主语 + keep up with + 宾语'), findsOneWidget);
    expect(find.textContaining('keep up with'), findsWidgets);
    expect(find.textContaining('本句速度'), findsOneWidget);

    // 停在这儿等用户点：翻页前游标不动。
    expect(vm.index, 0);
    await tester.tap(find.text('下一句'));
    await tester.pump();
    expect(vm.index, 1);

    await smokeFinish(tester);
  });

  testWidgets('第一句时「上一句」不可点，第二句起能退回去且不记成绩', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);
    final articles = ArticleRepository(db);
    await tester.runAsync(
      () => ArticleImportService(articles).createFromText(raw: _body),
    );

    final vm = SpeedReadViewModel(articles: articles, prefsStore: PrefsStore.memory());
    addTearDown(vm.dispose);
    await smokePump(
      tester,
      ChangeNotifierProvider<SpeedReadViewModel>.value(
        value: vm,
        child: const MaterialApp(home: SpeedReadPage()),
      ),
    );
    await tester.runAsync(() async {
      await vm.openArticle((await articles.list()).single.id);
      await vm.setAutoDrill(false);
    });
    await tester.pump();

    // 第一句：上一句按钮在，但点了不动（禁用的效果）。
    expect(find.text('第 1 / 3 句'), findsOneWidget);
    expect(find.text('上一句'), findsOneWidget);
    await tester.tap(find.text('上一句'));
    await tester.pump();
    expect(find.text('第 1 / 3 句'), findsOneWidget);
    expect(vm.rows, isEmpty);

    // 读一句翻到第二句，再用「上一句」退回去。
    await tester.tap(find.text('下一句'));
    await tester.pump();
    await tester.tap(find.text('下一句'));
    await tester.pump();
    expect(find.text('第 2 / 3 句'), findsOneWidget);

    await tester.tap(find.text('上一句'));
    await tester.pump();
    expect(find.text('第 1 / 3 句'), findsOneWidget);
    // 回退只移游标，不算成绩。
    expect(vm.rows, hasLength(1));

    await smokeFinish(tester);
  });
}
