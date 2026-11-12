import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:dlaoshi_app/data/db/migrations.dart';
import 'package:dlaoshi_app/data/prefs_store.dart';
import 'package:dlaoshi_app/data/repositories/article_repository.dart';
import 'package:dlaoshi_app/data/repositories/learning_repository.dart';
import 'package:dlaoshi_app/data/repositories/vocab_repository.dart';
import 'package:dlaoshi_app/services/ai_client.dart' show AiReply;
import 'package:dlaoshi_app/services/article_import_service.dart';
import 'package:dlaoshi_app/services/backup_service.dart';
import 'package:dlaoshi_app/services/shadowing_recorder.dart';
import 'package:dlaoshi_app/services/shadowing_speech.dart';
import 'package:dlaoshi_app/viewmodels/ai_batch_view_model.dart';
import 'package:dlaoshi_app/viewmodels/backup_view_model.dart';
import 'package:dlaoshi_app/viewmodels/drill_sentence_view_model.dart';
import 'package:dlaoshi_app/viewmodels/golden_view_model.dart';
import 'package:dlaoshi_app/viewmodels/production_view_model.dart';
import 'package:dlaoshi_app/viewmodels/reader_view_model.dart';
import 'package:dlaoshi_app/viewmodels/shadowing_view_model.dart';
import 'package:dlaoshi_app/viewmodels/speed_read_view_model.dart';
import 'package:dlaoshi_app/viewmodels/study_view_model.dart';
import 'package:dlaoshi_app/viewmodels/theme_view_model.dart';
import 'package:dlaoshi_app/viewmodels/vocab_browse_view_model.dart';
import 'package:dlaoshi_app/viewmodels/writing_view_model.dart';
import 'package:dlaoshi_app/views/ai_batch_page.dart';
import 'package:dlaoshi_app/views/articles_page.dart';
import 'package:dlaoshi_app/views/backup_page.dart';
import 'package:dlaoshi_app/views/golden_page.dart';
import 'package:dlaoshi_app/views/home_page.dart';
import 'package:dlaoshi_app/views/production_page.dart';
import 'package:dlaoshi_app/views/shadowing_page.dart';
import 'package:dlaoshi_app/views/speed_read_page.dart';
import 'package:dlaoshi_app/views/study_page.dart';
import 'package:dlaoshi_app/views/vocab_browse_page.dart';
import 'package:dlaoshi_app/views/writing_page.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  /// 默认测试窗口只有 800×600，十张入口卡放不下 —— 最后一张会落在视口外，
  /// `ListView` 就不会挂载它，`find.text('AI 跑批')` 自然找不到。
  /// 这里按一台普通手机的高宽给个够高的屏幕，用例本身不关心滚动。
  void useTallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('首页：十条入口全部接通，没有「开发中」', (tester) async {
    useTallScreen(tester);
    await tester.pumpWidget(const MaterialApp(home: HomePage()));

    expect(find.text('精读'), findsOneWidget);
    expect(find.text('背单词'), findsOneWidget);
    expect(find.text('词库'), findsOneWidget);
    expect(find.text('速读'), findsOneWidget);
    expect(find.text('产出训练'), findsOneWidget);
    expect(find.text('小课堂'), findsOneWidget);
    expect(find.text('金句课'), findsOneWidget);
    expect(find.text('备份'), findsOneWidget);
    expect(find.text('跟读'), findsOneWidget);
    expect(find.text('AI 跑批'), findsOneWidget);

    // 十条都接通了：不许再出现「开发中」占位，每条都有 chevron。
    expect(find.text('开发中'), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsNWidgets(10));
  });

  testWidgets('首页：十条入口点进去都落到对应页面，返回还能再进', (tester) async {
    useTallScreen(tester);
    // 光数 chevron 图标证明不了「点得动」——这里真点一遍，落到目标页面再返回来。
    // 目标页面各自要在 initState 里 bootstrap 真库，所以得把整套 Provider 都装上，
    // 和 main.dart 的装配一致（少一个就会在 context.read 处炸）。
    late final Database db;
    await tester.runAsync(() async {
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      await ensureSchema(db);
    });
    addTearDown(() async => tester.runAsync(() => db.close()));

    final articles = ArticleRepository(db);
    final vocab = VocabRepository(db);
    final learning = LearningRepository(db);
    final imports = ArticleImportService(articles);
    final prefs = PrefsStore.memory();

    // 十个 ViewModel 都在外面造好、用 .value 交给 Provider：
    // 这样拆树时 Provider 不会替我们 dispose，异步 bootstrap 回来时
    // notifyListeners 还打得到活对象；销毁放在 addTearDown 里手动做。
    final reader = ReaderViewModel(
      articlesRepo: articles,
      vocabRepo: vocab,
      importsService: imports,
    );
    final study = StudyViewModel(
      vocab: vocab,
      learning: learning,
      prefsStore: prefs,
    );
    final browse = VocabBrowseViewModel(vocab: vocab, articles: articles);
    final production = ProductionViewModel(
      vocab: vocab,
      learning: learning,
      prefsStore: prefs,
    );
    final writing = WritingViewModel(learning: learning, prefsStore: prefs);
    final drill = DrillSentenceViewModel(learning: learning, prefsStore: prefs);
    final golden = GoldenViewModel(
      articles: articles,
      learning: learning,
      prefsStore: prefs,
    );
    final backup = BackupViewModel(
      BackupService(
        articles: articles,
        vocab: vocab,
        learning: learning,
        prefsStore: prefs,
      ),
    );
    final shadowing = ShadowingViewModel(
      articles: articles,
      speech: SystemSpeech(),
      recorder: DeviceRecorder(),
      prefsStore: prefs,
    );
    // 跑批页用假回调：整条链路不碰网络，也不碰平台通道。
    final aiBatch = AiBatchViewModel(
      vocab: vocab,
      complete: (config, prompt) async => AiReply.ok(''),
      prefsStore: prefs,
    );
    final speedRead = SpeedReadViewModel(articles: articles, prefsStore: prefs);
    // 刻意不 dispose：每个页面进 initState 都会拉一次真库，那些 Future 可能在
    // 用例结束之后才回来。Provider 的 .value 不接管销毁，这里也不手动销毁，
    // 否则回来时会对着已 dispose 的对象 notifyListeners（报 "used after being disposed"）。
    // 一次性的测试进程里让它们跟着进程走，代价可以忽略。

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ArticleRepository>.value(value: articles),
          Provider<VocabRepository>.value(value: vocab),
          Provider<LearningRepository>.value(value: learning),
          Provider<ArticleImportService>.value(value: imports),
          Provider<PrefsStore>.value(value: prefs),
          ChangeNotifierProvider<ThemeViewModel>.value(
            value: ThemeViewModel(prefsStore: prefs),
          ),
          ChangeNotifierProvider<ReaderViewModel>.value(value: reader),
          ChangeNotifierProvider<StudyViewModel>.value(value: study),
          ChangeNotifierProvider<VocabBrowseViewModel>.value(value: browse),
          ChangeNotifierProvider<ProductionViewModel>.value(value: production),
          ChangeNotifierProvider<WritingViewModel>.value(value: writing),
          ChangeNotifierProvider<DrillSentenceViewModel>.value(value: drill),
          ChangeNotifierProvider<GoldenViewModel>.value(value: golden),
          ChangeNotifierProvider<BackupViewModel>.value(value: backup),
          ChangeNotifierProvider<ShadowingViewModel>.value(value: shadowing),
          ChangeNotifierProvider<SpeedReadViewModel>.value(value: speedRead),
          ChangeNotifierProvider<AiBatchViewModel>.value(value: aiBatch),
        ],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await tester.pump();

    Future<void> visit(String title, Type page) async {
      await tester.tap(find.widgetWithText(ListTile, title));
      // 目标页会在 initState 里 bootstrap 真 SQLite（真实异步 IO）：
      // 先让出真实事件循环把那些 Future 走完，再 pump 一次看界面。
      // 不这么做，用例结束后 bootstrap 才回来，会对着已 dispose 的 ViewModel
      // 调 notifyListeners，报 "used after being disposed"。
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
      await tester.pump();
      expect(
        find.byType(page),
        findsOneWidget,
        reason: '点「$title」应该进到 $page',
      );
      // 返回来，确认首页还在、还能再点（历史栈没被写坏）。
      await tester.pageBack();
      await tester.pump();
      await tester.pump();
      expect(find.byType(page), findsNothing, reason: '返回后 $page 应该关掉');
      expect(find.byType(HomePage), findsOneWidget);
    }

    await visit('精读', ArticlesPage);
    await visit('背单词', StudyPage);
    await visit('词库', VocabBrowsePage);
    await visit('速读', SpeedReadPage);
    await visit('产出训练', ProductionPage);
    await visit('小课堂', WritingPage);
    await visit('金句课', GoldenPage);
    await visit('备份', BackupPage);
    await visit('跟读', ShadowingPage);
    await visit('AI 跑批', AiBatchPage);

    // 走完一整轮，十条入口都还点得动（没有哪次导航把路由搞坏）。
    expect(find.byIcon(Icons.chevron_right), findsNWidgets(10));

    // 收尾：最后一次进页还会在后台读库。这些 Future 的续体落在 FakeAsync 的
    // 假时钟上（sqflite 的事务锁还会额外排一个 Timer），等一轮往往只等到了
    // 上一轮，新的一轮又刚排上——只推一次会偶发
    // "A Timer is still pending even after the widget tree was disposed"。
    // 所以反复「让出真事件循环 + 推进假时钟」，直到不再冒新的计时器。
    for (var round = 0; round < 6; round++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 500));
    }
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
