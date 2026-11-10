// 页面 smoke 测试的公共装配：和 test/widget_test.dart 保持同一套 Provider / SQLite 套路。
//
// 本文件不是 *_test.dart，flutter test 不会把它当用例收集，只给同目录的
// smoke 测试 import。把重复装配收在一处，避免每个文件各抄一份抄漏。
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
import 'package:dlaoshi_app/viewmodels/study_view_model.dart';
import 'package:dlaoshi_app/viewmodels/vocab_browse_view_model.dart';
import 'package:dlaoshi_app/viewmodels/writing_view_model.dart';

/// 每个 *_test.dart 的 setUpAll 里调用一次。
void smokeInitFfi() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}

/// 默认 800×600 放不下多张卡 / 长页，给个够高的屏幕。
void smokeUseTallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// 真 SQLite 是真实异步 IO，必须放在 runAsync 里。
Future<Database> smokeOpenDb(WidgetTester tester) async {
  late final Database db;
  await tester.runAsync(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await ensureSchema(db);
  });
  addTearDown(() async => tester.runAsync(() => db.close()));
  return db;
}

/// 和 main.dart 一致的整套 Provider 装配；十个 VM 全部 .value 注入、刻意不 dispose。
Widget smokeApp(Database db, Widget home) {
  final articles = ArticleRepository(db);
  final vocab = VocabRepository(db);
  final learning = LearningRepository(db);
  final imports = ArticleImportService(articles);
  final prefs = PrefsStore.memory();
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
  final aiBatch = AiBatchViewModel(
    vocab: vocab,
    complete: (config, prompt) async => AiReply.ok(''),
    prefsStore: prefs,
  );
  return MultiProvider(
    providers: [
      Provider<ArticleRepository>.value(value: articles),
      Provider<VocabRepository>.value(value: vocab),
      Provider<LearningRepository>.value(value: learning),
      Provider<ArticleImportService>.value(value: imports),
      Provider<PrefsStore>.value(value: prefs),
      ChangeNotifierProvider<ReaderViewModel>.value(value: reader),
      ChangeNotifierProvider<StudyViewModel>.value(value: study),
      ChangeNotifierProvider<VocabBrowseViewModel>.value(value: browse),
      ChangeNotifierProvider<ProductionViewModel>.value(value: production),
      ChangeNotifierProvider<WritingViewModel>.value(value: writing),
      ChangeNotifierProvider<DrillSentenceViewModel>.value(value: drill),
      ChangeNotifierProvider<GoldenViewModel>.value(value: golden),
      ChangeNotifierProvider<BackupViewModel>.value(value: backup),
      ChangeNotifierProvider<ShadowingViewModel>.value(value: shadowing),
      ChangeNotifierProvider<AiBatchViewModel>.value(value: aiBatch),
    ],
    child: MaterialApp(home: home),
  );
}

/// pumpWidget + 让 initState 的 bootstrap 真实 IO 走完；
/// 不用 pumpAndSettle（不少页面常驻 LinearProgressIndicator，永远 settle 不了）。
Future<void> smokePump(WidgetTester tester, Widget app) async {
  await tester.pumpWidget(app);
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 30)),
  );
  await tester.pump();
  await tester.pump();
}

/// 收尾消掉 pending Timer（sqflite 事务锁 / 250ms 防抖草稿 / TTS 都会排 Timer）。
Future<void> smokeFinish(WidgetTester tester) async {
  for (var round = 0; round < 6; round++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 500));
  }
}
